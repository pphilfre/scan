import SwiftUI
import SwiftData
import CloudKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AccessController.self) private var access
    @Environment(WorkspaceFolder.self) private var workspace
    @AppStorage("iCloudSync") private var iCloudSync = false
    @AppStorage("appLock") private var appLock = false
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentColor") private var accentColor = "sage"
    @State private var checking = false
    @State private var message: String?
    @State private var chooseFolder = false
    @State private var disconnecting = false
    @State private var studyTransfer = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if workspace.busy { ProgressView(workspace.restoring ? "Opening working folder…" : "Connecting or saving working folder…") }
                    if let name = workspace.folderName {
                        LabeledContent("Folder", value: name)
                        Label(workspace.isConnected && workspace.error == nil ? "Connected" : "Needs attention", systemImage: workspace.isConnected && workspace.error == nil ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .font(.caption).foregroundStyle(workspace.isConnected && workspace.error == nil ? .green : .orange)
                        if let saved = workspace.lastSaved { LabeledContent("Last saved to folder", value: saved.formatted(date: .abbreviated, time: .standard)) }
                        Button("Save now", systemImage: "externaldrive.badge.checkmark") { Task { await workspace.saveNow(context: context) } }.disabled(workspace.busy || !workspace.isConnected)
                    }
                    Button(workspace.folderName == nil ? "Choose working folder…" : "Choose or reconnect folder…", systemImage: "folder") { chooseFolder = true }.disabled(workspace.busy)
                    if workspace.folderName != nil { Button("Disconnect folder", role: .destructive) { disconnecting = true }.disabled(workspace.busy) }
                    if let error = workspace.error { Text(error).font(.caption).foregroundStyle(.red) }
                } header: { Text("Working folder") } footer: {
                    Text("Folio automatically saves into “Folio Library” inside the selected folder. Original images are in its “originals” folder. If LiveContainer resets the app, choose the same folder to recover your books, scans and ink. Keep it outside the app’s container and available offline. Face ID protects Folio; files in this folder can still be opened in Files.")
                }
                Section {
                    Toggle("iCloud sync", isOn: Binding(get: { iCloudSync }, set: { enabled in setSync(enabled) })).disabled(checking)
                    if checking { ProgressView("Checking iCloud…") }
                } header: { Text("Sync") } footer: { Text("Offline access stays available. Changes keep a version history. Restart Folio after changing sync. iCloud needs a signed installation with the matching CloudKit capability.") }
                Section {
                    Toggle("Protect Folio", isOn: Binding(get: { appLock }, set: { enabled in
                        Task { if await access.authenticate(reason: "Change protection for Folio") { appLock = enabled; access.appUnlocked = true } }
                    }))
                    if let message = access.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Privacy") } footer: { Text("Uses Face ID or your device passcode. Protect individual books from their menus. Folio locks again when you leave the app.") }
                DisplayPreferences()
                Section("Study") {
                    StudyHapticPreference()
                    Button("Study import, export and AI prompt") { studyTransfer = true }
                }
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    ColorChoices(selection: $accentColor)
                }
                Section("Capture") {
                    Text("Add the Folio widget to your Home Screen or Lock Screen, or use the Scan note shortcut. Pages go to Unfiled until you choose a book. Widget and shortcut availability depends on the installation method.").font(.subheadline).foregroundStyle(.secondary)
                }
                Section { LabeledContent("Folio", value: "2.0.1") }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(workspace.busy) } }
            .interactiveDismissDisabled(workspace.busy)
            .sheet(isPresented: $studyTransfer) { StudyTransferView() }
            .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): Task { do { try await workspace.connect(url, context: context) } catch { workspace.error = error.localizedDescription } }
                case .failure(let error): workspace.error = error.localizedDescription
                }
            }
            .confirmationDialog("Disconnect this folder? Its saved files and your local library will be kept.", isPresented: $disconnecting, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { workspace.disconnect() }
            }
            .alert("iCloud", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
        }
    }
    private func setSync(_ enabled: Bool) {
        if !enabled { iCloudSync = false; message = "Close and reopen Folio to stop syncing. The local library stays available."; return }
        checking = true
        Task {
            defer { checking = false }
            do {
                if try await CKContainer(identifier: "iCloud.dev.freddiephilpot.folio").accountStatus() == .available {
                    iCloudSync = true; message = "Close and reopen Folio to start syncing this library."
                } else { message = "Sign in to iCloud in Settings and check that iCloud Drive is enabled." }
            } catch { message = "iCloud isn’t available for this installation. " + error.localizedDescription }
        }
    }
}

struct ExportFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
