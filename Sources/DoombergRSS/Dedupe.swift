import Foundation

struct DedupeTracker {
    private var latestByKey: [String: Date] = [:]

    mutating func shouldEmit(url: URL?, title: String, publishedAt: Date) -> Bool {
        let key: String
        if let url {
            key = URLNormalizer.normalize(url).absoluteString
        } else {
            key = normalizedTitle(title)
        }

        if let existing = latestByKey[key] {
            if publishedAt > existing {
                latestByKey[key] = publishedAt
                return true
            }
            return false
        }

        latestByKey[key] = publishedAt
        return true
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
