import SwiftUI
import SwiftData

enum PaperStage: String, CaseIterable, Identifiable {
    case sit = "Sit", scan = "Scan", mark = "Mark", reflect = "Reflect"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .sit: "timer"; case .scan: "viewfinder"; case .mark: "pencil.tip"; case .reflect: "chart.bar.xaxis" }
    }
}

struct PaperWorkspace: View {
    let recordID: String
    @Environment(\.modelContext) private var context
    @Environment(AccessController.self) private var access
    @Environment(\.scenePhase) private var scenePhase
    @Query private var items: [StudyItem]
    @Query private var storedPages: [NotePage]
    @State private var stage: PaperStage = .sit
    @State private var loaded = false
    @State private var capture = false
    @State private var draft: StudyDraft?
    @State private var reader: StudyReaderSelection?
    @State private var importer = ImportCoordinator()
    @State private var reset = false
    @State private var finishEarly = false
    @State private var error: String?
    @State private var feedback = StudyFeedbackState()
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var paper: StudyRecord? { records.first { $0.id == recordID } }
    private var questions: [StudyRecord] { records.filter { $0.type == .question && $0["paper"] == recordID } }
    private var total: StudyMarks { StudyMarks.total(questions) }
    var body: some View {
        Group {
            if let paper {
                VStack(spacing: 0) {
                    stageRail(paper).padding(.horizontal, 16).padding(.vertical, 12)
                    if stage == .mark {
                        PaperMarkingView(paperID: paper.id)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                switch stage {
                                case .sit: sitting(paper)
                                case .scan: scanning(paper)
                                case .reflect: reflection(paper)
                                case .mark: EmptyView()
                                }
                            }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
                        }
                    }
                }.navigationTitle(paper.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Edit paper details", systemImage: "pencil") { draft = StudyDraft(record: paper) }
                                Button("Add question", systemImage: "plus") { draft = StudyDraft(record: StudyRecord(.question, ["paper": paper.id])) }
                                Button("Add mark scheme", systemImage: "doc.text") { draft = StudyDraft(record: StudyRecord(.markScheme, ["paper": paper.id])) }
                                NavigationLink("All details and history", destination: StudyDetailView(recordID: paper.id, showPaperWorkspace: false))
                                if !paper["timerState"].isEmpty { Button("Reset sitting timer", systemImage: "arrow.counterclockwise") { reset = true } }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                    .sheet(isPresented: $capture) { StudyCaptureView(recordID: paper.id, importer: importer) }
                    .confirmationDialog("Reset this sitting? Your scans and marks are kept.", isPresented: $reset, titleVisibility: .visible) {
                        Button("Reset timer", role: .destructive) { save(PaperClock.reset(paper)) }
                    }
                    .confirmationDialog("Finish the sitting and scan your work?", isPresented: $finishEarly, titleVisibility: .visible) {
                        Button("Finish sitting") { if save(PaperClock.finish(paper)) { stage = .scan } }
                    }
                    .task {
                        guard !loaded else { return }; loaded = true
                        if ["running", "paused"].contains(paper["timerState"]) { stage = .sit }
                        else if !paper.ids("pages").isEmpty { stage = total.count > 0 && total.marked == total.count ? .reflect : .mark }
                        else if paper["timerState"] == "finished" { stage = .scan }
                        checkDeadline()
                    }
                    .task(id: paper["timerDeadline"]) {
                        guard paper["timerState"] == "running", let deadline = paper.date("timerDeadline") else { return }
                        let delay = max(0, deadline.timeIntervalSinceNow)
                        do { try await Task.sleep(for: .seconds(delay)); checkDeadline() } catch { }
                    }
            } else { ContentUnavailableView("Paper removed", systemImage: "doc") }
        }.background(StudyPalette.canvas)
            .sheet(item: $draft) { StudyEditor(record: $0.record) }
            .fullScreenCover(item: $reader) { selection in
                if let first = selection.pages.first { PageReader(pages: selection.pages, initialID: first.id, importer: importer, preservePageOrder: true, titleOverride: selection.title) }
            }
            .alert("Couldn’t save the paper", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
            .onChange(of: scenePhase) { _, phase in if phase == .active { checkDeadline() } }
            .studyFeedback(feedback)
    }
    private func stageRail(_ paper: StudyRecord) -> some View {
        HStack(spacing: 4) {
            ForEach(PaperStage.allCases) { item in
                Button { stage = item; feedback.selection += 1 } label: {
                    VStack(spacing: 7) {
                        Image(systemName: completed(item, paper) && stage != item ? "checkmark.circle.fill" : item.symbol).font(.title3)
                        Text(item.rawValue).font(.caption.weight(.semibold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(stage == item ? Color.white : completed(item, paper) ? StudyPalette.progress : Color.secondary)
                        .background(stage == item ? StudyPalette.focus : Color.clear, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain).accessibilityIdentifier("paper.stage." + item.rawValue)
                    .accessibilityAddTraits(stage == item ? .isSelected : [])
            }
        }.padding(5).background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private func completed(_ stage: PaperStage, _ paper: StudyRecord) -> Bool {
        switch stage {
        case .sit: paper["timerState"] == "finished"
        case .scan: !paper.ids("pages").isEmpty
        case .mark: total.count > 0 && total.count == total.marked
        case .reflect: false
        }
    }
    private func sitting(_ paper: StudyRecord) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(paper["timerState"] == "finished" ? "Pens down. Work saved." : "Just you and the paper.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(paper["timerState"] == "finished" ? "Bring your working into Folio when you’re ready." : "Do your working on paper. Folio keeps the time.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let seconds = PaperClock.remaining(paper, now: timeline.date)
                StudyDial(progress: seconds / PaperClock.duration(paper), value: PaperClock.label(seconds),
                    caption: paper["timerState"] == "paused" ? "paused" : paper["timerState"] == "finished" ? "finished" : "remaining",
                    color: seconds > 0 && seconds <= 300 ? StudyPalette.revisit : StudyPalette.focus, size: 222)
                    .padding(16).accessibilityIdentifier("paper.timer")
            }
            if paper["timerState"].isEmpty {
                Stepper(value: Binding(get: { Int(PaperClock.duration(paper) / 60) }, set: { minutes in
                    var changed = paper; changed["durationMinutes"] = String(minutes); save(changed)
                }), in: 1...720, step: 1) { Text("\(Int(PaperClock.duration(paper) / 60)) minutes").monospacedDigit() }
                    .padding(16).background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                HStack {
                    ForEach([30, 60, 90, 120], id: \.self) { minutes in
                        Button("\(minutes)m") { var changed = paper; changed["durationMinutes"] = String(minutes); save(changed); feedback.selection += 1 }
                            .buttonStyle(.bordered).tint(StudyPalette.focus)
                    }
                }
            }
            if paper["timerState"] == "finished" {
                Button("Scan my working", systemImage: "viewfinder") { stage = .scan; capture = true }.buttonStyle(.borderedProminent).tint(StudyPalette.focus)
            } else {
                Button(paper["timerState"] == "running" ? "Pause timer" : paper["timerState"] == "paused" ? "Resume timer" : "Start timer",
                    systemImage: paper["timerState"] == "running" ? "pause.fill" : "play.fill") {
                    if save(paper["timerState"] == "running" ? PaperClock.pause(paper) : PaperClock.start(paper)) { feedback.selection += 1 }
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(StudyPalette.focus).accessibilityIdentifier("paper.timer.toggle")
                if !paper["timerState"].isEmpty {
                    Button("Finish sitting") { finishEarly = true }.accessibilityIdentifier("paper.timer.finish")
                }
                Text("Keeps time when you leave the app. No background alarm.").font(.caption).foregroundStyle(.secondary)
                Button("Already done it? Scan my working", systemImage: "viewfinder") { stage = .scan }.font(.subheadline)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    private func scanning(_ paper: StudyRecord) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Paper to pages.").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Scan your completed working in page order. Then put your marks directly beside each scan.").foregroundStyle(.secondary)
            Button { capture = true } label: {
                VStack(spacing: 14) {
                    Image(systemName: "viewfinder").font(.system(size: 48, weight: .light))
                    Text(paper.ids("pages").isEmpty ? "Scan my working" : "Add more pages").font(.headline)
                    Text("Camera, photos, PDF or existing scans").font(.caption)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
                    .background(StudyPalette.focus.opacity(0.09), in: RoundedRectangle(cornerRadius: 28))
            }.buttonStyle(.plain).foregroundStyle(StudyPalette.focus).accessibilityIdentifier("paper.scan")
            let available = scans(paper)
            if !available.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 150))], spacing: 16) {
                    ForEach(available) { page in
                        VStack(spacing: 7) {
                            PageThumbnail(page: page).aspectRatio(0.71, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 9))
                            Text("Page \((paper.ids("pages").firstIndex(of: page.id) ?? 0) + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Mark my pages", systemImage: "pencil.tip") { stage = .mark; feedback.selection += 1 }
                    .buttonStyle(.borderedProminent).tint(StudyPalette.progress).accessibilityIdentifier("paper.scan.mark")
                Button("Open \(available.count) pages in reader", systemImage: "book") { reader = StudyReaderSelection(pages: available, title: paper.title) }
            }
            unavailablePages(paper)
        }
    }
    private func reflection(_ paper: StudyRecord) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(total.marked > 0 ? "See what stuck." : "Your next insight starts here.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            HStack(spacing: 24) {
                StudyDial(progress: total.available > 0 ? total.earned / total.available : 0,
                    value: total.marked == 0 || total.available == 0 ? "—" : "\(Int(total.earned / total.available * 100))%",
                    caption: total.marked < total.count ? "so far" : "score", size: 116)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(total.earned.formatted()) / \(total.available.formatted()) marks").font(.title3.weight(.semibold))
                    Text("\(total.marked) of \(total.count) questions marked").foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(StudyPalette.progress.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
            if total.marked < total.count || total.count == 0 {
                Button("Continue marking", systemImage: "pencil.tip") { stage = .mark }.buttonStyle(.borderedProminent).tint(StudyPalette.progress)
            }
            let leaves = StudyMarks.leaves(questions)
            let lost = leaves.filter { question in
                guard let earned = question.number("earned"), let marks = question.number("marks") else { return false }
                return earned < marks
            }
            if !lost.isEmpty {
                Text("Give these another look").font(.title3.weight(.semibold))
                ForEach(lost) { question in
                    NavigationLink { StudyDetailView(recordID: question.id) } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(StudyPalette.revisit)
                            StudyRecordRow(record: question, records: records)
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }.padding(14).background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 17))
                    }.buttonStyle(.plain)
                }
            } else if total.marked > 0 && total.marked == total.count {
                Label("Every question marked. That’s a paper understood.", systemImage: "checkmark.seal.fill").foregroundStyle(StudyPalette.progress)
            }
            let tagged = Dictionary(grouping: leaves.filter { !StudyRules.inherited("topic", for: $0, in: questions)["topic"].isEmpty }, by: { StudyRules.inherited("topic", for: $0, in: questions)["topic"] })
            if !tagged.isEmpty {
                Text("By topic").font(.title3.weight(.semibold))
                ForEach(tagged.keys.sorted(), id: \.self) { id in
                    if let topic = records.first(where: { $0.id == id }) {
                        let marks = StudyMarks.total(tagged[id] ?? [])
                        NavigationLink { StudyDetailView(recordID: topic.id) } label: {
                            HStack { Text(topic.title); Spacer(); Text("\(marks.earned.formatted()) / \(marks.available.formatted())").monospacedDigit() }
                                .padding(16).background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }
            }
            DisclosureGroup("All questions and mark schemes") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(questions.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { question in
                        NavigationLink { StudyDetailView(recordID: question.id) } label: { StudyRecordRow(record: question, records: records) }
                            .accessibilityIdentifier("study.record." + question.id)
                    }
                    ForEach(records.filter { $0.type == .markScheme && $0["paper"] == paper.id }) { scheme in
                        NavigationLink(scheme.title) { StudyDetailView(recordID: scheme.id) }
                    }
                }.padding(.top, 12)
            }
        }
    }
    private func scans(_ paper: StudyRecord) -> [NotePage] {
        paper.ids("pages").compactMap { id in storedPages.first { $0.id == id && access.canRead($0) } }
    }
    @ViewBuilder private func unavailablePages(_ paper: StudyRecord) -> some View {
        let missing = paper.ids("pages").count - scans(paper).count
        if missing > 0 { Label("\(missing) pages unavailable. Unlock their book or restore your working folder.", systemImage: "lock.doc").font(.caption).foregroundStyle(.secondary) }
    }
    @discardableResult private func save(_ changed: StudyRecord) -> Bool {
        do { try StudyStore.write([changed], context: context); return true }
        catch { self.error = error.localizedDescription; feedback.error += 1; return false }
    }
    private func checkDeadline() {
        guard let paper, paper["timerState"] == "running", PaperClock.remaining(paper) <= 0 else { return }
        if save(PaperClock.finish(paper)) { feedback.success += 1 }
    }
}
