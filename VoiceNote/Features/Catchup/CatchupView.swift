import SwiftUI

// 待补的一天(骨架用本地示例;真实实现从"有条目但无成稿"的日期聚合)
struct CatchupDay: Identifiable {
    let id = UUID()
    var date: String
    var count: String
    var preview: String
    var status: String
    var selected: Bool

    static var samples: [CatchupDay] {
        [
            CatchupDay(date: "2026.08.10", count: "6 条", preview: "提案初稿、和设计对齐、晚上加了会班。", status: "待补", selected: true),
            CatchupDay(date: "2026.08.09", count: "3 条", preview: "周末,买菜,顺手修了自行车。", status: "待补", selected: true),
            CatchupDay(date: "2026.08.07", count: "8 条", preview: "出差,高铁上想了很多事。", status: "待补", selected: false),
            CatchupDay(date: "2026.08.05", count: "4 条", preview: "看了场电影,回来写了几句。", status: "待补", selected: false),
        ]
    }
}

struct CatchupView: View {
    @Environment(Router.self) private var router
    @State private var days = CatchupDay.samples
    @State private var running = false

    private var selectedCount: Int { days.filter(\.selected).count }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                topBar
                HRule()
                intro
                HRule()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($days) { $day in
                            dayRow($day)
                            HRule()
                        }
                    }
                }
                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Space.s3) {
            Button("返回") { router.go(.history) }.buttonStyle(GhostButton())
            Text("补稿").font(.heading(20))
            Spacer()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("补稿会逐天在本机生成正文,每天约 1–2 分钟。默认排在充电且连 Wi-Fi 的夜间进行,不占用你现在的记录。")
                .font(.serifBody(13.5)).lineSpacing(4).foregroundStyle(DC.neutral700)
            HStack(spacing: Space.s2) {
                Button("最近 7 天") { setAll(true) }.buttonStyle(SecondaryButton())
                Button("全部") { setAll(true) }.buttonStyle(SecondaryButton())
                Button("手动挑") { setAll(false) }.buttonStyle(GhostButton())
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func dayRow(_ day: Binding<CatchupDay>) -> some View {
        Button { day.wrappedValue.selected.toggle() } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                checkbox(day.wrappedValue.selected)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(day.wrappedValue.date) · \(day.wrappedValue.count)")
                        .font(.serifBody(14)).monospacedDigit()
                    Text(day.wrappedValue.preview)
                        .font(.serifBody(12.5)).foregroundStyle(DC.neutral700).lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(day.wrappedValue.status)
                    .font(.serifBody(11.5))
                    .foregroundStyle(day.wrappedValue.status == "待补" ? DC.neutral600 : DC.accent700)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func checkbox(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: Radius.sm)
            .fill(on ? DC.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(on ? DC.accent : DC.neutral400, lineWidth: 1))
            .frame(width: 16, height: 16)
            .overlay {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DC.bg)
                }
            }
            .padding(.top, 2)
    }

    private var bottomBar: some View {
        VStack(spacing: Space.s2) {
            if running {
                HStack(spacing: Space.s2) {
                    ProgressView().controlSize(.mini)
                    Text("正在本机补稿 · \(selectedCount) 天排队中")
                        .font(.serifBody(13)).foregroundStyle(DC.accent700)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { run() } label: {
                Text(running ? "补稿进行中…" : "开始补稿 · \(selectedCount) 天")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
            .disabled(selectedCount == 0 || running)
            .opacity(selectedCount == 0 || running ? 0.45 : 1)
            Text("补稿只读你自己的条目,全程本机")
                .font(.serifBody(11.5)).foregroundStyle(DC.neutral600)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s2)
        .background(DC.neutral100)
        .overlay(alignment: .top) { HRule() }
    }

    private func setAll(_ v: Bool) {
        for i in days.indices { days[i].selected = v }
    }

    private func run() {
        running = true
        for i in days.indices where days[i].selected { days[i].status = "排队中" }
    }
}

#Preview {
    CatchupView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
