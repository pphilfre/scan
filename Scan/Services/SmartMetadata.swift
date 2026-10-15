import Foundation

struct SmartMetadata {
    static func title(from text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "Untitled note"
        return String(first.prefix(70))
    }
    static func date(from text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date
    }
    static func section(from text: String) -> String {
        let lower = text.lowercased()
        let groups: [(String, [String])] = [
            ("Definitions", ["definition", "defined as", "terminology"]),
            ("Worked examples", ["example", "solution", "solve"]),
            ("Revision", ["revision", "summary", "exam", "review"]),
            ("Lecture notes", ["lecture", "lesson", "chapter"])
        ]
        return groups.first { $0.1.contains(where: lower.contains) }?.0 ?? ""
    }
    static func snippet(_ text: String, matching query: String) -> String {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return String(text.prefix(130)) }
        let start = text.index(range.lowerBound, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end].replacingOccurrences(of: "\n", with: " ")
    }
}
