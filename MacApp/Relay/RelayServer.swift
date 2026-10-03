import Darwin
import Foundation
import os
import PrefillKit

// Listens on the relay socket and answers each request from Prefill's native messaging host
// with the same MessageRouter the Safari extension uses on iPhone. Requests are checked
// again here, so a host that let something through still can't reach the card with it.
final class RelayServer: Sendable {
    private static let log = PrefillLog.logger("relay")
    private static let backlog: Int32 = 16

    private let router: MessageRouter
    private let answered: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.tarunyadgirkar.prefill.relay", attributes: .concurrent)
    private let listener: Int32

    init?(router: MessageRouter, answered: @escaping @Sendable () -> Void) {
        guard let listener = Self.listen(at: RelaySocket.path) else { return nil }
        self.router = router
        self.answered = answered
        self.listener = listener
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    private static func listen(at path: String) -> Int32? {
        try? FileManager.default.createDirectory(at: RelaySocket.directory, withIntermediateDirectories: true)
        chmod(RelaySocket.directory.path(percentEncoded: false), 0o700)
        unlink(path)
        guard var address = RelaySocket.address(path) else { return nil }
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(socket, backlog) == 0 else {
            log.error("relay socket not ready: \(errno, privacy: .public)")
            close(socket)
            return nil
        }
        return socket
    }

    private func acceptLoop() {
        while true {
            let connection = accept(listener, nil, nil)
            if connection < 0 {
                if errno == EBADF || errno == EINVAL {
                    Self.log.error("relay stopped: \(errno, privacy: .public)")
                    return
                }
                continue
            }
            queue.async { [self] in serve(connection) }
        }
    }

    private func serve(_ connection: Int32) {
        defer { close(connection) }
        RelaySocket.setTimeout(connection)
        guard CodeIdentity.isPeer(CodeIdentity.hostIdentifier, socket: connection) else {
            Self.log.error("refused a connection from something other than Prefill's host")
            return
        }
        guard let body = FrameIO.read(connection, max: NativeFraming.maxRequest) else { return }
        let checked = try? MessageCoding.validatedRequest(body)
        let message = checked.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let standingDown = (try? MessageCoding.request(from: message)).flatMap(AutofillMode.standDown)
        let response = standingDown ?? checked.map { _ in router.route(message) } ?? .error(reason: "unknown message")
        _ = FrameIO.write(connection, body: MessageCoding.replyData(response))
        answered()
    }
}
