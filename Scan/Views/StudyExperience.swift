import SwiftUI
import SwiftData

enum StudyPalette {
    static let focus = Color(light: UIColor(red: 0.20, green: 0.29, blue: 0.78, alpha: 1), dark: UIColor(red: 0.59, green: 0.65, blue: 1, alpha: 1))
    static let progress = Color(light: UIColor(red: 0.02, green: 0.45, blue: 0.43, alpha: 1), dark: UIColor(red: 0.30, green: 0.80, blue: 0.71, alpha: 1))
    static let revisit = Color(light: UIColor(red: 0.61, green: 0.34, blue: 0.04, alpha: 1), dark: UIColor(red: 1, green: 0.73, blue: 0.32, alpha: 1))
    static let canvas = Color(light: UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1), dark: UIColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1))
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct StudyDial: View {
    var progress: Double
    var value: String
    var caption: String
    var color: Color = StudyPalette.progress
    var size: CGFloat = 92
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.13), lineWidth: size * 0.07)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: progress)
            VStack(spacing: 2) {
                Text(value).font(.system(size: size * 0.24, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text(caption).font(.system(size: max(11, size * 0.105), weight: .medium)).foregroundStyle(.secondary)
            }.padding(size * 0.12)
        }.frame(width: size, height: size)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(value) \(caption)")
    }
}

struct StudyActionTile: View {
    var title: String
    var detail: String
    var symbol: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2.weight(.medium)).foregroundStyle(color)
                .frame(width: 46, height: 46).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading).padding(18)
            .background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 23))
            .contentShape(RoundedRectangle(cornerRadius: 23))
    }
}

struct StudyDesk: View {
    @Query private var items: [StudyItem]
    @State private var draft: StudyDraft?
    @State private var createdPaperID: String?
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var questions: [StudyRecord] { records.filter { $0.type == .question } }
    private var papers: [StudyRecord] { records.filter { $0.type == .paper } }
    private var due: Int { records.filter { $0.type == .card && StudySchedule.due($0) }.count }
    private var resume: StudyRecord? {
        papers.first { $0["timerState"] == "running" } ?? papers.first { $0["timerState"] == "paused" } ?? papers.first { paper in
            let marks = StudyMarks.total(questions.filter { $0["paper"] == paper.id })
            return !paper.ids("pages").isEmpty && (marks.count == 0 || marks.marked < marks.count)
        } ?? papers.first { $0.ids("pages").isEmpty }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Make the next page count.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("A paper, a few cards, a little more understood.").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                let marked = StudyMarks.total(questions)
                StudyDial(progress: marked.count == 0 ? 0 : Double(marked.marked) / Double(marked.count), value: "\(marked.marked)", caption: "marked")
                VStack(alignment: .leading, spacing: 6) {
                    Text(marked.marked == 0 ? "Your desk is ready" : "Work you can see").font(.headline)
                    Text("\(papers.count) papers in your collection\n\(due) cards ready to review").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(StudyPalette.progress.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
            if let paper = resume {
                NavigationLink { PaperWorkspace(recordID: paper.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: paper["timerState"] == "running" ? "timer" : "pencil.and.list.clipboard").font(.title2).foregroundStyle(StudyPalette.focus)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pick up where you left off").font(.caption).foregroundStyle(.secondary)
                            Text(paper.title).font(.headline).foregroundStyle(.primary)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(StudyPalette.focus)
                    }.padding(18).background(StudyPalette.focus.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
            } else {
                Button { draft = StudyDraft(record: StudyRecord(.paper)) } label: {
                    Label("Start a past paper", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.borderedProminent).tint(StudyPalette.focus)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(StudyArea.allCases) { area in
                    NavigationLink { StudyLibraryView(area: area) } label: {
                        StudyActionTile(title: area == .cards ? "Recall" : area.rawValue,
                            detail: tileDetail(area), symbol: area.symbol, color: tileColor(area))
                    }.buttonStyle(.plain).accessibilityIdentifier("library.study." + area.id)
                }
            }
        }.sheet(item: $draft) { item in StudyEditor(record: item.record) { createdPaperID = item.record.id } }
            .navigationDestination(item: $createdPaperID) { PaperWorkspace(recordID: $0) }
    }
    private func tileDetail(_ area: StudyArea) -> String {
        switch area {
        case .papers: "Sit, scan and mark on the page"
        case .courses: "See how the topics connect"
        case .cards: "\(due) ready when you are"
        case .mistakes: "Turn lost marks into next steps"
        }
    }
    private func tileColor(_ area: StudyArea) -> Color {
        switch area { case .papers: StudyPalette.focus; case .courses: StudyPalette.progress; case .cards: .purple; case .mistakes: StudyPalette.revisit }
    }
}

/// Searchable topic tree with explicit selection; reopening always shows the
/// current tag. Existing topics can be chosen without creating a course first.
struct StudyTopicPicker: View {
    @Binding var selection: String
    var subjectID: String = ""
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [StudyItem]
    @State private var search = ""
    @State private var subject = ""
    @State private var draft: StudyDraft?
    @State private var feedback = StudyFeedbackState()
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var subjects: [StudyRecord] { records.filter { $0.type == .subject } }
    private var topics: [StudyRecord] {
        records.filter { $0.type == .topic && (subject.isEmpty || $0["subject"] == subject) &&
            (search.isEmpty || ($0.title + " " + path($0)).localizedCaseInsensitiveContains(search)) }
            .sorted { (path($0) + "/" + $0.title).localizedStandardCompare(path($1) + "/" + $1.title) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What was this testing?").font(.system(.title2, design: .rounded, weight: .bold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            subjectChip("All subjects", id: "")
                            ForEach(subjects) { subjectChip($0.title, id: $0.id) }
                        }
                    }
                    Button { choose("") } label: {
                        Label("No topic yet", systemImage: selection.isEmpty ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    }.buttonStyle(.bordered)
                    ForEach(topics) { topic in
                        Button { choose(topic.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection == topic.id ? "checkmark.circle.fill" : "circle").foregroundStyle(StudyPalette.progress)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(topic.title).font(.headline).foregroundStyle(.primary)
                                    Text(path(topic)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(16).background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).accessibilityIdentifier("study.topic." + topic.id)
                    }
                    if topics.isEmpty { Text("No topics here yet. Add one, or choose another subject.").foregroundStyle(.secondary) }
                    Button(subjects.isEmpty ? "Create a subject" : "Add a topic", systemImage: "plus") {
                        draft = StudyDraft(record: StudyRecord(subjects.isEmpty ? .subject : .topic, ["subject": subject.isEmpty ? subjects.first?.id ?? "" : subject]))
                    }.buttonStyle(.bordered)
                }.padding(22).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(StudyPalette.canvas).searchable(text: $search, prompt: "Search topics and subtopics")
                .navigationTitle("Choose a topic").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .sheet(item: $draft) { StudyEditor(record: $0.record) }
                .onAppear { subject = subjectID }
                .studyFeedback(feedback)
        }
    }
    private func subjectChip(_ title: String, id: String) -> some View {
        Button { subject = id; feedback.selection += 1 } label: {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(subject == id ? Color.white : Color.primary)
                .background(subject == id ? StudyPalette.focus : StudyPalette.surface, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(subject == id ? .isSelected : [])
    }
    private func choose(_ id: String) { selection = id; feedback.selection += 1; dismiss() }
    private func path(_ topic: StudyRecord) -> String {
        var parts: [String] = []; var cursor = topic; var seen: Set<String> = [topic.id]
        while let parent = records.first(where: { $0.id == cursor["parent"] }), seen.insert(parent.id).inserted {
            parts.insert(parent.title, at: 0); cursor = parent
        }
        if let owner = subjects.first(where: { $0.id == topic["subject"] }) { parts.insert(owner.title, at: 0) }
        return parts.joined(separator: " / ")
    }
}
