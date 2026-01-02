import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
    public enum State: Sendable, Equatable {
        case idle
        case running
        case stopping
    }

    public private(set) var state: State = .idle

    private var feeds: [String: FeedDefinition] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
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
            startFeedTask(feed: source)
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
            startFeedTask(feed: feed)
        }

        return newStream
    }

    public func stop() async {
        if state == .idle {
            return
        }

        state = .stopping
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        streamContinuation?.finish()
        streamContinuation = nil
        stream = nil
        state = .idle
    }

    private func startFeedTask(feed: FeedDefinition) {
        guard let continuation = streamContinuation else { return }
        let task = Task.detached { [feed, httpClient, pollIntervalPolicy, logger, continuation] in
            await Self.runFeedLoop(
                feed: feed,
                httpClient: httpClient,
                pollIntervalPolicy: pollIntervalPolicy,
                logger: logger,
                emit: { items in
                    for item in items {
                        continuation.yield(item)
                    }
                }
            )
        }
        tasks[feed.id] = task
    }

    private static func runFeedLoop(
        feed: FeedDefinition,
        httpClient: HTTPClient,
        pollIntervalPolicy: PollIntervalPolicy,
        logger: DoomLogger,
        emit: @Sendable ([NewsItem]) async -> Void
    ) async {
        var dedupe = DedupeTracker()
        let parser = RSSParser()

        while !Task.isCancelled {
            do {
                let data = try await httpClient.fetch(url: feed.url)
                let entries = try parser.parse(data: data)
                let ingestedAt = Date()
                var items: [NewsItem] = []

                for entry in entries {
                    guard !entry.title.isEmpty else { continue }
                    guard let linkValue = entry.link, let url = URL(string: linkValue) else { continue }
                    let publishedAt = entry.publishedAt ?? ingestedAt

                    if dedupe.shouldEmit(url: url, title: entry.title, publishedAt: publishedAt) {
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
                    }
                }

                if !items.isEmpty {
                    await emit(items)
                }
            } catch {
                logger.error("Feed \(feed.id) failed: \(error)")
            }

            let interval = pollIntervalPolicy.pollIntervalSeconds(for: feed)
            do {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } catch {
                break
            }
        }
    }
}
