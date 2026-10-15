import SwiftUI
import SwiftData

struct StudyEditor: View {
    let record: StudyRecord
    var sessionID: String?
    var onSave: (() -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [StudyItem]
    @State private var draft: StudyRecord
    @State private var error: String?
    @State private var feedback = StudyFeedbackState()
    @State private var linkingNotes = false
    init(record: StudyRecord, sessionID: String? = nil, onSave: (() -> Void)? = nil) {
        self.record = record; self.sessionID = sessionID; self.onSave = onSave
        _draft = State(initialValue: record)
    }
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var isNew: Bool { !records.contains { $0.id == record.id } }
    private func binding(_ key: String) -> Binding<String> { Binding(get: { draft[key] }, set: { draft[key] = $0 }) }
    private var editableFields: [String] {
        draft.type.fields.filter { !["pages", "noteBooks", "noteSections", "notePages", "sourcePage", "interval", "repetitions", "due", "retryAt", "durationMinutes", "timerState", "timerDeadline", "timerRemaining", "completedAt", "markingMode"].contains($0) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if draft.type == .paper {
                        fieldEditor("title")
                        fieldEditor("subject")
                        if draft["subject"].isEmpty { fieldEditor("subjectName") }
                        DisclosureGroup("Board, year and other details") {
                            ForEach(editableFields.filter { !["title", "subject", "subjectName"].contains($0) }, id: \.self) { fieldEditor($0) }
                        }
                        Text("Next: sit the paper with a timer, or scan work you’ve already done.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(editableFields, id: \.self) { field in fieldEditor(field) }
                    }
                }
                if [.topic, .mistake].contains(draft.type) {
                    Section("Related notes") {
                        Text("\(draft.ids("noteBooks").count) books · \(draft.ids("noteSections").count) dividers · \(draft.ids("notePages").count) pages").font(.caption)
                        Button("Choose notes", systemImage: "link") { linkingNotes = true }
                    }
                }
                if [.question, .mistake].contains(draft.type) {
                    Section("Another attempt") {
                        Toggle("Schedule a retry", isOn: Binding(get: { !draft["retryAt"].isEmpty }, set: { draft["retryAt"] = $0 ? ISO8601DateFormatter().string(from: .now.addingTimeInterval(86400)) : "" }))
                        if !draft["retryAt"].isEmpty {
                            DatePicker("Retry", selection: Binding(get: { draft.date("retryAt") ?? .now }, set: { draft["retryAt"] = ISO8601DateFormatter().string(from: $0) }))
                        }
                    }
                }
                if draft.type == .card {
                    Section {
                        Text("New cards enter the review queue immediately. Rating a card sets its next review.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("study.editor.error") } }
            }
            .navigationTitle("\(isNew ? "New" : "Edit") \(record.type.name.lowercased())")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("study.save") }
            }
            .sheet(isPresented: $linkingNotes) { StudyNotePicker(record: $draft) }
            .studyFeedback(feedback)
        }
    }
    @ViewBuilder private func fieldEditor(_ field: String) -> some View {
        if let kinds = StudyRules.references(draft.type)[field] {
            let candidates = records.filter { candidate in
                guard kinds.contains(candidate.type), candidate.id != draft.id else { return false }
                if field == "parent" {
                    if StudyRules.descendants(of: draft.id, in: records).contains(candidate.id) { return false }
                    return candidate[draft.type == .topic ? "subject" : "paper"] == draft[draft.type == .topic ? "subject" : "paper"]
                }
                if draft.type == .markScheme && field == "question" { return candidate["paper"] == draft["paper"] }
                return true
            }
            Picker(label(field), selection: binding(field)) {
                Text("None").tag("")
                ForEach(candidates) { Text(referenceTitle($0)).tag($0.id) }
            }.onChange(of: draft[field]) { _, _ in
                if field == "subject" || field == "paper" { draft["parent"] = "" }
            }
        } else if field == "confidence" {
            Picker("Confidence", selection: Binding(get: { draft[field].isEmpty ? "New" : draft[field] }, set: { draft[field] = $0 })) {
                ForEach(StudyRules.confidence, id: \.self) { Text($0).tag($0) }
            }
        } else if field == "category" {
            VStack(alignment: .leading) {
                TextField("Category (optional)", text: binding(field))
                Menu("Suggestions") { ForEach(StudyRules.categories, id: \.self) { category in Button(category) { draft[field] = category } } }
            }
        } else if field == "resolved" {
            Toggle("Resolved", isOn: Binding(get: { draft[field] == "true" }, set: { draft[field] = $0 ? "true" : "false" }))
        } else if ["prompt", "answer", "what", "reasoning", "working", "correction", "feedback", "notes"].contains(field) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label(field)).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: binding(field)).frame(minHeight: field == "notes" ? 70 : 110).accessibilityLabel(label(field)).accessibilityIdentifier("study.field." + field)
            }
        } else {
            TextField(label(field), text: binding(field))
                .keyboardType(["marks", "earned"].contains(field) ? .decimalPad : ["year", "pageStart", "pageEnd"].contains(field) ? .numberPad : .default)
                .accessibilityIdentifier("study.field." + field)
        }
    }
    private func referenceTitle(_ record: StudyRecord) -> String {
        let owner = records.first { $0.id == record[record.type == .topic ? "subject" : "paper"] }
        return [owner?.title, record.title].compactMap { $0 }.joined(separator: " · ")
    }
    private func label(_ field: String) -> String {
        ["title": "Title", "board": "Exam board", "qualification": "Qualification", "subjectName": "Subject name (no course required)", "year": "Year", "session": "Exam session", "number": "Paper number", "label": "Question number, e.g. 1(a)", "marks": "Marks available", "earned": "Marks achieved", "pageStart": "First scan page (1-based)", "pageEnd": "Last scan page (optional)", "source": "Source (record:ID, URL or description)", "what": "What I did", "reasoning": "Correct reasoning", "feedback": "Teacher feedback", "correction": "Corrections", "parent": "Parent", "topic": "Topic (optional)", "subject": "Subject", "paper": "Paper", "question": "Original question", "prompt": "Prompt", "answer": "Answer", "working": "Working", "hint": "Hint", "notes": "Notes"][field] ?? field.capitalized
    }
    private func save() {
        do {
            if draft.type == .paper, let current = records.first(where: { $0.id == draft.id }) {
                // Editing a title must not rewind a clock that finished while
                // this sheet was open, or replace newly appended scans.
                for field in ["durationMinutes", "timerState", "timerDeadline", "timerRemaining", "completedAt", "pages"] { draft[field] = current[field] }
            }
            if draft.type == .question && draft.number("earned") != nil { draft["retryAt"] = "" }
            let marksChanged = isNew || record["earned"] != draft["earned"] || record["marks"] != draft["marks"]
            let changes = draft.type == .question ? StudyStore.attempt(record, replacing: draft, session: sessionID, recordAttempt: marksChanged) : [draft]
            try StudyStore.write(changes, context: context)
            feedback.success += 1; onSave?(); dismiss()
        } catch { self.error = error.localizedDescription; feedback.error += 1 }
    }
}

struct StudyMarkEditor: View {
    let question: StudyRecord
    var sessionID: String?
    var onSave: () -> Void
    var body: some View {
        PageQuestionEditor(question: question, sessionID: sessionID, onSave: onSave)
    }
}

struct StudyNotePicker: View {
    @Binding var record: StudyRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(AccessController.self) private var access
    @Query(sort: \Notebook.title) private var books: [Notebook]
    @Query(sort: \NotePage.rank) private var pages: [NotePage]
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Text("Links open the original notes. Locked books must be unlocked in Books before choosing their contents.").font(.caption).foregroundStyle(.secondary)
                if record.type == .topic {
                    Section("Books and dividers") {
                        ForEach(books.filter { $0.trashedAt == nil && access.canOpen($0) }) { book in
                            linkRow(book.title, id: book.id, field: "noteBooks")
                            ForEach(book.activeSections.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { section in
                                linkRow("\(book.title) · \(section.title)", id: section.id, field: "noteSections")
                            }
                        }
                    }
                }
                Section("Pages") {
                    ForEach(pages.filter { access.canRead($0) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }) { page in
                        linkRow("\(page.book?.title ?? "Unfiled") · \(page.title)", id: page.id, field: "notePages")
                    }
                }
            }.searchable(text: $search).navigationTitle("Link notes")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func linkRow(_ title: String, id: UUID, field: String) -> some View {
        Button {
            var ids = record.ids(field)
            if ids.contains(id) { ids.removeAll { $0 == id } } else { ids.append(id) }
            record.setIDs(field, ids)
        } label: {
            HStack { Text(title).foregroundStyle(.primary); Spacer(); if record.ids(field).contains(id) { Image(systemName: "checkmark") } }
        }
    }
}
