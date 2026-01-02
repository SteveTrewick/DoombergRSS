import Foundation

public protocol PollIntervalPolicy: Sendable {
    func pollIntervalSeconds(for feed: FeedDefinition) -> Int
}

public struct DefaultPollIntervalPolicy: PollIntervalPolicy {
    public let defaultIntervalSeconds: Int

    public init(defaultIntervalSeconds: Int = 300) {
        self.defaultIntervalSeconds = defaultIntervalSeconds
    }

    public func pollIntervalSeconds(for feed: FeedDefinition) -> Int {
        let candidate = feed.pollIntervalSeconds ?? defaultIntervalSeconds
        return max(candidate, 1)
    }
}
