import SwiftUI

struct GeneratingView: View {
    @Environment(Router.self) private var router

    @State private var progress: Double = 0
    @State private var stageIndex = 0

    private let stages: [(no: String, label: String, note: String)] = [
        ("01", "读取今天的条目", "结构化输入"),
        ("02", "整理与归纳", "按逻辑分节"),
        ("03", "生成成稿", "润色与提要"),
    ]

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.s8) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Kicker(text: "On-device · Qwen3 1.7B")
                    Text("正在整理今天").font(.heading(34))
                    Text("全程在这台设备上完成,不联网。可以离开此页,完成后通知你。")
                        .font(.serifBody(14)).lineSpacing(4)
                        .foregroundStyle(DC.neutral700)
                }

                VStack(spacing: Space.s3) {
                    ProgressBar(value: progress)
                    HStack {
                        Text(stages[min(stageIndex, 2)].label)
                            .font(.serifBody(14)).foregroundStyle(DC.accent700)
                        Spacer()
                        Text(etaLabel).font(.serifBody(12.5)).monospacedDigit()
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
                    Button("取消") { router.go(.home) }
                        .buttonStyle(GhostButton())
                }
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .task { await run() }
    }

    private var etaLabel: String {
        "约剩 \(max(0, Int((1 - progress) * 40))) 秒"
    }

    private func run() async {
        // 骨架:把本地生成 30–150 秒的等待压缩到 ~4 秒展示;真实实现替换为模型推理进度回调
        for step in 1...30 {
            try? await Task.sleep(nanoseconds: 130_000_000)
            withAnimation(.linear(duration: 0.13)) { progress = Double(step) / 30 }
            stageIndex = min(2, Int(Double(step) / 30 * 3))
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        router.showResult(SampleData.makeTodayDraft())
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
