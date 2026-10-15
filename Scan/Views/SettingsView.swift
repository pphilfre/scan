import SwiftUI
import CloudKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("iCloudSync") private var iCloudSync = false
    @State private var checking = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "book.pages").font(.largeTitle).foregroundStyle(FolioStyle.ink)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Folio").font(.system(.title2, design: .serif))
                            Text("A home for handwritten ideas").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                }
                Section {
                    Toggle("iCloud sync", isOn: Binding(get: { iCloudSync }, set: { requested in setSync(requested) })).disabled(checking)
                    if checking { ProgressView("Checking iCloud…") }
                } header: { Text("Storage") } footer: {
                    Text("Your library works offline. iCloud keeps it up to date across your devices when enabled. After changing this setting, close and reopen Folio. Sync requires an iCloud-enabled, signed app.")
                }
                Section("On your device") {
                    Label("On-device text recognition", systemImage: "text.viewfinder")
                    Label("Original scans always preserved", systemImage: "document.badge.clock")
                    Label("No account or subscription needed", systemImage: "person.crop.circle.badge.checkmark")
                }
                Section {
                    Text("For clearer recognition, use even lighting, keep the whole page in frame, and review the detected edges before saving. You can correct recognised text at any time.").font(.subheadline).foregroundStyle(.secondary)
                } header: { Text("A better scan") }
                Section {
                    LabeledContent("Version", value: "1.0.0")
                    Text("Made for paper people.").font(.system(.subheadline, design: .serif)).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("iCloud", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
        }
    }
    private func setSync(_ enabled: Bool) {
        if !enabled { iCloudSync = false; message = "Close and reopen Folio to use your library without iCloud syncing."; return }
        checking = true
        Task {
            defer { checking = false }
            do {
                let status = try await CKContainer(identifier: "iCloud.dev.freddiephilpot.folio").accountStatus()
                if status == .available {
                    iCloudSync = true
                    message = "iCloud is ready. Close and reopen Folio to start syncing this library."
                } else { message = "Sign in to iCloud in Settings and check that iCloud Drive is enabled, then try again." }
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
