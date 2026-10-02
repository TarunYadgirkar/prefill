import AppKit
import Darwin
import Foundation
import PrefillKit

// Chrome, Arc, Brave and Edge start this for each message the extension sends: one framed
// request on stdin, one framed reply on stdout. It never reads Contacts itself, since
// macOS would ask on the browser's behalf; the running app answers.

private let launchWait: TimeInterval = 5
private let retryInterval: useconds_t = 100_000

private func reply(_ body: Data) -> Never {
    exit(FrameIO.write(STDOUT_FILENO, body: body) ? 0 : 1)
}

private func fail(_ reason: String) -> Never {
    reply(MessageCoding.replyData(.error(reason: reason)))
}

private func connectToApp() -> Int32? {
    guard var address = RelaySocket.address(RelaySocket.path) else { return nil }
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

// The app that holds this host, found from the host's own path.
private func enclosingApp() -> URL? {
    var url = URL(filePath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    while url.path != "/" {
        if url.pathExtension == "app" { return url }
        url = url.deletingLastPathComponent()
    }
    return nil
}

private func launchApp() {
    guard let appURL = enclosingApp() else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    let opened = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in opened.signal() }
    _ = opened.wait(timeout: .now() + launchWait)
}

private func connectLaunchingIfNeeded() -> Int32? {
    if let socket = connectToApp() { return socket }
    launchApp()
    let deadline = Date.now.addingTimeInterval(launchWait)
    while Date.now < deadline {
        if let socket = connectToApp() { return socket }
        usleep(retryInterval)
    }
    return nil
}

guard CodeIdentity.isBrowser(pid: getppid()) else { fail("Prefill only answers Chrome, Arc, Brave and Edge.") }
guard let body = FrameIO.read(STDIN_FILENO, max: NativeFraming.maxRequest) else { fail("unreadable message") }
guard let request = try? MessageCoding.validatedRequest(body) else { fail("unknown message") }
guard let socket = connectLaunchingIfNeeded() else { fail("Prefill isn't running on this Mac. Open Prefill.") }
guard FrameIO.write(socket, body: request), let answer = FrameIO.read(socket, max: NativeFraming.maxReply) else {
    fail("Prefill didn't answer. Try again in a moment.")
}
close(socket)
reply(answer)
