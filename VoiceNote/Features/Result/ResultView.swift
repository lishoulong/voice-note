import SwiftUI
import SwiftData

struct ResultView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.createdAt, order: .forward) private var entries: [Entry]

    @State private var note: DiaryNote?
    @State private var showSource = false
    @State private var saved = false

    var body: some View {
        let n = note ?? SampleData.makeTodayDraft()
        Screen {
            VStack(spacing: 0) {
                topBar
                HRule()
                ScrollView { content(n) }
                bottomBar(n)
            }
        }
        .onAppear {
            if note == nil { note = router.resultNote ?? SampleData.makeTodayDraft() }
            saved = note?.savedToDiary ?? false
        }
    }

    private var topBar: some View {
        HStack {
            Button("返回") { router.go(.home) }.buttonStyle(GhostButton())
            Spacer()
            Kicker(text: "Draft · 可编辑")
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
    }

    private func content(_ n: DiaryNote) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Kicker(text: n.dateLabel)
                Text(n.title).font(.heading(29))
            }

            // mood + tags
            HStack(spacing: Space.s2) {
                Text("mood").font(.serifBody(12)).foregroundStyle(DC.neutral600)
                Tag(text: n.moodLabel, kind: .accent)
                Rectangle().fill(DC.divider).frame(width: 1, height: 14)
                ForEach(n.tags, id: \.self) { Tag(text: "#\($0)", kind: .outline) }
            }

            // 金句
            VStack(spacing: 0) {
                HRule()
                Text("「\(n.quote)」")
                    .font(.heading(20)).italic()
                    .foregroundStyle(DC.accent800)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                HRule()
            }

            // 分节正文
            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(n.sections) { sec in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        HStack(spacing: Space.s3) {
                            Kicker(text: sec.no, color: DC.accent700)
                            Text(sec.title).font(.heading(19))
                            Rectangle().fill(DC.divider).frame(height: 1).frame(maxWidth: .infinity)
                            Text(sec.fromLabel).font(.serifBody(11)).foregroundStyle(DC.neutral600)
                        }
                        Text(sec.body).font(.serifBody(15.5)).lineSpacing(6)
                    }
                }
            }

            Text("按逻辑分节,不按时间。双击任意段落可就地改写;节标题也可改。")
                .font(.serifBody(12.5)).foregroundStyle(DC.neutral600).lineSpacing(3)

            HRule()
            metaGrid(n)

            Button { withAnimation { showSource.toggle() } } label: {
                Text(showSource ? "收起原始条目" : "展开原始条目回溯")
                    .font(.serifBody(13.5)).foregroundStyle(DC.accent700).underline()
            }
            .buttonStyle(.plain)

            if showSource { sourceList }
        }
        .padding(Space.s4)
    }

    private func metaGrid(_ n: DiaryNote) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
            GridRow {
                Text("人物").foregroundStyle(DC.neutral600)
                Text(n.people.isEmpty ? "—" : n.people.joined(separator: " · "))
            }
            GridRow {
                Text("地点").foregroundStyle(DC.neutral600)
                Text(n.places.isEmpty ? "—" : n.places.joined(separator: " · "))
            }
            GridRow {
                Text("来源").foregroundStyle(DC.neutral600)
                Text(n.sourceLabel).monospacedDigit()
            }
        }
        .font(.serifBody(14))
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(entries) { e in
                HStack(alignment: .top, spacing: Space.s3) {
                    Text(e.timeLabel).font(.serifBody(13)).monospacedDigit()
                        .foregroundStyle(DC.neutral600)
                    Text(e.text).font(.serifBody(13)).foregroundStyle(DC.neutral700).lineSpacing(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Space.s3)
        .overlay(alignment: .leading) { Rectangle().fill(DC.accent400).frame(width: 1) }
    }

    private func bottomBar(_ n: DiaryNote) -> some View {
        VStack(spacing: Space.s2) {
            if saved {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    Text("已存入日记 · \(n.dateLabel)").font(.serifBody(13))
                }
                .foregroundStyle(DC.accent700)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Space.s2) {
                Button("重新生成") { router.go(.generating) }.buttonStyle(SecondaryButton())
                Button { save() } label: {
                    Text(saved ? "已保存" : "保存进日记").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s2)
        .background(DC.neutral100)
        .overlay(alignment: .top) { HRule() }
    }

    private func save() {
        guard !saved, let n = note else { return }
        n.savedToDiary = true
        context.insert(n)
        try? context.save()
        saved = true
    }
}

#Preview {
    ResultView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
