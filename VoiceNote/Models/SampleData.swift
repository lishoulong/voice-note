import Foundation
import SwiftData

/// 骨架阶段的示例数据:内存态 ModelContainer,每次启动预填,便于直接看到完整界面。
/// TODO: 后续替换为磁盘持久化 container(ModelConfiguration 默认),并做首启 seed 判断。
@MainActor
enum SampleData {
    static let container: ModelContainer = {
        let container: ModelContainer
        do {
            // 默认配置 = 磁盘持久化(Application Support/default.store),重启保留
            container = try ModelContainer(for: Entry.self, DiaryNote.self)
        } catch {
            // 磁盘容器创建失败(如 schema 变更)时回退内存,保证 App 仍能启动
            let mem = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: Entry.self, DiaryNote.self, configurations: mem)
        }
        seedIfNeeded(container.mainContext)
        return container
    }()

    /// 仅在空库(首次启动)时填充示例数据;之后使用真实持久化数据
    static func seedIfNeeded(_ ctx: ModelContext) {
        let entryCount = (try? ctx.fetchCount(FetchDescriptor<Entry>())) ?? 0
        let noteCount = (try? ctx.fetchCount(FetchDescriptor<DiaryNote>())) ?? 0
        guard entryCount == 0, noteCount == 0 else { return }
        todayEntries.forEach { ctx.insert($0) }
        historyNotes.forEach { ctx.insert($0) }
        try? ctx.save()
    }

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9, _ mi: Int = 0) -> Date {
        var comp = DateComponents()
        comp.year = y; comp.month = mo; comp.day = d; comp.hour = h; comp.minute = mi
        return Calendar.current.date(from: comp) ?? .now
    }

    // 今天(2026.08.14)的随手记
    static var todayEntries: [Entry] {
        [
            Entry(createdAt: date(2026, 8, 14, 8, 12),
                  text: "先把提案第三节重写一遍,别拖了。昨晚想的那个结构应该更顺。",
                  voiceSeconds: 14),
            Entry(createdAt: date(2026, 8, 14, 9, 40),
                  text: "巷口那家面馆居然重新开了,中午约了阿哲。"),
            Entry(createdAt: date(2026, 8, 14, 13, 40),
                  text: "妈妈打电话说有点想我,聊了二十分钟,她最近睡得不好。",
                  voiceSeconds: 32),
            Entry(createdAt: date(2026, 8, 14, 21, 15),
                  text: "沿着城南河堤跑了 5 公里,跑完脑子一下就空了,很久没这么静。"),
        ]
    }

    // 历史成稿
    static var historyNotes: [DiaryNote] {
        [
            DiaryNote(date: date(2026, 8, 13, 23, 0), title: "把清单删短", moodLabel: "平静",
                      quote: "做完一件难事,比列十件都强。",
                      sections: [
                        DiarySection(no: "01", title: "工作", body: "只保留了三件事,其余都推到下周。删清单比列清单难,但今天做到了。", fromLabel: "依据 5 条"),
                        DiarySection(no: "02", title: "状态", body: "晚上没有再刷手机,读了几页书就睡了。", fromLabel: "依据 2 条"),
                      ], tags: ["工作", "独处"], savedToDiary: true),
            DiaryNote(date: date(2026, 8, 12, 22, 30), title: "开了一天会", moodLabel: "疲惫",
                      quote: "连轴转的日子,记录会变少。",
                      sections: [
                        DiarySection(no: "01", title: "工作", body: "四个会连着开,中间几乎没有喘息。真正推进的事其实只有一件。", fromLabel: "依据 6 条"),
                      ], tags: ["会议", "疲惫"], people: ["组里"], savedToDiary: true),
            DiaryNote(date: date(2026, 8, 11, 21, 0), title: "河边走了很久", moodLabel: "松弛",
                      quote: "安静是稀缺资源。",
                      sections: [
                        DiarySection(no: "01", title: "关系", body: "和老同学通了很长的电话,聊到能不能长期说真话这件事。", fromLabel: "依据 4 条"),
                        DiarySection(no: "02", title: "状态", body: "沿着河边走了很久,没有目的地。", fromLabel: "依据 3 条"),
                      ], tags: ["朋友", "散步"], people: ["老同学"], places: ["河边"], savedToDiary: true),
        ]
    }

    /// 点「整理今日」后展示的成稿草稿(骨架不真跑模型,用对应设计稿的预置内容)。
    static func makeTodayDraft() -> DiaryNote {
        DiaryNote(
            date: date(2026, 8, 14, 21, 30),
            title: "凉了一点的一天",
            moodLabel: "平静 · 略疲惫",
            quote: "我们其实都在等一个更安静的工作节奏。",
            sections: [
                DiarySection(no: "01", title: "工作",
                             body: "上午把提案第三节从头重写了一遍,换了个更顺的结构,总算不再拖着。一天只推进这一件难事,反而踏实。",
                             fromLabel: "依据 2 条"),
                DiarySection(no: "02", title: "关系",
                             body: "中午和阿哲在重新开张的巷口面馆碰面。下午妈妈打来电话,说有点想我,也说最近睡得不好——聊了二十分钟。",
                             fromLabel: "依据 2 条"),
                DiarySection(no: "03", title: "状态",
                             body: "入夜沿城南河堤跑了 5 公里。跑完脑子一下空了,很久没有这么安静过。",
                             fromLabel: "依据 1 条"),
            ],
            tags: ["写作", "跑步", "家人"],
            people: ["阿哲", "妈妈"],
            places: ["巷口面馆", "城南河堤"],
            sourceLabel: "本机 · Qwen3 1.7B"
        )
    }
}
