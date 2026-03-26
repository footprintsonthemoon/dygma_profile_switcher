import Foundation
import Combine

/// Structured file logger with an in-memory ring buffer for the Settings UI.
/// Log directory is resolved at runtime via FileManager — no hardcoded paths.
final class AppLogger: ObservableObject {

    static let shared = AppLogger()

    @Published private(set) var recentLines: [String] = []

    private let maxBufferLines = 200
    private var fileHandle: FileHandle?
    private var currentLevel: LogLevel = .info
    private let queue = DispatchQueue(label: "com.dygmacontext.logger", qos: .utility)

    // MARK: - Log Directory (runtime-resolved)

    var logDirectoryURL: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return lib.appendingPathComponent("Logs/DygmaContext", isDirectory: true)
    }

    var logFileURL: URL {
        logDirectoryURL.appendingPathComponent("dygma-context.log")
    }

    // MARK: - Setup

    func configure(level: LogLevel) {
        currentLevel = level
        queue.async { self.openLogFile() }
    }

    private func openLogFile() {
        let dir = logDirectoryURL
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
    }

    // MARK: - Logging

    func log(_ message: String, level: LogLevel = .info) {
        guard shouldLog(level) else { return }
        let line = formatLine(message, level: level)
        queue.async {
            self.writeLine(line)
            DispatchQueue.main.async {
                self.recentLines.append(line)
                if self.recentLines.count > self.maxBufferLines {
                    self.recentLines.removeFirst(self.recentLines.count - self.maxBufferLines)
                }
            }
        }
    }

    private func shouldLog(_ level: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warning, .error]
        guard let currentIdx = order.firstIndex(of: currentLevel),
              let messageIdx = order.firstIndex(of: level) else { return true }
        return messageIdx >= currentIdx
    }

    private func formatLine(_ message: String, level: LogLevel) -> String {
        let ts = ISO8601DateFormatter().string(from: Date())
        return "[\(ts)] [\(level.rawValue.uppercased())] \(message)"
    }

    private func writeLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        fileHandle?.write(data)
    }

    // MARK: - Export

    /// Writes the current in-memory buffer to a temp file and returns its URL.
    func export() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dygma-context-export-\(Date().timeIntervalSince1970).log")
        let content = recentLines.joined(separator: "\n")
        try? content.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }
}
