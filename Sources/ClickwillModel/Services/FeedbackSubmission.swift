import Foundation

/// A report from Send Feedback, sent to the Clickwill server (`POST /api/feedback`).
///
/// Only what the user sees in the sheet is sent: their text, the diagnostic report
/// if they left it checked, and the app version and build. No e-mail,
/// no installation identifier, no cookies. The server does not store the IP address.
public struct FeedbackSubmission: Sendable, Equatable {
    public var message: String
    public var report: String?
    public var version: String
    public var build: String

    /// The same limits as on the server - better to refuse
    /// right away than after sending.
    public static let maxMessage = 8000
    public static let maxReport = 64000

    public init(message: String, report: String?, version: String, build: String) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.report = report.flatMap { $0.isEmpty ? nil : String($0.prefix(Self.maxReport)) }
        self.version = version
        self.build = build
    }

    public var canSend: Bool { !message.isEmpty && message.count <= Self.maxMessage }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case offline
        case rejected
        case busy
        case server

        public var description: String {
            switch self {
            case .offline: "feedback: no connection"
            case .rejected: "feedback: rejected by the server"
            case .busy: "feedback: daily limit reached"
            case .server: "feedback: server error"
            }
        }
    }

    func request(to site: URL) throws -> URLRequest {
        var request = URLRequest(url: site.appendingPathComponent("api/feedback"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Clickwill/\(version)", forHTTPHeaderField: "User-Agent")
        var body: [String: String] = ["message": message, "version": version, "build": build]
        if let report { body["report"] = report }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// Mapping of the server response; `nil` - the report was accepted.
    static func failure(status: Int) -> Failure? {
        switch status {
        case 200..<300: return nil
        case 400, 413: return .rejected
        case 429: return .busy
        default: return .server
        }
    }

    /// Sends the report; `nil` - it arrived. A session without cookies or cache.
    public func send(to site: URL) async -> Failure? {
        guard canSend else { return .rejected }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: try request(to: site))
            return Self.failure(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return .offline
        }
    }
}
