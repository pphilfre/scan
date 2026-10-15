import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StudyTransferView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var items: [StudyItem]
    @State private var text = ""
    @State private var parsed: StudyParseResult?
    @State private var rows: [StudyImportRow] = []
    @State private var subject = ""
    @State private var paper = ""
    @State private var message: String?
    @State private var exportFile: ExportFile?
    @State private var feedback = StudyFeedbackState()
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var plan: StudyImportPlan { StudyInterchange.plan(rows, existing: records, subject: subject, paper: paper) }
    private var issues: [StudyIssue] {
        Dictionary(((parsed?.issues ?? []) + plan.issues).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values.sorted { $0.id < $1.id }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ask an external AI to format your material, paste its JSON here, then check each record before saving. AI content is unverified and stays editable.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Copy prompt for AI", systemImage: "document.on.clipboard") { UIPasteboard.general.string = StudyInterchange.aiPrompt; message = "AI prompt copied" }
                    DisclosureGroup("Format rules and example") {
                        Text(StudyInterchange.aiPrompt).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Load example into paste area") { text = StudyInterchange.example; clearPreview() }
                    }
                }
                Section("Paste study data") {
                    TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 240)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityLabel("Study import data").accessibilityIdentifier("study.import.text")
                        .onChange(of: text) { _, _ in clearPreview() }
                    PasteButton(payloadType: String.self) { values in text = values.joined(separator: "\n") }
                    Button("Parse and validate", systemImage: "checkmark.magnifyingglass", action: parse).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("study.import.parse")
                }
                if parsed != nil {
                    Section("Destinations for records without a link") {
                        Picker("Subject", selection: $subject) { Text("Choose if needed").tag(""); ForEach(records.filter { $0.type == .subject }) { Text($0.title).tag($0.id) } }
                        Picker("Paper", selection: $paper) { Text("Choose if needed").tag(""); ForEach(records.filter { $0.type == .paper }) { Text($0.title).tag($0.id) } }
                        Text("Papers are always saved in Past Papers. Choose an existing scanned paper when pasting its questions separately.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Preview · review before saving") {
                        ForEach($rows) { $row in
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(row.record.type.name): \(row.record.title)").font(.headline)
                                Text(row.record.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                if let match = row.match {
                                    Text("Possible duplicate: \(match.title). Repeated imports default to Skip.").font(.caption).foregroundStyle(.secondary)
                                    if items.contains(where: { $0.id == match.id && $0.removedAt != nil }) {
                                        Text("Previously deleted. Update restores it; Import as new keeps the deletion and creates a separate record.").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Picker("On import", selection: $row.action) { ForEach(StudyDuplicateAction.allCases) { Text($0.rawValue).tag($0) } }
                                } else {
                                    Picker("On import", selection: $row.action) { Text("Add").tag(StudyDuplicateAction.new); Text("Skip").tag(StudyDuplicateAction.skip) }
                                }
                                DisclosureGroup("Fields") {
                                    ForEach(row.record.type.fields.filter { !row.record[$0].isEmpty }, id: \.self) { field in
                                        VStack(alignment: .leading) { Text(field).font(.caption).foregroundStyle(.secondary); Text(row.record[field]).textSelection(.enabled) }
                                    }
                                }
                            }.padding(.vertical, 5)
                        }
                    }
                    if !issues.isEmpty {
                        Section("Correct these fields in the paste area, then validate again") {
                            ForEach(issues) { Text($0.description).foregroundStyle(.red).textSelection(.enabled) }
                        }
                    }
                    Section("Final summary") {
                        Text("\(plan.additions) additions · \(plan.updates) updates · \(plan.skipped) skipped · \(issues.count) errors").accessibilityIdentifier("study.import.summary")
                        Text("Updates preserve omitted fields and the existing order of scanned pages. Import as new creates fresh IDs and redirects links within this import.").font(.caption).foregroundStyle(.secondary)
                        Button("Confirm import", systemImage: "square.and.arrow.down", action: commit)
                            .disabled(!issues.isEmpty || plan.records.isEmpty).accessibilityIdentifier("study.import.confirm")
                    }
                }
                if let message { Section { Text(message).textSelection(.enabled).accessibilityIdentifier("study.import.result") } }
                Section("Export and backup") {
                    Button("Copy study data", systemImage: "doc.on.doc") { export(copy: true) }
                    Button("Export study JSON file", systemImage: "square.and.arrow.up") { export(copy: false) }
                    Text("Includes study records and practice history. Scans, ink, deletions and edit history are backed up with your working folder in Settings.").font(.caption).foregroundStyle(.secondary)
                }
            }.scrollDismissesKeyboard(.interactively).navigationTitle("Study import & export").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $exportFile) { ShareSheet(items: [$0.url]) }
                .onChange(of: subject) { _, _ in refreshRows() }
                .onChange(of: paper) { _, _ in refreshRows() }
                .studyFeedback(feedback)
        }
    }
    private func clearPreview() { parsed = nil; rows = []; message = nil }
    private func parse() {
        let result = StudyInterchange.parse(text); parsed = result
        refreshRows()
        if !(result.issues + plan.issues).isEmpty { feedback.error += 1 }
        message = "Preview ready. Correct any errors and choose how to handle duplicates."
    }
    private func refreshRows() {
        guard let parsed else { return }
        let reserved = StudyStore.records(items, includingRemoved: true)
        rows = StudyInterchange.rows(parsed.records, existing: reserved, subject: subject, paper: paper)
    }
    private func commit() {
        let final = plan
        guard issues.isEmpty else { feedback.error += 1; return }
        do {
            try StudyStore.write(final.records, context: context)
            message = "Import complete · " + final.summary
            // Recompute against the newly saved store; a second confirmation
            // cannot create a second copy or reapply an obsolete preview.
            parsed = nil; rows = []; feedback.success += 1
        } catch { message = error.localizedDescription; feedback.error += 1 }
    }
    private func export(copy: Bool) {
        do {
            // Explicitly decode every active item so damaged payloads are never
            // silently omitted from a purported backup.
            try StudyStore.reconcile(context)
            if context.hasChanges { try LibraryPersistence.save(context) }
            let active = try StudyStore.items(context).filter { $0.removedAt == nil }.map { try $0.decoded() }
            let data = try StudyInterchange.export(active)
            if copy { UIPasteboard.general.string = data; message = "Study data copied" }
            else {
                let url = URL.temporaryDirectory.appending(path: "Folio-study-\(UUID().uuidString).json")
                try Data(data.utf8).write(to: url, options: .atomic); exportFile = ExportFile(url: url)
                message = "Study export ready"
            }
        } catch { message = error.localizedDescription; feedback.error += 1 }
    }
}
