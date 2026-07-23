import HoldTypeDomain

/// App-owned persistence boundary used by the iOS Fixes editor.
nonisolated struct IOSTextFixEditorClient: Sendable {
    typealias Load = @Sendable () async throws -> TextFixCatalog
    typealias Save = @Sendable (TextFixCatalog) async throws -> TextFixCatalog

    let load: Load
    let save: Save

    init(
        load: @escaping Load,
        save: @escaping Save
    ) {
        self.load = load
        self.save = save
    }
}
