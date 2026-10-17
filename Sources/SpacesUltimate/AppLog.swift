import Foundation
import os

@MainActor
final class AppLog {
    static let shared = AppLog()

    private let logger = Logger(subsystem: "local.spacesultimate", category: "app")
    private(set) var recentMessages: [String] = []

    private init() {}

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append("INFO \(message)")
    }

    func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        append("WARN \(message)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR \(message)")
    }

    private func append(_ message: String) {
        let stamped = "\(Self.formatter.string(from: Date())) \(message)"
        if ProcessInfo.processInfo.environment["SPACESULTIMATE_STDOUT_LOGS"] == "1" {
            print(stamped)
        }
        recentMessages.append(stamped)
        if recentMessages.count > 200 {
            recentMessages.removeFirst(recentMessages.count - 200)
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
