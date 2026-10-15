import Foundation
import SwiftData

struct StudyIssue: Identifiable, Equatable, Sendable {
    var record: String
    var field: String
    var message: String
    var id: String { record + ":" + field + ":" + message }
    var description: String { "\(record) · \(field): \(message)" }
}
struct StudyFailure: LocalizedError {
    var issues: [StudyIssue]
    var errorDescription: String? { issues.map(\.description).joined(separator: "\n") }
}

enum StudyRules {
    static let confidence = ["New", "Exploring", "Practising", "Confident"]
    static let categories = ["knowledge gap", "method error", "misread question", "careless slip"]
    static func references(_ type: StudyKind) -> [String: Set<StudyKind>] {
        var result: [String: Set<StudyKind>] = [:]
        switch type {
        case .topic: result = ["subject": [.subject], "parent": [.topic]]
        case .paper: result = ["subject": [.subject]]
        case .question: result = ["paper": [.paper], "parent": [.question], "topic": [.topic]]
        case .markScheme: result = ["paper": [.paper], "question": [.question]]
        case .mistake: result = ["question": [.question], "topic": [.topic]]
        case .card: result = ["topic": [.topic]]
        case .attempt: result = ["question": [.question], "mistake": [.mistake], "session": [.session]]
        case .review: result = ["card": [.card], "session": [.session]]
        case .session: result = ["scope": [.subject, .topic, .paper]]
        case .subject: break
        }
        return result
    }
    static func validate(_ records: [StudyRecord], against existing: [StudyRecord] = []) -> [StudyIssue] {
        var all = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in records { all[record.id] = record }
        var issues: [StudyIssue] = []
        var seen: Set<String> = []
        for record in records {
            func issue(_ field: String, _ message: String) { issues.append(StudyIssue(record: record.id, field: field, message: message)) }
            if record.id.isEmpty || record.id.count > 200 || record.id.contains(where: { $0.isWhitespace }) { issue("id", "Use a nonempty stable ID of at most 200 characters without spaces.") }
            if !seen.insert(record.id).inserted { issue("id", "This ID occurs more than once in the import.") }
            for field in record.fields.keys where !record.type.fields.contains(field) { issue(field, "Unsupported field for \(record.type.rawValue).") }
            for field in record.type.required where record[field].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issue(field, "This field is required.") }
            for (field, kinds) in references(record.type) where !record[field].isEmpty {
                if let target = all[record[field]] {
                    if !kinds.contains(target.type) { issue(field, "The linked record has the wrong type.") }
                } else { issue(field, "No record with ID ‘\(record[field])’. Include it, choose a destination, or correct the link.") }
            }
            if record.type == .card, !record["source"].isEmpty, record["source"].hasPrefix("record:"), all[String(record["source"].dropFirst(7))] == nil {
                issue("source", "The source record does not exist. Use record:ID for a study record, or plain text/a URL for an external source.")
            }
            for field in ["marks", "earned", "interval", "repetitions", "durationMinutes", "timerRemaining"] where !record[field].isEmpty {
                guard let number = record.number(field), number.isFinite, number >= 0 else { issue(field, "Use a finite number, zero or greater."); continue }
                if ["repetitions", "durationMinutes"].contains(field) && number.rounded() != number { issue(field, "Use a whole number.") }
                if field == "interval" && number > 180 { issue(field, "The maximum interval is 180 days.") }
                if field == "durationMinutes" && (number < 1 || number > 720) { issue(field, "Choose a duration between 1 and 720 minutes.") }
                if field == "timerRemaining" && number > 43200 { issue(field, "Remaining time cannot exceed 12 hours.") }
            }
            if let earned = record.number("earned") {
                if let marks = record.number("marks") {
                    if earned > marks { issue("earned", "Marks achieved cannot exceed marks available.") }
                } else { issue("marks", "Enter marks available when recording marks achieved.") }
            }
            for field in ["pageStart", "pageEnd", "year"] where !record[field].isEmpty {
                if let value = Int(record[field]), value > 0 {} else { issue(field, "Use a positive whole number.") }
            }
            if !record["pageEnd"].isEmpty && record["pageStart"].isEmpty { issue("pageStart", "Enter the first page of the range.") }
            if let start = Int(record["pageStart"]), let end = Int(record["pageEnd"]), end < start { issue("pageEnd", "The last page must be at or after the first page.") }
            if record.type == .question, let paper = all[record["paper"]], !paper.ids("pages").isEmpty {
                for field in ["pageStart", "pageEnd"] {
                    if let page = Int(record[field]), page > paper.ids("pages").count { issue(field, "This paper has \(paper.ids("pages").count) scanned pages.") }
                }
            }
            if record.type == .question {
                if !record["markingMode"].isEmpty && record["markingMode"] != "pageTotal" { issue("markingMode", "Use pageTotal or leave this field empty for individual questions.") }
                if let parent = all[record["parent"]], parent["markingMode"] == "pageTotal" { issue("parent", "A page total cannot contain subquestions. Remove the total before adding individual questions.") }
                if record["markingMode"] == "pageTotal" {
                    if record["pageStart"].isEmpty || !record["parent"].isEmpty || (!record["pageEnd"].isEmpty && record["pageEnd"] != record["pageStart"]) {
                        issue("pageStart", "A page total covers one scan page and has no parent.")
                    }
                }
                let paperQuestions = all.values.filter { $0.type == .question && $0["paper"] == record["paper"] }
                let leaves = StudyMarks.leaves(paperQuestions)
                for total in leaves where total["markingMode"] == "pageTotal" {
                    if let page = Int(total["pageStart"]), leaves.contains(where: { $0.id != total.id && StudyRules.pageRange($0, in: paperQuestions)?.contains(page) == true }) {
                        issue("pageStart", "Page \(page) has a page total and individual questions. Remove the page total before marking the questions separately.")
                    }
                }
            }
            for field in ["retryAt", "due", "date", "started", "finished", "timerDeadline", "completedAt"] where !record[field].isEmpty {
                if record.date(field) == nil { issue(field, "Use an ISO 8601 date with time and timezone, e.g. 2026-10-15T17:00:00Z.") }
            }
            if record.type == .paper {
                if !record["timerState"].isEmpty && !["running", "paused", "finished"].contains(record["timerState"]) { issue("timerState", "Use running, paused or finished.") }
                if record["timerState"] == "running" && record.date("timerDeadline") == nil { issue("timerDeadline", "A running timer needs a deadline.") }
                if record["timerState"] == "paused" && record.number("timerRemaining") == nil { issue("timerRemaining", "A paused timer needs its remaining seconds.") }
            }
            if !record["resolved"].isEmpty && !["true", "false"].contains(record["resolved"]) { issue("resolved", "Use true or false as a string.") }
            if !record["confidence"].isEmpty && !confidence.contains(record["confidence"]) { issue("confidence", "Choose New, Exploring, Practising or Confident.") }
            if !record["rating"].isEmpty && !["Again", "Nearly", "Got it"].contains(record["rating"]) { issue("rating", "Choose Again, Nearly or Got it.") }
            for field in ["pages", "noteBooks", "noteSections", "notePages", "sourcePage"] where !record[field].isEmpty {
                let values = record[field].split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if values.contains(where: { UUID(uuidString: $0) == nil }) { issue(field, "Use comma-separated Folio UUIDs in the intended order.") }
                if Set(values.map { $0.lowercased() }).count != values.count { issue(field, "Each linked scan or note should occur only once.") }
                if field == "sourcePage" && values.count != 1 { issue(field, "A card has one source page.") }
            }
            if let parent = all[record["parent"]] {
                let owner = record.type == .topic ? "subject" : "paper"
                if record[owner] != parent[owner] { issue("parent", "Parent and child must belong to the same \(owner).") }
                var visited: Set<String> = [record.id]
                var cursor: StudyRecord? = parent
                while let value = cursor {
                    if !visited.insert(value.id).inserted { issue("parent", "This parent creates a cycle."); break }
                    cursor = all[value["parent"]]
                }
            }
            if [.topic, .question].contains(record.type) {
                let owner = record.type == .topic ? "subject" : "paper"
                if all.values.contains(where: { $0.type == record.type && $0["parent"] == record.id && $0[owner] != record[owner] }) {
                    issue(owner, "Move or detach this record’s children before changing its \(owner).")
                }
            }
            if record.type == .markScheme, let question = all[record["question"]], question["paper"] != record["paper"] { issue("question", "The question belongs to a different paper.") }
            if record.type == .attempt && record["question"].isEmpty && record["mistake"].isEmpty { issue("question", "An attempt must link to a question or mistake.") }
        }
        return issues
    }
    static func descendants(of id: String, in records: [StudyRecord]) -> Set<String> {
        var result: Set<String> = [id]
        var changed = true
        while changed {
            changed = false
            for record in records where result.contains(record["parent"]) {
                if result.insert(record.id).inserted { changed = true }
            }
        }
        return result
    }
    static func scoped(_ records: [StudyRecord], to scope: StudyRecord?) -> [StudyRecord] {
        guard let scope else { return records }
        let topics: Set<String>
        switch scope.type {
        case .subject: topics = Set(records.filter { $0.type == .topic && $0["subject"] == scope.id }.map(\.id))
        case .topic: topics = descendants(of: scope.id, in: records.filter { $0.type == .topic })
        default: topics = []
        }
        var questions = Set(records.filter { $0.type == .question && (topics.contains($0["topic"]) || (scope.type == .paper && $0["paper"] == scope.id)) }.map(\.id))
        for id in Array(questions) { questions.formUnion(descendants(of: id, in: records.filter { $0.type == .question })) }
        let mistakes = Set(records.filter { $0.type == .mistake && (topics.contains($0["topic"]) || questions.contains($0["question"])) }.map(\.id))
        return records.filter {
            let sourceID = $0["source"].hasPrefix("record:") ? String($0["source"].dropFirst(7)) : ""
            return topics.contains($0.id) || questions.contains($0.id) || mistakes.contains($0.id) ||
            ($0.type == .card && (topics.contains($0["topic"]) || questions.contains(sourceID) || mistakes.contains(sourceID)))
        }
    }
    static func needsRetry(_ question: StudyRecord, in records: [StudyRecord]) -> Bool {
        let ids = descendants(of: question.id, in: records.filter { $0.type == .question })
        let questions = records.filter { $0.type == .question && ids.contains($0.id) }
        if questions.contains(where: { !$0["retryAt"].isEmpty }) { return true }
        if StudyMarks.leaves(questions).contains(where: { item in
            guard let earned = item.number("earned"), let marks = item.number("marks") else { return false }
            return earned < marks
        }) { return true }
        return records.contains { $0.type == .mistake && ids.contains($0["question"]) && $0["resolved"] != "true" }
    }
    static func inherited(_ field: String, for question: StudyRecord, in records: [StudyRecord]) -> StudyRecord {
        var current = question; var seen: Set<String> = []
        while current[field].isEmpty, seen.insert(current.id).inserted,
              let parent = records.first(where: { $0.type == .question && $0.id == current["parent"] }) { current = parent }
        return current
    }
    static func pageRange(_ question: StudyRecord, in records: [StudyRecord]) -> ClosedRange<Int>? {
        let value = inherited("pageStart", for: question, in: records)
        guard let first = Int(value["pageStart"]), first > 0 else { return nil }
        let last = Int(value["pageEnd"]) ?? first
        return last >= first ? first...last : nil
    }
}

struct StudyMarks: Equatable {
    var earned: Double = 0
    var available: Double = 0
    var marked = 0
    var count = 0
    var label: String { "\(earned.formatted()) / \(available.formatted()) marks · \(marked)/\(count) marked" }
    static func leaves(_ questions: [StudyRecord]) -> [StudyRecord] {
        let parents = Set(questions.map { $0["parent"] }.filter { !$0.isEmpty })
        return questions.filter { !parents.contains($0.id) }
    }
    static func total(_ questions: [StudyRecord]) -> Self {
        // Parents describe their subquestions; count only leaf marks to avoid
        // counting question 1 and 1(a)/1(b) twice. Zero is a marked score.
        var result = Self()
        for question in leaves(questions) {
            result.count += 1
            result.available += question.number("marks") ?? 0
            if let earned = question.number("earned") { result.earned += earned; result.marked += 1 }
        }
        return result
    }
    static func sections(_ questions: [StudyRecord]) -> [String: Self] {
        func section(_ question: StudyRecord) -> String {
            var current = question; var seen: Set<String> = []
            while current["section"].isEmpty, seen.insert(current.id).inserted,
                  let parent = questions.first(where: { $0.id == current["parent"] }) { current = parent }
            return current["section"]
        }
        return Dictionary(grouping: leaves(questions), by: section).mapValues(total)
    }
}

enum StudySchedule {
    static func due(_ card: StudyRecord, now: Date = .now) -> Bool { (card.date("due") ?? .distantPast) <= now }
    static func rate(_ card: StudyRecord, _ rating: String, now: Date = .now) -> StudyRecord {
        var updated = card
        let previous = min(180, max(0, card.number("interval") ?? 0))
        let days: Double
        switch rating {
        case "Again": days = 10 / 1440
        case "Nearly": days = 1
        default: days = min(180, max(3, previous * 2.3))
        }
        updated["interval"] = String(days)
        updated["due"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(days * 86400))
        updated["repetitions"] = String(min(1_000_000, max(0, card.number("repetitions") ?? 0)) + 1)
        return updated
    }
}

@MainActor enum StudyStore {
    static func items(_ context: ModelContext) throws -> [StudyItem] { try context.fetch(FetchDescriptor<StudyItem>()) }
    static func records(_ items: [StudyItem], includingRemoved: Bool = false) -> [StudyRecord] {
        // Failed decodes stay in the store and are reported by export/restore.
        let canonical = Dictionary(items.filter { !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt ? a : b }
            if (a.removedAt != nil) != (b.removedAt != nil) { return a.removedAt != nil ? a : b }
            return a.payload.lexicographicallyPrecedes(b.payload) ? a : b
        })
        return canonical.values.filter { includingRemoved || $0.removedAt == nil }.compactMap { try? $0.decoded() }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    static func records(_ context: ModelContext) throws -> [StudyRecord] { records(try items(context)) }
    static func write(_ records: [StudyRecord], context: ModelContext, validate: Bool = true, persist: Bool = true) throws {
        try reconcile(context)
        let stored = try items(context)
        var issues = validate ? StudyRules.validate(records, against: self.records(stored)) : []
        for record in records {
            if let previous = stored.first(where: { $0.id == record.id }), try previous.decoded().type != record.type {
                issues.append(.init(record: record.id, field: "type", message: "This ID already belongs to a different record type. Import as new or use a different ID."))
            }
        }
        guard issues.isEmpty else { throw StudyFailure(issues: issues) }
        let autosave = context.autosaveEnabled; context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            for var record in records {
                if let item = stored.first(where: { $0.id == record.id }) {
                    var snapshot = try item.snapshot()
                    if [.paper, .markScheme].contains(record.type) {
                        var ids = snapshot.record.ids("pages")
                        for id in record.ids("pages") where !ids.contains(id) { ids.append(id) }
                        record.setIDs("pages", ids)
                    }
                    if snapshot.record == record && item.removedAt == nil { continue }
                    snapshot.history.append(StudyVersion(date: item.modifiedAt, record: snapshot.record))
                    item.historyData = try JSONEncoder().encode(snapshot.history)
                    item.payload = try JSONEncoder().encode(record); item.modifiedAt = .now; item.removedAt = nil
                } else { context.insert(try StudyItem(record)) }
            }
            if persist { try LibraryPersistence.save(context) }
        } catch { context.rollback(); throw error }
    }
    static func remove(_ record: StudyRecord, context: ModelContext) throws {
        let all = try self.records(context)
        let structural = all.filter { candidate in
            candidate.id != record.id && StudyRules.references(candidate.type).keys.contains { candidate.type.required.contains($0) && candidate[$0] == record.id } && candidate.type != .review
        }
        guard structural.isEmpty else {
            throw StudyFailure(issues: [.init(record: record.id, field: "links", message: "Contains \(structural.count) linked records. Move or delete these first; their scans and practice history are kept.")])
        }
        var changes: [StudyRecord] = []
        var removed: Set<String> = [record.id]
        for var candidate in all where candidate.id != record.id {
            let before = candidate
            for field in StudyRules.references(candidate.type).keys where candidate[field] == record.id { candidate[field] = "" }
            if candidate["source"] == "record:" + record.id { candidate["source"] = "Removed source: " + record.title }
            if candidate.type == .review && candidate["card"].isEmpty || candidate.type == .attempt && candidate["question"].isEmpty && candidate["mistake"].isEmpty {
                removed.insert(candidate.id)
            } else if before != candidate { changes.append(candidate) }
        }
        let autosave = context.autosaveEnabled; context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            if !changes.isEmpty { try write(changes, context: context, persist: false) }
            for item in try items(context) where removed.contains(item.id) { item.removedAt = .now; item.modifiedAt = .now }
            try LibraryPersistence.save(context)
        } catch { context.rollback(); throw error }
    }
    static func merge(_ snapshots: [StudySnapshot], context: ModelContext) throws {
        var stored = Dictionary(try items(context).map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.modifiedAt >= b.modifiedAt ? a : b })
        for incoming in snapshots {
            guard let item = stored[incoming.record.id] else {
                let item = try StudyItem(incoming.record); context.insert(item); stored[item.id] = item
                item.modifiedAt = incoming.modified; item.removedAt = incoming.removed
                item.historyData = try JSONEncoder().encode(incoming.history); continue
            }
            try apply(incoming, to: item)
        }
    }
    private static func apply(_ incoming: StudySnapshot, to item: StudyItem) throws {
        let current = try item.snapshot()
        guard current.record.type == incoming.record.type else {
            throw StudyFailure(issues: [.init(record: incoming.record.id, field: "type", message: "This folder reuses an existing ID for a different type. Its files are unchanged; export its study JSON and import as new to combine these libraries.")])
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let tieWinner: Bool
        if (incoming.removed != nil) != (current.removed != nil) { tieWinner = incoming.removed != nil }
        else { tieWinner = try encoder.encode(incoming.record).lexicographicallyPrecedes(encoder.encode(current.record)) }
        let incomingWins = incoming.modified > current.modified || incoming.modified == current.modified && tieWinner
        var history = current.history
        for version in incoming.history where !history.contains(where: { $0.id == version.id }) { history.append(version) }
        if incoming.record != current.record {
            let loser = incomingWins ? current : incoming
            if !history.contains(where: { $0.date == loser.modified && $0.record == loser.record }) {
                history.append(StudyVersion(date: loser.modified, record: loser.record))
            }
        }
        var winner = incomingWins ? incoming.record : current.record
        if [.paper, .markScheme].contains(winner.type) {
            var ids = winner.ids("pages")
            let other = incomingWins ? current.record : incoming.record
            for id in other.ids("pages") where !ids.contains(id) { ids.append(id) }
            winner.setIDs("pages", ids)
        }
        item.payload = try encoder.encode(winner)
        if incomingWins { item.modifiedAt = incoming.modified; item.removedAt = incoming.removed }
        item.historyData = try encoder.encode(history.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        })
    }
    static func reconcile(_ context: ModelContext) throws {
        for group in Dictionary(grouping: try items(context), by: \.id).values where group.count > 1 {
            let sorted = group.sorted { $0.modifiedAt > $1.modifiedAt }
            guard let keep = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                // merge includes the losing payload in history, even on a tie.
                try apply(duplicate.snapshot(), to: keep)
                if duplicate !== keep { context.delete(duplicate) }
            }
        }
    }
    static func attempt(_ question: StudyRecord, replacing draft: StudyRecord, session: String? = nil, recordAttempt: Bool = true) -> [StudyRecord] {
        var result = [draft]
        if recordAttempt && draft.number("earned") != nil || !question["earned"].isEmpty && draft["earned"].isEmpty {
            var attempt = StudyRecord(.attempt, ["question": draft.id, "date": ISO8601DateFormatter().string(from: .now), "earned": draft["earned"], "marks": draft["marks"]])
            attempt["session"] = session ?? ""; result.append(attempt)
        }
        return result
    }
}
