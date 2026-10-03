import Foundation

// The rows that still fit what's typed in the field, or all of them while it's empty. A
// field that already holds one of them offers nothing. Same rule as `matching` in
// web/src/dropdown.ts.
public enum RowFilter {
    public static let maxRows = 5

    public static func matching(_ rows: [AutofillRow], typed: String) -> [AutofillRow] {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return Array(rows.prefix(maxRows)) }
        if rows.contains(where: { $0.value.lowercased() == text }) { return [] }
        return Array(rows.filter { $0.value.lowercased().contains(text) }.prefix(maxRows))
    }
}
