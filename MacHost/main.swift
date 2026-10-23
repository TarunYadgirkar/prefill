import Darwin
import Foundation
import PrefillKit

// Chrome, Arc, Brave and Edge start this for each message the extension sends: one framed
// request on stdin, one framed reply on stdout. It never reads Contacts itself, since
// macOS would ask on the browser's behalf; the running app answers.

private func reply(_ body: Data) -> Never {
    exit(FrameIO.write(STDOUT_FILENO, body: body) ? 0 : 1)
}

private func fail(_ reason: String) -> Never {
    reply(MessageCoding.replyData(.error(reason: reason)))
}

guard CodeIdentity.isBrowser(pid: getppid()) else { fail("Prefill only answers Chrome, Arc, Brave and Edge.") }
guard let body = FrameIO.read(STDIN_FILENO, max: NativeFraming.maxRequest) else { fail("unreadable message") }
guard let request = try? MessageCoding.validatedRequest(body) else { fail("unknown message") }
let app = RelayClient.enclosingApp(of: URL(filePath: CommandLine.arguments[0]))
guard let answer = RelayClient.send(request, to: RelaySocket.path, launching: app) else {
    fail("Prefill isn't running on this Mac. Open Prefill.")
}
reply(answer)
