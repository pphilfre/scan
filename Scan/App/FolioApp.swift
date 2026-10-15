import SwiftUI
import SwiftData
import CoreData

@MainActor @Observable final class LibraryStorage {
    var container: ModelContainer?
    var error: String?
    init() { open() }
    func open(offline: Bool = false) {
        if offline { UserDefaults.standard.set(false, forKey: "iCloudSync") }
        do {
            let schema = Schema([Notebook.self, BookSection.self, NotePage.self, PageRevision.self, PageLink.self, StudyItem.self])
            #if DEBUG
            if UITestFixture.enabled {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                let opened = try ModelContainer(for: schema, configurations: [config])
                try UITestFixture.seed(opened.mainContext)
                container = opened; error = nil
                return
            }
            #endif
            let sync = UserDefaults.standard.bool(forKey: "iCloudSync")
            let url = URL.applicationSupportDirectory.appending(path: "Folio.store")
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try StorageMigration.prepareStore(at: url)
            let config = ModelConfiguration("Folio", schema: schema, url: url,
                cloudKitDatabase: sync ? .private("iCloud.dev.freddiephilpot.folio") : .none)
            let opened = try ModelContainer(for: schema, configurations: [config])
            try LibraryReconciler.run(opened.mainContext)
            try LibraryPersistence.save(opened.mainContext)
            container = opened
            UserDefaults.standard.set(StorageMigration.currentFormat, forKey: "folioStoreFormat")
            error = nil
        } catch { container = nil; self.error = error.localizedDescription }
    }
}

@main struct FolioApp: App {
    @State private var storage = LibraryStorage()
    @State private var access = AccessController()
    @State private var actions = LibraryActions()
    @State private var workspace = WorkspaceFolder()
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentColor") private var accentColor = "sage"
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if let container = storage.container {
                    ZStack {
                        if access.appUnlocked { LibraryView() }
                        else { LibraryLockView() }
                        if workspace.restoring {
                            FolioStyle.paper.ignoresSafeArea().overlay { ProgressView("Opening working folder…") }
                        }
                        if scenePhase != .active { FolioStyle.paper.ignoresSafeArea().overlay { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary) } }
                    }
                    .modelContainer(container)
                    .environment(access).environment(actions).environment(workspace).environment(CaptureRouter.shared)
                    .task {
                        #if DEBUG
                        if UITestFixture.enabled { return }
                        #endif
                        await workspace.resume(context: container.mainContext)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in workspace.schedule(context: container.mainContext) }
                    .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                        Task {
                            do { try await Task.sleep(for: .milliseconds(250)); try LibraryReconciler.run(container.mainContext) }
                            catch { actions.error = error.localizedDescription }
                        }
                    }
                    .onOpenURL { CaptureRouter.shared.open($0) }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background {
                            access.lock(); ThumbnailMemory.shared.clear()
                            Task { await workspace.saveNow(context: container.mainContext) }
                        }
                        PrivacyShield.setVisible(phase != .active)
                    }
                } else {
                    VStack(spacing: 20) {
                        ContentUnavailableView("Your library couldn’t open", systemImage: "externaldrive.badge.exclamationmark",
                            description: Text((storage.error ?? "Please restart Folio.") + " Your saved files have been kept."))
                        Button("Open offline") { storage.open(offline: true) }.buttonStyle(.glassProminent)
                        Button("Try again") { storage.open() }
                    }.padding()
                }
            }.tint(FolioStyle.color(accentColor))
                .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil)
        }
    }
}

struct LibraryLockView: View {
    @Environment(AccessController.self) private var access
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(FolioStyle.ink)
            Text("Folio is locked").font(.system(.title, design: .serif))
            Button("Unlock", systemImage: "faceid") { Task { await access.unlockApp() } }.buttonStyle(.glassProminent).disabled(access.isAuthenticating)
            if let message = access.message { Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(FolioStyle.paper)
    }
}

struct BookLockView: View {
    let book: Notebook
    @Environment(AccessController.self) private var access
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock").font(.largeTitle)
            Text(book.title).font(.system(.title, design: .serif))
            Button("Unlock book", systemImage: "faceid") { Task { await access.unlock(book) } }.buttonStyle(.glassProminent).disabled(access.isAuthenticating)
            if let message = access.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(FolioStyle.paper)
    }
}
