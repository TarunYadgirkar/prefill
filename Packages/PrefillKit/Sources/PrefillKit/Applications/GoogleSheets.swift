import CryptoKit
import Foundation

// Writing applications straight to a Google Sheet Prefill creates in the person's Drive, after
// they sign in with Google on the Mac. The scope is drive.file: Prefill reaches only files it
// created. Like ApplicationSheet, this only builds requests and reads answers; the Mac app
// makes the calls, so the keyboard, which links PrefillKit, has no network code.
public enum GoogleSheets {
    public static let scope = "https://www.googleapis.com/auth/drive.file"
    public static let title = "Job Applications"
    static let tab = "Applications"

    // An installed app's OAuth client (type iOS in Google Cloud). Its ID isn't a secret.
    public struct Client: Sendable, Hashable {
        public let id: String

        public init?(id: String) {
            let trimmed = id.trimmingCharacters(in: .whitespaces)
            let suffix = ".apps.googleusercontent.com"
            guard trimmed.hasSuffix(suffix), trimmed.count > suffix.count, !trimmed.hasPrefix("$(") else { return nil }
            self.id = trimmed
        }

        // Google's redirect for an iOS client is its ID reversed, as a URL scheme.
        public var callbackScheme: String {
            "com.googleusercontent.apps." + id.replacing(".apps.googleusercontent.com", with: "")
        }

        var redirectURI: String { callbackScheme + ":/oauth2redirect" }
    }

    public struct Tokens: Codable, Sendable, Hashable {
        public let accessToken: String
        public let expiresAt: Date
        public let refreshToken: String?

        public func isFresh(at now: Date) -> Bool { expiresAt.timeIntervalSince(now) > 60 }
    }

    public struct Spreadsheet: Codable, Sendable, Hashable {
        public let id: String
        public let url: URL

        // Only an ID Google could have made and a Google Docs address, so a changed settings
        // file can't send the token elsewhere or open another page.
        public var isValid: Bool {
            !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
                && url.scheme == "https" && url.host() == "docs.google.com"
        }
    }

    public enum Failure: Error, Equatable {
        case unreadable
        case signInNeeded
        case refused(Int)
    }

    // PKCE: the verifier stays on the Mac, Google sees only its hash.
    public static func newVerifier() -> String {
        let bytes = (0..<48).map { _ in UInt8.random(in: 0...255) }
        return base64URL(Data(bytes))
    }

    public static func authorizationURL(client: Client, verifier: String, state: String) -> URL {
        var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        parts.queryItems = [
            .init(name: "client_id", value: client.id),
            .init(name: "redirect_uri", value: client.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        return parts.url!
    }

    // The code from Google's redirect, only when it carries the state this sign-in sent.
    public static func code(from callback: URL, state: String) -> String? {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { return nil }
        return items.first { $0.name == "code" }?.value
    }

    public static func tokenRequest(code: String, verifier: String, client: Client) -> URLRequest {
        form([
            "code": code, "code_verifier": verifier, "client_id": client.id,
            "redirect_uri": client.redirectURI, "grant_type": "authorization_code"
        ])
    }

    // Ends the sign-in at Google too, not only on this Mac.
    public static func revokeRequest(token: String) -> URLRequest {
        var request = form(["token": token])
        request.url = URL(string: "https://oauth2.googleapis.com/revoke")
        return request
    }

    public static func refreshRequest(refreshToken: String, client: Client) -> URLRequest {
        form(["refresh_token": refreshToken, "client_id": client.id, "grant_type": "refresh_token"])
    }

    // A refresh answer has no refresh token; the one already held stays.
    public static func tokens(from data: Data, keeping refreshToken: String? = nil, now: Date) throws -> Tokens {
        struct Answer: Decodable {
            let access_token: String // swiftlint:disable:this identifier_name
            let expires_in: Double // swiftlint:disable:this identifier_name
            let refresh_token: String? // swiftlint:disable:this identifier_name
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw Failure.unreadable }
        return Tokens(
            accessToken: answer.access_token, expiresAt: now.addingTimeInterval(answer.expires_in),
            refreshToken: answer.refresh_token ?? refreshToken
        )
    }

    // A new sheet with the columns the person's sheet already used, and a header row.
    public static func createRequest(token: String) -> URLRequest {
        let header = ApplicationSheet.columns.map { ["userEnteredValue": ["stringValue": $0]] }
        let body: [String: Any] = [
            "properties": ["title": title],
            "sheets": [[
                "properties": ["title": tab, "gridProperties": ["frozenRowCount": 1]],
                "data": [["rowData": [["values": header]]]]
            ]]
        ]
        return json(URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!, token: token, body: body)
    }

    public static func spreadsheet(from data: Data) throws -> Spreadsheet {
        struct Answer: Decodable {
            let spreadsheetId: String
            let spreadsheetUrl: URL
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw Failure.unreadable }
        let spreadsheet = Spreadsheet(id: answer.spreadsheetId, url: answer.spreadsheetUrl)
        guard spreadsheet.isValid else { throw Failure.unreadable }
        return spreadsheet
    }

    // Adds one row per application under the last one.
    public static func appendRequest(
        _ applications: [SubmittedApplication], to sheetID: String, token: String
    ) -> URLRequest {
        var parts = URLComponents(string: "https://sheets.googleapis.com")!
        parts.path = "/v4/spreadsheets/\(sheetID)/values/\(tab)!A1:append"
        parts.queryItems = [
            .init(name: "valueInputOption", value: "RAW"), .init(name: "insertDataOption", value: "INSERT_ROWS")
        ]
        let rows = applications.map { ApplicationSheet.row($0).cells }
        return json(parts.url!, token: token, body: ["values": rows])
    }

    private static func form(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parts = URLComponents()
        parts.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((parts.percentEncodedQuery ?? "").replacing("+", with: "%2B").utf8)
        return request
    }

    private static func json(_ url: URL, token: String, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
    }
}
