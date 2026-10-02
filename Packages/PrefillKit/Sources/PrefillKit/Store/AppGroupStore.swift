import Foundation

// Files are readable only once the device has been unlocked after a restart (the extension
// may run while the phone is locked later) and stay out of backups, like the Keychain items
// of the other backend.
public struct AppGroupStore: SharedStore {
    private static let writing: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func readAppState() throws -> AppState {
        try read(.appState) ?? AppState()
    }

    public func writeAppState(_ state: AppState) throws {
        let data = try DocumentCoder.encode(state)
        try coordinate(.appState, options: .forReplacing) { url in
            try data.write(to: url, options: Self.writing)
        }
    }

    public func readEvents() throws -> ExtensionEvents {
        try read(.events) ?? ExtensionEvents()
    }

    public func appendEvents(_ new: ExtensionEvents) throws {
        try coordinate(.events, options: .forMerging) { url in
            let current = try Self.load(ExtensionEvents.self, at: url) ?? ExtensionEvents()
            let next = current.appending(new)
            let data = try DocumentCoder.encode(next)
            try data.write(to: url, options: Self.writing)
        }
    }

    public func removeAll() throws {
        for document in StoreDocument.allCases {
            try coordinate(document, options: .forDeleting) { url in
                do {
                    try FileManager.default.removeItem(at: url)
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    return
                }
            }
        }
    }

    private func read<T: Decodable>(_ document: StoreDocument) throws -> T? {
        var result: Result<Data?, any Error> = .success(nil)
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url(document), options: [], error: &coordinationError) { url in
            result = Result { try Self.contents(of: url) }
        }
        if coordinationError != nil { throw StoreError.coordination }
        return try result.get().map { try DocumentCoder.decode(T.self, from: $0) }
    }

    private func coordinate(
        _ document: StoreDocument, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void
    ) throws {
        try prepareDirectory()
        var result: Result<Void, any Error> = .success(())
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url(document), options: options, error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if coordinationError != nil { throw StoreError.coordination }
        try result.get()
    }

    private func prepareDirectory() throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: attributes
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = directory
        try excluded.setResourceValues(values)
    }

    // Events are expendable history, so a damaged file is replaced rather than blocking
    // every later append.
    private static func load<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard let data = try contents(of: url) else { return nil }
        do {
            return try DocumentCoder.decode(type, from: data)
        } catch is DecodingError {
            StoreLog.logger.error("damaged events file replaced")
            return nil
        }
    }

    private static func contents(of url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func url(_ document: StoreDocument) -> URL {
        directory.appending(path: "\(document.rawValue).json")
    }
}
