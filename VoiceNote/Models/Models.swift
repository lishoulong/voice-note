import Foundation
import SwiftData

// MARK: - 随手记条目
@Model
final class Entry {
    var id: UUID
    var createdAt: Date
    var text: String
    /// 有语音听写来源时记录时长(秒);打字条目为 nil
    var voiceSeconds: Int?

    init(id: UUID = UUID(), createdAt: Date, text: String, voiceSeconds: Int? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.voiceSeconds = voiceSeconds
    }

    /// "09:12"
    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: createdAt)
    }

    /// "0:14"
    var voiceLabel: String? {
        guard let s = voiceSeconds else { return nil }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 成稿的一个逻辑分节(按逻辑分节,不按时间)
struct DiarySection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var no: String        // "01"
    var title: String     // "工作" / "关系" / "状态"
    var body: String
    var fromLabel: String // "依据 5 条"

    enum CodingKeys: String, CodingKey { case id, no, title, body, fromLabel }
}

// MARK: - 一天的成稿日记
@Model
final class DiaryNote {
    var id: UUID
    var date: Date
    var title: String
    var moodLabel: String
    var quote: String
    var sections: [DiarySection]
    var tags: [String]
    var people: [String]
    var places: [String]
    var sourceLabel: String
    var savedToDiary: Bool

    init(id: UUID = UUID(),
         date: Date,
         title: String,
         moodLabel: String,
         quote: String,
         sections: [DiarySection],
         tags: [String],
         people: [String] = [],
         places: [String] = [],
         sourceLabel: String = "本机 · Qwen3 1.7B",
         savedToDiary: Bool = false) {
        self.id = id
        self.date = date
        self.title = title
        self.moodLabel = moodLabel
        self.quote = quote
        self.sections = sections
        self.tags = tags
        self.people = people
        self.places = places
        self.sourceLabel = sourceLabel
        self.savedToDiary = savedToDiary
    }

    /// "2026.08.14"
    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }

    var excerpt: String { sections.first?.body ?? "" }
}
