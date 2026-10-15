import SwiftUI
import SwiftData

struct StudyDetailView: View {
    let recordID: String
    var sessionID: String?
    var showPaperWorkspace = true
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AccessController.self) private var access
    @Query private var items: [StudyItem]
    @Query private var storedPages: [NotePage]
    @Query private var books: [Notebook]
    @State private var importer = ImportCoordinator()
    @State private var draft: StudyDraft?
    @State private var capture = false
    @State private var reader: StudyReaderSelection?
    @State private var session = false
    @State private var reviewing = false
    @State private var deleting = false
    @State private var afterMarking = false
    @State private var pendingMarkActions = false
    @State private var marking = false
    @State private var error: String?
    @State private var notice: String?
    @State private var feedback = StudyFeedbackState()
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var record: StudyRecord? { records.first { $0.id == recordID } }
    var body: some View {
        Group {
            if let record {
                if record.type == .paper && showPaperWorkspace {
                    PaperWorkspace(recordID: record.id)
                } else {
                List {
                    if let notice { Section { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.secondary) } }
                    if [.subject, .topic, .paper].contains(record.type) {
                        Section {
                            Button("Study here", systemImage: "play.circle") { session = true }
                            Button("Review due cards", systemImage: "rectangle.on.rectangle") { reviewing = true }
                        }
                    }
                    switch record.type {
                    case .subject: subjectContent(record)
                    case .topic: topicContent(record)
                    case .paper: paperContent(record)
                    case .question: questionContent(record)
                    case .mistake: mistakeContent(record)
                    case .card: cardContent(record)
                    case .markScheme: scanContent(record)
                    default: EmptyView()
                    }
                    if !record["notes"].isEmpty { Section("Notes") { Text(record["notes"]).textSelection(.enabled) } }
                    sourceContent(record)
                    historyContent(record)
                }.navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Edit", systemImage: "pencil") { draft = StudyDraft(record: record) }
                                if [.question, .mistake].contains(record.type) { Button("Make flashcard", systemImage: "rectangle.on.rectangle") { makeCard(record) } }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                    .sheet(isPresented: $capture) { StudyCaptureView(recordID: record.id, importer: importer) }
                    .sheet(isPresented: $session) { StudySessionView(initialScope: record) }
                    .sheet(isPresented: $reviewing) { StudyReviewView(scope: record) }
                    .confirmationDialog("Delete this \(record.type.name.lowercased())? Linked scans are kept in your library.", isPresented: $deleting, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            do { try StudyStore.remove(record, context: context); dismiss() }
                            catch { self.error = error.localizedDescription; feedback.error += 1 }
                        }
                    }
                    .confirmationDialog("Marks saved. What would help next?", isPresented: $afterMarking, titleVisibility: .visible) {
                        Button("Record a mistake") { makeMistake(record) }
                        Button("Make a flashcard") { makeCard(record) }
                        Button("Retry tomorrow") { retryTomorrow(record) }
                        Button("Done", role: .cancel) {}
                    }
                }
            } else { ContentUnavailableView("Study record removed", systemImage: "tray") }
        }
        .scrollContentBackground(.hidden).background(FolioStyle.paper)
        .sheet(item: $draft, onDismiss: { if pendingMarkActions { pendingMarkActions = false; afterMarking = true } }) { item in
            StudyEditor(record: item.record, sessionID: sessionID) {
                feedback.success += 1; notice = "Saved"
                if item.record.type == .question && item.record.id == recordID { pendingMarkActions = true }
            }
        }
        .sheet(isPresented: $marking, onDismiss: { if pendingMarkActions { pendingMarkActions = false; afterMarking = true } }) {
            if let question = record {
                StudyMarkEditor(question: question, sessionID: sessionID) {
                    pendingMarkActions = true; feedback.success += 1; notice = "Marks saved"
                }
            }
        }
        .fullScreenCover(item: $reader) { selection in
            if let first = selection.pages.first { PageReader(pages: selection.pages, initialID: first.id, importer: importer, preservePageOrder: true, titleOverride: selection.title) }
        }
        .alert("Study data needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        .studyFeedback(feedback)
        .onAppear { if record?.type == .topic { feedback.selection += 1 } }
    }
    @ViewBuilder private func subjectContent(_ subject: StudyRecord) -> some View {
        Section("Your course") {
            StudyRecordRow(record: subject, records: records)
            Text(StudyMarks.total(StudyRules.scoped(records, to: subject).filter { $0.type == .question }).label).font(.caption).foregroundStyle(.secondary)
            Text([subject["board"], subject["qualification"]].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
            Button("Add topic", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(.topic, ["subject": subject.id])) }
        }
        Section("Topics and subtopics") {
            ForEach(orderedTopics(subject)) { topic in
                NavigationLink { StudyDetailView(recordID: topic.id, sessionID: sessionID) } label: {
                    StudyRecordRow(record: topic, records: records).padding(.leading, CGFloat(depth(topic)) * 14)
                }
            }
        }
    }
    @ViewBuilder private func topicContent(_ topic: StudyRecord) -> some View {
        Section("Confidence") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(StudyRules.confidence, id: \.self) { value in
                    let selected = (topic["confidence"].isEmpty ? "New" : topic["confidence"]) == value
                    Button {
                        var changed = topic; changed["confidence"] = value; save(changed, notice: "Confidence updated"); feedback.selection += 1
                    } label: {
                        Label(value, systemImage: selected ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? Color.white : StudyPalette.progress)
                            .background(selected ? StudyPalette.progress : StudyPalette.progress.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Confidence is your judgement. New topics are opportunities; marks don’t set this rating for you.").font(.caption).foregroundStyle(.secondary)
            Button("Add subtopic", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(.topic, ["subject": topic["subject"], "parent": topic.id])) }
            ForEach(records.filter { $0.type == .topic && $0["parent"] == topic.id }) { linked($0) }
        }
        let scoped = StudyRules.scoped(records, to: topic)
        Section("Practice") {
            Text(StudyMarks.total(scoped.filter { $0.type == .question }).label).font(.caption).foregroundStyle(.secondary)
            ForEach(scoped.filter { $0.type == .question }) { linked($0) }
            if !scoped.contains(where: { $0.type == .question }) { Text("Link questions from Past Papers whenever you’re ready.").foregroundStyle(.secondary) }
        }
        noteContent(topic)
        Section("Mistakes") {
            Button("Add mistake", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(.mistake, ["topic": topic.id])) }
            ForEach(scoped.filter { $0.type == .mistake }) { linked($0) }
        }
        Section("Flashcards") {
            Button("Add flashcard", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(.card, ["topic": topic.id])) }
            ForEach(scoped.filter { $0.type == .card }) { linked($0) }
        }
    }
    @ViewBuilder private func paperContent(_ paper: StudyRecord) -> some View {
        Section("Paper") {
            Text([paper["subjectName"], records.first { $0.id == paper["subject"] }?.title ?? "", paper["board"], paper["qualification"], paper["year"], paper["session"], paper["number"]].filter { !$0.isEmpty }.joined(separator: " · "))
            Text(StudyMarks.total(questions(paper)).label)
        }
        scanContent(paper)
        Section("Questions") {
            Button("Add question or subquestion", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(.question, ["paper": paper.id])) }
            ForEach(questions(paper).sorted { $0["label"].localizedStandardCompare($1["label"]) == .orderedAscending }) { linked($0) }
        }
        Section("Section totals") {
            let totals = StudyMarks.sections(questions(paper))
            let sections = totals.keys.sorted()
            ForEach(sections, id: \.self) { section in
                VStack(alignment: .leading) {
                    Text(section.isEmpty ? "Unsectioned" : section)
                    Text(totals[section]?.label ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Totals count leaf subquestions once. Edit a question’s marks to correct them; parents show their children’s totals.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Mark schemes") {
            Button("Add mark scheme", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(.markScheme, ["paper": paper.id])) }
            ForEach(records.filter { $0.type == .markScheme && $0["paper"] == paper.id }) { linked($0) }
        }
    }
    @ViewBuilder private func scanContent(_ record: StudyRecord) -> some View {
        Section("Scanned pages · original order") {
            let pages = scans(record)
            Button(pages.isEmpty ? "Scan or import pages" : "Append scans, photos or files", systemImage: "camera") { capture = true }
            if !pages.isEmpty {
                Button("Open \(pages.count) pages in reader", systemImage: "book") { reader = StudyReaderSelection(pages: pages, title: record.title) }
                Text("Annotate with Folio’s reader tools. Editing study metadata keeps these originals and their order.").font(.caption).foregroundStyle(.secondary)
            }
            let missing = record.ids("pages").count - pages.count
            if missing > 0 { Text("\(missing) pages are unavailable or protected. Open their book in Books to unlock, or restore the original library folder.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private func questionContent(_ question: StudyRecord) -> some View {
        Section("Attempt and mark") {
            Text(StudyMarks.total(questionTree(question)).label)
            if !question["prompt"].isEmpty { Text(question["prompt"]).textSelection(.enabled) }
            if questionTree(question).count == 1 {
                Button("Record marks, working or feedback", systemImage: "pencil") { marking = true }.accessibilityIdentifier("study.mark")
            } else {
                Text("Mark the subquestions below. This question’s total is calculated from them.").font(.caption).foregroundStyle(.secondary)
            }
            if let paper = records.first(where: { $0.id == question["paper"] }) {
                linked(paper)
                let pages = questionScans(question, paper: paper)
                if !pages.isEmpty { Button("Open question scans", systemImage: "doc.viewfinder") { reader = StudyReaderSelection(pages: pages, title: paper.title + " · " + question.title) } }
                else { Text("Set its scan page range after scanning the paper.").font(.caption).foregroundStyle(.secondary) }
                Button("Add subquestion", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(.question, ["paper": paper.id, "parent": question.id, "topic": question["topic"]])) }
            }
            ForEach(records.filter { $0.type == .question && $0["parent"] == question.id }) { linked($0) }
        }
        Section("Learn from this question") {
            Button("Record mistake", systemImage: "arrow.trianglehead.clockwise") { makeMistake(question) }
            Button("Make flashcard", systemImage: "rectangle.on.rectangle") { makeCard(question) }
            Button("Retry tomorrow", systemImage: "calendar") { retryTomorrow(question) }
            if let date = question.date("retryAt") { Text("Retry \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
            ForEach(records.filter { ($0.type == .mistake && $0["question"] == question.id) || ($0.type == .card && $0["source"] == "record:" + question.id) }) { linked($0) }
        }
        Section("Working, corrections and feedback") {
            ForEach(["working", "answer", "correction", "feedback"], id: \.self) { field in
                if !question[field].isEmpty { DisclosureGroup(field.capitalized) { Text(question[field]).textSelection(.enabled) } }
            }
            ForEach(records.filter { $0.type == .markScheme && $0["paper"] == question["paper"] && ($0["question"].isEmpty || $0["question"] == question.id) }) { linked($0) }
        }
        if let topic = records.first(where: { $0.id == StudyRules.inherited("topic", for: question, in: records)["topic"] }) { Section("Topic") { linked(topic) } }
    }
    @ViewBuilder private func mistakeContent(_ mistake: StudyRecord) -> some View {
        Section("What I’m learning") {
            LabeledContent("Category", value: mistake["category"].isEmpty ? "Uncategorised" : mistake["category"])
            Text(mistake["what"]).textSelection(.enabled)
            DisclosureGroup("Correct reasoning") { Text(mistake["reasoning"]).textSelection(.enabled) }
        }
        Section("Retry") {
            Text("Try the original question before revealing the reasoning. Record how this attempt felt.").font(.caption).foregroundStyle(.secondary)
            if let question = records.first(where: { $0.id == mistake["question"] }) { linked(question) }
            Button("Resolved this time", systemImage: "checkmark.circle") { logRetry(mistake, resolved: true) }
            Button("Keep practising", systemImage: "arrow.clockwise") { logRetry(mistake, resolved: false) }
            Button("Make flashcard", systemImage: "rectangle.on.rectangle") { makeCard(mistake) }
        }
        Section("Links") {
            if let topic = records.first(where: { $0.id == mistake["topic"] }) { linked(topic) }
            ForEach(records.filter { $0.type == .card && $0["source"] == "record:" + mistake.id }) { linked($0) }
        }
        noteContent(mistake)
    }
    @ViewBuilder private func cardContent(_ card: StudyRecord) -> some View {
        Section("Prompt") { Text(card["prompt"]).textSelection(.enabled) }
        if !card["hint"].isEmpty { Section { DisclosureGroup("Hint") { Text(card["hint"]) } } }
        Section { DisclosureGroup("Answer") { Text(card["answer"]).textSelection(.enabled) } }
        if let topic = records.first(where: { $0.id == card["topic"] }) { Section("Topic") { linked(topic) } }
    }
    @ViewBuilder private func sourceContent(_ record: StudyRecord) -> some View {
        if !record["source"].isEmpty || !record["sourcePage"].isEmpty {
            Section("Source · verify imported content") {
                if record["source"].hasPrefix("record:"), let target = records.first(where: { $0.id == String(record["source"].dropFirst(7)) }) { linked(target) }
                else if !record["source"].isEmpty { Text(record["source"]).textSelection(.enabled) }
                if let pageID = record.ids("sourcePage").first, let page = storedPages.first(where: { $0.id == pageID && access.canRead($0) }) {
                    Button("Open source note", systemImage: "doc") { reader = StudyReaderSelection(pages: [page]) }
                }
            }
        }
    }
    @ViewBuilder private func noteContent(_ record: StudyRecord) -> some View {
        Section("Related notes") {
            Button("Edit note links", systemImage: "link") { draft = StudyDraft(record: record) }
            ForEach(books.filter { record.ids("noteBooks").contains($0.id) && $0.trashedAt == nil }) { book in
                NavigationLink { BookView(book: book, importer: importer) } label: { Label(book.title, systemImage: book.isLocked ? "lock" : "book") }
            }
            ForEach(books.filter { $0.trashedAt == nil && access.canOpen($0) }) { book in
                ForEach(book.activeSections.filter { record.ids("noteSections").contains($0.id) }) { section in
                    Button("\(book.title) · \(section.title)") { reader = StudyReaderSelection(pages: book.pages(in: section)) }
                }
            }
            ForEach(storedPages.filter { record.ids("notePages").contains($0.id) && access.canRead($0) }) { page in
                Button(page.title, systemImage: "doc") { reader = StudyReaderSelection(pages: [page]) }
            }
        }
    }
    @ViewBuilder private func historyContent(_ record: StudyRecord) -> some View {
        let events = records.filter { ($0.type == .attempt && ($0["question"] == record.id || $0["mistake"] == record.id)) || ($0.type == .review && $0["card"] == record.id) }
        if !events.isEmpty {
            Section("Practice history") {
                ForEach(events.sorted { ($0.date("date") ?? .distantPast) > ($1.date("date") ?? .distantPast) }) { event in
                    VStack(alignment: .leading) {
                        Text(event.date("date")?.formatted(date: .abbreviated, time: .shortened) ?? "Attempt").font(.caption).foregroundStyle(.secondary)
                        if event.type == .review { Text(event["rating"]) }
                        else if !event["resolved"].isEmpty { Text(event["resolved"] == "true" ? "Resolved" : "Still practising") }
                        else { Text("\(event["earned"].isEmpty ? "—" : event["earned"]) / \(event["marks"]) marks") }
                    }
                }
            }
        }
        if let item = items.first(where: { $0.id == record.id }), let snapshot = try? item.snapshot(), !snapshot.history.isEmpty {
            Section("Edit history") {
                ForEach(Array(snapshot.history.sorted { $0.date > $1.date }.prefix(20)), id: \.id) { version in
                    DisclosureGroup(version.date.formatted(date: .abbreviated, time: .shortened)) {
                        ForEach(version.record.type.fields.filter { !version.record[$0].isEmpty }, id: \.self) { field in
                            Text("\(field): \(version.record[field])").font(.caption).textSelection(.enabled)
                        }
                        Button("Restore these study fields") { save(version.record, notice: "Previous study version restored") }
                    }
                }
            }
        }
    }
    private func linked(_ record: StudyRecord) -> some View {
        NavigationLink { StudyDetailView(recordID: record.id, sessionID: sessionID) } label: { StudyRecordRow(record: record, records: records) }
            .accessibilityIdentifier("study.record." + record.id)
    }
    private func scans(_ record: StudyRecord) -> [NotePage] {
        record.ids("pages").compactMap { id in storedPages.first { $0.id == id && access.canRead($0) } }
    }
    private func questionScans(_ question: StudyRecord, paper: StudyRecord) -> [NotePage] {
        guard let range = StudyRules.pageRange(question, in: records) else { return [] }
        let ids = paper.ids("pages")
        guard range.upperBound <= ids.count else { return [] }
        return ids[(range.lowerBound - 1)..<range.upperBound].compactMap { id in storedPages.first { $0.id == id && access.canRead($0) } }
    }
    private func questions(_ paper: StudyRecord) -> [StudyRecord] { records.filter { $0.type == .question && $0["paper"] == paper.id } }
    private func questionTree(_ question: StudyRecord) -> [StudyRecord] {
        let ids = StudyRules.descendants(of: question.id, in: records.filter { $0.type == .question })
        return records.filter { ids.contains($0.id) }
    }
    private func orderedTopics(_ subject: StudyRecord) -> [StudyRecord] {
        let topics = records.filter { $0.type == .topic && $0["subject"] == subject.id }
        func path(_ topic: StudyRecord) -> String {
            var parts = [topic.title]; var current = topic; var seen: Set<String> = [topic.id]
            while let parent = topics.first(where: { $0.id == current["parent"] }), seen.insert(parent.id).inserted { parts.insert(parent.title, at: 0); current = parent }
            return parts.joined(separator: " / ")
        }
        return topics.sorted { path($0).localizedStandardCompare(path($1)) == .orderedAscending }
    }
    private func depth(_ topic: StudyRecord) -> Int {
        var count = 0; var current = topic; var seen: Set<String> = [topic.id]
        while let parent = records.first(where: { $0.id == current["parent"] }), seen.insert(parent.id).inserted { count += 1; current = parent }
        return min(count, 10)
    }
    private func makeCard(_ source: StudyRecord) {
        let topic = source.type == .question ? StudyRules.inherited("topic", for: source, in: records)["topic"] : source["topic"]
        draft = StudyDraft(record: StudyRecord(.card, ["topic": topic, "source": "record:" + source.id,
            "prompt": source.type == .question ? source["prompt"] : source.title,
            "answer": source.type == .mistake ? source["reasoning"] : source["answer"]]))
    }
    private func makeMistake(_ question: StudyRecord) {
        draft = StudyDraft(record: StudyRecord(.mistake, ["question": question.id, "topic": StudyRules.inherited("topic", for: question, in: records)["topic"], "title": "Question " + question.title,
            "what": question["working"], "reasoning": question["correction"]]))
    }
    private func retryTomorrow(_ record: StudyRecord) {
        var changed = record; changed["retryAt"] = ISO8601DateFormatter().string(from: .now.addingTimeInterval(86400))
        save(changed, notice: "Retry scheduled for tomorrow")
    }
    private func save(_ record: StudyRecord, notice: String) {
        do { try StudyStore.write([record], context: context); self.notice = notice; feedback.success += 1 }
        catch { self.error = error.localizedDescription; feedback.error += 1 }
    }
    private func logRetry(_ mistake: StudyRecord, resolved: Bool) {
        var changed = mistake; changed["resolved"] = resolved ? "true" : "false"
        changed["retryAt"] = resolved ? "" : ISO8601DateFormatter().string(from: .now.addingTimeInterval(86400))
        var event = StudyRecord(.attempt, ["mistake": mistake.id, "resolved": changed["resolved"], "date": ISO8601DateFormatter().string(from: .now)])
        event["session"] = sessionID ?? ""
        do { try StudyStore.write([changed, event], context: context); notice = resolved ? "Retry saved · Resolved" : "Retry saved · Try again tomorrow"; feedback.success += 1 }
        catch { self.error = error.localizedDescription; feedback.error += 1 }
    }
}
