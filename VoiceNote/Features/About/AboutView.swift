import SwiftUI

struct AboutView: View {
    @Environment(Router.self) private var router

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                topBar
                HRule()
                ScrollView { content }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("今天") { router.go(.home) }.buttonStyle(GhostButton())
            Spacer()
            Kicker(text: "user.md")
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            // 头部 + 统计
            VStack(alignment: .leading, spacing: Space.s2) {
                Kicker(text: "每天 23:30 自动重算 · 更新后推一条通知")
                Text("关于我").font(.heading(32))
                HStack(alignment: .top, spacing: Space.s6) {
                    stat("214", "条")
                    stat("68", "天")
                    stat("12", "连续")
                }
                .padding(.top, Space.s1)
                streakBar
                Text("这份画像只从你自己的日记里长出来,全程在本机推理。每句判断都能点回它依据的那几天。")
                    .font(.serifBody(13.5)).lineSpacing(4).foregroundStyle(DC.neutral700)
            }

            // 维度
            VStack(alignment: .leading, spacing: Space.s4) {
                dimension("性格倾向", "依据 41 条",
                          "内耗型的自我要求者。你在独处后写得最长,在连续开会的日子几乎不记录;情绪低落时倾向于用「还是做完了」收尾,而不是抱怨。")
                dimension("价值观", "依据 33 条",
                          "把「安静」当作稀缺资源:反复出现的关键词是节奏、独处、不被打断。对关系的判断标准是能否长期说真话,而不是频次。")
                dimension("工作观", "依据 52 条",
                          "你满意的日子几乎都有一个共同点:一天只推进一件难事。当日记里出现三个以上并行任务,第二天的记录多为疲惫与自责。")
            }

            weeklyChange

            VStack(spacing: Space.s2) {
                Button { } label: { Text("导出 user.md").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButton())
                Button { } label: { Text("立即重算 · 约 2 分钟").frame(maxWidth: .infinity) }
                    .buttonStyle(GhostButton())
                Text("重算只读日记正文,不读原始录音;可在设置里改时间或关闭。")
                    .font(.serifBody(12)).foregroundStyle(DC.neutral600).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Space.s4)
    }

    private func stat(_ n: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n).font(.heading(26)).monospacedDigit()
            Text(l).font(.serifBody(11)).tracking(1).foregroundStyle(DC.neutral600)
        }
    }

    private var streakBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<30, id: \.self) { i in
                Rectangle()
                    .fill(([3, 4, 11, 19, 25].contains(i)) ? DC.neutral300 : DC.accent300)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
            }
        }
        .padding(.top, Space.s1)
    }

    private func dimension(_ title: String, _ from: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(title).font(.heading(20))
                Spacer()
                Text(from).font(.serifBody(11.5)).monospacedDigit().foregroundStyle(DC.neutral600)
            }
            .padding(.bottom, Space.s2)
            .overlay(alignment: .bottom) { HRule() }
            Text(body).font(.serifBody(15)).lineSpacing(6)
        }
    }

    private var weeklyChange: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Kicker(text: "本周变化", color: DC.accent700)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
                GridRow {
                    Text("+").foregroundStyle(DC.accent700)
                    Text("开始把跑步写成「清空脑子的手段」,而非任务。")
                }
                GridRow {
                    Text("−").foregroundStyle(DC.neutral500)
                    Text("对搬家/离别的焦虑提及减少(上周 6 次 → 本周 2 次)。")
                        .foregroundStyle(DC.neutral700)
                }
            }
            .font(.serifBody(14))
        }
        .padding(Space.s4)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(DC.divider, lineWidth: 1))
    }
}

#Preview {
    AboutView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
