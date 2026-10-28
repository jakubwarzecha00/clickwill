import Foundation
import Testing
@testable import ClickwillModel

@Suite("A report from Send Feedback")
struct FeedbackSubmissionTests {

    @Test("only the text, the report, the version and the build are sent - no e-mail and no identifiers")
    func requestBody() throws {
        let submission = FeedbackSubmission(message: "  Cover stays old  \n", report: "iPod classic",
                                            version: "0.1.3.2", build: "6")
        let request = try submission.request(to: URL(string: "https://clickwilldev.com")!)
        #expect(request.url?.absoluteString == "https://clickwilldev.com/api/feedback")
        #expect(request.httpMethod == "POST")
        let data = try #require(request.httpBody)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(body == ["message": "Cover stays old", "report": "iPod classic", "version": "0.1.3.2", "build": "6"])
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("without a report the report field is not sent at all")
    func withoutReport() throws {
        let submission = FeedbackSubmission(message: "Hi", report: nil, version: "0.1.3.2", build: "6")
        let data = try #require(try submission.request(to: URL(string: "http://localhost:8787")!).httpBody)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(body?["report"] == nil)
    }

    @Test("an empty or too long message does not go out")
    func limits() {
        #expect(!FeedbackSubmission(message: " \n ", report: nil, version: "1", build: "1").canSend)
        #expect(!FeedbackSubmission(message: String(repeating: "a", count: 8001), report: nil, version: "1", build: "1").canSend)
        #expect(FeedbackSubmission(message: "ok", report: String(repeating: "r", count: 70000), version: "1", build: "1").report?.count == 64000)
    }

    @Test("server responses")
    func outcomes() {
        #expect(FeedbackSubmission.failure(status: 200) == nil)
        #expect(FeedbackSubmission.failure(status: 413) == .rejected)
        #expect(FeedbackSubmission.failure(status: 429) == .busy)
        #expect(FeedbackSubmission.failure(status: 500) == .server)
    }
}
