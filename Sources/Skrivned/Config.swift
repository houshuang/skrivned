import Foundation

struct Config: Codable {
    var hotkey: HotkeyConfig
    var languageHints: [String]

    static let defaultConfig = Config(
        hotkey: HotkeyConfig(keyCode: 61, modifiers: []),     // Right Option
        languageHints: ["en"]
    )

    static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/skrivned")
    }

    static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    static var envFile: URL {
        configDir.appendingPathComponent(".env")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile) else {
            let config = Config.defaultConfig
            try? config.save()
            return config
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            fputs("Warning: unable to parse \(configFile.path): \(error.localizedDescription)\n", stderr)
            return Config.defaultConfig
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: Config.configFile)
    }

    static func loadApiKey() -> String? {
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SONIOX_KEY=") {
                let value = String(trimmed.dropFirst("SONIOX_KEY=".count))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    static func loadGeminiKey() -> String? {
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("GEMINI_KEY=") {
                let value = String(trimmed.dropFirst("GEMINI_KEY=".count))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}

struct HotkeyConfig: Codable {
    var keyCode: UInt16
    var modifiers: [String]

    var modifierFlags: UInt64 {
        var flags: UInt64 = 0
        for mod in modifiers {
            switch mod.lowercased() {
            case "cmd", "command": flags |= UInt64(1 << 20)
            case "shift": flags |= UInt64(1 << 17)
            case "ctrl", "control": flags |= UInt64(1 << 18)
            case "opt", "option", "alt": flags |= UInt64(1 << 19)
            default: break
            }
        }
        return flags
    }
}
