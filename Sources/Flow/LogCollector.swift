import Foundation
import AppKit

/// Persistent log collector for debugging and crash reporting.
///
/// All print() statements in ChatFlow also go through here so we can
/// collect logs when users report issues. Logs rotate daily and are
/// kept for 7 days max.
final class LogCollector {
    static let shared = LogCollector()

    private let logDir: URL
    private let maxLogAgeDays = 7
    private var currentFileHandle: FileHandle?
    private var currentDate = ""
    private let queue = DispatchQueue(label: "ai.flow.logcollector", qos: .utility)

    private init() {
        logDir = Self.logDirectory
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        rotateLogs()
    }

    static var logDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ChatFlow/logs")
    }

    /// Current log file path (today's log).
    var currentLogPath: URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        return logDir.appendingPathComponent("chatflow-\(dateStr).log")
    }

    /// Full bundle path for zip export.
    var allLogs: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "log" }.sorted()
    }

    // MARK: - Writing

    func log(_ message: String) {
        queue.async { [weak self] in
            self?.write(message)
        }
    }

    private func write(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        // Rotate if day changed
        if today != currentDate {
            currentDate = today
            currentFileHandle = try? FileHandle(forWritingTo: currentLogPath)
            if currentFileHandle == nil {
                try? Data().write(to: currentLogPath)
                currentFileHandle = try? FileHandle(forWritingTo: currentLogPath)
            }
            currentFileHandle?.seekToEndOfFile()
        }

        let timestamp = DateFormatter.localizedString(by: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            currentFileHandle?.write(data)
        }
    }

    // MARK: - Rotation

    private func rotateLogs() {
        queue.async { [weak self] in
            guard let self else { return }
            let cutoff = Calendar.current.date(byAdding: .day, value: -self.maxLogAgeDays, to: Date())!
            for file in self.allLogs {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    // MARK: - Export

    /// Export all logs as a single text string for sharing.
    func exportLogs() -> String {
        var combined = ""
        combined += "ChatFlow Log Export\n"
        combined += "Date: \(Date())\n"
        combined += "App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")\n"
        combined += "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        combined += "═══════════════════════════════════\n\n"

        for file in allLogs {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                combined += "── \(file.lastPathComponent) ──\n"
                combined += content
                combined += "\n"
            }
        }

        return combined
    }

    /// Copy log file to a temporary file for sharing (e.g. drag to email).
    func exportToFile() -> URL? {
        let content = exportLogs()
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "chatflow-logs-\(Int(Date().timeIntervalSince1970)).txt"
        let url = tempDir.appendingPathComponent(fileName)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("⚠️ Failed to export logs: \(error)")
            return nil
        }
    }
}

// MARK: - Global log function

/// Drop-in replacement for print() that also writes to the log file.
/// Usage: log("message") instead of print("message")
func log(_ message: String) {
    print(message)
    LogCollector.shared.log(message)
}
