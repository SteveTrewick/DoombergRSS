import Foundation
import XCTest
import DoomModels
@testable import DoombergRSS

final class IngesterAcceptanceTests: XCTestCase {
    func testEmitsNewsItemsFromStubbedFeed() async throws {
        let fixtureData = try loadFixture(named: "bbc_world.xml")
        let feedURL = URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!
        let stubClient = StubHTTPClient(responses: [feedURL: fixtureData])
        let ingester = RSSIngester(
            pollIntervalPolicy: DefaultPollIntervalPolicy(defaultIntervalSeconds: 3600),
            httpClient: stubClient
        )

        let feed = FeedDefinition(id: "bbc-world", url: feedURL, title: "BBC World", enabled: true)
        await ingester.register(source: feed)

        let stream = await ingester.start()
        let item = try await firstNewsItem(from: stream, timeoutSeconds: 2)
        XCTAssertEqual(item.feedID, "bbc-world")
        XCTAssertFalse(item.title.isEmpty)
        XCTAssertEqual(item.url.absoluteString, "https://www.bbc.co.uk/news/world-europe-67812345")
        XCTAssertNotNil(item.publishedAt)
        XCTAssertNotNil(item.ingestedAt)

        await ingester.stop()
    }
}

private func loadFixture(named name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: nil)!
    return try Data(contentsOf: url)
}

private enum TimeoutError: Error {
    case timedOut
}

private func firstNewsItem(
    from stream: AsyncStream<NewsItem>,
    timeoutSeconds: UInt64
) async throws -> NewsItem {
    return try await withThrowingTaskGroup(of: NewsItem.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let value = await iterator.next() else {
                throw TimeoutError.timedOut
            }
            return value
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            throw TimeoutError.timedOut
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct StubHTTPClient: HTTPClient {
    let responses: [URL: Data]

    func fetch(url: URL) async throws -> Data {
        if let data = responses[url] {
            return data
        }
        throw URLError(.badURL)
    }
}
