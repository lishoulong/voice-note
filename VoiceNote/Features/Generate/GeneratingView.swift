import SwiftUI
import SwiftData

struct GeneratingView: View {
    @Environment(Router.self) private var router
    @Query(sort: \Entry.createdAt, order: .forward) private var entries: [Entry]

    private var coordinator: GenerationCoordinator { .shared }

    @State private var progress: Double = 0
    @State private var stageIndex = 0
    @State private var elapsed = 0

    private let stages: [(no: String, label: String, note: String)] = [
        ("01", "读取今天的条目", "结构化输入"),
        ("02", "整理与归纳", "按逻辑分节"),
        ("03", "生成成稿", "润色与提要"),
    ]

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.s8) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Kicker(text: sourceLabel)
                    Text("正在整理今天").font(.heading(34))
                    Text("全程在这台设备上完成,不联网。可以回到今天页继续记录,完成后横幅和通知会提醒你;切出 App 会暂停,回来自动继续。")
                        .font(.serifBody(14)).lineSpacing(4)
                        .foregroundStyle(DC.neutral700)
                }

                VStack(spacing: Space.s3) {
                    ProgressBar(value: progress)
                    HStack {
                        Text(stages[min(stageIndex, 2)].label)
                            .font(.serifBody(14)).foregroundStyle(DC.accent700)
                        Spacer()
                        Text(elapsedLabel).font(.serifBody(12.5)).monospacedDigit()
                            .foregroundStyle(DC.neutral600)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(stages.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(stages[i].no).font(.serifBody(12)).monospacedDigit()
                                .foregroundStyle(DC.neutral600)
                            Text(stages[i].label).font(.serifBody(14.5))
                            Spacer()
                            Text(stages[i].note).font(.serifBody(12))
                                .foregroundStyle(DC.neutral600)
                        }
                        .opacity(i <= stageIndex ? 1 : 0.35)
                        .padding(.vertical, Space.s3)
                        if i < stages.count - 1 { HRule() }
                    }
                }

                HStack(spacing: Space.s3) {
                    Button("后台运行") { router.go(.home) }
                        .buttonStyle(SecondaryButton())
                    Button("回到今天") { router.go(.home) }
                        .buttonStyle(GhostButton())
                }
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .task { await run() }
    }

    private var sourceLabel: String { DiaryGenerator.sourceLabel }

    private var elapsedLabel: String {
        String(format: "已进行 %02d:%02d", elapsed / 60, elapsed % 60)
    }

    private func run() async {
        // 若已有完成待查看的成稿,直接呈现;否则启动(协调器持有任务,离开本页不中断)
        if let n = coordinator.take() {
            router.showResult(n)
            return
        }
        coordinator.start(entries: entries)

        var ticks = 0
        while coordinator.isRunning && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            ticks += 1
            elapsed = ticks / 2
            // 渐近推进到 92%,真实完成时补到 100%
            withAnimation(.linear(duration: 0.4)) {
                progress += (0.92 - progress) * 0.035
            }
            stageIndex = progress < 0.3 ? 0 : (progress < 0.7 ? 1 : 2)
        }
        guard !Task.isCancelled else { return }   // 用户已离开,由横幅/通知承接
        if let n = coordinator.take() {
            withAnimation { progress = 1; stageIndex = 2 }
            try? await Task.sleep(nanoseconds: 250_000_000)
            router.showResult(n)
        }
    }
}

// 细进度条(3px 轨道 + accent 填充)
struct ProgressBar: View {
    var value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DC.neutral300)
                Rectangle().fill(DC.accent)
                    .frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 3)
    }
}

#Preview {
    GeneratingView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
