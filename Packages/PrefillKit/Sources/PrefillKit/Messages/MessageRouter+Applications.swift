import Foundation

// A job application the person sent. It waits in the events until the app moves it into its
// archive; nothing reaches the card or Prefill's contact.
extension MessageRouter {
    static let maxApplicationsPerWindow = 10
    static let applicationWindow: TimeInterval = 60

    func application(_ request: ApplicationRequest) -> ApplicationResponse {
        Self.eventLock.withLock { _ in
            let date = now()
            let recent = events().applications.count { date.timeIntervalSince($0.date) < Self.applicationWindow }
            guard !request.fields.isEmpty || !request.files.isEmpty, recent < Self.maxApplicationsPerWindow else {
                return ApplicationResponse(saved: false)
            }
            let saved = append(ExtensionEvents(applications: [SubmittedApplication(date: date, request: request)]))
            return ApplicationResponse(saved: saved)
        }
    }
}
