# 语音口述日记 → 本地小模型自动整理笔记 App：技术调研与实现方案（2026年8月）

## TL;DR
- **完全可行，且比你原来的方案简单一个数量级**：因为你不再需要本地模型读写整个 Obsidian 库（不需要文件系统 agent、function calling、MCP），App 只需管好三件事——存文本条目、调用一次模型做「多条→一篇」的摘要、把结果写到两个地方。iOS 和 Android 都能做，且两端可跨端。
- **推荐技术栈**：iOS 用 Apple Foundation Models（iOS 26+，零模型体积、系统级、官方支持简体中文）为主、Gemini 2.5 Flash-Lite（$0.10/$0.40 每百万 token）云端兜底；Android 因为「系统级中文摘要」这条路 2026 年仍不成熟（ML Kit Summarization 官方仅支持英日韩、Gemini Nano v3 只覆盖极少数 2026 旗舰），改用 **llama.cpp + Qwen3-4B (Q4_K_M) GGUF** 自带推理引擎，中文质量最好且跨端一致。业务逻辑层可用 **Kotlin Multiplatform (KMP)** 共享，UI 与推理层各写原生。
- **务必先做云端 MVP**：日记内容零散、模型质量是产品成败关键，先用 Gemini/通义等云端 API 跑通「模板汇总」这一步（每天成本远低于 1 分钱），验证 prompt 和产品逻辑，再逐步替换为本地模型。云端兜底必须是用户显式开启的选项。

---

## Key Findings

1. **这个需求本质上是一个「单次、有界的摘要任务」**，而不是 agent。输入是当天几十条短文本（几千 token 量级），输出是一篇结构化 markdown。这正是当前所有端侧小模型（1B–4B）最擅长、也是各家系统级 API 明确主推的场景。

2. **iOS 端最省事的路是 Apple Foundation Models**，但有三个硬约束必须设计进去：①仅 iPhone 15 Pro / 16 / 17 全系等 A17 Pro 及以上机型可用，iPhone 14 及更早无法使用；②上下文窗口仅 4096 token（含指令+输入+输出，由 iOS 26.4 起可通过 `SystemLanguageModel.contextSize` 读取，官方 WWDR 工程师确认「context window of 4096 tokens per language model session, and all the input and response contribute tokens」），一天条目多时必须分段摘要；③内置 guardrails 无法关闭，日记里的敏感内容（情绪、冲突、健康）可能被误伤。它官方支持简体中文，但 Apple 自己承认非英语质量偏弱。

3. **Android 端「系统级中文摘要」这条路 2026 年基本走不通**：Google 官方文档明确「The GenAI Summarization API supports English, Japanese, and Korean」（且单次最多摘要 3,000 英文词），无中文；更灵活的 Prompt API 没有公布任何语言支持列表，且 Gemini Nano v3（Gemini Intelligence）设备门槛极高（12GB RAM、旗舰芯片，Pixel 9 / Galaxy S25 都被排除，仅 Pixel 10 / Galaxy S26 / OnePlus 15 等 2026 旗舰支持）。因此 Android 必须走「自带推理引擎 + 自带模型」路线。

4. **模型选型对中文用户结论明确：选 Qwen 系列，不要指望 Gemma 的中文**。Qwen3-4B（Q4_K_M 约 2.5GB）在中端以上安卓旗舰和 iPhone 上可跑，中文摘要质量足够；Qwen3-1.7B 是更轻的保底。据 Qwen3 技术报告（arXiv:2505.09388），Qwen3-8B/4B/1.7B-Base 在半数以上基准上超越更大的 Qwen2.5-14B/7B/3B-Base（尤其 STEM 与代码方向）。两者均为 Apache 2.0，商用无障碍。Gemma 4 已改为 Apache 2.0，但 Gemma 系列中文能力相对弱，不是中文日记的首选。

5. **写 Obsidian 双端都有成熟的官方授权持久化机制**：iOS 用 UIDocumentPicker 选文件夹 + bookmark 持久化（注意：iOS 严格来说不支持「security-scoped」bookmark，用普通 bookmark 即可持久化目录访问）；Android 用 `ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission` + DocumentFile。关键风险是同步冲突——绝不能让 App 和 Obsidian Sync/iCloud 同时抢写同一个文件。

6. **KMP 在 2026 年已是生产就绪**（JetBrains 于 2023 年 11 月发布稳定版；生产用户含 Netflix、Cash App、McDonald's、VMware、Electrolux、Philips 等——McDonald's 的 KMP 应用每月处理约 650 万笔购买、日服约 6900 万顾客；Compose Multiplatform for iOS 也在 2025 年 5 月达到 Stable），适合共享「数据模型 + 本地存储 + prompt 组装 + markdown 生成 + 云端兜底逻辑」，UI 和推理层保持原生。这能把你「两端各写一遍」的重复工作量削减一大块。

---

## Details

### 一、可行性与整体架构

#### 为什么比原方案简单
你原来的设想是「本地模型直接读写 iPhone 上 790MB / 4004 项的 Obsidian 库」，这要求模型/App 具备：遍历文件系统、理解库结构、决定读哪些写哪些——本质是一个带工具调用的 agent，在 iOS 沙盒下几乎不可行。

新需求去掉了所有这些复杂度：

| 原方案需要 | 新方案是否需要 |
|---|---|
| 文件系统遍历 agent | ❌ 不需要 |
| Function calling / 工具调用 | ❌ 不需要 |
| MCP / 读写整个库 | ❌ 不需要 |
| 长上下文理解整库 | ❌ 不需要 |
| 单次有界摘要（几千 token 进，一篇出） | ✅ 只需要这个 |
| 一次目录写入授权 | ✅ 只需要这个 |

模型只做一件纯文本任务：把当天 N 条零散输入按模板汇总成一篇。这是「一次调用、输入输出都可控」的任务，没有任何 agent 循环。

#### 数据流架构

```
[系统/第三方输入法语音听写] 
      │ 用户随手记一条文字
      ▼
[输入框] ──► [本地数据库(SQLDelight/SwiftData/Room)] 存 Entry{id,时间戳,文本,日期}
      │
      │（用户点"生成今日笔记" 或 定时触发）
      ▼
[取出当天所有 Entry] ──► [Prompt 模板组装] ──► [Token 计数]
                                                  │
                       ┌──────────────────────────┤
              token超限？│                          │否
                       ▼                          ▼
              [Map-Reduce 分段摘要]         [单次调用 LLM]
                       │                          │
                       └──────────┬───────────────┘
                                  ▼
                    [本地LLM优先 / 云端兜底路由]
                                  ▼
                    [生成结构化 Markdown + YAML frontmatter]
                                  ▼
              ┌───────────────────┴────────────────────┐
              ▼                                         ▼
   [App内部存一份(可导出/分享)]          [写入用户Obsidian库 YYYY-MM-DD.md]
                                          (授权目录 + 冲突规避)
```

#### 「两端各写一遍」的工作量与 KMP

原生 Swift + Kotlin 两端各写一遍，重复的主要是三块：数据模型/存储、prompt 组装与 markdown 生成、云端兜底 HTTP 逻辑。UI 和本地推理调用天然是平台特定的，无论如何都要写两遍。

**KMP 在 2026 年成熟度**：Kotlin Multiplatform 自 2023 年 11 月起为 Stable，Google 官方推荐用于 Android/iOS 业务逻辑共享，Netflix（2020 年即在 Prodicle 应用中率先采用）、Cash App、McDonald's、VMware、Electrolux、Philips 等在生产环境使用。Compose Multiplatform for iOS 也在 2025 年 5 月达到 Stable。核心库（Ktor 网络、Room/SQLDelight 存储、ViewModel、DataStore 等）都有 KMP 版本。

**建议**：用 KMP 的 `commonMain` 共享——数据模型、SQLDelight 数据库、prompt 模板逻辑、token 估算、markdown/frontmatter 生成、云端兜底客户端（Ktor）、降级路由的判定逻辑。**不要**用 Compose Multiplatform 强行共享 UI（你明确要原生），iOS 用 SwiftUI、Android 用 Jetpack Compose。本地推理层用 `expect/actual` 声明接口：iOS 的 actual 调 Foundation Models / MLX，Android 的 actual 调 llama.cpp JNI。这样共享层可覆盖大约一半代码量，且把最容易出 bug 的存储/格式化逻辑只写一次。

> 取舍提示：如果你更想保持「纯粹两端原生、零 Kotlin 依赖进 iOS 工程」的干净度，也可以两端各写。鉴于本 App 逻辑层很薄（就是存储+字符串拼接+一个 HTTP 调用），不上 KMP 的重复成本其实可以承受。KMP 的收益在于「模板/frontmatter 规则改一次两端同步」，这对一个会长期迭代模板的日记 App 有价值。

---

### 二、iOS 端本地推理方案对比

| 方案 | 模型体积/来源 | iPhone 速度 | 中文摘要质量 | 集成难度 | App体积影响 | 关键坑 |
|---|---|---|---|---|---|---|
| **Apple Foundation Models** (iOS26+) | 0（系统自带~3B） | 首token可用，短任务够 | 官方支持简中，但 Apple 承认非英语偏弱 | 最低（几行 Swift） | 0 | 4096 token 上限；仅A17Pro+；guardrails无法关；iPhone14及以前不可用 |
| **MLX / MLX Swift** | 需下载(Qwen3-4B ~2.5GB) | Qwen 3.5 2B 约 61 tok/s(iPhone17Pro) | 取决于模型(Qwen 中文好) | 中（mlx-swift-examples） | 大（内置或下载模型） | 内存峰值高；模型分发 |
| **llama.cpp / LLM.swift** | GGUF(可与安卓共用文件) | Qwen 3.5 2B 约 39 tok/s | 取决于模型 | 中 | 大 | 需自己管理下载与内存 |
| **LiteRT-LM (Swift API)** | .litertlm(Gemma 系为主) | Gemma 4 E2B 约 55 tok/s(最快) | Gemma 中文弱 | 中 | 大 | 模型目录以 Gemma 为主，Qwen 支持有限 |
| **Core ML + Stateful** | 转换后 INT4/INT8 | Qwen 3.5 2B 约 27.9 tok/s | 取决于模型 | 高（转换麻烦） | 小（约 241MB 可跑 2B 级，内存最省） | 转换路径复杂 |

（以上 tokens/s 来自开发者在 iPhone 17 Pro / A19 Pro 上的实测博客，为参考量级。）

**结论（iOS）**：主用 **Apple Foundation Models**——零体积、零下载、系统优化、官方支持简体中文，且你的任务（摘要）正是它主推场景。当机型不支持或质量不达标时，走云端兜底。如果你想要「不依赖 Apple Intelligence、老机型也能本地跑」的第二档，再考虑内置 MLX 或 llama.cpp + Qwen3-4B（与安卓共用同一个 GGUF）。

**Foundation Models 核实要点**：
- 上下文窗口 4096 token（系统模型），指令+prompt+输出都算在内；超限抛 `GenerationError.exceededContextWindowSize`。iOS 26.4 起新增 `contextSize` 属性与 `tokenCount(for:)` 方法用于精确记账。注意：中文是 1 token ≈ 1 字符，所以一天几十条中文很容易接近上限，需分段。
- 可用性检查：`SystemLanguageModel.default.availability`，不可用时优雅降级到云端或禁用；应「把模型当作 feature flag，而非保证」。
- 结构化输出：`@Generable` + `@Guide` 保证类型安全输出（可直接产出结构化字段再拼 markdown）。
- guardrails 无法禁用，且已知有误报（`guardrailViolation` 有时在意外内容上触发）——对日记这种可能含负面情绪/健康/冲突的内容是真实风险，务必捕获该错误并回退到云端或提示用户。
- 支持简体中文（iOS 26.1 起还加了繁体中文，Apple 研究报告将中文归入其 15 种目标语言）；但 Apple 官方明确指出「非英语质量普遍更弱」，务必用真实中文日记做本地化评测。也可运行时读 `SystemLanguageModel.default.supportedLanguages` 确认返回 `zh (CN)`。
- App Store：模型是系统的，无需打包权重、无需下载，审核层面最省心。

---

### 三、Android 端本地推理方案对比

| 方案 | 模型/分发 | 设备门槛 | 中文能力 | 关键结论 |
|---|---|---|---|---|
| **ML Kit GenAI Summarization** | Gemini Nano(系统) | 需 AICore + Nano | ❌ 官方仅英/日/韩 | 中文不支持，直接排除 |
| **ML Kit GenAI Prompt API** | Gemini Nano(系统) | 极高(见下) | ⚠️ 官方未列语言 | 设备覆盖太窄，中文无保证 |
| **Gemini Nano v3 / Gemini Intelligence** | 系统 | 12GB RAM+旗舰芯片，仅2026旗舰 | 底层 Gemma 3n 架构多语言 | 覆盖面太小，不能作主路 |
| **llama.cpp via JNI** | GGUF(自带) | 中端旗舰(4-8GB可跑1.7B，8-12GB跑4B) | ✅ 取决于模型 | **推荐主路**，Qwen 中文好，跨端共用 |
| **LiteRT-LM (Android)** | .task/.litertlm | GPU/NPU加速 | Gemma 中文弱 | Gemma 系最快，但中文非首选 |
| **ONNX Runtime GenAI** | ONNX | CPU/GPU | 取决于模型 | 可选，生态不如 llama.cpp |
| **MLC LLM Android** | 编译后 | GPU | 取决于模型 | 可选 |

**关键事实**：
- Google 官方文档明确「The GenAI Summarization API supports English, Japanese, and Korean」，无中文；且单次最多摘要 3,000 英文词。
- MediaPipe LLM Inference API（Android/iOS）已进入 maintenance-only / deprecated（Web 除外），官方建议迁移到 LiteRT-LM。
- Gemini Nano v3 / Gemini Intelligence 设备门槛：12GB RAM、旗舰芯片、Nano v3。Pixel 9 系列、Galaxy S25 系列、Galaxy Z Fold 7 都被排除，只有 Pixel 10、Galaxy S26、OnePlus 15 等 2026 机型支持。
- 较老的 Gemini Nano（v2，通过 AICore）覆盖 Pixel 8/9、Galaxy S24/S25 等，但 Summarization API 仍限英日韩，Prompt API 语言无官方保证。

**结论（Android）**：走 **llama.cpp (JNI) + Qwen3-4B (Q4_K_M) GGUF**。这样中文质量最好、设备覆盖最广（不依赖旗舰专用 NPU），而且能和 iOS 端共用同一个 GGUF 文件和同一套 prompt/grammar，是跨端一致性最好的路线。中端机降级到 Qwen3-1.7B。LiteRT-LM 可作为 Gemma 加速的备选，但中文场景不推荐。

---

### 四、模型选型

#### 针对「中文零散口述→结构化日记」的推荐

| 模型 | 参数 | Q4体积 | 中文 | 许可证 | 定位 |
|---|---|---|---|---|---|
| **Qwen3-4B** | 4B | ~2.5GB | 强 | Apache 2.0 | **首选**，旗舰机本地主力 |
| **Qwen3-1.7B** | 1.7B | ~1.1GB | 较强 | Apache 2.0 | 中端机/保底 |
| Gemma 3 1B / Gemma 4 E2B | 1B/~2B(E2B) | ~1GB | 弱 | Gemma ToU / Apache2.0(Gemma4) | 仅在走 LiteRT 加速时考虑 |
| Phi-4-mini | ~3.8B | ~2.3GB | 中 | MIT | 备选 |
| Apple 系统模型 | ~3B | 0 | 官方支持但偏弱 | 系统 | iOS 专用主路 |

**中文能力**：Qwen 系列由阿里训练，中文明显强于 Gemma。据 Qwen3 技术报告，Qwen3-4B-Base 在半数以上基准上超越更大的 Qwen2.5-7B-Base。对「把口语化中文碎片整理成通顺日记」这种任务，Qwen3-1.7B/4B 足够。

**量化**：Q4_K_M 是体积/质量的甜点，4B 约 2.5GB、1.7B 约 1.1GB。iPhone 建议留 OS 2-4GB 余量，8GB 机型跑 4B 偏紧、12GB 机型舒适；中端安卓 4-8GB 建议 1.7B。

**上下文长度评估**：一天零散输入通常几十条、每条几十字，总量多在 1000–4000 中文字，即 1000–4000 token（中文近似 1 字 1 token）。
- llama.cpp/MLX 跑 Qwen3（128K 上下文）完全够，单次摘要即可。
- Apple Foundation Models 只有 4096 token，中文场景很容易触顶，需要 **Map-Reduce 分段摘要**：把当天条目分批（如每批 1500 token）各自摘要成小节，再把各小节汇总成最终日记。

**结构化 markdown 稳定输出**：
- Apple：用 `@Generable` 定义结构体字段（如 highlights / todos / mood），由框架保证类型安全，再拼成 markdown。
- llama.cpp：用 GBNF grammar / JSON schema 约束解码（`--grammar-file` 或 server 的 `response_format` json_schema），机械上杜绝非法输出；注意 schema 不会注入 prompt，需在 prompt 里显式描述期望结构。llama.cpp 自带 `json.gbnf` 与 `json_schema_to_grammar` 转换器，grammar mask 的性能开销通常是个位数百分比。
- 实践建议：让模型先自由生成，再用第二次调用抽取为 schema；或直接约束输出 JSON，App 端再渲染成模板 markdown（比让模型直接吐 markdown 更稳）。

---

### 五、云端兜底方案设计

**降级触发条件**（按优先级）：
1. 设备不支持本地模型（iPhone 14 及以前 / 低配安卓）。
2. 本地初始化或推理失败、内存不足（OOM 前拦截）。
3. 本地输出质量校验失败（如 JSON 解析失败、长度异常、guardrail 误伤）。
4. 用户手动选择「用云端生成更好的版本」。

**推荐云端 API 与价格**（此任务每天 1–2 次、输入几千 token，成本极低）：

| API | 输入价/百万token | 输出价/百万token | 备注 |
|---|---|---|---|
| **Gemini 2.5 Flash-Lite** | $0.10 | $0.40 | 最便宜；但 Google 定于 **2026-10-16 退役** |
| Gemini 3.1 Flash-Lite | $0.25 | $1.50 | 2.5 退役后的接替，仍极便宜 |
| Gemini 3.6 Flash | $1.50 | $7.50 | 质量更高的中档 |

以 Flash-Lite 计，每天输入 4000 token + 输出 1000 token ≈ $0.0008/天，一年不到 $0.30。成本完全可忽略。中文用户也可考虑国内直连的通义千问/DeepSeek/智谱等 API（同样便宜且中文强），规避网络问题。

**隐私**：日记高度敏感。云端兜底**必须**做成默认关闭、用户显式开启的开关，并在 UI 明确说明「开启后当天文本会上传到 X 服务生成」。本地优先是隐私卖点，别默默上传。

---

### 六、写入 Obsidian 库（两端都要）

#### iOS
**主方案：UIDocumentPicker 选目录 + bookmark 持久化**
- 用 `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])` 让用户选中 Obsidian vault（或其中的 Daily Notes 目录）。
- 回调里 `url.startAccessingSecurityScopedResource()`，然后 `url.bookmarkData()` 生成 bookmark，存入 UserDefaults/SwiftData。
- 下次启动 `URL(resolvingBookmarkData:bookmarkDataIsStale:)` 恢复；若 `isStale == true` 必须重新生成并保存，否则会丢访问权。
- **重要澄清**：Apple DTS 官方明确「iOS 技术上不支持 security-scoped bookmarks（那是 macOS 的）」，但只要你曾获得该资源访问权，用**普通 bookmark** 即可跨启动持久化目录访问。写文件前后配对调用 start/stopAccessingSecurityScopedResource。
- 代码要点：
```swift
// 保存
let didAccess = url.startAccessingSecurityScopedResource()
defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
let bookmark = try url.bookmarkData() // iOS 用普通 bookmark
UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
// 恢复
var stale = false
let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
if stale { /* 重新生成并保存 */ }
```

**iCloud Drive 中的 vault**：如果用户的库在 iCloud Drive，可以通过 iCloud Documents 访问，但更简单可靠的仍是让用户用 DocumentPicker 直接选中那个 iCloud 目录（Files app 会呈现 iCloud 位置）。注意 iCloud 占位文件（`.icloud`）需先触发下载。

**备选方案**：Obsidian Advanced URI / x-callback-url 可以用 URL scheme 让 Obsidian 自己创建/追加笔记（不用直接写文件，天然避开冲突），但依赖用户装了 Advanced URI 插件。

**最低保底**：Share Sheet / 导出到 Files，用户手动放进库。

#### Android
**Storage Access Framework**
- `Intent(ACTION_OPEN_DOCUMENT_TREE)` 让用户选 vault 目录。
- 回调里 `contentResolver.takePersistableUriPermission(uri, FLAG_GRANT_READ|WRITE)` 持久化授权（跨重启有效）。
- 用 `DocumentFile.fromTreeUri(context, uri)` 拿到目录，`createFile("text/markdown", "2026-08-13.md")` 或找已存在文件，`contentResolver.openOutputStream()` 写入。
- 代码要点：
```kotlin
val uri = result.data!!.data!!
contentResolver.takePersistableUriPermission(
    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
val tree = DocumentFile.fromTreeUri(context, uri)!!
val existing = tree.findFile("2026-08-13.md")
val file = existing ?: tree.createFile("text/markdown", "2026-08-13.md")!!
contentResolver.openOutputStream(file.uri, "wt")!!.use { it.write(md.toByteArray()) }
```
- **Android 11+ 分区存储**：SAF 是官方推荐路径，无需 `MANAGE_EXTERNAL_STORAGE` 危险权限，也能写到用户选的任意目录（含被其他 app 管理的目录）。

#### Obsidian Daily Notes 约定
- 文件名：`YYYY-MM-DD.md`（与 Daily Notes 插件默认一致）。
- YAML frontmatter 示例：
```markdown
---
date: 2026-08-13
tags: [daily, voice-journal]
created: 2026-08-13T22:30:00
source: VoiceJournalApp
---

## 今日汇总
...

## 碎碎念原文
- 08:12 ...
- 13:40 ...
```
- 建议保留「原始条目 + AI 汇总」两部分，既可读又可追溯。

#### 同步冲突规避（关键风险）
用户的库若通过 iCloud / Obsidian Sync 同步，App 直接写文件可能与同步引擎抢写，产生 `xxx.conflict-时间戳.md` 冲突副本，严重时丢内容。规避策略：
1. **只在生成时写一次**，不做持续后台写。写之前先读现有文件、在内存合并、一次性覆盖写。
2. **追加而非覆盖**：若当天文件已存在，优先「在指定标题下追加」而不是整文件重写，减少与同步的冲突面。
3. **写完提示用户**「已写入，请等 Obsidian 同步完成再在别处编辑」。
4. 文档社区共识：**一个库只用一种同步机制**（不要同时用 iCloud + Obsidian Sync，或 Syncthing + Dropbox），否则「两个系统各按各的节奏写同一批文件，谁慢谁的版本被覆盖」。
5. App 自己那份存在 App 沙盒内（不参与用户的同步），作为可靠副本和导出源。

---

### 七、UI/交互设计

**极简主界面**：一个顶部输入框（或大号「+」）+ 当天时间线列表（每条带时间戳）+ 底部「生成今日笔记」按钮。生成后弹出可编辑预览，确认后双写。

**快速捕获（提升「随手记」体验，强烈建议做）**：
- iOS：主屏 Widget（点开直接进输入框）、锁屏 Widget、**Action Button / 控制中心**快捷进入、**Share Extension** 接收其他 App 分享的文字、App Intents + Siri Shortcuts（「记一条日记」语音触发）。
- Android：**Quick Settings Tile**、桌面小组件、分享菜单接收（`ACTION_SEND` text/plain）。

**语音输入**：如你所愿，App 不做 ASR。输入框聚焦后用户自行点系统键盘的听写键，或用讯飞/搜狗输入法的语音输入。App 只接收文本。

**后台定时自动生成 vs 手动**：
- iOS `BGTaskScheduler` 不保证准时（系统按用电/网络/使用习惯调度），不适合「每天 23:00 准时生成」。
- Android `WorkManager` 相对可靠但也有 Doze 限制。
- **建议**：以「手动触发 + 睡前提醒通知」为主（更可靠、用户有掌控感），把定时自动生成作为可选增强，且生成后只发通知不强写库，让用户确认。

---

### 八、其他实际问题

**App 上架体积与模型分发**：
- iOS 蜂窝下载限制 200MB（用户可在设置里选「始终允许」绕过），但 App 本体塞进 2.5GB 模型不现实。**On-Demand Resources 在 iOS 27 起已废弃**，Apple 建议改用 **Background Assets**。若走 MLX/llama.cpp 自带模型路线，应首次启动后从你的 CDN/Hugging Face 按需下载模型，而非打包进 IPA。走 Foundation Models 则零下载、无此问题。
- Android：用 App Bundle + **Play Asset Delivery**（或首启动下载）分发大模型，别塞进基础 APK。

**模型许可证**：
- Qwen3 系列 **Apache 2.0**，商用/上架/再分发无门槛（保留 license 声明即可）。**这是选 Qwen 的又一理由。**
- Gemma：Gemma 1/2/3 是自定义 Gemma ToU（有再分发条件、需在你的协议里附带使用限制与 Prohibited Use Policy、Google 保留远程限制权），**Gemma 4 已改为 Apache 2.0**。若用 Gemma 3 及以前，须在你的 ToS 里传递使用限制并附 Notice 文件。
- Apple 系统模型：随系统，无需你操心许可证。

**电池与发热**：本地 3-4B 模型生成几百 token，安卓上普遍 15–23 tok/s 且随发热下降，单次生成耗电有体感但因为每天只跑一两次、几秒到十几秒，总体可接受。iPhone 上 2B 级约 40–60 tok/s，更轻快。建议：生成时提示「正在本地生成…」，避免频繁全量重算。

**同类开源项目参考**：
- **VoiceVault**（GitHub PJH720/VoiceVault）：本地 Whisper 转写 + AI 摘要 + Obsidian 兼容导出，桌面端，思路高度契合。
- **Jurnal**（dev.to 项目）：voice-first 日记，本地 Whisper + LLM 整理成带 summary/highlights/intentions 的 markdown，正是你要的「先转写后整理」范式（但你不需要 Whisper，用输入法即可）。
- **NotelyVoice**（GitHub Notely-Voice/NotelyVoice，Compose Multiplatform + Whisper，iOS+Android 全本地，GPL-3.0）：跨端架构可直接参考（虽然它侧重转写）。
- GitHub `voice-notes` topic 下有「Offline iOS voice-first care journal，on-device 转写 + daily summary，SwiftData」等项目，可借鉴 SwiftData + Foundation Models 组合。

**是否先做云端 MVP**：**强烈建议**。理由：产品成败取决于「汇总质量 + prompt 模板」而非推理引擎；云端 API 能让你几天内跑通端到端，快速迭代模板和交互；成本可忽略。验证后再把推理层替换为本地模型（接口用 `expect/actual` 或协议隔离，替换成本低）。

---

## Recommendations

**推荐技术栈组合**：
- **共享层（可选 KMP）**：SQLDelight 存储 + Ktor 云端客户端 + 共享的 prompt 模板/token 估算/markdown+frontmatter 生成/降级路由。
- **iOS**：SwiftUI + SwiftData（若不用 KMP）+ **Apple Foundation Models（主）** + Gemini/通义 Flash-Lite（兜底）+ UIDocumentPicker/bookmark 写库。
- **Android**：Jetpack Compose + Room（若不用 KMP）+ **llama.cpp JNI + Qwen3-4B/1.7B GGUF（主）** + 云端兜底 + SAF 写库。
- **模型**：Qwen3-4B (Q4_K_M) 主力、Qwen3-1.7B 保底，均 Apache 2.0。

**分阶段路线图**：

**MVP（1–2 周，验证产品逻辑）**
- 单平台先做（建议 iOS，因为 Foundation Models 免费省事）。
- 极简 UI：输入框 + 时间线 + 生成按钮。
- 本地 SQLite 存条目。
- 汇总**全部走云端 API**（Flash-Lite 或通义），跑通 prompt 模板。
- 生成结果先只做「App 内展示 + 分享/导出 md」。
- 验收基准：连续用 1 周，AI 汇总质量是否可用、模板是否合理。

**v1（核心成型）**
- 接入 Obsidian 双写（DocumentPicker/SAF + bookmark/持久化授权 + 冲突规避 + frontmatter）。
- iOS 接入 **Foundation Models 本地推理**（含可用性检查、4096 分段摘要、guardrail 错误捕获→云端兜底）。
- 云端兜底做成显式开关。
- 快速捕获：iOS Share Extension + Widget；Android 分享接收 + Tile。
- 验收基准：iPhone 15 Pro+ 上本地生成质量 ≥ 云端 80%，且能稳定写入 Obsidian 不产生冲突副本。

**v2（跨端与增强）**
- Android 端：llama.cpp + Qwen3 GGUF 本地推理，按需下载模型（Play Asset Delivery）。
- （可选）抽出 KMP 共享层，两端复用存储/模板/兜底逻辑。
- 结构化输出用 @Generable / GBNF 约束，模板可自定义。
- 睡前提醒 + 可选定时生成。
- 验收基准：中端安卓（8GB，Qwen3-4B 或降级 1.7B）本地生成可用；两端模板一致。

**会改变建议的阈值**：
- 若你的目标用户多用 iPhone 14 及更早 → 放弃 Foundation Models 作主路，iOS 也改内置 Qwen GGUF。
- 若实测 Foundation Models 中文汇总质量不达标 → iOS 主路切 MLX/llama.cpp + Qwen3-4B。
- 若「一天输入量」经常 > 4000 token → 无论哪端都要实现 Map-Reduce 分段摘要，且更偏向 Qwen（128K 上下文）而非 4096 的 Apple 模型。
- 若 Android 目标机型主要是 2026 旗舰（Pixel 10 / Galaxy S26 等）→ 可评估 ML Kit Prompt API 直接用系统 Gemini Nano，省掉打包模型（但仍需实测中文质量）。

---

## Caveats

- **端侧生态变化极快**：MediaPipe LLM Inference 已转 maintenance-only/deprecated、ODR 在 iOS 27 废弃、Gemini Nano 设备门槛 2026 年大幅抬高——本报告基于 2026 年 8 月的资料，落地前请复核官方文档最新状态。
- **Apple 系统模型中文质量缺乏独立量化基准**：Apple 官方承认非英语更弱，但缺少针对「中文日记摘要」的第三方 benchmark，务必用真实数据自测再决定是否作主路。
- **Foundation Models guardrails 误伤**是真实风险，日记含情绪/健康/冲突内容时可能被拒；必须有兜底路径。
- **tokens/s 数据来自开发者实测博客（iPhone 17 Pro 等）**，你的目标机型/量化格式不同结果会有差异，属参考量级而非承诺。
- **Gemini 2.5 Flash-Lite 定于 2026-10-16 退役**，若上线晚请直接用 3.1 Flash-Lite（$0.25/$1.50）或国内 API。
- **KMP 引入 iOS 工程有一定构建复杂度**（Kotlin/Native、XCFramework、git-LFS、SwiftPM unsafe-flags 等），若团队无 Kotlin 经验，MVP 阶段可先不上 KMP。
- **同步冲突**是这类 App 最容易翻车的点，上线前务必在 iCloud + Obsidian Sync 同时开启的真实环境下做写入冲突测试。
- **ML Kit Prompt API 语言支持无官方文档**：底层 nano-v3 基于 Gemma 3n 架构（多语言），中文*可能*可用，但 Google 未公开承诺，且设备覆盖窄——不要在没有实测的前提下把它当 Android 主路。