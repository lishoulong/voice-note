import SwiftUI

struct SettingsView: View {
    @Environment(Router.self) private var router
    @State private var cloud = false
    @State private var downloader = ModelDownloader.shared
    @AppStorage(ModelTier.storageKey) private var activeTierRaw = ModelTier.qwen1_7B.rawValue

    private var activeTier: ModelTier { ModelTier(rawValue: activeTierRaw) ?? .qwen1_7B }

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

    // MARK: - Model(双档:1.7B 保底 / 4B 高质量)
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Kicker(text: "Model")
            ForEach(ModelTier.allCases, id: \.rawValue) { tier in
                tierRow(tier)
            }
            Text("切换后,下一次「整理今日」即用所选模型。4B 生成时请尽量保持 App 前台。")
                .font(.serifBody(12)).foregroundStyle(DC.neutral600).lineSpacing(3)
        }
    }

    private func tierRow(_ tier: ModelTier) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("\(tier.displayName) · Q4_K_M").font(.serifBody(15))
                Text(tier.sizeLabel).font(.serifBody(12)).monospacedDigit()
                    .foregroundStyle(DC.neutral600)
                Spacer()
                statusTag(tier)
            }
            Text(tier.detail)
                .font(.serifBody(12.5)).lineSpacing(3).foregroundStyle(DC.neutral700)

            if downloader.downloadingTier == tier {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressBar(value: downloader.progress)
                    HStack {
                        Text(String(format: "%.0f / %.0f MB", downloader.receivedMB, downloader.totalMB))
                            .font(.serifBody(12)).monospacedDigit().foregroundStyle(DC.neutral600)
                        Spacer()
                        Button("取消") { downloader.cancel() }.buttonStyle(GhostButton())
                    }
                }
            } else if tier.isDownloaded {
                HStack(spacing: Space.s2) {
                    if tier != activeTier {
                        Button { activeTierRaw = tier.rawValue } label: {
                            Text("启用").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButton())
                        Button("删除") { downloader.deleteModel(tier: tier) }
                            .buttonStyle(GhostButton())
                    }
                }
            } else {
                Button { downloader.start(tier: tier) } label: {
                    Text("下载 \(tier.displayName)(\(tier.sizeLabel) · 建议 Wi-Fi)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButton())
                .disabled(downloader.downloadingTier != nil)
                .opacity(downloader.downloadingTier != nil ? 0.45 : 1)
            }

            if case .failed(let msg) = downloader.status, downloader.downloadingTier == nil, !tier.isDownloaded {
                Text("上次下载失败:\(msg)")
                    .font(.serifBody(11.5)).foregroundStyle(DC.neutral600)
            }
        }
        .padding(.bottom, Space.s3)
        .overlay(alignment: .bottom) { HRule() }
    }

    @ViewBuilder
    private func statusTag(_ tier: ModelTier) -> some View {
        if tier == activeTier && tier.isDownloaded {
            Tag(text: "使用中", kind: .accent)
        } else if tier.isDownloaded {
            Tag(text: "已就位", kind: .outline)
        } else if downloader.downloadingTier == tier {
            Tag(text: "下载中", kind: .accent)
        } else {
            Tag(text: "未下载", kind: .neutral)
        }
    }

    // MARK: - Privacy
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

    // MARK: - Storage(模型占用按实际文件计算)
    private var storageSection: some View {
        let modelMB = ModelTier.allCases.reduce(0.0) { sum, t in
            let size = (try? FileManager.default.attributesOfItem(atPath: t.fileURL.path)[.size] as? Int) ?? 0
            return sum + Double(size ?? 0) / 1_048_576
        }
        return VStack(alignment: .leading, spacing: Space.s3) {
            Kicker(text: "Storage")
            HStack {
                Text(modelMB > 900
                     ? String(format: "模型 %.1f GB", modelMB / 1024)
                     : String(format: "模型 %.0f MB", modelMB))
                Spacer()
                Text("笔记 < 10 MB")
            }
            .font(.serifBody(12.5)).monospacedDigit().foregroundStyle(DC.neutral700)
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
