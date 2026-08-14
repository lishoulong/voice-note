#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift ↔ llama.cpp 的 ObjC++ 桥。
/// 负责加载 GGUF 模型,并用 chat template + GBNF grammar 做一次结构化生成。
@interface LlamaBridge : NSObject

/// 模型是否已加载
@property (nonatomic, readonly) BOOL isLoaded;

/// 加载模型(n_gpu_layers=99 走 Metal)。耗时,务必放后台线程调用。
/// @param path GGUF 文件路径
/// @param nCtx 上下文长度(移动端建议 4096)
/// @return 是否加载成功
- (BOOL)loadModelAtPath:(NSString *)path contextSize:(int)nCtx;

/// 生成一次。system/user 会套用模型内置 chat template(Qwen)。
/// @param grammar GBNF grammar 字符串(约束结构化 JSON,可空)
/// 同步阻塞,务必放后台线程调用。返回生成文本(失败返回 nil)。
- (nullable NSString *)generateWithSystem:(NSString *)system
                                     user:(NSString *)user
                                  grammar:(nullable NSString *)grammar
                                maxTokens:(int)maxTokens;

/// 释放模型与上下文
- (void)unload;

@end

NS_ASSUME_NONNULL_END
