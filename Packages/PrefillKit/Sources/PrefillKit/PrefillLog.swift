import os

public enum PrefillLog {
    public static let subsystem = "com.tarunyadgirkar.prefill"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
