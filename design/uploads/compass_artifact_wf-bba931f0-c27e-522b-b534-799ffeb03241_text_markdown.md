# 双端统一 llama.cpp + Qwen3 GGUF 方案：iOS/Android 工程可行性、实施细节与风险评估

## TL;DR
- **总体判断：这个"双端统一 llama.cpp + Qwen3 GGUF"方案在 iOS 上是"可行但有明显代价"，不是"完全可行"，也未到"严重不可行"** —— 前提是把默认模型从 4B 降级、按设备 RAM 分档，并保留一条 fallback（Apple Foundation Models 或云端）。硬跑 Qwen3-4B Q4_K_M（约 2.7–2.9GB 权重）在 8GB iPhone 上生成峰值内存约 3.3–3.8GB，接近 jetsam 单进程上限（8GB 机约 4GB），在 6GB 及更低设备上会被系统杀掉。
- **模型选型必须更新：用户决策时的"Qwen3-4B/1.7B"已过时。** 截至 2026 年 8 月，Qwen3.5 小模型（0.8B/2B/4B/9B，2026 年 2–3 月发布，Apache 2.0，256K 上下文，**小模型默认以 non-thinking 模式运行**）已是更优选择；Qwen3.6（27B/35B-A3B，2026 年 4 月）也已发布但小尺寸未必齐全。建议改用 Qwen3.5-4B / Qwen3.5-2B。
- **推荐落地策略：iOS 端默认 2B 档（Qwen3.5-2B Q4_K_M，约 1.5–1.8GB），仅在 8GB+ 且用户显式选择"高质量"时用 4B；模型走首启动后台下载（iOS 用自建 CDN/HF + URLSession background；Android 用 Play Asset Delivery fast-follow 或自下载）；用 GBNF grammar 约束结构化输出；n_ctx 移动端设 4K–8K。**

## Key Findings

### 1. iOS 集成路径已成熟，但要用二进制 XCFramework 而非源码编译
- llama.cpp 官方仓库自 2025 年起在每个 release 提供预编译 `llama-b<NNNN>-xcframework.zip`，可直接作为 SPM `binaryTarget` 引入（支持 iOS/visionOS/tvOS/macOS）。这是首选路径。
- 官方 `Package.swift` 依赖 `unsafeFlags`，会破坏 SPM 语义化版本；Stanford BDHG fork 与 `mattt/llama.swift` 通过预编译 XCFramework 解决了这个问题，可做语义化版本管理。
- **重要坑：XCFramework 只暴露公开 API。GBNF grammar 相关的 `llama_grammar_*`、`llama_grammar_element` 在 `src/llama-grammar.h` 属私有头，不随 XCFramework 导出**（GitHub Discussion #12320 确认）。但 grammar 可以通过采样链的公开 API（sampler chain）使用——需要用公开的 `llama_sampler_init_grammar` 一类接口而非直接调私有结构体。
- 第三方 Swift 封装：官方 `examples/llama.swiftui` 是最权威的参考实现（含 Metal、bench 按钮）；SwiftLlama、LLM.swift（eastriverlee）等封装便捷但跟进上游速度不一，建议自己写一层 Objective-C++ bridge（`LlamaBridge.mm`）直接调 C API，以便完全控制 grammar、KV cache、采样参数。

### 2. iOS 内存是最大风险，4B 在主流机型上处于危险边缘
- **iOS 单进程内存上限远低于物理 RAM。** 通过 `os_proc_available_memory()` 获取。实测：iPhone 13（4GB）即使加了 increased-memory-limit entitlement 也只报告约 2.2–2.3GB 可用；4GB 机（iPhone 12）jetsam 硬限约 2098MB（`ActiveHard 2098 MB fatal`）；8GB 机（iPhone 16 Pro）约 4000MB。
- **entitlement 的真实效果：** `com.apple.developer.kernel.increased-memory-limit` 抬高物理 RAM（resident）上限——6GB 机约到 4.5GB、8GB 机约到 6GB（社区实测，非官方承诺）；`com.apple.developer.kernel.extended-virtual-addressing` 抬高虚拟地址空间上限（对 mmap 大模型有用）。二者对 iPhone 11 及更早（4GB）无效。Fumiya Yamanaka 在 iPhone 17 Pro（8GB）实测 Gemma 4 E4B（3.65GB）时，开任一 entitlement 即可让加载成功，同时开两个"peak memory usage 无显著差异"。**关键警告：有开发者报告该 entitlement 在开发签名下有效（可用到 ~15GB），但 App Store 分发版又回落到标准上限（~6GB），存在"本地能跑、上架后崩"的风险（Apple Dev Forum #770868），需在真机 App Store/TestFlight 构建上验证。** 该 entitlement 现在可在 Xcode Signing & Capabilities 直接勾选，无需向 Apple 单独审批（自 iOS 15 起）。
- **4B 实际内存峰值：** 3B Q4 加载后约 2.1GB、生成峰值约 2.8GB（PocketLLM 实测，iPhone 15 Pro）；4B Q4 权重约 2.7–2.9GB（Gemma 3 4B ~2.9GB、Phi-4 Mini 3.8B ~2.7GB），加 KV cache 后峰值现实约 3.3–3.8GB。**结论：4B Q4 在 8GB iPhone 上可跑但余量小，在 6GB 上会被 jetsam 杀；应在 6GB 机降到 1.7B/2B。**
- **一个隐蔽的 Metal 陷阱：** iPhone Air（12GB）上 Metal 的 `recommendedMaxWorkingSetSize` 仍只报约 8192MB，即 GPU 侧可用工作集不随物理 RAM 线性增长，13B Q4（~7.32GB）因此无法加载（Apple Dev Forum #805161）。

### 3. 双端实测性能（真机，llama.cpp/Metal）
| 设备 | 模型/量化 | decode tg (tok/s) | prefill pp (tok/s) | 来源 |
|---|---|---|---|---|
| iPhone 13 Pro (A15,6GB) | phi2-3B Q4_0 | 16.7 | 120.5 | llama.cpp Disc #4508 |
| iPhone 14 Pro (A16,6GB) | phi2-3B Q4_0 | 23.3 | 121.6 | llama.cpp Disc #4508 |
| iPhone 15 Pro (A17,8GB) | Llama3.2-3B Q4_K_M | 18 | ~157 | PocketLLM |
| iPhone 16 Pro (A18,8GB) | Llama3.2-3B Q4_K_M | 22 | ~180 | PocketLLM |
| iPhone 17 Pro (A19) | Gemma3-4B Q4_K_M | 10–13 | ~600+ | promptquorum |
| iPhone Air (A19,12GB) | 8B Q4_K | ~9 | — | Apple Dev Forum #805161 |
| iPhone Air (A19,12GB) | phi2-3B Q4_0 | 36.0 | 690.0 | llama.cpp Disc #4508 |
| Galaxy S24 (Android) | ~3B 4bit | 10.7 | — | ExecuTorch |
| OnePlus 12 (Android) | ~3B 4bit | 11.6 | — | ExecuTorch |

- **生成一篇 500–800 字中文日记（约 1000–1500 token 输出）：** 按 4B 档 iOS 约 10–20 tok/s 估算，纯 decode 约 60–150 秒；2B 档约 25–35 tok/s，约 30–60 秒。prefill（读入当天零散条目，可能几百到一两千 token）在 A16+ 上约 1–2 秒。A19（iPhone 17 系列）因 Metal 4 API 使 prefill 提升约 5 倍。关闭 thinking 后能省下大量无用 token，这对时长影响最大。

### 4. Qwen3 thinking mode 关闭在 llama.cpp 上有已知坑
- Qwen3 老系列用 `/no_think` 软开关或 `enable_thinking=False`；Qwen3.5 **小模型（0.8B/2B/4B/9B）默认就以 non-thinking 模式运行**（官方 Qwen3.5-0.8B 卡片："Qwen3.5-0.8B operates in non-thinking mode by default"），省心。
- **已知 bug：** 在 llama.cpp 上 `--chat-template-kwargs '{"enable_thinking":false}'` 在 `llama-cli` 上常常不生效（多个 GitHub issue：#20182、#20409、#20476），但在 `llama-server`/API 路径通常有效。可靠做法：(a) 用默认关闭 thinking 的 Qwen3.5 小模型；(b) 走 `--jinja` + 传 `chat_template_kwargs`；(c) 必要时用 `--reasoning-budget 0`；(d) 直接在 prompt 里加 `/no_think`（老 Qwen3）。**移动端务必在集成后真机验证输出里没有 `<think>` 块。**

### 5. 模型分发：两端都别把模型塞进安装包
- **iOS：** On-Demand Resources 已在 iOS 27 废弃（App Store Connect 文档："On-demand resources is a legacy technology, so migrating to Background Assets is recommended"；Apple DTS 工程师 Quinn 在开发者论坛明确"It wouldn't be wise to use ODR in a new product"），官方推荐迁移到 **Background Assets**（iOS 16+，Apple-Hosted asset packs 需 iOS 26+）。**而且即便不废弃，ODR 也装不下 2.5GB GGUF：ODR 单 tag 上限 512MB（分片后）、"in-use"上限 2GB——2.5GB 模型两条都超。** 因此对 GGUF 更稳妥、跨版本兼容更好的是**自建 CDN / 从 Hugging Face 下载**，用 `URLSession` background configuration 做后台断点续传；下载后存到 Application Support 目录并设 `isExcludedFromBackupKey=true` 排除 iCloud 备份。
- **Android：** Play Asset Delivery 三模式：**install-time（所有 install-time 包合计上限 1GB）、fast-follow（单包上限 512MB）、on-demand（单包 512MB）；所有 asset pack 总和上限 2GB，最多 50 个包**（Android 官方 + Microsoft Learn）。2.5GB 单模型超过 PAD 总上限，需拆包或改为自下载（WorkManager + OkHttp，优于易被系统回收的 DownloadManager）。
- **审核：** 已上架的 PocketPal AI（React Native + llama.rn）、Private LLM（原生 Swift）、fullmoon、Pocket 都采用"空壳 App + 首次运行下载模型"模式并通过审核。**但有明确拒审先例：审核员用慢网测试，若首启动下载/解包让 App 超过约 10 分钟不可用会被拒（Apple Forum #709653，一款首启下载 2.5GB 资源的 App 因"launched...took more than 10 minutes"被拒 Guideline 4.0）；ODR 路径还出现过审核端无法解析下载主机名导致被拒的案例。** 缓解：App 不 gate 在下载完成上（先给可用 UI）、在描述里披露下载大小、提供 Wi-Fi-only 选项。

### 6. 跨端一致性：同一 GGUF 不保证逐字节相同输出
- 不同后端（iOS Metal vs Android Vulkan/CPU）存在浮点/量化 kernel 数值差异，**即使固定 seed 和采样参数，也不能保证两端逐 token 完全一致**。对"日记汇总"这种任务，一致性目标应是"结构一致、语义等价"，而非逐字节相同。
- **保证结构一致的正确工具是 GBNF grammar / JSON schema 约束解码**，而不是指望采样一致。grammar 有性能开销（llama.cpp 用 runtime check，复杂 grammar 更慢；`x{0,N}` 写法比 `x? x? ...` 快得多；也可选 `LLAMA_LLGUIDANCE=ON` 用更快的约束后端，但需 Rust 工具链，移动端集成成本高）。

### 7. 相比 Apple Foundation Models，iOS 端统一走 llama.cpp 的额外代价
| 代价项 | 具体影响 | 缓解措施 |
|---|---|---|
| App 体积/首次下载 | FM 零下载零体积；llama.cpp 需下 1.5–2.9GB | 默认 2B（~1.5GB）、Wi-Fi 下载、断点续传、进度可见 |
| 内存/jetsam | FM 由系统托管；4B 峰值 3.3–3.8GB 逼近 8GB 机 ~4GB 上限 | 设备分档、降默认到 2B、开 entitlement、autoreleasepool |
| 电池/发热 | 持续推理约 1%/分钟耗电，约 10 分钟可到 thermalState `serious` | 后台整理、限制生成长度、关 thinking、降档 |
| 维护成本 | 自己跟 llama.cpp 更新、Metal 兼容（shader 编译失败/OOM 静默损坏） | 锁定 XCFramework 版本、CI 回归 |
| 审核风险 | 大下载/慢启动可能触发 4.2.3/4.0 | 披露大小、不 gate UI、Wi-Fi 下载 |
| 开发工作量 | bridge、下载器、内存管理都要自己写 | 复用 llama.swiftui 参考、复用 Stanford SpeziLLM |

## Details

### 一、iOS 端 llama.cpp 集成完整工程细节

**集成方式对比**

| 方式 | 2026 维护状态 | grammar/Metal/KV | 推荐度 |
|---|---|---|---|
| 官方 XCFramework（release zip 作 SPM binaryTarget） | 官方每 build 发布，活跃 | Metal✓ KV✓ grammar需走公开sampler API | ★★★★★ 首选 |
| 官方 Package.swift（源码 SPM） | 活跃但用 unsafeFlags | 全支持但破坏语义版本 | ★★★ |
| Stanford BDHG llama.cpp / SpeziLLM | 活跃（硕士论文起） | 预编译XCFramework，语义版本OK | ★★★★ |
| mattt/llama.swift | 跟随上游，Swift 6+ | 重导出 C API | ★★★★ |
| examples/llama.swiftui | 官方示例，最权威参考 | 全支持 | 参考用 |
| SwiftLlama / LLM.swift（eastriverlee） | 第三方，跟进速度不一 | 封装度高但不透明 | ★★ |

**构建配置要点**
- 用官方 XCFramework 省去 CMake；若自编：`cmake -B build-ios -G Xcode -DCMAKE_TOOLCHAIN_FILE=... -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON`，务必 embed metal library（否则运行时要在同目录找 `ggml-metal.metal`）。
- bitcode 已被 Apple 全面弃用，无需开启。
- 架构：arm64 真机 + arm64 模拟器（Apple Silicon Mac）；模拟器无法真实反映内存/热/Metal 行为，**必须真机测**。
- 静态库 vs 动态框架：XCFramework（内含静态库）更简单；注意 App 二进制体积。Release 构建把"Build Active Architecture Only"设为 No。

**关键 Swift/ObjC++ 代码要点**
1. 加载：`llama_model_load_from_file` + `llama_context_params`（设 `n_ctx`、`n_batch`、`n_gpu_layers=99` 全量 offload 到 Metal）。
2. Chat template：用 `llama_chat_apply_template` 套用 GGUF 内置 Qwen3 template（等价 `--jinja`），注入 system prompt + 用户零散条目。
3. 推理：`llama_decode` 循环 + sampler chain（temp/top_p/top_k/penalty + grammar sampler）。
4. 流式：每 token 回调到 SwiftUI（注意主线程更新 UI，推理放后台队列）。
5. **释放/内存：每次 decode 用 `@autoreleasepool` 包裹**（已知 Metal `MTLCommandBuffer` 泄漏，官方 issue #5436 确认加 autoreleasepool 后 1000 次推理内存稳定）；用完 `llama_free` / `llama_model_free`。

**Metal 后端**：`-ngl 99` 全 offload；首次运行有 shader JIT 编译延迟（embed library 可缓解）；已知 issue：iOS 上某些 flash-attention kernel 编译失败（#7261）、OOM 时 Metal 输出静默损坏（#1881）、命令缓冲 OOM（#16646）。**务必在 OOM/编译失败时优雅降级到 CPU 或更小模型，而非硬崩。**

### 二、内存限制深入（重点）

**分档策略（建议规则）**

| 设备 RAM | 代表机型 | 单进程可用（约） | 推荐默认模型 | 上限模型 |
|---|---|---|---|---|
| 4GB | iPhone 12/SE3 | ~2.0–2.3GB | 不支持本地，走云端/FM | 1B Q4 勉强 |
| 6GB | iPhone 13/14/15 | ~3–4.5GB（带entitlement） | Qwen3.5-2B Q4（~1.5GB） | 1.7B–2B |
| 8GB | 15 Pro/16/17 | ~4–6GB（带entitlement） | Qwen3.5-2B（默认）/4B（高质量） | 4B Q4 |
| 12GB | 17 Pro/Air | ~6–8GB（Metal 工作集仍限~8GB） | Qwen3.5-4B Q4 | 4B–8B Q4 |

用 `os_proc_available_memory()` 在运行时探测，而非硬编码机型；加载前预留至少 1.5× 模型大小的余量，不足则降档。

**KV cache 内存计算**：`KV_bytes = 2 × n_layers × n_kv_heads × head_dim × n_ctx × bytes_per_elem`。Qwen3 系列用 GQA，KV 占用小（一个 4B/GQA 模型 2K ctx 约 0.2GB、32K ctx 约 3GB 量级）。移动端建议 **n_ctx = 4096–8192**（而非 32K/256K）；**KV cache 在 llama.cpp 启动时按 n_ctx 一次性预分配**，设太大直接吃内存并可能立即触发 OOM。可用 `--cache-type-k q8_0 --cache-type-v q8_0` 把 KV 减半。日记场景输入通常几百 token，4K–8K 足够；超长时用 map-reduce 分段。

**Android 侧**：6GB 机跑 2B、8GB 跑 4B；OOM 风险主要在低端 4GB 机。Android 无 iOS 式硬 jetsam，但 low-memory-killer 同样会杀后台，建议前台 Service + 限制 n_ctx。参考实测：~3B Q4 在 Galaxy S24 约 10.7 tok/s、OnePlus 12 约 11.6 tok/s。

### 三、模型分发细节
- **iOS 存储位置**：`Application Support/Models/`，设 `URLResourceValues.isExcludedFromBackupKey=true`。
- **后台下载**：`URLSessionConfiguration.background(withIdentifier:)`，支持 App 挂起后继续、断点续传（`URLSessionDownloadTask` + resume data）。失败指数退避重试。注意 iOS 对超 200MB 的 App Store 下载在蜂窝网默认询问，自下载模型也应默认 Wi-Fi。
- **清理策略**：App 内"存储管理"页，显示各模型占用，允许删除/切换；低空间时提示。
- **Android**：自下载用 WorkManager（约束 Wi-Fi、充电）+ OkHttp（Range 断点续传），存 internal storage；或 PAD fast-follow/on-demand（但 2.5GB 超总限需拆分）。

### 四、Qwen3/Qwen3.5 模型工程
- **量化选择（Qwen3.5-4B，来自 unsloth GGUF 实际体积）**：IQ4_XS 2.48GB、Q4_K_M 2.74GB、Q5_K_M 3.14GB、UD-Q4_K_XL 2.91GB（Unsloth Dynamic 2.0，重要层升到 8/16bit，质量最好）、UD-Q3_K_XL 2.44GB、UD-Q2_K_XL 1.94GB。移动端推荐 **IQ4_XS 或 Q4_K_M**；想更省内存可 UD-Q3_K_XL。GGUF 来源：Qwen 官方、Unsloth（day-zero、动态量化）、bartowski。
- **无专门"移动端优化"量化**，但 IQ4_XS/Q4_0（online repacking for ARM，build b4282 起自动）对 ARM 更友好。
- **采样参数（Qwen 官方 Qwen3.5-0.8B 卡片 non-thinking 文本任务推荐）**：`temperature=0.7, top_p=0.80, top_k=20, min_p=0.0, presence_penalty=1.5, repetition_penalty=1.0`。**日记汇总要"稳不发散"，建议 temp 取 0.6–0.7、保留 presence_penalty≈1.5 防重复；绝不要用贪心解码（会退化成无尽重复）。**

### 五、GBNF grammar 示例（日记结构）

```gbnf
root ::= "{" ws "\"date\":" ws "\"" date "\"," ws
         "\"summary\":" ws string "," ws
         "\"highlights\":" ws strlist "," ws
         "\"todos\":" ws strlist "," ws
         "\"mood\":" ws mood "}"
date   ::= [0-9] [0-9] [0-9] [0-9] "-" [0-9] [0-9] "-" [0-9] [0-9]
mood   ::= "\"" ("积极"|"平静"|"疲惫"|"焦虑"|"低落") "\""
strlist::= "[" ws (string (ws "," ws string)*)? ws "]"
string ::= "\"" ([^"\\] | "\\" .)* "\""
ws     ::= [ \t\n]*
```
生成后由 App 渲染成 Markdown（YYYY-MM-DD.md + YAML frontmatter）写入 Obsidian 库。用 JSON schema → GBNF 自动转换亦可（llama.cpp 内置 `json-schema-to-grammar`）。注意：grammar 不能 100% 保证 JSON 完整（模型可能在闭合前耗尽 token），需设合理 max_tokens 并对截断做校验/重试。

### 六、prompt 设计
- system prompt 用中文明确角色（"你是日记整理助手，把用户当天零散记录整理成结构化 JSON，忠实原意、不虚构"）+ 输出契约（字段说明）。
- 小模型建议给 **1 个 few-shot 示例**提升结构稳定性（与 grammar 双保险）。
- map-reduce：单次输入超过约 n_ctx 的 60%（如 8K ctx 下超 ~4.5K token）时，分段先摘要再合并。

## Recommendations

**阶段 0（决策校正，立即）：** 把默认模型从"Qwen3-4B/1.7B"升级为 **Qwen3.5-4B / Qwen3.5-2B**（默认关 thinking、Apache 2.0、中文更好、256K 上下文）。iOS 默认档定为 **2B**，4B 仅作 8GB+ 高质量可选项。用户"统一 GGUF + 一套 prompt/grammar"的核心诉求完全保留。

**阶段 1（MVP，2–4 周）：**
- 交付：单输入框 UI + ObjC++ bridge + 官方 XCFramework 集成 + Qwen3.5-2B Q4_K_M（首启下载）+ 固定 prompt 生成纯文本日记 + 写本地 + 导出 md。
- 验收：iPhone 15/16（8GB）真机能稳定生成 500–800 字中文日记不崩；**此阶段就做真机内存/热实测**（`os_proc_available_memory`、`ProcessInfo.thermalState` 打点）。
- 触发降级/fallback 的阈值：可用内存 < 1.5× 模型大小 → 降档；设备 <6GB 或加载失败 → 走 fallback。

**阶段 2（v1，4–8 周）：**
- 交付：GBNF 结构化输出 + Obsidian md+YAML 双写 + 设备分档自动选模型 + 后台断点续传下载器 + 存储管理页 + Android 端（同 GGUF + Vulkan/CPU）。
- 验收：两端结构一致（非逐字节）、6GB 机跑 2B 不被杀、下载可恢复、通过 TestFlight/内测审核。
- **在 App Store distribution 构建上验证 entitlement 真实内存上限**（避免"本地能跑上架崩"）。

**阶段 3（v2）：**
- 交付：云端兜底（默认关、用户显式开、内容脱敏提示）+ 4B 高质量档 + map-reduce 长文 + fallback 到 Foundation Models（仅 iOS 不支持本地的设备）。
- 验收：云端开关行为正确、隐私文案合规、崩溃率 < 1%。

**保留 fallback 的触发条件（强烈建议保留）：** 设备 RAM ≤ 4GB、或 `os_proc_available_memory()` 不足、或模型加载/Metal 编译失败——此时 iOS 端回退到 Apple Foundation Models（零内存开销、系统托管、iOS 26+）或云端。这不违背用户"统一 llama.cpp"的主张：主路径仍是 llama.cpp，fallback 只兜底极端情况，能显著降低崩溃率和差评。**改变建议的信号：** 若 Qwen3.5-2B 在 6GB 机实测崩溃率仍高，应把 iOS 默认降到 1.7B/1B 或对 6GB 机直接走 fallback。

## Caveats
- **性能数字多为不同设备/不同模型的实测或估算，已在表中标注来源设备。** 目前缺少 Qwen3.5-4B Q4_K_M 在具体 iPhone 上的公开逐机型 tg/pp 实测；表中用 Llama3.2-3B/Gemma3-4B/phi2-3B 作同量级代理，4B 实际速度会比 3B 略慢、内存略高。上线前须在目标机型自测（PocketPal 内置 benchmark + 其公开 leaderboard 可作对照）。
- **entitlement 的实际提升量（6GB→4.5GB、8GB→6GB）来自社区实测，非 Apple 官方承诺，且可能随 iOS 版本变化；"开发签名能跑、App Store 版回落"的现象需重点验证。**
- Qwen3.5/3.6 为 2026 年新发布，GGUF 生态（尤其小尺寸的 llama.cpp 完整支持、thinking 关闭稳定性）仍在快速演进，`enable_thinking=false` 在 llama.cpp 的生效路径存在版本相关 bug，须锁定并回归测试具体 llama.cpp build。
- 跨端"输出一致性"不可能做到逐字节；本报告的一致性方案是"结构一致 + 语义等价"，通过 grammar 保证。
- 云端兜底涉及日记隐私，务必默认关闭、显式开启、明确脱敏与数据留存政策。
- Metal 相关崩溃（shader 编译失败、OOM 静默输出损坏）在旧机型/新 OS 组合上仍有报告，需在多机型矩阵回归。