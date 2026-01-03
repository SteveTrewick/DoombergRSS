import Foundation
import XCTest
import DoomModels
@testable import DoombergRSS

final class SchedulerTests: XCTestCase {
    func testInitialOffsetsSpreadAcrossFeeds() {
        let feedIDs = ["alpha", "beta", "gamma", "delta", "epsilon"]
        let offsets = feedIDs.map {
            RSSIngester.initialOffsetSeconds(
                feedID: $0,
                enabledCount: feedIDs.count,
                base: 300,
                mode: .bursty
            )
        }
        let uniqueOffsets = Set(offsets)
        XCTAssertGreaterThan(uniqueOffsets.count, 1)
    }

    func testSmoothOffsetsStayWithinBaseWindow() {
        let base = 120
        let offset = RSSIngester.initialOffsetSeconds(
            feedID: "smooth-feed",
            enabledCount: 3,
            base: base,
            mode: .smooth,
            smoothMaxInitialSpreadSeconds: 90
        )
        XCTAssertGreaterThanOrEqual(offset, 0)
        XCTAssertLessThan(offset, min(base, 90))
    }

    func testJitterIsDeterministicAndBounded() {
        let base = 300
        let jitter = RSSIngester.jitterSeconds(feedID: "jitter-feed", base: base)
        let jitterRange = max(1, min(10, base / 20))
        XCTAssertGreaterThanOrEqual(jitter, -jitterRange)
        XCTAssertLessThanOrEqual(jitter, jitterRange)

        let jitterRepeat = RSSIngester.jitterSeconds(feedID: "jitter-feed", base: base)
        XCTAssertEqual(jitter, jitterRepeat)
    }

    func testBackoffFactorAndInterval() {
        let base = 10
        let feedID = "backoff-feed"
        let baseWithJitter = max(1, base + RSSIngester.jitterSeconds(feedID: feedID, base: base))

        XCTAssertEqual(RSSIngester.backoffFactor(failures: 0), 1)
        XCTAssertEqual(RSSIngester.backoffFactor(failures: 1), 2)
        XCTAssertEqual(RSSIngester.backoffFactor(failures: 2), 4)
        XCTAssertEqual(RSSIngester.backoffFactor(failures: 3), 8)
        XCTAssertEqual(RSSIngester.backoffFactor(failures: 4), 8)

        let interval = RSSIngester.nextIntervalSeconds(base: base, failures: 2, feedID: feedID)
        XCTAssertEqual(interval, baseWithJitter * 4)
    }

    func testStopFinishesStream() async {
        let ingester = RSSIngester()
        let stream = await ingester.start()
        await ingester.stop()

        var iterator = stream.makeAsyncIterator()
        let item = await iterator.next()
        XCTAssertNil(item)
    }
}
