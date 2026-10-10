import Foundation

// A CSV for a spreadsheet such as Google Sheets: one row per question, so a sheet can filter
// by question ("graduation") across every application.
public enum ApplicationExport {
    static let header = ["Date", "Company or role", "Site", "Page", "Question", "Answer", "Files"]

    public static func csv(_ applications: [SubmittedApplication]) -> String {
        let rows = applications.flatMap(rows)
        return ([header] + rows).map { $0.map(escaped).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    nonisolated(unsafe) private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func rows(_ application: SubmittedApplication) -> [[String]] {
        let date = day.string(from: application.date)
        let files = application.files.map(\.name).joined(separator: ", ")
        let page = "https://\(application.host)\(application.path)"
        let lead = [date, application.title, application.site, page]
        guard !application.fields.isEmpty else { return [lead + ["", "", files]] }
        return application.fields.map { lead + [$0.question, $0.answer, files] }
    }

    // A cell that starts with = + - or @ would run as a formula in a spreadsheet.
    static func escaped(_ cell: String) -> String {
        let safe = cell.first.map { "=+-@".contains($0) } == true ? "'" + cell : cell
        guard safe.contains(where: { ",\"\r\n".contains($0) }) else { return safe }
        return "\"" + safe.replacing("\"", with: "\"\"") + "\""
    }
}
