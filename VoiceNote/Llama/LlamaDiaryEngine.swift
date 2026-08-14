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
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let ok = bridge.loadModel(atPath: path, contextSize: 4096)
        loadedPath = ok ? path : nil
        return ok
    }

    /// 把当天条目整理成成稿。失败返回 nil(调用方降级)。
    func makeDraft(entries: [(time: String, text: String)], date: Date) -> DiaryNote? {
        guard ensureLoaded() else { return nil }
        let lines = entries.map { "\($0.time) \($0.text)" }.joined(separator: "\n")
        let user = "今天的零散记录：\n\(lines)\n请把以上整理成结构化日记 JSON。/no_think"

        guard let raw = bridge.generate(withSystem: Self.systemPrompt, user: user,
                                        grammar: Self.grammar, maxTokens: 800),
              let json = Self.extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let d = try? JSONDecoder().decode(LlamaDraft.self, from: data)
        else { return nil }

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
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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
    1. 按主题逻辑分节（例如 工作、关系、状态），把相关的多条记录合并进同一节；总共 2 到 3 节，不要一条一节，也不要按时间先后分节。
    2. 每节 body 是连贯自然的成稿段落，不要保留时间戳（如 08:12 这种数字）。
    3. 人名、地名等专有名词照抄原文，不得改写或杜撰。
    4. quote 从当天记录本身提炼一句最有感受的话，不要套用现成名言。
    5. mood 用简短中文；tags 给 3 到 5 个主题词，不带井号。
    只输出 JSON，不要任何解释或思考过程。
    """

    static let grammar = #"""
    root ::= "{" ws "\"title\":" ws string "," ws "\"mood\":" ws string "," ws "\"quote\":" ws string "," ws "\"sections\":" ws sections "," ws "\"tags\":" ws strlist "," ws "\"people\":" ws strlist "," ws "\"places\":" ws strlist ws "}"
    sections ::= "[" ws section (ws "," ws section){1,2} ws "]"
    section ::= "{" ws "\"title\":" ws string "," ws "\"body\":" ws string ws "}"
    strlist ::= "[" ws (string (ws "," ws string)*)? ws "]"
    string ::= "\"" ([^"\\] | "\\" .)* "\""
    ws ::= [ \t\n]*
    """#
}
