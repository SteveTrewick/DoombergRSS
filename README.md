# DoombergRSS

Runtime RSS ingester actor for the Doomberg Terminal system.

This package provides a Swift concurrency-based ingester that accepts validated feed
definitions from an orchestration layer, schedules polls with a central scheduler,
parses RSS/Atom responses, performs per-feed deduplication, and emits `NewsItem` values
through a single `AsyncStream`.

## Features

- Runtime-only ingestion (no feed file loading or validation)
- Central scheduler with configurable polling policy and backoff
- Concurrency cap for in-flight polls
- Optional smooth scheduling mode with spread and launch spacing controls
- Per-feed deduplication with update semantics
- Single non-throwing `AsyncStream<NewsItem>` for downstream consumers
- Linux-compatible networking and XML parsing via conditional imports

## API overview

```swift
import DoombergRSS

let ingester = RSSIngester()
let feed = FeedDefinition(
    id: "bbc-world",
    url: URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!,
    title: "BBC World",
    enabled: true,
    pollIntervalSeconds: nil,
    tags: ["news"],
    priority: 1,
    notes: nil
)

ingester.register(source: feed)
// Or batch:
// ingester.register(sources: [feed])

// Smooth scheduling (optional):
// let ingester = RSSIngester(
//     schedulingMode: .smooth,
//     smoothMinLaunchSpacingSeconds: 2.0,
//     smoothMaxInitialSpreadSeconds: 180
// )
let stream = await ingester.start()

Task {
    for await item in stream {
        print("\(item.title) -> \(item.url)")
    }
}

// Later...
await ingester.stop()
```

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Notes

- The ingester is restartable after `stop()`.
- Runtime errors are logged out of band and never terminate the stream.
- URL normalization and deduplication follow the rules in `spec.md`.

## License

MIT
