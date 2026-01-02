# Doomberg Terminal – Technical Specification (v2)


## Status

Living document. This version incorporates an updated public API that cleanly separates **orchestration (feed loading/validation)** from **runtime ingestion**.

---

## System Architecture (High Level)

```
[ Orchestration ] → [ RSS Ingester Actor ] → [ AsyncStream<NewsItem> ] → [ Downstream Consumers ]
```

- Orchestration owns feed discovery, loading, and validation
- RSS Ingester owns runtime polling, parsing, deduplication, and streaming

---

## Language & Platform

- Language: Swift 6
- Delivery: **Swift Package** (SwiftPM library target)
- Platforms: macOS, Linux (CI / cloud)
- Concurrency: Swift Concurrency (async/await, actors)

---

## Data Model

### NewsItem

```swift
struct NewsItem: Identifiable, Codable, Sendable {
    let id: UUID
    let feedID: String
    let source: String
    let title: String
    let body: String?
    let url: URL
    let publishedAt: Date
    let ingestedAt: Date
}
```

### FeedDefinition

```swift
struct FeedDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let url: URL
    var title: String?
    var enabled: Bool
    var pollIntervalSeconds: Int?
    var tags: [String]?
    var priority: Int?
    var notes: String?
}
```

---

## Polling Policy

Polling cadence is intentionally abstracted from feed registration.

```swift
protocol PollIntervalPolicy: Sendable {
    func pollIntervalSeconds(for feed: FeedDefinition) -> Int
}

struct DefaultPollIntervalPolicy: PollIntervalPolicy {
    let defaultIntervalSeconds: Int
    func pollIntervalSeconds(for feed: FeedDefinition) -> Int
}
```

This abstraction allows future semantic layers to dynamically adjust polling frequency.

---

## RSS Ingester – Public API (Locked)

The RSS Ingester is a **runtime actor**. It does not load feeds from disk and does not validate configuration files.

Feed loading and validation are the responsibility of the orchestration layer or test drivers.

```swift
actor RSSIngester {

    enum State: Sendable, Equatable {
        case idle
        case running
        case stopping
    }

    private(set) var state: State = .idle

    /// Register a feed definition with the ingester.
    ///
    /// Semantics:
    /// - If a feed with the same `id` is already registered:
    ///   - Log duplicate (OOB)
    ///   - Do not replace existing feed
    ///   - Return without side effects
    /// - Otherwise:
    ///   - Store feed internally
    ///   - If `state == .running`, immediately start the per-feed task
    func register(source: FeedDefinition)

    /// Start ingestion and return the single public stream (the system heartbeat).
    ///
    /// Semantics:
    /// - If already running:
    ///   - Log (OOB)
    ///   - Return the existing stream
    func start() -> AsyncStream<NewsItem>

    /// Stop ingestion.
    ///
    /// Semantics:
    /// - Cancel all per-feed tasks
    /// - Finish the stream
    /// - Transition to `.idle`
    func stop() async
}
```

### Lifecycle Rules

- Feeds may be registered in `idle` or `running` state
- In `idle`, registration stores feeds only
- In `running`, registration stores feeds and immediately starts tasks
- `stop()` is idempotent and leaves the actor restartable

---

## Task Model

- One task per enabled feed
- Each task:
  - Fetches RSS/Atom via async networking
  - Parses entries defensively
  - Performs per-feed deduplication
  - Emits `NewsItem` to the actor
  - Sleeps until next poll interval

The actor marshals all per-feed output into the single public stream.

---

## Fetching

- Use `URLSession` with async/await
- Dedicated session instance (not `.shared`)
- Start with `URLSessionConfiguration.ephemeral`
- Explicit request timeouts
- Conditional requests (ETag / Last-Modified) are optional

---

## Parsing

- Use Foundation `XMLParser`
- Support RSS 2.0 and Atom
- Required fields:
  - `title`
  - `link`
  - `publishedAt` (`pubDate` / `updated`)
- If `publishedAt` missing or invalid, set to `ingestedAt`
- Parse errors log and skip the current poll only

---

## Deduplication (Per Feed, Locked)

- Deduplication logic lives inside each per-feed task
- No shared dedupe state

### Dedupe Key & Update Semantics

- Primary key: normalized URL
- Fallback key: normalized title (URL missing only)
- Track latest `publishedAt` per key

Rules:
- If same key arrives with **strictly later** `publishedAt`, emit (treat as update)
- Otherwise suppress as duplicate

### URL Normalization (Locked)

Always:
- Parse with `URLComponents`
- Lowercase scheme + host
- Remove fragment
- Remove default ports
- Drop tracking query params
- Sort remaining query params

Never:
- Rewrite http/https
- Remove trailing slash
- Lowercase path
- Follow redirects
- Apply host-specific rules

Tracking params:
- Any param starting with `utm_`
- gclid, gbraid, wbraid
- fbclid
- mc_cid, mc_eid
- igshid
- msclkid
- yclid
- vero_id
- ref, ref_src

---

## Logging

- Runtime errors are logged out-of-band
- Stream never throws due to runtime errors
- Apple platforms: `os.Logger`
- Linux: stdout/stderr with timestamps

---

## Testing Strategy

### Minimal Acceptance Test (Locked)

- Register BBC World feed via `register(source:)`
- Stub RSS XML response
- Call `start()`
- Assert stream emits ≥1 `NewsItem`
- Validate `feedID`, title, URL, and timestamps
- No real network calls

---

## Design Constraints

- Prefer clarity over cleverness
- No global singletons
- Actor is the sole owner of side effects

