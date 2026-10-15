import Foundation
import LocalAuthentication
import Observation

@MainActor @Observable final class AccessController {
    var appUnlocked = !UserDefaults.standard.bool(forKey: "appLock")
    var unlockedBooks: Set<UUID> = []
    var isAuthenticating = false
    var message: String?
    func canRead(_ page: NotePage) -> Bool {
        appUnlocked && page.trashedAt == nil && page.book?.trashedAt == nil && (page.book.map(canOpen) ?? true)
    }
    func canOpen(_ book: Notebook) -> Bool { !book.isLocked || unlockedBooks.contains(book.id) }
    func lock() {
        unlockedBooks.removeAll()
        appUnlocked = !UserDefaults.standard.bool(forKey: "appLock")
    }
    func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Set a device passcode in Settings to protect your notes."
            return false
        }
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch {
            if (error as? LAError)?.code != .userCancel && (error as? LAError)?.code != .appCancel {
                message = error.localizedDescription
            }
            return false
        }
    }
    func unlockApp() async { if await authenticate(reason: "Unlock your Folio library") { appUnlocked = true } }
    func unlock(_ book: Notebook) async { if await authenticate(reason: "Unlock \(book.title)") { unlockedBooks.insert(book.id) } }
}
