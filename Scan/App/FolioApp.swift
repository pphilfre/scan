import SwiftUI
import SwiftData

@MainActor @Observable final class LibraryStorage {
    var container: ModelContainer?
    var error: String?
    init() { open() }
    func open(offline: Bool = false) {
        if offline { UserDefaults.standard.set(false, forKey: "iCloudSync") }
        do {
            let schema = Schema([Notebook.self, BookSection.self, NotePage.self])
            let sync = UserDefaults.standard.bool(forKey: "iCloudSync")
            let url = URL.applicationSupportDirectory.appending(path: "Folio.store")
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            let config = ModelConfiguration("Folio", schema: schema, url: url,
                cloudKitDatabase: sync ? .private("iCloud.dev.freddiephilpot.folio") : .none)
            container = try ModelContainer(for: schema, configurations: [config])
            error = nil
        } catch {
            container = nil
            self.error = error.localizedDescription
        }
    }
}

@main struct FolioApp: App {
    @State private var storage = LibraryStorage()
    var body: some Scene {
        WindowGroup {
            if let container = storage.container {
                LibraryView().modelContainer(container).tint(FolioStyle.ink)
            } else {
                VStack(spacing: 20) {
                    ContentUnavailableView("Your library couldn’t open", systemImage: "externaldrive.badge.exclamationmark",
                        description: Text((storage.error ?? "Please restart Folio.") + " Your saved files have been kept."))
                    Button("Open offline") { storage.open(offline: true) }.buttonStyle(.glassProminent)
                    Button("Try again") { storage.open() }
                }.padding()
            }
        }
    }
}
