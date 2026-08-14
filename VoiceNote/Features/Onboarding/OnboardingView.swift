import SwiftUI

struct OnboardingView: View {
    @Environment(Router.self) private var router
    @State private var pick = 0   // 0 = 1.7B, 1 = 4B

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.s6) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Kicker(text: "Step 2 / 3")
                    Text("选一个本地模型").font(.heading(34))
                    Text("已探测本机:iPhone 15 · 可用内存 5.4 GB。两档都能跑,随时可在设置里换。")
                        .font(.serifBody(14)).lineSpacing(4).foregroundStyle(DC.neutral700)
                }

                VStack(spacing: Space.s3) {
                    modelCard(index: 0, name: "Qwen3 1.7B", tag: "推荐", tagKind: .accent,
                              desc: "下载 1.5 GB · 峰值内存约 2.1 GB · 单次整理 30–60 秒。日常够用,发热小。")
                    modelCard(index: 1, name: "Qwen3 4B", tag: "更整齐", tagKind: .outline,
                              desc: "下载 2.9 GB · 峰值内存约 3.6 GB · 单次整理 70–150 秒。条目多、想要更好归纳时选它。")
                }

                Spacer(minLength: Space.s6)

                VStack(spacing: Space.s2) {
                    Text("下载在后台进行,期间你可以先开始记录。建议接入 Wi-Fi。")
                        .font(.serifBody(12.5)).foregroundStyle(DC.neutral600).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { router.go(.home) } label: {
                        Text("开始下载并进入").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButton())
                    Button { router.go(.home) } label: {
                        Text("稍后再下载").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GhostButton())
                }
            }
            .padding(Space.s6)
        }
    }

    private func modelCard(index: Int, name: String, tag: String, tagKind: TagKind, desc: String) -> some View {
        Button { withAnimation { pick = index } } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text(name).font(.heading(22))
                    Spacer()
                    Tag(text: tag, kind: tagKind)
                }
                Text(desc)
                    .font(.serifBody(13.5)).lineSpacing(4)
                    .foregroundStyle(DC.neutral800)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dcCard(border: pick == index ? DC.accent : DC.divider, padding: Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
