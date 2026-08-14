import Foundation

/// 封装 LlamaBridge:加载本地 Qwen GGUF,用 chat template + GBNF grammar 生成结构化日记 JSON。
/// actor 保证串行访问(同一模型上下文不可并发)。
actor LlamaDiaryEngine {
    static let shared = LlamaDiaryEngine()

    private let bridge = LlamaBridge()
    private var loadedPath: String?

    /// 模型存放路径:Application Support/Models/Qwen3-1.7B-Q4_K_M.gguf
    nonisolated static var modelURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Models/Qwen3-1.7B-Q4_K_M.gguf")
    }

    nonisolated static var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    private func ensureLoaded() -> Bool {
        let path = Self.modelURL.path
        if bridge.isLoaded, loadedPath == path { return true }
        guard FileManager.default.fileExists(atPath: path) else {
            AppLog.log("llama: 模型文件不存在 \(path)")
            return false
        }
        // llama.cpp 全部日志落盘 Documents/llama.log(真机可用 devicectl 拉回)
        let llamaLog = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("llama.log")
        LlamaBridge.redirectLlamaLog(toFile: llamaLog.path)
        AppLog.log("llama: 开始加载模型(含后端重建)")
        let t0 = Date()
        let ok = bridge.loadModel(atPath: path, contextSize: 4096)
        AppLog.log("llama: 加载\(ok ? "成功" : "失败") 耗时 \(String(format: "%.1f", -t0.timeIntervalSinceNow))s")
        loadedPath = ok ? path : nil
        return ok
    }

    /// 把当天条目整理成成稿。失败返回 nil(调用方降级)。
    func makeDraft(entries: [(time: String, text: String)], date: Date) -> DiaryNote? {
        AppLog.log("整理今日: 开始, \(entries.count) 条")
        guard ensureLoaded() else { return nil }
        let lines = entries.map { "\($0.time) \($0.text)" }.joined(separator: "\n")
        let user = "今天的零散记录：\n\(lines)\n请把以上整理成结构化日记 JSON。/no_think"

        let t0 = Date()
        guard let raw = bridge.generate(withSystem: Self.systemPrompt, user: user,
                                        grammar: Self.grammar, maxTokens: 1500) else {
            AppLog.log("整理今日: 生成失败(decode 中断/后端错误), 耗时 \(String(format: "%.0f", -t0.timeIntervalSinceNow))s, 详见 llama.log")
            return nil
        }
        AppLog.log("整理今日: 生成完成, 耗时 \(String(format: "%.0f", -t0.timeIntervalSinceNow))s, 输出 \(raw.count) 字")
        guard let json = Self.extractJSONObject(raw) else {
            AppLog.log("整理今日: JSON 提取失败(输出未闭合/被截断), 开头: \(String(raw.prefix(120)))")
            return nil
        }
        guard let data = json.data(using: .utf8),
              let d = try? JSONDecoder().decode(LlamaDraft.self, from: data)
        else {
            AppLog.log("整理今日: JSON 解析失败, 开头: \(String(json.prefix(120)))")
            return nil
        }
        AppLog.log("整理今日: 成稿解析成功, \(d.sections.count) 节")

        let secs = d.sections.enumerated().map { i, s in
            DiarySection(no: String(format: "%02d", i + 1), title: s.title, body: s.body, fromLabel: "")
        }
        return DiaryNote(date: date, title: d.title, moodLabel: d.mood, quote: d.quote,
                         sections: secs, tags: d.tags, people: d.people, places: d.places,
                         sourceLabel: "本机 · Qwen3-1.7B")
    }

    /// 轻润色一段口语文字(断句/去口水词/修同音错字,保持原意与专名)。失败返回 nil。
    func polish(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ensureLoaded() else { return nil }
        let sys = """
        你是文字润色助手。把用户这段语音转写的口语文字整理成通顺的书面中文。
        只做:断句与加标点、去掉口水词(嗯、那个、就是说、然后就)、修正明显的同音错别字。
        严格保持原意,不增删信息,不改写人名、地名等专有名词。只输出润色后的文字,不要任何解释。
        """
        guard let raw = bridge.generate(withSystem: sys, user: trimmed + " /no_think",
                                        grammar: nil, maxTokens: 400) else { return nil }
        // Qwen3 关思考后仍会输出空的 <think></think>,无 grammar 约束时会漏进结果,剥掉
        let cleaned = Self.stripThink(raw)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// 去掉 Qwen 输出中的 <think>…</think> 块(含未闭合的残留标签)
    nonisolated static func stripThink(_ s: String) -> String {
        var out = s
        while let start = out.range(of: "<think>"),
              let end = out.range(of: "</think>", range: start.upperBound..<out.endIndex) {
            out.removeSubrange(start.lowerBound..<end.upperBound)
        }
        out = out.replacingOccurrences(of: "<think>", with: "")
        out = out.replacingOccurrences(of: "</think>", with: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - JSON 模型
    private struct LlamaDraft: Codable {
        var title: String
        var mood: String
        var quote: String
        var sections: [Sec]
        var tags: [String]
        var people: [String]
        var places: [String]
        struct Sec: Codable { var title: String; var body: String }
    }

    /// 从生成文本取第一个平衡的 JSON 对象(grammar 已约束,这里再兜底)
    nonisolated static func extractJSONObject(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0, inStr = false, esc = false
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if inStr {
                if esc { esc = false }
                else if c == "\\" { esc = true }
                else if c == "\"" { inStr = false }
            } else if c == "\"" { inStr = true }
            else if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { return String(s[start...i]) } }
            i = s.index(after: i)
        }
        return nil
    }

    // MARK: - Prompt & Grammar(阶段1 命令行验证过,两端复用)
    static let systemPrompt = """
    你是日记整理助手。把用户当天的零散记录整理成一篇结构化中文日记，只输出 JSON。

    严格遵守：
    1. 按主题逻辑分节（例如 工作、关系、状态、阅读），把相关的多条记录合并进同一节；按内容多少分 2 到 5 节，不要一条一节，也不要按时间先后分节。必须覆盖每一条记录提到的事件，一件都不能遗漏。
    2. 每节 body 是连贯自然的成稿段落，不要保留时间戳（如 08:12 这种数字）。
    3. 人名、地名等专有名词照抄原文，不得改写或杜撰。
    4. quote 从当天记录本身提炼一句最有感受的话，不要套用现成名言。
    5. mood 用简短中文；tags 给 3 到 5 个主题词，不带井号。
    只输出 JSON，不要任何解释或思考过程。
    """

    static let grammar = #"""
    root ::= "{" ws "\"title\":" ws string "," ws "\"mood\":" ws string "," ws "\"quote\":" ws string "," ws "\"sections\":" ws sections "," ws "\"tags\":" ws strlist "," ws "\"people\":" ws strlist "," ws "\"places\":" ws strlist ws "}"
    sections ::= "[" ws section (ws "," ws section){1,4} ws "]"
    section ::= "{" ws "\"title\":" ws string "," ws "\"body\":" ws string ws "}"
    strlist ::= "[" ws (string (ws "," ws string)*)? ws "]"
    string ::= "\"" ([^"\\] | "\\" .)* "\""
    ws ::= [ \t\n]*
    """#
}
