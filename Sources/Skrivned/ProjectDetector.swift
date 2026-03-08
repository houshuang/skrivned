import Foundation

struct ProjectMapping: Codable {
    var prefix: String
    var project: String
}

struct ProjectDetector {
    private static var cachedMappings: [ProjectMapping]?

    static var projectsFile: URL {
        Config.configDir.appendingPathComponent("projects.json")
    }

    /// Load project mappings from ~/.config/skrivned/projects.json
    static func loadMappings() -> [ProjectMapping] {
        if let cached = cachedMappings { return cached }
        guard let data = try? Data(contentsOf: projectsFile),
              let mappings = try? JSONDecoder().decode([ProjectMapping].self, from: data) else {
            return []
        }
        cachedMappings = mappings
        return mappings
    }

    static func reloadMappings() {
        cachedMappings = nil
    }

    /// Detect the active project by querying iTerm2's current session path
    static func detectProject() -> String? {
        guard let path = queryITermPath() else { return nil }
        return matchProject(path: path)
    }

    /// Query iTerm2 for the current session's working directory
    static func queryITermPath() -> String? {
        // First check if iTerm2 is the frontmost app
        let frontmostScript = """
        tell application "System Events" to get name of first application process whose frontmost is true
        """
        guard let frontApp = runAppleScript(frontmostScript),
              frontApp.contains("iTerm") else {
            return nil
        }

        let pathScript = """
        tell application "iTerm2"
            tell current session of current tab of current window
                get variable named "path"
            end tell
        end tell
        """
        return runAppleScript(pathScript)
    }

    static func matchProject(path: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let relativePath = path.hasPrefix(home) ? String(path.dropFirst(home.count + 1)) : path

        for mapping in loadMappings() {
            if relativePath.hasPrefix(mapping.prefix) {
                return mapping.project
            }
        }
        return nil
    }

    private static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        } catch {
            return nil
        }
    }
}
