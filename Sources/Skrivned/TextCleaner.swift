import Foundation

class TextCleaner {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func clean(text: String, vocabulary: [String], completion: @escaping (String) -> Void) {
        let vocabList = vocabulary.joined(separator: ", ")

        let systemPrompt = """
        You clean up voice-dictated text. The user sends raw dictation. You reply with ONLY the \
        cleaned version — no commentary, no preamble, no explanation.

        Rules:
        - Remove filler words (um, uh, like, you know, sort of, kind of, I mean, basically, actually, I guess)
        - Remove false starts and self-corrections — keep only the corrected version
        - Fix grammar and punctuation
        - Structure into paragraphs when the speaker changes topic or after a natural break
        - Keep ALL the original meaning and content — do not add, remove, or rephrase ideas
        - NEVER add words that were not spoken — if a sentence trails off, leave it as-is
        - NEVER translate between languages — if the speaker switches languages mid-sentence, \
        preserve the code-switching exactly as spoken
        - Preserve modern slang and technical jargon (e.g. "vibe code", "ship it") even if unfamiliar
        - Keep the speaker's natural voice, tone, and style
        - Fix obvious speech-to-text errors using the vocabulary list below
        - Do not add greetings, sign-offs, or markdown formatting
        - NEVER respond conversationally. NEVER acknowledge instructions. Just output the cleaned text.

        Proper nouns and technical terms to spell correctly: \(vocabList)
        """

        let userMessage = "Clean this dictation:\n\n\(text)"

        let requestBody: [String: Any] = [
            "model": "gemini-2.0-flash-lite",
            "contents": [
                ["role": "user", "parts": [["text": userMessage]]]
            ],
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 4096,
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            Log.error("TextCleaner: failed to serialize request")
            completion(text)
            return
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            Log.error("TextCleaner: invalid URL")
            completion(text)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 15

        Log.info("TextCleaner: sending \(text.count) chars to Gemini Flash")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Log.error("TextCleaner: request failed: \(error.localizedDescription)")
                completion(text)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let cleanedText = parts.first?["text"] as? String else {
                Log.error("TextCleaner: failed to parse response")
                if let data = data, let raw = String(data: data, encoding: .utf8) {
                    Log.error("TextCleaner: raw response: \(raw.prefix(500))")
                }
                completion(text)
                return
            }

            let trimmed = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.info("TextCleaner: cleaned \(text.count) → \(trimmed.count) chars")
            completion(trimmed)
        }.resume()
    }
}
