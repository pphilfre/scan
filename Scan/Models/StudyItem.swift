import Foundation
import SwiftData

/// A separate, additive entity leaves all shipped notebook relationships intact.
/// App identifiers (rather than SwiftData relationships/unique constraints) are
/// portable across folder restores and compatible with CloudKit duplication.
@Model final class StudyItem {
    var id: String = ""
    var payload: Data = Data()
    var modifiedAt: Date = Date()
    var removedAt: Date?
    @Attribute(.externalStorage) var historyData: Data?

    init(_ record: StudyRecord) throws {
        id = record.id
        payload = try JSONEncoder().encode(record)
    }
    func decoded() throws -> StudyRecord { try JSONDecoder().decode(StudyRecord.self, from: payload) }
    func snapshot() throws -> StudySnapshot {
        StudySnapshot(record: try decoded(), modified: modifiedAt, removed: removedAt,
            history: try historyData.map { try JSONDecoder().decode([StudyVersion].self, from: $0) } ?? [])
    }
}

enum StudyKind: String, Codable, CaseIterable, Sendable {
    case subject, topic, paper, question, markScheme, mistake, card, attempt, review, session
    var name: String {
        switch self {
        case .subject: "Subject"
        case .topic: "Topic"
        case .paper: "Past paper"
        case .question: "Question"
        case .markScheme: "Mark scheme"
        case .mistake: "Mistake"
        case .card: "Flashcard"
        case .attempt: "Attempt"
        case .review: "Review"
        case .session: "Study session"
        }
    }
    var fields: [String] {
        switch self {
        case .subject: ["title", "board", "qualification", "notes", "source"]
        case .topic: ["title", "subject", "parent", "confidence", "notes", "noteBooks", "noteSections", "notePages", "source"]
        case .paper: ["title", "subject", "subjectName", "board", "qualification", "year", "session", "number", "notes", "pages", "source", "durationMinutes", "timerState", "timerDeadline", "timerRemaining", "completedAt"]
        case .question: ["label", "paper", "parent", "section", "topic", "prompt", "answer", "working", "correction", "feedback", "marks", "earned", "pageStart", "pageEnd", "retryAt", "notes", "source", "markingMode"]
        case .markScheme: ["title", "paper", "question", "pages", "notes", "source"]
        case .mistake: ["title", "question", "topic", "what", "reasoning", "category", "resolved", "retryAt", "notePages", "source"]
        case .card: ["prompt", "answer", "hint", "topic", "source", "sourcePage", "due", "interval", "repetitions", "notes"]
        case .attempt: ["question", "mistake", "earned", "marks", "resolved", "date", "session", "notes"]
        case .review: ["card", "rating", "date", "session"]
        case .session: ["title", "scope", "started", "finished", "notes"]
        }
    }
    var required: [String] {
        switch self {
        case .subject, .paper, .session: ["title"]
        case .topic: ["title", "subject"]
        case .question: ["label", "paper"]
        case .markScheme: ["title", "paper"]
        case .mistake: ["title", "what", "reasoning"]
        case .card: ["prompt", "answer"]
        case .attempt: ["date"]
        case .review: ["card", "rating", "date"]
        }
    }
}

/// Flat string fields make the JSON interchange format easy to paste and edit.
/// JSON escaping gives multiline text an unambiguous representation.
struct StudyRecord: Codable, Identifiable, Equatable, Sendable {
    var type: StudyKind
    var id: String
    var fields: [String: String] = [:]
    init(_ type: StudyKind, id: String = UUID().uuidString, _ fields: [String: String] = [:]) {
        self.type = type; self.id = id; self.fields = fields
    }
    subscript(_ field: String) -> String {
        get { fields[field] ?? "" }
        set { fields[field] = newValue }
    }
    var title: String { self["title"].isEmpty ? (self["label"].isEmpty ? String(self["prompt"].prefix(100)) : self["label"]) : self["title"] }
    func number(_ field: String) -> Double? { Double(self[field]) }
    func date(_ field: String) -> Date? { ISO8601DateFormatter().date(from: self[field]) }
    func ids(_ field: String) -> [UUID] { self[field].split(separator: ",").compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    mutating func setIDs(_ field: String, _ ids: [UUID]) { self[field] = ids.map(\.uuidString).joined(separator: ",") }
    private struct Key: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        type = try values.decode(StudyKind.self, forKey: Key("type"))
        id = try values.decode(String.self, forKey: Key("id"))
        fields = [:]
        for key in values.allKeys where !["type", "id"].contains(key.stringValue) {
            fields[key.stringValue] = try values.decode(String.self, forKey: key)
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        try values.encode(type, forKey: Key("type")); try values.encode(id, forKey: Key("id"))
        for (key, value) in fields { try values.encode(value, forKey: Key(key)) }
    }
}

struct StudyVersion: Codable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var record: StudyRecord
}
struct StudySnapshot: Codable, Sendable {
    var record: StudyRecord
    var modified: Date
    var removed: Date?
    var history: [StudyVersion]
}
