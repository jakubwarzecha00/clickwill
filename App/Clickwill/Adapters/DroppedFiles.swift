import Foundation

extension NSItemProvider {
    /// File URLs from the dragged items, in drag order.
    /// Items that are not files are skipped.
    static func fileURLs(from providers: [NSItemProvider], isolation: isolated (any Actor)? = #isolation) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url = await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
            }
            if let url, url.isFileURL { urls.append(url) }
        }
        return urls
    }
}
