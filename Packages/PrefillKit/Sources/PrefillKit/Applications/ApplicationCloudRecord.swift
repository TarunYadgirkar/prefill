import Foundation

// How one sent application is stored in the person's private iCloud database: one record per
// application, named by its id, its JSON in one encrypted field. Only the iPhone app and the
// Mac app talk to CloudKit (AppCloud/); this side stays free of it, so the keyboard links no
// network code.
public enum ApplicationCloudRecord {
    public static let zoneName = "Applications"
    public static let recordType = "Application"
    public static let payloadKey = "payload"
    // Under CloudKit's 1 MB record limit, with room for the record's own fields.
    public static let maxPayloadBytes = 900_000

    public static func recordName(_ id: UUID) -> String {
        id.uuidString
    }

    public static func payload(_ application: SubmittedApplication) -> Data? {
        guard let data = try? DocumentCoder.encode(application), data.count <= maxPayloadBytes else { return nil }
        return data
    }

    // A record another device wrote is held to the limits of the sends it combines, and must
    // carry the id it's named by.
    public static func application(recordName: String, payload: Data) -> SubmittedApplication? {
        guard payload.count <= maxPayloadBytes,
              let application = try? DocumentCoder.decode(SubmittedApplication.self, from: payload),
              recordName == Self.recordName(application.id), application.isValidRecord
        else { return nil }
        return application
    }
}
