import Foundation
import CoreFoundation
import SwiftData

struct StudyDocument: Codable, Sendable {
    var format = "folio-study"
    var version = 1
    var records: [StudyRecord]
}
struct StudyParseResult {
    var records: [StudyRecord] = []
    var issues: [StudyIssue] = []
}
enum StudyDuplicateAction: String, CaseIterable, Identifiable {
    case skip = "Skip", update = "Update", new = "Import as new"
    var id: String { rawValue }
}
struct StudyImportRow: Identifiable {
    var record: StudyRecord
    var match: StudyRecord?
    var action: StudyDuplicateAction
    let newID = UUID().uuidString
    let id = UUID()
}
struct StudyImportPlan {
    var records: [StudyRecord]
    var issues: [StudyIssue]
    var additions: Int
    var updates: Int
    var skipped: Int
    var summary: String { "\(additions) additions · \(updates) updates · \(skipped) skipped · \(issues.count) errors" }
}

enum StudyInterchange {
    static func parse(_ text: String) -> StudyParseResult {
        var result = StudyParseResult()
        func issue(_ record: String, _ field: String, _ message: String) { result.issues.append(.init(record: record, field: field, message: message)) }
        do {
            guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                issue("document", "format", "Paste one JSON object, without Markdown fences."); return result
            }
            for key in root.keys where !["format", "version", "records"].contains(key) { issue("document", key, "Unsupported document field.") }
            guard root["format"] as? String == "folio-study" else { issue("document", "format", "Expected folio-study."); return result }
            guard let version = root["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1 else { issue("document", "version", "Only version 1 is supported."); return result }
            guard let rows = root["records"] as? [Any] else { issue("document", "records", "Expected an array of record objects."); return result }
            if rows.isEmpty { issue("document", "records", "Include at least one record.") }
            var ids: Set<String> = []
            for (index, row) in rows.enumerated() {
                let label = "Record \(index + 1)"
                guard let value = row as? [String: Any] else { issue(label, "record", "Expected an object."); continue }
                let id = value["id"] as? String ?? label
                guard let name = value["type"] as? String, let type = StudyKind(rawValue: name) else {
                    issue(id, "type", "Unsupported type. Use \(StudyKind.allCases.map(\.rawValue).joined(separator: ", "))."); continue
                }
                if value["id"] as? String == nil { issue(id, "id", "A stable string ID is required.") }
                if !ids.insert(id).inserted { issue(id, "id", "Duplicate ID in the pasted document.") }
                var record = StudyRecord(type, id: id)
                for (key, field) in value where !["id", "type"].contains(key) {
                    guard type.fields.contains(key) else { issue(id, key, "Unsupported field for \(name)."); continue }
                    guard let text = field as? String else { issue(id, key, "Use a JSON string, including for marks, years and true/false."); continue }
                    record[key] = text
                }
                result.records.append(record)
            }
        } catch { issue("document", "JSON", "Invalid JSON: \(error.localizedDescription) Use escaped \\n inside multiline strings and remove trailing commas.") }
        return result
    }
    static func export(_ records: [StudyRecord]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(StudyDocument(records: records.sorted { $0.id < $1.id })), as: UTF8.self)
    }
    private static func fingerprint(_ record: StudyRecord) -> String {
        let fields: [String]
        switch record.type {
        case .subject: fields = ["title", "board", "qualification"]
        case .question: fields = ["paper", "label"]
        case .markScheme: fields = ["paper", "question", "title"]
        case .paper: fields = ["subject", "subjectName", "board", "year", "session", "number", "title"]
        case .topic: fields = ["subject", "parent", "title"]
        case .card: fields = ["topic", "prompt"]
        case .mistake: fields = ["question", "title", "what"]
        default: fields = ["title"]
        }
        // Immutable history records match only by stable ID.
        if [.attempt, .review, .session].contains(record.type) { return record.id }
        return ([record.type.rawValue] + fields.map { record[$0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).joined(separator: "\u{1F}")
    }
    static func rows(_ imported: [StudyRecord], existing: [StudyRecord], subject: String = "", paper: String = "") -> [StudyImportRow] {
        var result = imported.map { original in
            var record = original
            if record["subject"].isEmpty && [.topic, .paper].contains(record.type) && !subject.isEmpty { record["subject"] = subject }
            if record["paper"].isEmpty && [.question, .markScheme].contains(record.type) && !paper.isEmpty { record["paper"] = paper }
            let match = existing.first { $0.id == record.id }
            return StudyImportRow(record: record, match: match, action: match == nil ? .new : .skip)
        }
        // Resolve likely duplicates after canonicalising linked IDs. This works
        // even when an external AI returns records in a different order.
        for _ in 0...result.count {
            let mapping = Dictionary(result.compactMap { row in row.match.map { (row.record.id, $0.id) } }, uniquingKeysWith: { a, _ in a })
            var changed = false
            for index in result.indices where result[index].match == nil {
                var candidate = result[index].record
                for field in StudyRules.references(candidate.type).keys {
                    if let target = mapping[candidate[field]] { candidate[field] = target }
                }
                if let match = existing.first(where: { fingerprint($0) == fingerprint(candidate) }) {
                    result[index].match = match; result[index].action = .skip; changed = true
                }
            }
            if !changed { break }
        }
        return result
    }
    static func plan(_ rows: [StudyImportRow], existing: [StudyRecord], subject: String = "", paper: String = "") -> StudyImportPlan {
        var mapping: [String: String] = [:]
        for row in rows {
            mapping[row.record.id] = row.action == .new ? (row.match == nil ? row.record.id : row.newID) : (row.match?.id ?? row.record.id)
        }
        var output: [StudyRecord] = []
        var additions = 0, updates = 0, skipped = 0
        var planIssues: [StudyIssue] = []
        for row in rows {
            if row.action == .skip { skipped += 1; continue }
            if row.match == nil, existing.contains(where: { $0.id == row.record.id }) {
                planIssues.append(.init(record: row.record.id, field: "id", message: "This record was added after the preview. Parse again to review the duplicate."))
                continue
            }
            if row.action == .update, let match = row.match, let current = existing.first(where: { $0.id == match.id }), current != match {
                planIssues.append(.init(record: row.record.id, field: "record", message: "This record changed after the preview. Parse again before updating it."))
                continue
            }
            var record = row.record
            record.id = mapping[row.record.id] ?? row.record.id
            let existingMatch = row.action == .update ? row.match : nil
            if let match = existingMatch {
                if match.type != record.type { planIssues.append(.init(record: row.record.id, field: "type", message: "An existing ID has a different type. Skip or import as new.")); continue }
                record.fields = match.fields.merging(record.fields, uniquingKeysWith: { _, incoming in incoming })
                // Structured metadata never detaches or reorders scanned originals.
                if [.paper, .markScheme].contains(record.type) {
                    var ids = match.ids("pages")
                    for id in row.record.ids("pages") where !ids.contains(id) { ids.append(id) }
                    record.setIDs("pages", ids)
                }
                updates += 1
            } else { additions += 1 }
            if record.type.fields.contains("source") && record["source"].isEmpty && existingMatch == nil {
                record["source"] = "Pasted study data (unverified)"
            }
            for field in StudyRules.references(record.type).keys {
                // Only remap explicitly imported links; preserve omitted fields
                // from an updated record.
                if let imported = row.record.fields[field], let target = mapping[imported] { record[field] = target }
            }
            if record["source"].hasPrefix("record:"), let target = mapping[String(record["source"].dropFirst(7))] { record["source"] = "record:" + target }
            if record["subject"].isEmpty && [.topic, .paper].contains(record.type) { record["subject"] = subject }
            if record["paper"].isEmpty && [.question, .markScheme].contains(record.type) { record["paper"] = paper }
            output.append(record)
        }
        return StudyImportPlan(records: output, issues: planIssues + StudyRules.validate(output, against: existing), additions: additions, updates: updates, skipped: skipped)
    }
    static let example = #"""
    {
      "format": "folio-study",
      "version": 1,
      "records": [
        {"type":"subject","id":"maths","title":"Mathematics","board":"Edexcel","qualification":"A level"},
        {"type":"topic","id":"algebra","subject":"maths","title":"Algebra","confidence":"New"},
        {"type":"topic","id":"quadratics","subject":"maths","parent":"algebra","title":"Quadratics"},
        {"type":"paper","id":"maths-2025-1","title":"Pure Mathematics 1","subject":"maths","board":"Edexcel","qualification":"A level","year":"2025","session":"June","number":"9MA0/01"},
        {"type":"question","id":"q1","paper":"maths-2025-1","label":"1","section":"A","pageStart":"2"},
        {"type":"question","id":"q1a","paper":"maths-2025-1","parent":"q1","label":"1(a)","topic":"quadratics","marks":"3","earned":"2","prompt":"Solve x² − 5x + 6 = 0.","working":"Factorise:\n(x − 2)(x − 3) = 0","feedback":"State both roots."},
        {"type":"markScheme","id":"ms-2025-1","paper":"maths-2025-1","question":"q1a","title":"Question 1 mark scheme","notes":"Scan the official scheme separately in Folio."},
        {"type":"mistake","id":"missed-root","question":"q1a","topic":"quadratics","title":"Missed a root","what":"I wrote only x = 2.","reasoning":"Each factor can equal zero.\nx = 2 or x = 3.","category":"method error","resolved":"false"},
        {"type":"card","id":"roots-card","topic":"quadratics","source":"record:missed-root","prompt":"How do you find all roots of a factorised quadratic?","answer":"Set each factor equal to zero.\nCheck both roots in the original equation.","hint":"Use the zero-product rule."}
      ]
    }
    """#
    static var aiPrompt: String {
        """
        Format my A level study material as Folio Study JSON version 1. Return ONLY one valid JSON object, without Markdown fences or commentary:
        {"format":"folio-study","version":1,"records":[...]}
        Each record has a type and a stable globally unique string id. Use the same IDs on later edits. ALL other values must be JSON strings, including marks, year and booleans. Omit unknown values. Escape multiline text using \\n. Do not invent exam content, marks or facts; preserve my sources and flag uncertainty in notes. Do not include scans or base64 data. Paper scans are attached separately in Folio; pages may be omitted. Papers need no course/topic link. References use record IDs. Cards' study sources use record:ID; external sources use plain text or URLs. Use only these fields (asterisk = required):
        \(StudyKind.allCases.map { kind in "\(kind.rawValue): " + kind.fields.map { $0 + (kind.required.contains($0) ? "*" : "") }.joined(separator: ", ") }.joined(separator: "\n"))
        Omit timerState, timerDeadline, timerRemaining and completedAt unless I supply actual sitting history. durationMinutes can specify the paper's real duration (1–720 minutes). markingMode is omitted for individual questions; pageTotal means one leaf covering exactly one scan page, with no overlapping individual questions or totals for that page.
        topic.parent links to a topic in the same subject; question.parent links to a question in the same paper. Do not create cycles. Optional question.section is a section name. Use marks/earned on leaf subquestions; parent totals are calculated from children. earned must be between zero and marks. pageStart/pageEnd are 1-based scan positions. category examples: knowledge gap, method error, misread question, careless slip. confidence: New, Exploring, Practising, Confident. resolved: "true" or "false". Dates: ISO 8601 with time and timezone. Folio noteBooks/noteSections/notePages/pages are ordered comma-separated existing UUIDs, and sourcePage is one existing page UUID; omit if unknown. Keep prompts, answers, reasoning, feedback and working editable and include source where available. attempt, review and session are optional history records; omit unless I supply this history. For review.rating use Again, Nearly or Got it. For attempt, include question or mistake.
        Example:
        \(example)
        My study material follows:
        """
    }
}
