import SwiftUI

struct SettingsView: View {
    @Environment(Router.self) private var router
    @State private var tierIs4B = false
    @State private var cloud = false
    @State private var downloader = ModelDownloader.shared

    private var tierLabel: String { tierIs4B ? "4B" : "1.7B" }
    private var otherTierLabel: String { tierIs4B ? "1.7B" : "4B" }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                topBar
                HRule()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s6) {
                        modelSection
                        privacySection
                        storageSection
                    }
                    .padding(Space.s4)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Space.s3) {
            Button("返回") { router.go(.home) }.buttonStyle(GhostButton())
            Text("设置").font(.heading(20))
            Spacer()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Kicker(text: "Model")
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("Qwen3 \(tierLabel) · Q4_K_M").font(.serifBody(15))
                    Spacer()
                    Tag(text: modelReady ? "已就位" : "未下载", kind: modelReady ? .accent : .neutral)
                }
                .padding(.bottom, Space.s2)
                .overlay(alignment: .bottom) { HRule() }

                Text("iPhone 14(6GB)推荐 1.7B。整理今日全程在本机用 llama.cpp + Qwen 生成,不联网。")
                    .font(.serifBody(13)).lineSpacing(3).foregroundStyle(DC.neutral700)

                downloadStatus
            }
        }
    }

    private var modelReady: Bool {
        if case .done = downloader.status { return true }
        return false
    }

    @ViewBuilder
    private var downloadStatus: some View {
        switch downloader.status {
        case .done:
            HStack(spacing: Space.s2) {
                Image(systemName: "checkmark.circle").foregroundStyle(DC.accent700)
                Text("模型已就位 · 可完全本机生成").font(.serifBody(13)).foregroundStyle(DC.accent700)
                Spacer()
                Button("删除") { downloader.deleteModel() }.buttonStyle(GhostButton())
            }
        case .downloading:
            VStack(alignment: .leading, spacing: 6) {
                ProgressBar(value: downloader.progress)
                HStack {
                    Text(String(format: "下载中 %.0f / %.0f MB", downloader.receivedMB, downloader.totalMB))
                        .font(.serifBody(12)).monospacedDigit().foregroundStyle(DC.neutral600)
                    Spacer()
                    Button("取消") { downloader.cancel() }.buttonStyle(GhostButton())
                }
            }
        case .idle:
            Button { downloader.start() } label: {
                Text("下载 Qwen3-1.7B(~1.1GB · 仅 Wi-Fi)").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButton())
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Text("下载失败:\(msg)").font(.serifBody(12)).foregroundStyle(DC.neutral700)
                Button { downloader.start() } label: {
                    Text("重试").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButton())
            }
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Kicker(text: "Privacy")
            Button { withAnimation { cloud.toggle() } } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("云端兜底 Cloud fallback").font(.serifBody(15))
                        Text("仅在本机生成失败时询问,永不自动上传")
                            .font(.serifBody(12.5)).foregroundStyle(DC.neutral700)
                    }
                    Spacer()
                    Text(cloud ? "已开启" : "已关闭")
                        .font(.serifBody(13)).foregroundStyle(DC.accent700).underline()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Space.s3)
            .overlay(alignment: .bottom) { HRule() }

            settingRow("录音仅本机保存", value: "开启")
            settingRowDetail("每日画像 user.md", "每天定时重算「关于我」,只读日记正文", value: "23:30")
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Kicker(text: "Storage")
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(DC.accent).frame(width: geo.size.width * 0.62)
                    Rectangle().fill(DC.accent300).frame(width: geo.size.width * 0.09)
                    Rectangle().fill(DC.neutral300)
                }
            }
            .frame(height: 3)
            HStack {
                Text("模型 1.1 GB"); Spacer()
                Text("录音 340 MB"); Spacer()
                Text("笔记 6 MB")
            }
            .font(.serifBody(12.5)).monospacedDigit().foregroundStyle(DC.neutral700)
            Button("清理已转写录音") { }.buttonStyle(GhostButton())
        }
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.serifBody(15))
            Spacer()
            Text(value).font(.serifBody(13)).foregroundStyle(DC.neutral700)
        }
        .padding(.bottom, Space.s3)
        .overlay(alignment: .bottom) { HRule() }
    }

    private func settingRowDetail(_ title: String, _ detail: String, value: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.serifBody(15))
                Text(detail).font(.serifBody(12.5)).foregroundStyle(DC.neutral700)
            }
            Spacer()
            Text(value).font(.serifBody(13)).monospacedDigit().foregroundStyle(DC.accent700)
        }
        .padding(.bottom, Space.s3)
        .overlay(alignment: .bottom) { HRule() }
    }
}

#Preview {
    SettingsView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
