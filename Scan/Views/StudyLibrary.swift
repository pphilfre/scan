import SwiftUI
import SwiftData

enum StudyArea: String, CaseIterable, Identifiable {
    case courses = "Course maps", papers = "Past Papers", cards = "Flashcards & review", mistakes = "Mistakes"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .courses: "map"; case .papers: "doc.text"; case .cards: "rectangle.on.rectangle"; case .mistakes: "arrow.trianglehead.clockwise" }
    }
    var kind: StudyKind {
        switch self { case .courses: .subject; case .papers: .paper; case .cards: .card; case .mistakes: .mistake }
    }
    var introduction: String {
        switch self {
        case .courses: "Build a subject one topic at a time, or paste a course map. New topics are room to grow."
        case .papers: "Scan a complete paper and keep it here. Add questions and topic links whenever you’re ready."
        case .cards: "Add a card from a note, question or mistake. Reviews fit around you; there are no missed-day penalties."
        case .mistakes: "Save the reasoning you want to remember. Each retry is another chance to learn."
        }
    }
}

struct StudyFeedbackState {
    var selection = 0
    var success = 0
    var error = 0
}
private struct StudyFeedback: ViewModifier {
    var state: StudyFeedbackState
    @AppStorage("studyHaptics") private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.selection, trigger: state.selection) { _, _ in enabled && !reduceMotion }
            .sensoryFeedback(.success, trigger: state.success) { _, _ in enabled && !reduceMotion }
            .sensoryFeedback(.error, trigger: state.error) { _, _ in enabled && !reduceMotion }
    }
}
extension View {
    func studyFeedback(_ state: StudyFeedbackState) -> some View { modifier(StudyFeedback(state: state)) }
}
struct StudyHapticPreference: View {
    @AppStorage("studyHaptics") private var enabled = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Study haptics", isOn: $enabled)
            Text("Light feedback for recall and topic selection, and confirmation for saved work. Uses system feedback and is also muted with Reduce Motion.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct StudyDraft: Identifiable { var record: StudyRecord; var id: String { record.id } }
struct StudyReaderSelection: Identifiable { let id = UUID(); var pages: [NotePage]; var title: String? = nil }

struct StudyLibraryView: View {
    let area: StudyArea
    @Environment(\.modelContext) private var context
    @Query private var items: [StudyItem]
    @State private var search = ""
    @State private var draft: StudyDraft?
    @State private var transfer = false
    @State private var reviewing = false
    @State private var session = false
    @State private var questionMode = false
    @State private var subject = ""
    @State private var board = ""
    @State private var year = ""
    @State private var topic = ""
    @State private var score = "All"
    @State private var retries = false
    @State private var showResolved = false
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var due: Int { records.filter { $0.type == .card && StudySchedule.due($0) }.count }
    private var visible: [StudyRecord] {
        let records = self.records
        let allQuestions = records.filter { $0.type == .question }
        let topicQuestionIDs = topic.isEmpty ? Set<String>() : Set(StudyRules.scoped(records, to: records.first { $0.id == topic }).filter { $0.type == .question }.map(\.id))
        return records.filter { record in
            guard record.type == (area == .papers && questionMode ? .question : area.kind) else { return false }
            if !search.isEmpty {
                let paper = record.type == .question ? records.first { $0.id == record["paper"] } : nil
                let text = ([record.title] + Array(record.fields.values) + (paper.map { Array($0.fields.values) } ?? [])).joined(separator: " ")
                if !text.localizedCaseInsensitiveContains(search) { return false }
            }
            if area == .mistakes && !showResolved && record["resolved"] == "true" { return false }
            if area == .papers {
                let paper = record.type == .paper ? record : records.first { $0.id == record["paper"] }
                if !subject.isEmpty && paper?["subject"] != subject && paper?["subjectName"] != subject { return false }
                if !board.isEmpty && paper?["board"].localizedCaseInsensitiveContains(board) != true { return false }
                if !year.isEmpty && paper?["year"] != year { return false }
                let questions = record.type == .question ? [record] : allQuestions.filter { $0["paper"] == record.id }
                if !topic.isEmpty {
                    if !questions.contains(where: { topicQuestionIDs.contains($0.id) }) { return false }
                }
                let questionIDs = record.type == .question ? StudyRules.descendants(of: record.id, in: allQuestions) : Set<String>()
                let selectedQuestions = record.type == .question ? allQuestions.filter { questionIDs.contains($0.id) } : questions
                let total = StudyMarks.total(selectedQuestions)
                if score == "Unmarked" && total.marked != 0 { return false }
                if score == "Below 70%" && (total.marked == 0 || total.available == 0 || total.earned / total.available >= 0.7) { return false }
                if score == "70% or more" && (total.available == 0 || total.earned / total.available < 0.7) { return false }
                if retries && !questions.contains(where: { StudyRules.needsRetry($0, in: records) }) { return false }
            }
            return true
        }
    }
    var body: some View {
        List {
            Section {
                Text(area.introduction).font(.subheadline).foregroundStyle(.secondary)
                Button("Start a study session", systemImage: "play.circle") { session = true }
                if area == .cards {
                    Button("Review \(due) due cards", systemImage: "rectangle.on.rectangle") { reviewing = true }.disabled(due == 0).accessibilityIdentifier("study.review")
                }
            }
            if area == .papers {
                Section {
                    Picker("Browse", selection: $questionMode) { Text("Papers").tag(false); Text("Questions").tag(true) }.pickerStyle(.segmented)
                    DisclosureGroup("Filter papers and questions") {
                        Picker("Subject", selection: $subject) {
                            Text("All").tag("")
                            ForEach(records.filter { $0.type == .subject }) { Text($0.title).tag($0.id) }
                            ForEach(Array(Set(records.filter { $0.type == .paper && $0["subject"].isEmpty }.map { $0["subjectName"] }.filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Exam board", text: $board)
                        TextField("Year", text: $year).keyboardType(.numberPad)
                        Picker("Topic", selection: $topic) { Text("All").tag(""); ForEach(records.filter { $0.type == .topic }) { Text($0.title).tag($0.id) } }
                        Picker("Score", selection: $score) { ForEach(["All", "Unmarked", "Below 70%", "70% or more"], id: \.self) { Text($0).tag($0) } }
                        Toggle("Needs another attempt", isOn: $retries)
                    }
                }
            }
            if area == .mistakes { Toggle("Include resolved mistakes", isOn: $showResolved) }
            Section {
                ForEach(visible) { record in
                    NavigationLink { StudyDetailView(recordID: record.id) } label: { StudyRecordRow(record: record, records: records) }
                        .accessibilityIdentifier("study.record." + record.id)
                }
                if visible.isEmpty { Text(search.isEmpty ? "Ready when you are. Add your first \(area.kind.name.lowercased()) using +, or paste study data." : "No matches. Try changing the filters.").foregroundStyle(.secondary) }
            }
            if items.contains(where: { (try? $0.decoded()) == nil }) {
                Text("A study record could not be read. Its saved data has been kept; export will report the error.").foregroundStyle(.red)
            }
        }
        .scrollContentBackground(.hidden).background(FolioStyle.paper)
        .navigationTitle(area.rawValue).searchable(text: $search)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Import or export", systemImage: "arrow.up.arrow.down") { transfer = true }.accessibilityIdentifier("study.transfer") }
            ToolbarItem(placement: .topBarTrailing) { Button("Add \(area.kind.name)", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(area.kind)) }.accessibilityIdentifier("study.add") }
        }
        .sheet(item: $draft) { StudyEditor(record: $0.record) }
        .sheet(isPresented: $transfer) { StudyTransferView() }
        .sheet(isPresented: $reviewing) { StudyReviewView() }
        .sheet(isPresented: $session) { StudySessionView() }
    }
}

struct StudyRecordRow: View {
    let record: StudyRecord
    let records: [StudyRecord]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.title.isEmpty ? record.type.name : record.title).font(.headline)
            if record.type == .paper {
                Text([record["subjectName"], record["board"], record["year"], record["session"]].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                Text(StudyMarks.total(records.filter { $0.type == .question && $0["paper"] == record.id }).label).font(.caption).foregroundStyle(.secondary)
            } else if record.type == .question {
                let ids = StudyRules.descendants(of: record.id, in: records.filter { $0.type == .question })
                Text(StudyMarks.total(records.filter { ids.contains($0.id) }).label + (record["retryAt"].isEmpty ? "" : " · Retry scheduled")).font(.caption).foregroundStyle(.secondary)
            } else if record.type == .subject {
                let topics = records.filter { $0.type == .topic && $0["subject"] == record.id }
                let explored = topics.filter { !$0["confidence"].isEmpty && $0["confidence"] != "New" }.count
                Text("\(explored) topics explored · \(topics.count - explored) ready to discover").font(.caption).foregroundStyle(.secondary)
                if !topics.isEmpty {
                    Text("Confidence: \(topics.filter { $0["confidence"] == "Confident" }.count) confident · \(topics.filter { $0["confidence"] == "Practising" }.count) practising · \(topics.filter { $0["confidence"] == "Exploring" }.count) exploring").font(.caption).foregroundStyle(.secondary)
                }
                if !topics.isEmpty { ProgressView(value: Double(explored), total: Double(topics.count)).tint(FolioStyle.color("sage")) }
            } else if record.type == .topic {
                Text(record["confidence"].isEmpty ? "New · Ready to discover" : record["confidence"]).font(.caption).foregroundStyle(.secondary)
            } else if record.type == .card {
                Text(StudySchedule.due(record) ? "Ready to review" : "Next review \(record.date("due")?.formatted(date: .abbreviated, time: .omitted) ?? "when ready")").font(.caption).foregroundStyle(.secondary)
            } else if record.type == .mistake {
                Text(record["resolved"] == "true" ? "Resolved · Learning retained" : "\(record["category"]) · Ready for another try").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}
