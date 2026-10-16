import AppKit
import AuthenticationServices
import Foundation
import PrefillKit
import Security

// The person's Google sign-in for their applications sheet. Google's page opens in a sheet of
// its own; Prefill keeps only the refresh token, in this Mac's Keychain, and asks for nothing
// but the files it creates (drive.file).
@MainActor
final class GoogleAccount: NSObject, ASWebAuthenticationPresentationContextProviding {
    // Prefill's OAuth client in Google Cloud (type iOS, bundle com.tarunyadgirkar.prefill.mac).
    // An installed app's client ID isn't a secret. Empty until it's created.
    static let clientID = ""
    static let client = GoogleSheets.Client(id: clientID)

    private static let service = "com.tarunyadgirkar.prefill.google"
    private var tokens: GoogleSheets.Tokens?
    private var session: ASWebAuthenticationSession?

    static var isSignedIn: Bool { storedRefreshToken() != nil }

    func signIn() async throws {
        guard let client = Self.client else { throw GoogleSheets.Failure.signInNeeded }
        let verifier = GoogleSheets.newVerifier()
        let state = UUID().uuidString
        let url = GoogleSheets.authorizationURL(client: client, verifier: verifier, state: state)
        let callback = try await withCheckedThrowingContinuation { continuation in
            let callback = ASWebAuthenticationSession.Callback.customScheme(client.callbackScheme)
            let session = ASWebAuthenticationSession(url: url, callback: callback) { url, error in
                if let url { continuation.resume(returning: url) } else {
                    continuation.resume(throwing: error ?? GoogleSheets.Failure.signInNeeded)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
        guard let code = GoogleSheets.code(from: callback, state: state) else {
            throw GoogleSheets.Failure.signInNeeded
        }
        let data = try await Self.data(GoogleSheets.tokenRequest(code: code, verifier: verifier, client: client))
        let fresh = try GoogleSheets.tokens(from: data, now: .now)
        guard let refresh = fresh.refreshToken else { throw GoogleSheets.Failure.signInNeeded }
        try Self.storeRefreshToken(refresh)
        tokens = fresh
    }

    // A current access token, refreshed when it's about to run out.
    func accessToken() async throws -> String {
        if let tokens, tokens.isFresh(at: .now) { return tokens.accessToken }
        guard let client = Self.client, let refresh = Self.storedRefreshToken() else {
            throw GoogleSheets.Failure.signInNeeded
        }
        let data = try await Self.data(GoogleSheets.refreshRequest(refreshToken: refresh, client: client))
        let fresh = try GoogleSheets.tokens(from: data, keeping: refresh, now: .now)
        tokens = fresh
        return fresh.accessToken
    }

    // Ends the sign-in at Google, best effort, and forgets the token here.
    func signOut() {
        tokens = nil
        if let refresh = Self.storedRefreshToken() {
            Task.detached { _ = try? await URLSession.shared.data(for: GoogleSheets.revokeRequest(token: refresh)) }
        }
        SecItemDelete(Self.query() as CFDictionary)
    }

    // A call to Google with the current token; a 401 means the cached token was revoked, so
    // it's dropped and the call made once more with a fresh one.
    func send(_ make: (String) -> URLRequest) async throws -> Data {
        do {
            return try await Self.data(make(accessToken()))
        } catch GoogleSheets.Failure.refused(401) {
            tokens = nil
            return try await Self.data(make(accessToken()))
        }
    }

    // Google answers a request it turned away with a 4xx; a 400 or 401 on the token means the
    // sign-in was revoked.
    static func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if request.url?.host() == "oauth2.googleapis.com", [400, 401].contains(status) {
                throw GoogleSheets.Failure.signInNeeded
            }
            throw GoogleSheets.Failure.refused(status)
        }
        return data
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
    }

    // In the data protection keychain, under this app's own access group, so no other app of
    // the same user can read it, and only on this Mac.
    private static func query() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "refresh-token",
            kSecUseDataProtectionKeychain: true
        ]
    }

    private static func storeRefreshToken(_ token: String) throws {
        let value = [kSecValueData: Data(token.utf8)] as CFDictionary
        var status = SecItemUpdate(query() as CFDictionary, value)
        if status == errSecItemNotFound {
            var item = query()
            item[kSecValueData] = Data(token.utf8)
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw GoogleSheets.Failure.signInNeeded }
    }

    private static func storedRefreshToken() -> String? {
        var lookup = query()
        lookup[kSecReturnData] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
