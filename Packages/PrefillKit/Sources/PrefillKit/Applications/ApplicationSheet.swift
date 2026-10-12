import Foundation

// The person's "Job Applications" Google Sheet: one row per application, newest at the top,
// in the columns the sheet already uses. Rows go to an Apps Script web app deployed from the
// sheet (scripts/sheet/Code.gs), which skips an application the sheet already lists. Only the
// apps send them; PrefillKit only builds the request and reads the answer, so the keyboard,
// which links PrefillKit, still has no network code.
public enum ApplicationSheet {
    static let columns = ["Date applied", "Company", "Role", "Type", "Status", "Last update", "Found in", "Email"]

    public struct Row: Codable, Sendable, Hashable {
        public let id: UUID
        public let cells: [String]
    }

    private struct Upload: Encodable {
        let rows: [Row]
    }

    private struct Reply: Decodable {
        let added: [UUID]?
        let skipped: [UUID]?
        let error: String?
    }

    public enum Failure: Error, Equatable {
        case refused(String)
        case unreadable
    }

    // The web app's address as Apps Script gives it on deploy, and nothing else, so a pasted
    // link can only ever reach a script.
    public static func address(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host() == "script.google.com", url.query() == nil,
              url.path().hasPrefix("/macros/s/"), url.path().hasSuffix("/exec")
        else { return nil }
        return url
    }

    // Apps Script answers a POST with a redirect to the reply, which URLSession follows as a GET.
    public static func request(_ applications: [SubmittedApplication], to address: URL) -> URLRequest {
        var request = URLRequest(url: address, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Upload(rows: applications.map(row)))
        return request
    }

    // Sends what's waiting and returns the applications the sheet now lists. The app passes the
    // network call in.
    public static func send(
        _ applications: [SubmittedApplication], with settings: SheetSettings,
        transport: @Sendable (URLRequest) async throws -> Data
    ) async throws -> Set<UUID> {
        let waiting = settings.waiting(applications)
        guard settings.isOn, let address = settings.address, !waiting.isEmpty else { return [] }
        return try listed(await transport(request(waiting, to: address)))
    }

    // The applications the sheet now lists: added, or already there.
    public static func listed(_ data: Data) throws -> Set<UUID> {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw Failure.unreadable }
        if let error = reply.error { throw Failure.refused(error) }
        return Set((reply.added ?? []) + (reply.skipped ?? []))
    }

    nonisolated(unsafe) private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func row(_ application: SubmittedApplication) -> Row {
        let date = day.string(from: application.date)
        let (company, role) = companyAndRole(application)
        let found = "Prefill: https://\(application.host)\(application.path)"
        return Row(id: application.id, cells: [date, company, role, kind(role), "Applied", date, found, ""])
    }

    static func kind(_ role: String) -> String {
        let words = role.lowercased()
        if words.contains(/\b(intern|internship|co-?op)\b/) { return "Internship" }
        if words.contains(/\b(hackathon|fellowship|program)\b/) { return "Program" }
        return "Job"
    }

    // Job boards title a page "Role @ Company" (Ashby), "Job Application for Role at Company"
    // (Greenhouse) or "Company - Role" (Lever). Otherwise the title is the role and the company
    // comes from the board's address.
    static func companyAndRole(_ application: SubmittedApplication) -> (String, String) {
        if application.site == "icims.com" {
            return (company(host: application.host, path: application.path), icimsRole(application))
        }
        let title = application.title.replacing(#/^Job Application for /#, with: "")
        for separator in [" @ ", " at "] {
            if let range = title.ranges(of: separator).last {
                return (String(title[range.upperBound...]), String(title[..<range.lowerBound]))
            }
        }
        if application.site == "lever.co", let range = title.firstRange(of: " - ") {
            return (String(title[..<range.lowerBound]), String(title[range.upperBound...]))
        }
        return (company(host: application.host, path: application.path), title)
    }

    private static let boardsByPath: Set<String> = ["greenhouse.io", "lever.co", "ashbyhq.com", "workable.com"]
    // iCIMS hosts read like us-careers-rivian.icims.com or careers-acme.icims.com.
    private static let icimsHostWords: Set<String> = ["us", "uk", "ca", "eu", "careers", "career", "jobs", "external"]

    // iCIMS titles a page "Role in City, State | Careers at Location", and every page of one
    // application sits under /jobs/<id>/<role-slug>/. The title's role is kept when it matches
    // the slug, else the slug is spelled out.
    static func icimsRole(_ application: SubmittedApplication) -> String {
        let segments = application.path.split(separator: "/")
        guard segments.count > 2, segments[0] == "jobs",
              let slug = String(segments[2]).removingPercentEncoding, !slug.isEmpty else { return application.title }
        let heading = String(application.title.split(separator: " | ").first ?? "")
            .replacing(#/ in [^|]*$/#, with: "")
        let letters = { (text: String) in text.lowercased().filter { $0.isLetter || $0.isNumber } }
        if letters(heading) == letters(slug) { return heading }
        let words = slug.replacing("---", with: " - ").replacing("-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func company(host: String, path: String) -> String {
        let site = Normalizer.registrableDomain(host)
        let slug: String? = if boardsByPath.contains(site) {
            path.split(separator: "/").first.map(String.init)
        } else if site == "myworkdayjobs.com" {
            host.split(separator: ".").first.map(String.init)
        } else if site == "icims.com" {
            host.split(separator: ".").first.map { label in
                label.split(separator: "-").filter { !icimsHostWords.contains(String($0)) }.joined(separator: "-")
            }
        } else {
            site.split(separator: ".").first.map(String.init)
        }
        return (slug ?? host).split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// Whether the apps send applications to the sheet, where, and which ones it already lists.
// It sits next to the archive in the app's own folder, never the store the keyboard reads, and
// "Delete Prefill data" removes it.
public struct SheetSettings: Codable, Sendable, Equatable {
    public var address: URL?
    public var isOn = false
    public var listed: Set<UUID> = []
    public var lastSent: Date?

    public init() {}

    public func waiting(_ applications: [SubmittedApplication]) -> [SubmittedApplication] {
        applications.filter { !listed.contains($0.id) }
    }
}

public struct SheetSettingsFile: Sendable {
    public static let fileName = "google-sheet.json"

    public let url: URL

    public init(directory: URL) {
        url = directory.appending(path: Self.fileName)
    }

    public static func live() -> SheetSettingsFile {
        SheetSettingsFile(directory: URL.applicationSupportDirectory.appending(path: "Prefill"))
    }

    public func read() -> SheetSettings {
        guard let data = try? Data(contentsOf: url) else { return SheetSettings() }
        return (try? DocumentCoder.decode(SheetSettings.self, from: data)) ?? SheetSettings()
    }

    public func write(_ settings: SheetSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DocumentCoder.encode(settings).write(to: url, options: Self.writeOptions)
    }

    public func removeAll() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    #if os(iOS)
    private static let writeOptions: Data.WritingOptions = [
        .atomic, .completeFileProtectionUntilFirstUserAuthentication
    ]
    #else
    private static let writeOptions: Data.WritingOptions = [.atomic]
    #endif
}
