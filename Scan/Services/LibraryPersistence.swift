import SwiftData

/// Explicit saves notify connected working folders even when a sheet is open
/// or SwiftData doesn't deliver its public save notification.
@MainActor enum LibraryPersistence {
    private struct Observer {
        weak var workspace: WorkspaceFolder?
        weak var context: ModelContext?
    }
    private static var observers: [ObjectIdentifier: Observer] = [:]
    static func observe(_ workspace: WorkspaceFolder, context: ModelContext) {
        observers[ObjectIdentifier(workspace)] = Observer(workspace: workspace, context: context)
    }
    static func stopObserving(_ workspace: WorkspaceFolder) {
        observers.removeValue(forKey: ObjectIdentifier(workspace))
    }
    static func save(_ context: ModelContext) throws {
        try context.save()
        observers = observers.filter { $0.value.workspace != nil && $0.value.context != nil }
        for observer in observers.values {
            if let attached = observer.context, attached.container === context.container {
                observer.workspace?.schedule(context: attached)
            }
        }
    }
}
