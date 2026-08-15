#import "LlamaBridge.h"
#import <llama/llama.h>
#include <vector>
#include <string>
#include <atomic>
#include <unistd.h>

// App 退后台时置位;推理循环等待而非提交 GPU(否则 Metal 后端进入错误态)
static std::atomic<bool> g_suspended{false};

// llama.cpp 日志落盘(真机不连 Xcode 也能事后取证)
static FILE *g_llamaLog = NULL;
static void vn_llama_log_cb(enum ggml_log_level level, const char *text, void *user_data) {
    (void)level; (void)user_data;
    if (g_llamaLog) { fputs(text, g_llamaLog); fflush(g_llamaLog); }
}

@implementation LlamaBridge {
    llama_model *_model;
    llama_context *_ctx;
    const llama_vocab *_vocab;
    int _nCtx;
    BOOL _broken;   // decode 失败后 Metal 后端不可恢复,需整体重建
}

+ (void)setGloballySuspended:(BOOL)suspended {
    g_suspended.store(suspended);
}

+ (void)redirectLlamaLogToFile:(NSString *)path {
    if (g_llamaLog) { fclose(g_llamaLog); g_llamaLog = NULL; }
    g_llamaLog = fopen(path.UTF8String, "a");
    llama_log_set(vn_llama_log_cb, NULL);
}

- (BOOL)isLoaded { return _model != NULL && _ctx != NULL && !_broken; }

- (BOOL)loadModelAtPath:(NSString *)path contextSize:(int)nCtx {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ llama_backend_init(); });
    [self unload];        // 后端中毒或换档时整体重建
    _broken = NO;

    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 99;   // 全量 offload 到 Metal
    _model = llama_model_load_from_file(path.UTF8String, mp);
    if (_model == NULL) return NO;

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = (uint32_t)nCtx;
    // n_batch 必须 ≥ 单次提交的 prompt 长度,否则 llama_decode 触发
    // GGML_ASSERT(n_tokens_all <= cparams.n_batch) 直接 abort。
    // 设为整个上下文长度,内部按 n_ubatch(默认512)自动分块计算。
    cp.n_batch = (uint32_t)nCtx;
    _nCtx = nCtx;
    _ctx = llama_init_from_model(_model, cp);
    if (_ctx == NULL) {
        llama_model_free(_model);
        _model = NULL;
        return NO;
    }
    _vocab = llama_model_get_vocab(_model);
    return YES;
}

- (NSString *)generateWithSystem:(NSString *)system
                            user:(NSString *)user
                         grammar:(NSString *)grammar
                       maxTokens:(int)maxTokens
                      onProgress:(LlamaProgressHandler)onProgress {
    if (![self isLoaded]) return nil;

    @autoreleasepool {
        // 清掉上一次生成残留的 KV cache:位置从 0 重新开始,避免旧对话污染与位置溢出
        llama_memory_clear(llama_get_memory(_ctx), true);
        // 1) 套用模型内置 chat template(Qwen)
        std::string sys = system ? system.UTF8String : "";
        std::string usr = user ? user.UTF8String : "";
        llama_chat_message msgs[2] = {
            { "system", sys.c_str() },
            { "user",   usr.c_str() },
        };
        const char *tmpl = llama_model_chat_template(_model, NULL);
        if (tmpl == NULL) return nil;   // Qwen GGUF 应内置 template
        std::vector<char> tbuf(sys.size() + usr.size() + 2048);
        int32_t tlen = llama_chat_apply_template(tmpl, msgs, 2, true,
                                                 tbuf.data(), (int32_t)tbuf.size());
        if (tlen < 0) return nil;
        if (tlen > (int32_t)tbuf.size()) {
            tbuf.resize(tlen);
            tlen = llama_chat_apply_template(tmpl, msgs, 2, true,
                                             tbuf.data(), (int32_t)tbuf.size());
        }
        std::string prompt(tbuf.data(), tlen);

        // 2) tokenize(先取长度,再填充)
        int32_t n_prompt = -llama_tokenize(_vocab, prompt.c_str(), (int32_t)prompt.size(),
                                           NULL, 0, true, true);
        if (n_prompt <= 0) return nil;
        std::vector<llama_token> tokens(n_prompt);
        if (llama_tokenize(_vocab, prompt.c_str(), (int32_t)prompt.size(),
                           tokens.data(), n_prompt, true, true) < 0) return nil;
        // prompt 超出上下文(留至少 64 token 生成余量)则放弃,由调用方降级,不能硬塞导致崩溃
        if (n_prompt >= _nCtx - 64) return nil;

        // 3) sampler chain:grammar(结构化) + top_k/top_p/temp + dist
        llama_sampler *smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
        if (grammar.length > 0) {
            llama_sampler *g = llama_sampler_init_grammar(_vocab, grammar.UTF8String, "root");
            if (g) llama_sampler_chain_add(smpl, g);
        }
        llama_sampler_chain_add(smpl, llama_sampler_init_top_k(20));
        llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.8f, 1));
        // Qwen 官方推荐 presence_penalty≈1.5:抑制小模型逐字重复整段的毛病
        llama_sampler_chain_add(smpl, llama_sampler_init_penalties(
            llama_vocab_n_tokens(_vocab), 256, 1.0f, 0.0f, 1.5f));
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.6f));
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

        // 4) decode 循环
        std::string result;
        llama_batch batch = llama_batch_get_one(tokens.data(), (int32_t)tokens.size());
        llama_token newTok = 0;   // 循环外持有,保证 &newTok 生命周期跨迭代
        for (int i = 0; i < maxTokens; i++) {
            // App 在后台则原地等待(iOS 禁止后台 GPU),回前台自动续跑
            while (g_suspended.load()) { usleep(150000); }
            if (n_prompt + i >= _nCtx - 1) break;   // 触顶上下文即收,防位置溢出
            if (llama_decode(_ctx, batch) != 0) { _broken = YES; break; }
            newTok = llama_sampler_sample(smpl, _ctx, -1);
            if (llama_vocab_is_eog(_vocab, newTok)) break;
            char piece[512];
            int32_t np = llama_token_to_piece(_vocab, newTok, piece, sizeof(piece), 0, true);
            if (np > 0) result.append(piece, np);
            // 每 8 个 token 回调一次进度(整串重建,规避 UTF-8 多字节被 token 边界切断)
            if (onProgress && (i & 7) == 0) {
                NSString *acc = [NSString stringWithUTF8String:result.c_str()];
                if (acc) onProgress(acc);
            }
            batch = llama_batch_get_one(&newTok, 1);
        }
        llama_sampler_free(smpl);

        if (_broken) return nil;   // 后端已错误态,产物不可信;下次 isLoaded=NO 触发重建
        return [NSString stringWithUTF8String:result.c_str()];
    }
}

- (void)unload {
    if (_ctx) { llama_free(_ctx); _ctx = NULL; }
    if (_model) { llama_model_free(_model); _model = NULL; }
    _vocab = NULL;
}

@end
