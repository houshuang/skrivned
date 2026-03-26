import Foundation

struct DictationEntry: Codable {
    let timestamp: String
    let raw: String
    let cleaned: String
    let project: String?
    let target: String?
}

enum DictationLog {
    private static let logFile: URL = {
        Config.configDir.appendingPathComponent("dictation_log.jsonl")
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func record(raw: String, cleaned: String, project: String?, target: DictationTarget? = nil) {
        var entry: [String: Any] = [
            "timestamp": isoFormatter.string(from: Date()),
            "raw": raw,
            "cleaned": cleaned,
        ]
        if let project = project {
            entry["project"] = project
        }
        if let target = target {
            entry["target"] = target.rawValue
        }

        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              var line = String(data: data, encoding: .utf8) else {
            Log.error("DictationLog: failed to serialize entry")
            return
        }
        line += "\n"

        if let lineData = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(lineData)
                    handle.closeFile()
                }
            } else {
                try? lineData.write(to: logFile)
            }
        }
        Log.info("DictationLog: recorded entry (\(raw.count) raw → \(cleaned.count) cleaned)")
    }

    static func lastEntry() -> DictationEntry? {
        guard let data = try? Data(contentsOf: logFile),
              let content = String(data: data, encoding: .utf8) else { return nil }
        let lines = content.split(separator: "\n").filter { !$0.isEmpty }
        guard let lastLine = lines.last,
              let lineData = lastLine.data(using: .utf8),
              let entry = try? JSONDecoder().decode(DictationEntry.self, from: lineData) else { return nil }
        return entry
    }
}
