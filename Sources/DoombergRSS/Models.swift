import Foundation

public struct NewsItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let feedID: String
    public let source: String
    public let title: String
    public let body: String?
    public let url: URL
    public let publishedAt: Date
    public let ingestedAt: Date

    public init(
        id: UUID = UUID(),
        feedID: String,
        source: String,
        title: String,
        body: String?,
        url: URL,
        publishedAt: Date,
        ingestedAt: Date
    ) {
        self.id = id
        self.feedID = feedID
        self.source = source
        self.title = title
        self.body = body
        self.url = url
        self.publishedAt = publishedAt
        self.ingestedAt = ingestedAt
    }
}

public struct FeedDefinition: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public var title: String?
    public var enabled: Bool
    public var pollIntervalSeconds: Int?
    public var tags: [String]?
    public var priority: Int?
    public var notes: String?

    public init(
        id: String,
        url: URL,
        title: String? = nil,
        enabled: Bool = true,
        pollIntervalSeconds: Int? = nil,
        tags: [String]? = nil,
        priority: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.enabled = enabled
        self.pollIntervalSeconds = pollIntervalSeconds
        self.tags = tags
        self.priority = priority
        self.notes = notes
    }
}
