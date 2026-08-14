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
                    try? context.save()
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
            .disabled(entries.isEmpty)
            .opacity(entries.isEmpty ? 0.4 : 1)
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

// MARK: - 录音 / 实时听写面板
struct RecordingSheet: View {
    @Binding var isPresented: Bool
    var onSend: (String, Int?) -> Void

    @State private var dictation = SpeechDictation()
    @State private var text = ""

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: Space.s3) {
                header
                editor
                statusLine
                waveform
                controls
            }
            .padding(Space.s4)
            .padding(.bottom, Space.s6)
            .frame(maxWidth: .infinity)
            .background(DC.bg)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.lg, topTrailingRadius: Radius.lg))
            .shadow(color: DC.text.opacity(0.22), radius: 16, y: -4)
        }
        .task { await dictation.start() }
        .onDisappear { dictation.stop() }
        .onChange(of: dictation.transcript) { _, new in
            if !new.isEmpty { text = new }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: Space.s2) {
                Circle()
                    .fill(dictation.isListening ? DC.accent : DC.neutral400)
                    .frame(width: 6, height: 6)
                Kicker(text: headerLabel,
                       color: dictation.isListening ? DC.accent700 : DC.neutral600)
            }
            Spacer()
            Text(timeLabel).font(.serifBody(12.5)).monospacedDigit()
                .foregroundStyle(DC.neutral600)
        }
    }

    private var headerLabel: String {
        switch dictation.status {
        case .listening:   "Listening · 本机实时转写"
        case .denied:      "权限未开 · 可直接打字"
        case .unavailable: "听写不可用 · 可直接打字"
        case .idle:        "已就绪 · 点麦克风开始"
        }
    }

    private var editor: some View {
        TextField("说话吧,文字会实时出现;也可直接打字…", text: $text, axis: .vertical)
            .font(.serifBody(15.5)).lineSpacing(6)
            .frame(minHeight: 92, alignment: .topLeading)
            .padding(Space.s3)
            .background(DC.bg)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(DC.divider, lineWidth: 1))
    }

    private var statusLine: some View {
        HStack {
            switch dictation.status {
            case .denied:
                Text("到 设置 开启麦克风与语音识别")
                    .font(.serifBody(12.5)).foregroundStyle(DC.neutral600)
            case .unavailable:
                Text("换真机或联网可用本机听写")
                    .font(.serifBody(12.5)).foregroundStyle(DC.neutral600)
            default:
                EmptyView()
            }
            Spacer()
            Text("单条上限 01:00").font(.serifBody(11.5)).foregroundStyle(DC.neutral600)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(dictation.levels.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(DC.accent400)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, 34 * dictation.levels[i]))
            }
        }
        .frame(height: 34)
        .animation(.linear(duration: 0.1), value: dictation.levels)
    }

    private var controls: some View {
        HStack(spacing: Space.s3) {
            Button("丢弃") { close() }.buttonStyle(SecondaryButton())
            Button { toggleMic() } label: {
                Image(systemName: dictation.isListening ? "mic.fill" : "mic.slash")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(SecondaryButton())
            Button { send() } label: {
                Text("发送到笔记").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
        }
    }

    private var timeLabel: String {
        String(format: "%02d:%02d / 01:00", dictation.seconds / 60, dictation.seconds % 60)
    }

    private func toggleMic() {
        if dictation.isListening {
            dictation.stop()
        } else {
            Task { await dictation.start() }
        }
    }

    private func close() {
        dictation.stop()
        withAnimation { isPresented = false }
    }

    private func send() {
        dictation.stop()
        let secs = dictation.seconds > 0 ? dictation.seconds : nil
        onSend(text, secs)
        withAnimation { isPresented = false }
    }
}

#Preview {
    HomeView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
