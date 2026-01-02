#if canImport(os)
import os
#endif
import Foundation

enum Logger {
#if canImport(os)
    private static let logger = os.Logger(subsystem: "DoombergRSS", category: "RSSIngester")
#endif

    static func info(_ message: String) {
        log(level: "INFO", message: message)
    }

    static func error(_ message: String) {
        log(level: "ERROR", message: message)
    }

    private static func log(level: String, message: String) {
#if canImport(os)
        logger.log("\(level, privacy: .public): \(message, privacy: .public)")
#else
        let timestamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write(Data("[\(timestamp)] \(level): \(message)\n".utf8))
#endif
    }
}
