import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.createdAt, order: .forward) private var entries: [Entry]

    @State private var showRecording = false

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                header
                HRule()
                timeline
                bottomBar
            }
        }
        .overlay {
            if showRecording {
                RecordingSheet(isPresented: $showRecording) { text, seconds in
                    context.insert(Entry(createdAt: .now, text: text, voiceSeconds: seconds))
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    // MARK: 顶栏
    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: "Thu · 2026.08.14")
                Text("今天").font(.heading(27))
            }
            Spacer()
            HStack(spacing: Space.s1) {
                IconButton(systemName: "clock.arrow.circlepath") { router.go(.history) }
                IconButton(systemName: "person") { router.go(.about) }
                IconButton(systemName: "gearshape") { router.go(.settings) }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: 时间线
    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { e in
                    entryRow(e)
                    HRule()
                }
                HStack {
                    Text("点这里接着写 · 双击某条可修改")
                        .font(.serifBody(13))
                        .foregroundStyle(DC.neutral500)
                    Spacer()
                }
                .frame(minHeight: 120, alignment: .top)
                .padding(.top, Space.s3)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { showRecording = true } }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
        }
    }

    private func entryRow(_ e: Entry) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(e.timeLabel)
                .font(.serifBody(12.5)).monospacedDigit()
                .foregroundStyle(DC.neutral600)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(e.text)
                    .font(.serifBody(15)).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let v = e.voiceLabel {
                    HStack(spacing: 5) {
                        Image(systemName: "mic").font(.system(size: 10))
                        Text("语音 · \(v)").monospacedDigit()
                    }
                    .font(.serifBody(11.5))
                    .foregroundStyle(DC.neutral600)
                }
            }
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: 底栏
    private var bottomBar: some View {
        VStack(spacing: 0) {
            HRule()
            Button { router.go(.generating) } label: {
                HStack {
                    Text("\(entries.count) 条随手记")
                        .font(.serifBody(13)).foregroundStyle(DC.neutral700)
                    Spacer()
                    HStack(spacing: 6) {
                        Text("整理今日笔记").font(.serifBody(14))
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(DC.accent700)
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HRule()
            Button { withAnimation { showRecording = true } } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "mic")
                    Text("口述 · 点一下开始,长按即按即说")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s2)
        }
        .background(DC.neutral100)
    }
}

// MARK: - 录音 / 实时转写面板
struct RecordingSheet: View {
    @Binding var isPresented: Bool
    var onSend: (String, Int?) -> Void

    @State private var text = "刚跟阿哲说好周末去爬山,顺路看看城南新开的那家书店。"
    @State private var polishing = true

    private let levels: [CGFloat] = [0.3,0.6,0.9,0.5,0.7,1.0,0.4,0.6,0.8,0.5,0.3,0.7,
                                     0.9,0.6,0.4,0.8,1.0,0.5,0.6,0.3,0.7,0.9,0.4,0.6]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    HStack(spacing: Space.s2) {
                        Circle().fill(DC.accent).frame(width: 6, height: 6)
                        Kicker(text: "Listening · 本机实时转写", color: DC.accent700)
                    }
                    Spacer()
                    Text("00:12").font(.serifBody(12.5)).monospacedDigit()
                        .foregroundStyle(DC.neutral600)
                }

                Text(text)
                    .font(.serifBody(15.5)).lineSpacing(6)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                    .padding(Space.s3)
                    .background(DC.bg)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(DC.divider, lineWidth: 1))

                if polishing {
                    HStack(spacing: Space.s2) {
                        ProgressView().controlSize(.mini)
                        Text("轻润色中 · 本机 1.7B · 只断句去口水词")
                            .font(.serifBody(13)).foregroundStyle(DC.accent700)
                    }
                }

                HStack {
                    Button { polishing.toggle() } label: {
                        Text(polishing ? "关闭轻润色" : "开启轻润色")
                            .font(.serifBody(13.5)).foregroundStyle(DC.accent700)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("单条上限 01:00").font(.serifBody(11.5)).foregroundStyle(DC.neutral600)
                }

                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(levels.indices, id: \.self) { i in
                        Rectangle().fill(DC.accent400)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, 34 * levels[i]))
                    }
                }
                .frame(height: 34)

                HStack(spacing: Space.s3) {
                    Button("丢弃") { close() }
                        .buttonStyle(SecondaryButton())
                    Button { send() } label: {
                        Text("发送到笔记").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButton())
                }
            }
            .padding(Space.s4)
            .padding(.bottom, Space.s6)
            .frame(maxWidth: .infinity)
            .background(DC.bg)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.lg, topTrailingRadius: Radius.lg))
            .shadow(color: DC.text.opacity(0.22), radius: 16, y: -4)
        }
    }

    private func close() { withAnimation { isPresented = false } }
    private func send() {
        onSend(text, 12)
        close()
    }
}

#Preview {
    HomeView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
