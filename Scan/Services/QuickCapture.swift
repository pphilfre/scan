import AppIntents
import Observation
import Foundation

@MainActor @Observable final class CaptureRouter {
    static let shared = CaptureRouter()
    var route: String?
    func open(_ url: URL) {
        guard url.scheme == "folio", let host = url.host, ["scan", "inbox"].contains(host) else { return }
        route = host
    }
}

struct ScanNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a note"
    static let description = IntentDescription("Open the native scanner and collect pages in Folio’s Unfiled inbox.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        CaptureRouter.shared.route = "scan"
        return .result()
    }
}

struct FolioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanNoteIntent(), phrases: ["Scan a note with \(.applicationName)", "Capture a page in \(.applicationName)"], shortTitle: "Scan note", systemImageName: "document.viewfinder")
    }
}
