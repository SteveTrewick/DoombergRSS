import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct ParsedEntry: Sendable {
    let title: String
    let link: String?
    let body: String?
    let publishedAt: Date?
}

enum RSSParserError: Error {
    case invalidXML
}

struct RSSParser {
    func parse(data: Data) throws -> [ParsedEntry] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        if !parser.parse() {
            throw RSSParserError.invalidXML
        }
        return delegate.entries
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    private struct WorkingEntry {
        var title: String = ""
        var link: String?
        var body: String?
        var publishedAt: Date?
    }

    private enum FeedKind {
        case rss
        case atom
    }

    private var kind: FeedKind?
    private var currentEntry: WorkingEntry?
    private var currentElement: String = ""
    private var currentText: String = ""

    private let rssDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private let isoFormatter = ISO8601DateFormatter()

    fileprivate var entries: [ParsedEntry] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()
        currentText = ""

        if elementName == "item" {
            kind = .rss
            currentEntry = WorkingEntry()
        } else if elementName == "entry" {
            kind = .atom
            currentEntry = WorkingEntry()
        }

        if elementName == "link", let href = attributeDict["href"] {
            if kind == .atom {
                currentEntry?.link = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let currentEntry {
            switch elementName.lowercased() {
            case "title":
                self.currentEntry?.title = trimmed
            case "link":
                if kind == .rss {
                    self.currentEntry?.link = trimmed
                }
            case "description", "content", "summary":
                if !trimmed.isEmpty {
                    self.currentEntry?.body = trimmed
                }
            case "pubdate":
                self.currentEntry?.publishedAt = parseRSSDate(trimmed)
            case "updated":
                self.currentEntry?.publishedAt = parseISODate(trimmed)
            case "item", "entry":
                let entry = ParsedEntry(
                    title: currentEntry.title,
                    link: currentEntry.link,
                    body: currentEntry.body,
                    publishedAt: currentEntry.publishedAt
                )
                entries.append(entry)
                self.currentEntry = nil
            default:
                break
            }
        }

        currentElement = ""
        currentText = ""
    }

    private func parseRSSDate(_ value: String) -> Date? {
        if let date = rssDateFormatter.date(from: value) {
            return date
        }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "EEE, dd MMM yyyy HH:mm Z"
        return fallback.date(from: value)
    }

    private func parseISODate(_ value: String) -> Date? {
        isoFormatter.date(from: value)
    }
}
