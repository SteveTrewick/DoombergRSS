# AGENTS.md – Codex Build Instructions (RSS Ingester Only, v2)


## Objective

Build a **Swift Package** that contains **only** the RSS Ingester runtime actor (library target).

Do **not** implement:
- Feed file loading or validation
- Signal engine
- UI / TUI
- Persistence (SQLite, etc.)

The ingester is a runtime component that accepts validated feed definitions from orchestration.

---

## Source of Truth

Use **`spec.md`** as canonical.

Focus on:
- Data Model
- PollIntervalPolicy
- RSS Ingester public API
- Actor lifecycle and task model
- Fetching, parsing, deduplication
- Testing strategy

---

## Core Responsibilities

The ingester must:
- Accept feeds via `register(source:)`
- Deduplicate registrations by `FeedDefinition.id`
- Start and stop cleanly via explicit lifecycle methods
- Poll feeds concurrently (one task per feed)
- Emit `NewsItem` via a single `AsyncStream`

---

## Behavioral Requirements (Do Not Drift)

- Single public stream: `AsyncStream<NewsItem>` (non-throwing)
- Actor marshals per-feed output into that stream
- `register(source:)`:
  - Duplicate ID → log and ignore
  - New ID:
    - Store
    - If running → start task immediately
- `start()` when already running:
  - Log and return existing stream
- `stop()`:
  - Cancel all tasks
  - Finish stream
  - Leave actor restartable
- Runtime errors are **OOB logged** and never terminate the stream
- Per-feed deduplication only (with update semantics)
- URL normalization must match spec exactly

---

## Platform Requirements

### Linux Compatibility (Required)

- Must compile and test on macOS and Linux

Conditional imports:

```swift
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(FoundationXML)
import FoundationXML
#endif
```

---

## Networking & Testing

- Prefer dependency injection for HTTP:
  - Internal `HTTPClient` protocol
  - URLSession-backed implementation
  - Deterministic stub for tests
- No real network calls in tests

---

## Suggested Package Structure

```
Sources/DoombergRSS/
  Models.swift
  Polling.swift
  RSSIngester.swift
  RSSParser.swift
  URLNormalization.swift
  Dedupe.swift
  Logging.swift

Tests/DoombergRSSTests/
  IngesterAcceptanceTests.swift
  Fixtures/
```

---

## Definition of Done

- `swift build` succeeds
- `swift test` passes on macOS and Linux
- Acceptance test registers feeds via `register(source:)`
- No file I/O inside the ingester
- Spec followed exactly

---

## Runbook

This repo is expected to be a standard **Swift Package Manager** layout (library target + tests).

### Build

```bash
swift build
```

### Test

```bash
swift test
```

This runbook is intentionally minimal and should stay boring.

