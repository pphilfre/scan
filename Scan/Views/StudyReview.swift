import SwiftUI
import SwiftData

struct StudyReviewView: View {
    var scope: StudyRecord?
    var sessionID: String?
    var onFinished: (() -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [StudyItem]
    @State private var queue: [String] = []
    @State private var loaded = false
    @State private var revealed = false
    @State private var reviewed = 0
    @State private var recalled = 0
    @State private var notice: String?
    @State private var error: String?
    @State private var draft: StudyDraft?
    @State private var feedback = StudyFeedbackState()
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var current: StudyRecord? { queue.compactMap { id in records.first { $0.id == id && $0.type == .card } }.first }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let notice { Label(notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("study.review.notice") }
                    if let card = current {
                        HStack(spacing: 18) {
                            StudyDial(progress: Double(reviewed) / Double(max(1, reviewed + queue.count)), value: "\(reviewed)", caption: "reviewed", color: .purple, size: 76)
                            Text("\(queue.count) to go.\nTake a moment to recall it.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(card["prompt"]).font(.system(.title2, design: .rounded, weight: .semibold)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading).padding(24)
                            .background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 28)).accessibilityIdentifier("study.review.prompt")
                        if !card["hint"].isEmpty { DisclosureGroup("Hint") { Text(card["hint"]) } }
                        if revealed {
                            Text(card["answer"]).textSelection(.enabled).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudyPalette.progress.opacity(0.09), in: RoundedRectangle(cornerRadius: 24)).accessibilityIdentifier("study.review.answer")
                            HStack {
                                ForEach(["Again", "Nearly", "Got it"], id: \.self) { rating in
                                    Button { rate(card, rating: rating) } label: {
                                        VStack(spacing: 9) {
                                            Image(systemName: rating == "Got it" ? "checkmark.circle.fill" : rating == "Nearly" ? "circle.lefthalf.filled" : "arrow.clockwise")
                                            Text(rating).font(.subheadline.weight(.semibold))
                                        }.frame(maxWidth: .infinity, minHeight: 76)
                                            .background((rating == "Got it" ? StudyPalette.progress : rating == "Nearly" ? StudyPalette.focus : StudyPalette.revisit).opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                                    }.buttonStyle(.plain).foregroundStyle(rating == "Got it" ? StudyPalette.progress : rating == "Nearly" ? StudyPalette.focus : StudyPalette.revisit).accessibilityIdentifier("study.rate." + rating)
                                }
                            }
                            Text("Again: 10 minutes · Nearly: tomorrow · Got it: a longer interval").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Reveal answer", systemImage: "eye") { revealed = true; feedback.selection += 1 }.buttonStyle(.borderedProminent).controlSize(.large).tint(.purple).accessibilityIdentifier("study.review.reveal")
                        }
                        if !card["source"].isEmpty {
                            if card["source"].hasPrefix("record:"), let source = records.first(where: { $0.id == String(card["source"].dropFirst(7)) }) {
                                NavigationLink("Source: \(source.title)") { StudyDetailView(recordID: source.id, sessionID: sessionID) }
                            } else { Text("Source: \(card["source"])").font(.caption).textSelection(.enabled) }
                        }
                        Button("Edit card", systemImage: "pencil") { draft = StudyDraft(record: card) }
                    } else if loaded {
                        Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(FolioStyle.color("sage"))
                        Text(reviewed == 0 ? "You’re ready for your next step" : "A little more learned").font(.system(.title, design: .serif))
                        Text("\(reviewed) \(reviewed == 1 ? "card" : "cards") reviewed · \(recalled) recalled with ‘Got it’.\nCome back when it suits you. Your next reviews are already scheduled.")
                        Button(onFinished == nil ? "Done" : "Continue to practice", action: finish).buttonStyle(.glassProminent).accessibilityIdentifier("study.review.done")
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(26).frame(maxWidth: 700).frame(maxWidth: .infinity, alignment: .center)
            }.background(StudyPalette.canvas).navigationTitle("Active recall").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Finish here", action: finish) } }
                .sheet(item: $draft) { StudyEditor(record: $0.record) }
                .onAppear {
                    guard !loaded else { return }
                    let available = scope == nil ? records : StudyRules.scoped(records, to: scope)
                    queue = available.filter { $0.type == .card && StudySchedule.due($0) }
                        .sorted { ($0.date("due") ?? .distantPast) < ($1.date("due") ?? .distantPast) }.map(\.id)
                    loaded = true
                }
                .studyFeedback(feedback)
        }
    }
    private func rate(_ card: StudyRecord, rating: String) {
        var event = StudyRecord(.review, ["card": card.id, "rating": rating, "date": ISO8601DateFormatter().string(from: .now)])
        event["session"] = sessionID ?? ""
        do {
            try StudyStore.write([StudySchedule.rate(card, rating), event], context: context)
            queue.removeAll { $0 == card.id }; revealed = false; reviewed += 1
            if rating == "Got it" { recalled += 1 }
            notice = "\(rating) · Next review saved"; error = nil; feedback.selection += 1
            if current == nil { feedback.success += 1 }
        } catch { self.error = error.localizedDescription; feedback.error += 1 }
    }
    private func finish() { onFinished?(); dismiss() }
}

struct StudySessionView: View {
    var initialScope: StudyRecord?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [StudyItem]
    @State private var scopeID = ""
    @State private var sessionRecord: StudyRecord?
    @State private var reviewing = false
    @State private var finished = false
    @State private var error: String?
    @State private var confidence: [String: String] = [:]
    @State private var feedback = StudyFeedbackState()
    private var records: [StudyRecord] { StudyStore.records(items) }
    private var scope: StudyRecord? { records.first { $0.id == scopeID } }
    private var scoped: [StudyRecord] { scope == nil ? records : StudyRules.scoped(records, to: scope) }
    private var events: [StudyRecord] { records.filter { $0["session"] == sessionRecord?.id && [.attempt, .review].contains($0.type) } }
    private var summary: String {
        let reviews = events.filter { $0.type == .review }
        let attempts = events.filter { $0.type == .attempt && !$0["question"].isEmpty && $0.number("earned") != nil }
        let latest = Dictionary(grouping: attempts, by: { $0["question"] }).values.compactMap { $0.max { ($0.date("date") ?? .distantPast) < ($1.date("date") ?? .distantPast) } }
        let earned = latest.reduce(0) { $0 + ($1.number("earned") ?? 0) }
        let available = latest.reduce(0) { $0 + ($1.number("marks") ?? 0) }
        let retries = events.filter { $0.type == .attempt && !$0["mistake"].isEmpty }.count
        let changes = scoped.filter { $0.type == .topic && confidence[$0.id] != $0["confidence"] }.count
        return "\(reviews.count) \(reviews.count == 1 ? "card" : "cards") reviewed · \(reviews.filter { $0["rating"] == "Got it" }.count) recalled\n\(latest.count) \(latest.count == 1 ? "question" : "questions") attempted · \(earned.formatted()) / \(available.formatted()) marks\n\(retries) mistakes retried · \(changes) confidence updates"
    }
    var body: some View {
        NavigationStack {
            List {
                if sessionRecord == nil {
                    Section("Choose a focus") {
                        Picker("Study", selection: $scopeID) {
                            Text("All my study material").tag("")
                            ForEach(records.filter { [.subject, .topic, .paper].contains($0.type) }) { Text("\($0.type.name) · \($0.title)").tag($0.id) }
                        }
                        Text("Review a few cards, try a question or revisit a mistake, then record what you learned.").foregroundStyle(.secondary)
                        Button("Start session", systemImage: "play.circle", action: start).accessibilityIdentifier("study.session.start")
                    }
                } else if finished {
                    Section("Time well spent") {
                        Text(summary).accessibilityIdentifier("study.session.summary")
                        Text(nextStep).foregroundStyle(.secondary)
                        Button("Done") { dismiss() }.accessibilityIdentifier("study.session.done")
                    }
                } else {
                    Section("1 · Active recall") {
                        Button("Review due flashcards", systemImage: "rectangle.on.rectangle") { reviewing = true }
                    }
                    Section("2 · Try a question") {
                        ForEach(scoped.filter { question in question.type == .question && !scoped.contains(where: { child in child.type == .question && child["parent"] == question.id }) }) { question in
                            NavigationLink { StudyDetailView(recordID: question.id, sessionID: sessionRecord?.id) } label: { StudyRecordRow(record: question, records: records) }
                        }
                        if !scoped.contains(where: { $0.type == .question }) { Text("Add a paper in Past Papers to practise a question. You can still finish with a short review today.").foregroundStyle(.secondary) }
                    }
                    Section("Or retry a mistake") {
                        ForEach(scoped.filter { $0.type == .mistake && $0["resolved"] != "true" }) { mistake in
                            NavigationLink { StudyDetailView(recordID: mistake.id, sessionID: sessionRecord?.id) } label: { StudyRecordRow(record: mistake, records: records) }
                        }
                    }
                    Section("3 · Reflect") {
                        ForEach(scoped.filter { $0.type == .topic }) { topic in
                            NavigationLink(topic.title) { StudyDetailView(recordID: topic.id, sessionID: sessionRecord?.id) }
                        }
                        Text(summary).font(.subheadline)
                        Button("Finish session", systemImage: "checkmark.circle", action: finish).accessibilityIdentifier("study.session.finish")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(FolioStyle.paper)
                .navigationTitle("Study session").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .sheet(isPresented: $reviewing) { StudyReviewView(scope: scope, sessionID: sessionRecord?.id) { reviewing = false } }
                .onAppear { if sessionRecord == nil, let initialScope { scopeID = initialScope.id } }
                .studyFeedback(feedback)
        }
    }
    private var nextStep: String {
        if scoped.contains(where: { $0.type == .mistake && $0["resolved"] != "true" }) { return "Next time, revisit one mistake and explain the reasoning in your own words." }
        if scoped.contains(where: { $0.type == .card && StudySchedule.due($0) }) { return "A few cards are ready whenever you have another moment." }
        return "Next time, try one question from a topic you want to explore."
    }
    private func start() {
        var record = StudyRecord(.session, ["title": scope?.title ?? "Study session", "scope": scopeID, "started": ISO8601DateFormatter().string(from: .now)])
        record["notes"] = "Session in progress"
        do {
            try StudyStore.write([record], context: context); sessionRecord = record
            confidence = Dictionary(uniqueKeysWithValues: scoped.filter { $0.type == .topic }.map { ($0.id, $0["confidence"]) })
            reviewing = true; feedback.selection += 1
        } catch { self.error = error.localizedDescription; feedback.error += 1 }
    }
    private func finish() {
        guard var record = sessionRecord else { return }
        record["finished"] = ISO8601DateFormatter().string(from: .now); record["notes"] = summary + "\n" + nextStep
        do { try StudyStore.write([record], context: context); finished = true; feedback.success += 1 }
        catch { self.error = error.localizedDescription; feedback.error += 1 }
    }
}
