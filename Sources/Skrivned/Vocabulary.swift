import Foundation

struct VocabularyData: Codable {
    var global: [String]
    var projects: [String: [String]]

    static let defaultData = VocabularyData(global: [], projects: [:])

    static var vocabFile: URL {
        Config.configDir.appendingPathComponent("vocabulary.json")
    }

    static func load() -> VocabularyData {
        guard let data = try? Data(contentsOf: vocabFile) else {
            return defaultData
        }
        do {
            return try JSONDecoder().decode(VocabularyData.self, from: data)
        } catch {
            Log.error("Failed to parse vocabulary: \(error.localizedDescription)")
            return defaultData
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: VocabularyData.vocabFile)
    }

    /// Terms for Soniox context.terms — project-specific + global, capped at ~10K chars
    func sonioxTerms(project: String?) -> [String] {
        var terms = global
        if let project = project, let projectTerms = projects[project] {
            terms = projectTerms + terms
        }
        // Soniox limit: ~10,000 characters total for context
        var totalChars = 0
        var result: [String] = []
        for term in terms {
            totalChars += term.count + 4 // account for JSON overhead
            if totalChars > 9000 { break }
            result.append(term)
        }
        return result
    }

    /// All terms for LLM cleanup prompt — no size limit
    func allTerms(project: String?) -> [String] {
        var terms = global
        if let project = project, let projectTerms = projects[project] {
            terms = projectTerms + terms
        }
        return Array(Set(terms)).sorted()
    }
}
