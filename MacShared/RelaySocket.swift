import Darwin
import Foundation
import PrefillKit

// The local channel between the native messaging host Chrome starts and the running app:
// a Unix socket in the app's support folder, one framed request and one framed reply per
// connection.
enum RelaySocket {
    static let timeout: TimeInterval = 5

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Prefill", directoryHint: .isDirectory)
    }

    static var path: String {
        directory.appending(path: "relay.sock").path(percentEncoded: false)
    }

    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    static func setTimeout(_ socket: Int32) {
        var limit = timeval(tv_sec: Int(timeout), tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &limit, size)
        setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &limit, size)
        var noSignal: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    }
}

// Blocking reads and writes of whole frames on a file descriptor.
enum FrameIO {
    static func read(_ descriptor: Int32, max: Int) -> Data? {
        guard let header = readExactly(descriptor, count: NativeFraming.headerSize),
              let length = NativeFraming.bodyLength(header, max: max) else { return nil }
        return readExactly(descriptor, count: length)
    }

    static func write(_ descriptor: Int32, body: Data) -> Bool {
        let frame = NativeFraming.frame(body)
        return frame.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let result = Darwin.write(descriptor, buffer.baseAddress! + sent, buffer.count - sent)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { return false }
                sent += result
            }
            return true
        }
    }

    private static func readExactly(_ descriptor: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            var received = 0
            while received < count {
                let result = Darwin.read(descriptor, buffer.baseAddress! + received, count - received)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { return false }
                received += result
            }
            return true
        }
        return complete ? data : nil
    }
}
