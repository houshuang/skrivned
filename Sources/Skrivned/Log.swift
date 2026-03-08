import Foundation

enum Log {
    private static let logFile: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/skrivned/skrivned.log")
        // Truncate on launch
        try? "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func error(_ message: String) {
        write("ERR ", message)
    }

    private static func write(_ level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)\n"
        print(line, terminator: "")
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
}
