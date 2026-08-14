import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(Router.self) private var router
    @Query(sort: \DiaryNote.date, order: .reverse) private var notes: [DiaryNote]

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                topBar
                HRule()
                pendingBanner
                ScrollView {
                    LazyVStack(spacing: Space.s3) {
                        ForEach(notes) { note in
                            Button { router.showResult(note) } label: { noteCard(note) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(Space.s4)
                }
            }
        }
    }

    private var topBar: some View {
        ZStack {
            Text("日记").font(.heading(20))
            HStack {
                Button("今天") { router.go(.home) }.buttonStyle(GhostButton())
                Spacer()
                IconButton(systemName: "magnifyingglass") { }
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
    }

    private var pendingBanner: some View {
        Button { router.go(.catchup) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("未整理 · 2 天").font(.serifBody(13.5))
                    Text("这些天只有零散条目,没有成稿,也不计入「关于我」")
                        .font(.serifBody(11.5)).foregroundStyle(DC.accent800)
                }
                Spacer()
                Text("补上").font(.serifBody(13.5)).foregroundStyle(DC.accent800).underline()
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity)
            .background(DC.accent100)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(DC.accent300).frame(height: 1) }
    }

    private func noteCard(_ note: DiaryNote) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(note.dateLabel).font(.serifBody(11.5)).tracking(1).monospacedDigit()
                    .foregroundStyle(DC.neutral600)
                Spacer()
                Text(note.moodLabel).font(.serifBody(11.5)).foregroundStyle(DC.neutral600)
            }
            Text(note.title).font(.heading(21))
            Text(note.excerpt)
                .font(.serifBody(14)).lineSpacing(3)
                .foregroundStyle(DC.neutral800)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s2) {
                ForEach(note.tags.prefix(2), id: \.self) { Tag(text: "#\($0)", kind: .outline) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dcCard(padding: Space.s4)
    }
}

#Preview {
    HistoryView()
        .environment(Router())
        .modelContainer(SampleData.container)
}
