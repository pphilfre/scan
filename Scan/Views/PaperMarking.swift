import SwiftUI
import SwiftData

struct PaperMarkingView: View {
    let paperID: String
    @Environment(AccessController.self) private var access
    @Query private var items: [StudyItem]
    @Query private var storedPages: [NotePage]
    @State private var selectedPage: UUID?
    @State private var draft: StudyDraft?
    @State private var capture = false
    @State private var reader: StudyReaderSelection?
    @State private var importer = ImportCoordinator()
    @State private var feedback = StudyFeedbackState()
    @State private var notice: String?
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var paper: StudyRecord? { records.first { $0.id == paperID } }
    private var questions: [StudyRecord] { records.filter { $0.type == .question && $0["paper"] == paperID } }
    private var leaves: [StudyRecord] { StudyMarks.leaves(questions) }
    private var pages: [NotePage] {
        (paper?.ids("pages") ?? []).compactMap { id in storedPages.first { $0.id == id && access.canRead($0) } }
    }
    private var current: NotePage? { pages.first { $0.id == selectedPage } ?? pages.first }
    private var pageNumber: Int? {
        guard let current, let index = paper?.ids("pages").firstIndex(of: current.id) else { return nil }
        return index + 1
    }
    private var onPage: [StudyRecord] {
        guard let number = pageNumber else { return [] }
        return leaves.filter { StudyRules.pageRange($0, in: questions)?.contains(number) == true }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var unassigned: [StudyRecord] {
        leaves.filter { question in
            guard let range = StudyRules.pageRange(question, in: questions) else { return true }
            // Include ranges with no accessible pages: every question stays reachable.
            return !pages.contains { page in
                guard let index = paper?.ids("pages").firstIndex(of: page.id) else { return false }
                return range.contains(index + 1)
            }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let notice { Label(notice, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(StudyPalette.progress).accessibilityIdentifier("paper.mark.saved") }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Marks on the page.").font(.system(.title2, design: .rounded, weight: .bold))
                        Text("\(StudyMarks.total(questions).marked) of \(leaves.count) questions marked").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Add scans", systemImage: "viewfinder") { capture = true }
                        if let paper, !pages.isEmpty {
                            Button("Open \(pages.count) pages in reader", systemImage: "book") { reader = StudyReaderSelection(pages: pages, title: paper.title) }
                        }
                        ForEach(records.filter { $0.type == .markScheme && $0["paper"] == paperID }) { scheme in
                            NavigationLink(scheme.title) { StudyDetailView(recordID: scheme.id) }
                        }
                    } label: { Label("Scans & scheme", systemImage: "doc.text.magnifyingglass").font(.caption) }
                }
                if !pages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(pages) { page in pageButton(page) }
                        }.padding(3)
                    }
                    if let current, let pageNumber {
                        Button {
                            reader = StudyReaderSelection(pages: [current], title: "Page \(pageNumber)")
                        } label: {
                            PageThumbnail(page: current).aspectRatio(0.71, contentMode: .fit)
                                .frame(maxHeight: 460).frame(maxWidth: .infinity)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .bottomTrailing) {
                                    Label("Zoom & annotate", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption.weight(.medium)).padding(10).background(.regularMaterial, in: Capsule()).padding(12)
                                }
                        }.buttonStyle(.plain).accessibilityLabel("Open page \(pageNumber) to zoom or annotate").accessibilityIdentifier("paper.mark.preview")
                        HStack {
                            Text("Page \(pageNumber)").font(.title3.weight(.semibold))
                            Spacer()
                            let marks = StudyMarks.total(onPage)
                            if marks.marked > 0 { Text("\(marks.earned.formatted()) / \(marks.available.formatted()) marks").font(.subheadline.weight(.medium)).foregroundStyle(StudyPalette.progress) }
                        }
                    }
                    ForEach(onPage) { questionRow($0) }
                    if onPage.isEmpty {
                        Text("Add a question’s marks, or use one total for this page. Use one approach for the same working to avoid counting marks twice.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if onPage.isEmpty {
                        Button("Mark this page", systemImage: "pencil.tip") { addQuestion(pageTotal: true) }
                            .buttonStyle(.borderedProminent).tint(StudyPalette.progress).accessibilityIdentifier("paper.mark.total")
                    }
                    if !onPage.contains(where: { $0["markingMode"] == "pageTotal" }) {
                        Button("Add a question", systemImage: "plus.circle.fill") { addQuestion() }
                            .buttonStyle(.bordered).tint(StudyPalette.progress).accessibilityIdentifier("paper.mark.add")
                    } else {
                        Text("This page uses one total. Tap it to edit marks or add a topic. To mark individual questions instead, remove this total in the question’s details.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let total = onPage.first(where: { $0["markingMode"] == "pageTotal" }) {
                            NavigationLink("Page total details") { StudyDetailView(recordID: total.id) }.font(.caption)
                        }
                    }
                    pageNavigation
                } else {
                    ContentUnavailableView("Bring your working in", systemImage: "viewfinder", description: Text("Scan your paper to mark beside each page. You can also mark existing questions below."))
                    Button("Scan my working", systemImage: "camera") { capture = true }.buttonStyle(.borderedProminent).tint(StudyPalette.focus)
                    Button("Add a question without scans", systemImage: "plus") { addQuestion() }.buttonStyle(.bordered)
                }
                if (paper?.ids("pages").count ?? 0) > pages.count {
                    Label("Some scans are unavailable. Unlock their book or restore the original working folder.", systemImage: "lock.doc").font(.caption).foregroundStyle(.secondary)
                }
                if !unassigned.isEmpty {
                    DisclosureGroup("Questions without an available scan (\(unassigned.count))") {
                        VStack(spacing: 12) { ForEach(unassigned) { questionRow($0) } }.padding(.top, 12)
                    }.accessibilityIdentifier("paper.mark.unassigned")
                }
            }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.sheet(item: $draft) { item in
            PageQuestionEditor(question: item.record) {
                notice = "Marks saved for \(item.record.title.isEmpty ? "this question" : item.record.title)"; feedback.success += 1
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $capture) { StudyCaptureView(recordID: paperID, importer: importer) }
        .fullScreenCover(item: $reader) { selection in
            if let first = selection.pages.first { PageReader(pages: selection.pages, initialID: first.id, importer: importer, preservePageOrder: true, titleOverride: selection.title) }
        }
        .studyFeedback(feedback)
    }
    private func pageButton(_ page: NotePage) -> some View {
        let number = (paper?.ids("pages").firstIndex(of: page.id) ?? 0) + 1
        let linked = leaves.filter { StudyRules.pageRange($0, in: questions)?.contains(number) == true }
        let done = !linked.isEmpty && linked.allSatisfy { $0.number("earned") != nil }
        return Button { selectedPage = page.id; notice = nil; feedback.selection += 1 } label: {
            VStack(spacing: 6) {
                PageThumbnail(page: page).frame(width: 56, height: 76).clipShape(RoundedRectangle(cornerRadius: 5))
                HStack(spacing: 3) {
                    if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(StudyPalette.progress) }
                    Text("\(number)").foregroundStyle(.primary)
                }.font(.caption.weight(.semibold))
            }.padding(8).background(current?.id == page.id ? StudyPalette.focus.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(current?.id == page.id ? StudyPalette.focus : Color.clear, lineWidth: 2) }
        }.buttonStyle(.plain).accessibilityLabel("Page \(number)\(done ? ", marked" : "")")
            .accessibilityIdentifier("paper.page.\(number)").accessibilityAddTraits(current?.id == page.id ? .isSelected : [])
    }
    private func questionRow(_ question: StudyRecord) -> some View {
        Button { draft = StudyDraft(record: question) } label: {
            HStack(spacing: 14) {
                let earned = question.number("earned")
                let available = question.number("marks") ?? 0
                StudyDial(progress: available > 0 ? (earned ?? 0) / available : 0,
                    value: earned?.formatted() ?? "—", caption: available > 0 ? "of \(available.formatted())" : "unmarked", size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.title).font(.headline).foregroundStyle(.primary)
                    let topicID = StudyRules.inherited("topic", for: question, in: questions)["topic"]
                    if let topic = records.first(where: { $0.id == topicID }) {
                        Label(topic.title, systemImage: "tag.fill").font(.caption).foregroundStyle(StudyPalette.focus)
                    } else { Text("Add a topic").font(.caption).foregroundStyle(.secondary) }
                    if let range = StudyRules.pageRange(question, in: questions), range.lowerBound != range.upperBound {
                        Text("Pages \(range.lowerBound)–\(range.upperBound) · counted once").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0); Image(systemName: "pencil").foregroundStyle(StudyPalette.progress)
            }.padding(16).background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("paper.question." + question.id)
    }
    private var pageNavigation: some View {
        HStack {
            Button("Previous", systemImage: "chevron.left") { movePage(-1) }.disabled(current?.id == pages.first?.id)
            Spacer()
            Button("Next page", systemImage: "chevron.right") { movePage(1) }.disabled(current?.id == pages.last?.id).accessibilityIdentifier("paper.page.next")
        }.buttonStyle(.bordered).padding(.vertical, 8)
    }
    private func movePage(_ offset: Int) {
        guard let current, let index = pages.firstIndex(where: { $0.id == current.id }), pages.indices.contains(index + offset) else { return }
        selectedPage = pages[index + offset].id; notice = nil; feedback.selection += 1
    }
    private func addQuestion(pageTotal: Bool = false) {
        var question = StudyRecord(.question, ["paper": paperID])
        if let pageNumber { question["pageStart"] = String(pageNumber) }
        if pageTotal, let pageNumber { question["label"] = "Page \(pageNumber) total"; question["markingMode"] = "pageTotal" }
        draft = StudyDraft(record: question)
    }
}

struct PageQuestionEditor: View {
    let question: StudyRecord
    var sessionID: String?
    var onSave: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [StudyItem]
    @State private var draft: StudyRecord
    @State private var topicPicker = false
    @State private var discard = false
    @State private var error: String?
    @State private var feedback = StudyFeedbackState()
    @FocusState private var focused: Bool
    init(question: StudyRecord, sessionID: String? = nil, onSave: @escaping () -> Void) {
        self.question = question; self.sessionID = sessionID; self.onSave = onSave
        _draft = State(initialValue: question)
    }
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var isNew: Bool { !records.contains { $0.id == question.id } }
    private func binding(_ field: String) -> Binding<String> { Binding(get: { draft[field] }, set: { draft[field] = $0 }) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if isNew && draft["markingMode"] != "pageTotal" {
                        TextField("Question number, e.g. 3(b) or Page 1 total", text: binding("label"))
                            .font(.headline).textFieldStyle(.roundedBorder).focused($focused).accessibilityIdentifier("study.field.label")
                        Text("Use individual questions or a page total for the same working.").font(.caption).foregroundStyle(.secondary)
                    } else { Text(question.title).font(.system(.title2, design: .rounded, weight: .bold)) }
                    HStack(spacing: 22) {
                        let maximum = draft.number("marks") ?? 0
                        StudyDial(progress: maximum > 0 ? (draft.number("earned") ?? 0) / maximum : 0,
                            value: draft["earned"].isEmpty ? "—" : draft["earned"], caption: "of \(maximum.formatted())", size: 110)
                        VStack(alignment: .leading, spacing: 14) {
                            markField("Marks available", field: "marks")
                            markField("Marks achieved", field: "earned")
                        }
                    }
                    HStack(spacing: 18) {
                        Button { adjust(-1) } label: { Image(systemName: "minus").frame(width: 48, height: 44) }
                            .buttonStyle(.bordered).disabled((draft.number("earned") ?? 0) <= 0).accessibilityLabel("Decrease achieved marks")
                        Button("Full marks") { draft["earned"] = draft["marks"]; feedback.selection += 1 }
                            .buttonStyle(.bordered).disabled(draft.number("marks") == nil)
                        Button { adjust(1) } label: { Image(systemName: "plus").frame(width: 48, height: 44) }
                            .buttonStyle(.bordered).disabled(draft.number("marks") == nil || (draft.number("earned") ?? -1) >= (draft.number("marks") ?? 0)).accessibilityLabel("Increase achieved marks")
                    }.frame(maxWidth: .infinity).tint(StudyPalette.progress)
                    HStack {
                        Button("Zero marks") { draft["earned"] = "0"; feedback.selection += 1 }.disabled(draft.number("marks") == nil)
                        Spacer()
                        Button("Leave unmarked") { draft["earned"] = ""; feedback.selection += 1 }
                    }.font(.subheadline)
                    Button { topicPicker = true; focused = false } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "tag.fill").foregroundStyle(StudyPalette.focus)
                            Text(records.first { $0.id == draft["topic"] }?.title ?? "Add a topic").foregroundStyle(.primary)
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(18).background(StudyPalette.focus.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).accessibilityIdentifier("paper.mark.topic")
                    let inheritedTopic = StudyRules.inherited("topic", for: draft, in: records)["topic"]
                    if draft["topic"].isEmpty, let topic = records.first(where: { $0.id == inheritedTopic }) {
                        Text("Uses parent topic: \(topic.title). Choose a topic above to override it.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Page range") {
                        VStack(spacing: 12) {
                            TextField("First scan page", text: binding("pageStart")).keyboardType(.numberPad).focused($focused)
                            TextField("Last scan page (optional)", text: binding("pageEnd")).keyboardType(.numberPad).focused($focused)
                        }.textFieldStyle(.roundedBorder).padding(.top, 12)
                    }
                    DisclosureGroup("Working, corrections and feedback") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(["working", "correction", "feedback"], id: \.self) { field in
                                Text(field.capitalized).font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: binding(field)).frame(minHeight: 100).padding(8)
                                    .background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel(field.capitalized)
                            }
                        }.padding(.top, 12)
                    }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("study.editor.error") }
                    Button("Save marks", systemImage: "checkmark") { save() }.buttonStyle(.borderedProminent).controlSize(.large).tint(StudyPalette.progress)
                        .frame(maxWidth: .infinity).accessibilityIdentifier("paper.mark.save")
                }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(StudyPalette.canvas).navigationTitle(isNew ? "Add marks" : "Record marks").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if draft != question { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("study.save") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
                }
                .interactiveDismissDisabled(draft != question)
                .confirmationDialog("Discard these unsaved marks?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
                .sheet(isPresented: $topicPicker) {
                    StudyTopicPicker(selection: binding("topic"), subjectID: records.first { $0.id == draft["paper"] }?["subject"] ?? "")
                }.studyFeedback(feedback)
        }
    }
    private func markField(_ title: String, field: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: binding(field)).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                .font(.title3.monospacedDigit()).focused($focused).accessibilityIdentifier("study.field." + field)
        }
    }
    private func adjust(_ delta: Double) {
        let maximum = draft.number("marks") ?? 0
        draft["earned"] = String(min(maximum, max(0, (draft.number("earned") ?? 0) + delta)))
        feedback.selection += 1
    }
    private func save() {
        do {
            draft["label"] = draft["label"].trimmingCharacters(in: .whitespacesAndNewlines)
            if isNew && records.contains(where: { $0.type == .question && $0["paper"] == draft["paper"] && $0["label"].localizedCaseInsensitiveCompare(draft["label"]) == .orderedSame }) {
                throw StudyFailure(issues: [.init(record: draft.id, field: "label", message: "This question already exists. Open its marks, or use a different question number.")])
            }
            if draft.number("earned") != nil { draft["retryAt"] = "" }
            let marksChanged = isNew || question["earned"] != draft["earned"] || question["marks"] != draft["marks"]
            try StudyStore.write(StudyStore.attempt(question, replacing: draft, session: sessionID, recordAttempt: marksChanged), context: context)
            feedback.success += 1; onSave(); dismiss()
        } catch { self.error = error.localizedDescription; feedback.error += 1 }
    }
}
