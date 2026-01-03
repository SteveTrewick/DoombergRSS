import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DoomModels
import DoomLogs

protocol HTTPClient: Sendable {
    func fetch(url: URL) async throws -> Data
}

final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
    }

    func fetch(url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }
}

public actor RSSIngester {
    private struct PerFeedState: Sendable {
        var dedupe = DedupeTracker()
        var pollCount: Int = 0
    }

    private struct PollOutcome: Sendable {
        let items: [NewsItem]
        let state: PerFeedState
        let success: Bool
    }

    public enum State: Sendable, Equatable {
        case idle
        case running
        case stopping
    }

    public private(set) var state: State = .idle

    private var feeds: [String: FeedDefinition] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var schedulerTask: Task<Void, Never>?
    private var inFlight: Set<String> = []
    private var nextDue: [String: Date] = [:]
    private var failureCount: [String: Int] = [:]
    private var perFeedState: [String: PerFeedState] = [:]
    private let maxConcurrentPolls: Int = 4
    private var stream: AsyncStream<NewsItem>?
    private var streamContinuation: AsyncStream<NewsItem>.Continuation?
    private let pollIntervalPolicy: PollIntervalPolicy
    private let httpClient: HTTPClient
    private let logger: DoomLogger

    public init(pollIntervalPolicy: PollIntervalPolicy = DefaultPollIntervalPolicy()) {
        self.pollIntervalPolicy = pollIntervalPolicy
        self.httpClient = URLSessionHTTPClient()
        self.logger = DoomLogger(subsystem: "DoombergRSS", category: "RSSIngester")
    }

    init(
        pollIntervalPolicy: PollIntervalPolicy,
        httpClient: HTTPClient,
        logger: DoomLogger = DoomLogger(subsystem: "DoombergRSS", category: "RSSIngester")
    ) {
        self.pollIntervalPolicy = pollIntervalPolicy
        self.httpClient = httpClient
        self.logger = logger
    }

    public func register(source: FeedDefinition) {
        if feeds[source.id] != nil {
            logger.info("Duplicate feed registration ignored: \(source.id)")
            return
        }

        feeds[source.id] = source

        if state == .running, source.enabled {
            scheduleInitialDueIfNeeded(for: source)
        }
    }

    public func register(sources: [FeedDefinition]) {
        for source in sources {
            register(source: source)
        }
    }

    public func start() -> AsyncStream<NewsItem> {
        if state == .running, let stream {
            logger.info("RSSIngester already running.")
            return stream
        }

        state = .running
        let newStream = AsyncStream<NewsItem> { continuation in
            self.streamContinuation = continuation
        }
        stream = newStream

        for feed in feeds.values where feed.enabled {
            scheduleInitialDueIfNeeded(for: feed)
        }

        startSchedulerIfNeeded()
        return newStream
    }

    public func stop() async {
        if state == .idle {
            return
        }

        state = .stopping
        schedulerTask?.cancel()
        schedulerTask = nil
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        inFlight.removeAll()
        nextDue.removeAll()
        failureCount.removeAll()
        perFeedState.removeAll()
        streamContinuation?.finish()
        streamContinuation = nil
        stream = nil
        state = .idle
    }

    private func startSchedulerIfNeeded() {
        guard schedulerTask == nil, state == .running else { return }
        schedulerTask = Task { [weak self] in
            guard let self else { return }
            await self.runScheduler()
        }
    }

    private func runScheduler() async {
        logger.info("Scheduler started.")
        while !Task.isCancelled {
            primeSchedulesIfNeeded()

            guard let (feedID, feed, dueAt) = nextScheduledFeed() else {
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    break
                }
                continue
            }

            let now = Date()
            if dueAt > now {
                let delay = dueAt.timeIntervalSince(now)
                let nanos = UInt64(max(0, delay) * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    break
                }
                continue
            }

            if inFlight.count >= maxConcurrentPolls {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    break
                }
                continue
            }

            launchWorker(for: feedID, feed: feed)
        }
        logger.info("Scheduler stopped.")
    }

    private func primeSchedulesIfNeeded() {
        let now = Date()
        let enabledCount = feeds.values.filter { $0.enabled }.count
        for feed in feeds.values where feed.enabled {
            if nextDue[feed.id] == nil {
                let offset = Self.initialOffsetSeconds(feedID: feed.id, enabledCount: enabledCount)
                nextDue[feed.id] = now.addingTimeInterval(TimeInterval(offset))
            }
        }

        let enabledIDs = Set(feeds.values.filter { $0.enabled }.map { $0.id })
        nextDue.keys.filter { !enabledIDs.contains($0) }.forEach { nextDue.removeValue(forKey: $0) }
    }

    private func nextScheduledFeed() -> (String, FeedDefinition, Date)? {
        var chosenID: String?
        var chosenFeed: FeedDefinition?
        var chosenDue = Date.distantFuture

        for (id, feed) in feeds where feed.enabled && !inFlight.contains(id) {
            let due = nextDue[id] ?? Date()
            if due < chosenDue {
                chosenDue = due
                chosenID = id
                chosenFeed = feed
            }
        }

        guard let feedID = chosenID, let feed = chosenFeed else {
            return nil
        }
        return (feedID, feed, chosenDue)
    }

    private func launchWorker(for feedID: String, feed: FeedDefinition) {
        guard tasks[feedID] == nil else { return }
        let state = perFeedState[feedID] ?? PerFeedState()
        inFlight.insert(feedID)

        let task = Task.detached { [feedID, feed, httpClient, logger, state] in
            let outcome = await Self.pollOnce(
                feed: feed,
                httpClient: httpClient,
                logger: logger,
                state: state
            )
            await self.handlePollCompletion(feedID: feedID, feed: feed, outcome: outcome)
        }

        tasks[feedID] = task
    }

    private func handlePollCompletion(feedID: String, feed: FeedDefinition, outcome: PollOutcome) {
        inFlight.remove(feedID)
        tasks.removeValue(forKey: feedID)
        perFeedState[feedID] = outcome.state

        if let continuation = streamContinuation, !outcome.items.isEmpty {
            for item in outcome.items {
                continuation.yield(item)
            }
        }

        guard state == .running else {
            return
        }

        if outcome.success {
            failureCount[feedID] = 0
        } else {
            let current = failureCount[feedID] ?? 0
            failureCount[feedID] = current + 1
        }

        let base = pollIntervalPolicy.pollIntervalSeconds(for: feed)
        let failures = failureCount[feedID] ?? 0
        let factor = Self.backoffFactor(failures: failures)
        let nextInterval = Self.nextIntervalSeconds(base: base, failures: failures, feedID: feed.id)
        nextDue[feedID] = Date().addingTimeInterval(TimeInterval(nextInterval))

        if outcome.success {
            logger.info("Poll complete for \(feed.id). Next in \(nextInterval)s.")
        } else {
            logger.info("Poll failed for \(feed.id). Backoff \(factor)x, next in \(nextInterval)s.")
        }
    }

    private func scheduleInitialDueIfNeeded(for feed: FeedDefinition) {
        guard nextDue[feed.id] == nil else { return }
        let enabledCount = feeds.values.filter { $0.enabled }.count
        let offset = Self.initialOffsetSeconds(feedID: feed.id, enabledCount: enabledCount)
        nextDue[feed.id] = Date().addingTimeInterval(TimeInterval(offset))
    }

    static func initialOffsetSeconds(feedID: String, enabledCount: Int) -> Int {
        guard enabledCount > 1 else { return 0 }
        let hash = stableHash(feedID)
        return Int(hash % 31)
    }

    static func jitterSeconds(feedID: String, base: Int) -> Int {
        guard base > 1 else { return 0 }
        let jitterRange = max(1, min(10, base / 20))
        let hash = stableHash(feedID)
        let raw = Int(hash % UInt64(jitterRange * 2 + 1)) - jitterRange
        return raw
    }

    static func backoffFactor(failures: Int) -> Int {
        min(8, 1 << min(failures, 3))
    }

    static func nextIntervalSeconds(base: Int, failures: Int, feedID: String) -> Int {
        let jitter = jitterSeconds(feedID: feedID, base: base)
        let baseWithJitter = max(1, base + jitter)
        let factor = backoffFactor(failures: failures)
        let maxInterval = max(baseWithJitter, 3600)
        return min(baseWithJitter * factor, maxInterval)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        let prime: UInt64 = 1099511628211
        var hash: UInt64 = 14695981039346656037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return hash
    }

    private static func pollOnce(
        feed: FeedDefinition,
        httpClient: HTTPClient,
        logger: DoomLogger,
        state: PerFeedState
    ) async -> PollOutcome {
        var state = state
        state.pollCount += 1
        let pollCount = state.pollCount
        let parser = RSSParser()

        do {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            logger.info("Polling feed \(feed.id) [\(pollCount)] at \(timestamp)")
            let data = try await httpClient.fetch(url: feed.url)
            let entries = try parser.parse(data: data)
            let ingestedAt = Date()
            var items: [NewsItem] = []

            for entry in entries {
                guard !entry.title.isEmpty else { continue }
                guard let linkValue = entry.link, let url = URL(string: linkValue) else { continue }
                let publishedAt = entry.publishedAt ?? ingestedAt

                if state.dedupe.shouldEmit(url: url, title: entry.title, publishedAt: publishedAt) {
                    let source = feed.title ?? feed.url.host ?? feed.id
                    let item = NewsItem(
                        feedID: feed.id,
                        source: source,
                        title: entry.title,
                        body: entry.body,
                        url: url,
                        publishedAt: publishedAt,
                        ingestedAt: ingestedAt
                    )
                    items.append(item)
                } else {
                    logger.info("Duplicate item ignored for \(feed.id) [\(pollCount)]: \(entry.title)")
                }
            }

            return PollOutcome(items: items, state: state, success: true)
        } catch {
            if error is CancellationError {
                return PollOutcome(items: [], state: state, success: false)
            }
            logger.error("Feed \(feed.id) failed: \(error)")
            return PollOutcome(items: [], state: state, success: false)
        }
    }
}
