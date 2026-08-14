import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 把当天条目整理成结构化成稿。
/// 主路:llama.cpp + Qwen3-1.7B(已下载 GGUF,覆盖 iPhone 14 等 A17 以下机型)。
/// 降级:Apple Foundation Models(iPhone 15 Pro+ / iOS 26)。都不可用则返回 nil(调用方用占位)。
enum DiaryGenerator {

    static var isModelAvailable: Bool {
        if LlamaDiaryEngine.isModelDownloaded { return true }
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var sourceLabel: String {
        if LlamaDiaryEngine.isModelDownloaded { return "On-device · Qwen3-1.7B" }
        #if canImport(FoundationModels)
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            return "On-device · Foundation Models"
        }
        #endif
        return "On-device · 占位(未下载模型)"
    }

    static func generate(from entries: [Entry], date: Date) async -> DiaryNote? {
        // 主路:llama.cpp + Qwen(本地 GGUF)。失败自动重试一次:
        // 若因后台 GPU 被拒导致后端中毒,重试时 ensureLoaded 会整体重建后端并重跑
        if LlamaDiaryEngine.isModelDownloaded {
            let items = entries.map { (time: $0.timeLabel, text: $0.text) }
            for _ in 0..<2 {
                if let note = await LlamaDiaryEngine.shared.makeDraft(entries: items, date: date) {
                    return note
                }
            }
        }

        // 降级:Apple Foundation Models(iPhone 15 Pro+)
        #if canImport(FoundationModels)
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let lines = entries.map { "\($0.timeLabel) \($0.text)" }.joined(separator: "\n")
                let prompt = "今天的零散记录(按时间):\n\(lines)\n\n请整理成一篇结构化日记。"
                let draft = try await session.respond(to: prompt, generating: DiaryDraftGen.self).content
                return draft.toDiaryNote(date: date)
            } catch {
                return nil
            }
        }
        #endif

        return nil
    }

    static let instructions = """
    你是日记整理助手。把用户当天的零散记录整理成一篇结构化中文日记。
    要求:忠实原意、不虚构;按逻辑(而非时间)分节,如 工作/关系/状态;
    给出凝练的标题、一句概括当天感受的提要金句、心情、3到5个主题标签,以及涉及的人物与地点。
    """
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
struct DiaryDraftGen {
    @Guide(description: "日记标题,6到12个字,凝练当天基调")
    var title: String
    @Guide(description: "心情,如 平静、疲惫、焦虑、低落、积极,可加简短修饰")
    var mood: String
    @Guide(description: "一句提要金句,概括当天感受,不超过30字")
    var quote: String
    @Guide(description: "按逻辑分节的正文,3节左右")
    var sections: [DiarySectionGen]
    @Guide(description: "3到5个主题标签,不带井号")
    var tags: [String]
    @Guide(description: "当天涉及的人物")
    var people: [String]
    @Guide(description: "当天涉及的地点")
    var places: [String]

    func toDiaryNote(date: Date) -> DiaryNote {
        let secs = sections.enumerated().map { idx, s in
            DiarySection(no: String(format: "%02d", idx + 1),
                         title: s.title, body: s.body, fromLabel: "")
        }
        return DiaryNote(date: date, title: title, moodLabel: mood, quote: quote,
                         sections: secs, tags: tags, people: people, places: places,
                         sourceLabel: "本机 · Foundation Models")
    }
}

@available(iOS 26, *)
@Generable
struct DiarySectionGen {
    @Guide(description: "小节标题,如 工作、关系、状态")
    var title: String
    @Guide(description: "该节正文,连贯的中文段落")
    var body: String
}
#endif
