import Foundation

/// Persist transitions, derive ticks from a deadline. Navigation, suspension and
/// process termination cannot pause or reset a running paper.
enum PaperClock {
    static func duration(_ paper: StudyRecord) -> TimeInterval {
        let minutes = paper.number("durationMinutes") ?? 90
        return (minutes.isFinite && minutes > 0 ? min(minutes, 720) : 90) * 60
    }
    static func remaining(_ paper: StudyRecord, now: Date = .now) -> TimeInterval {
        if paper["timerState"] == "running", let deadline = paper.date("timerDeadline") {
            return max(0, deadline.timeIntervalSince(now))
        }
        if paper["timerState"] == "finished" { return 0 }
        let saved = paper.number("timerRemaining") ?? duration(paper)
        return saved.isFinite ? max(0, min(saved, duration(paper))) : duration(paper)
    }
    static func start(_ paper: StudyRecord, now: Date = .now) -> StudyRecord {
        var changed = paper
        let seconds = remaining(paper, now: now)
        guard seconds > 0 else { return finish(paper, now: now) }
        changed["timerState"] = "running"
        changed["timerDeadline"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(seconds))
        changed["timerRemaining"] = String(seconds)
        return changed
    }
    static func pause(_ paper: StudyRecord, now: Date = .now) -> StudyRecord {
        if remaining(paper, now: now) <= 0 { return finish(paper, now: now) }
        var changed = paper
        changed["timerRemaining"] = String(remaining(paper, now: now))
        changed["timerDeadline"] = ""
        changed["timerState"] = "paused"
        return changed
    }
    static func finish(_ paper: StudyRecord, now: Date = .now) -> StudyRecord {
        var changed = paper
        changed["timerState"] = "finished"; changed["timerRemaining"] = "0"
        changed["timerDeadline"] = ""
        changed["completedAt"] = ISO8601DateFormatter().string(from: now)
        return changed
    }
    static func reset(_ paper: StudyRecord) -> StudyRecord {
        var changed = paper
        for field in ["timerState", "timerRemaining", "timerDeadline", "completedAt"] { changed[field] = "" }
        return changed
    }
    static func label(_ seconds: TimeInterval) -> String {
        let value = Int(ceil(max(0, seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
