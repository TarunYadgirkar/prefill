import AppKit
import Darwin
import Foundation
import PrefillKit

// The asking side of the relay: Chrome's host and the Safari extension each send one framed
// request to the running app and wait for its reply, opening the app first when it's closed.
enum RelayClient {
    private static let launchWait: TimeInterval = 5
    private static let retryInterval: useconds_t = 100_000

    static func send(_ request: Data, to path: String, launching appURL: URL?) -> Data? {
        guard let socket = connectLaunchingIfNeeded(path, appURL: appURL) else { return nil }
        defer { close(socket) }
        guard FrameIO.write(socket, body: request) else { return nil }
        return FrameIO.read(socket, max: NativeFraming.maxReply)
    }

    // The app that holds this code, found from its own path.
    static func enclosingApp(of executable: URL) -> URL? {
        var url = executable.resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app" { return url }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    private static func connect(_ path: String) -> Int32? {
        guard var address = RelaySocket.address(path) else { return nil }
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(socket)
            return nil
        }
        RelaySocket.setTimeout(socket)
        guard CodeIdentity.isPeer(CodeIdentity.appIdentifier, socket: socket) else {
            close(socket)
            return nil
        }
        return socket
    }

    private static func launch(_ appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let opened = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in opened.signal() }
        _ = opened.wait(timeout: .now() + launchWait)
    }

    private static func connectLaunchingIfNeeded(_ path: String, appURL: URL?) -> Int32? {
        if let socket = connect(path) { return socket }
        guard let appURL else { return nil }
        launch(appURL)
        let deadline = Date.now.addingTimeInterval(launchWait)
        while Date.now < deadline {
            if let socket = connect(path) { return socket }
            usleep(retryInterval)
        }
        return nil
    }
}
