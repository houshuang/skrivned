import Foundation

protocol SonioxTranscriberDelegate: AnyObject {
    func transcriber(_ transcriber: SonioxTranscriber, didProduceText text: String)
    func transcriber(_ transcriber: SonioxTranscriber, didChangeState connected: Bool)
}

class SonioxTranscriber {
    weak var delegate: SonioxTranscriberDelegate?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let apiKey: String
    private let languageHints: [String]
    private var isConnected = false
    private var pendingAudioBuffer: [Data] = []
    private var accumulatedFinal = ""
    private var typedLength = 0
    private var contextTerms: [String] = []

    init(apiKey: String, languageHints: [String]) {
        self.apiKey = apiKey
        self.languageHints = languageHints
    }

    func connect(terms: [String] = []) {
        guard webSocketTask == nil else {
            Log.info("WS connect: already has task, skipping")
            return
        }

        contextTerms = terms
        accumulatedFinal = ""
        typedLength = 0
        Log.info("WS connecting to soniox...")
        let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession!.webSocketTask(with: url)
        webSocketTask?.resume()

        sendInitMessage()
        receiveMessage()
    }

    func disconnect() {
        Log.info("WS disconnect (isConnected=\(isConnected), buffer=\(pendingAudioBuffer.count) chunks)")
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        pendingAudioBuffer.removeAll()
        delegate?.transcriber(self, didChangeState: false)
    }

    func sendAudio(_ data: Data) {
        guard isConnected else {
            pendingAudioBuffer.append(data)
            return
        }
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                Log.error("Send audio: \(error.localizedDescription)")
            }
        }
    }

    private func flushPendingAudio() {
        let buffered = pendingAudioBuffer
        pendingAudioBuffer.removeAll()
        Log.info("Flushing \(buffered.count) buffered audio chunks")
        for chunk in buffered {
            webSocketTask?.send(.data(chunk)) { error in
                if let error = error {
                    Log.error("Flush audio: \(error.localizedDescription)")
                }
            }
        }
    }

    func finalize(completion: @escaping () -> Void) {
        Log.info("WS finalize (isConnected=\(isConnected))")
        guard isConnected else {
            completion()
            return
        }

        let msg = "{\"type\":\"finalize\"}"
        webSocketTask?.send(.string(msg)) { error in
            if let error = error {
                Log.error("Finalize send: \(error.localizedDescription)")
            }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            completion()
        }
    }

    private func sendInitMessage() {
        var initMsg: [String: Any] = [
            "api_key": apiKey,
            "model": "stt-rt-preview",
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1,
            "language_hints": languageHints,
        ]

        if !contextTerms.isEmpty {
            initMsg["context"] = ["terms": contextTerms]
            Log.info("WS context: \(contextTerms.count) terms")
        }

        guard let data = try? JSONSerialization.data(withJSONObject: initMsg),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        Log.info("WS sending init message...")
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                Log.error("WS init message: \(error.localizedDescription)")
            } else {
                Log.info("WS connected + init sent OK")
                self?.isConnected = true
                self?.flushPendingAudio()
                DispatchQueue.main.async {
                    self?.delegate?.transcriber(self!, didChangeState: true)
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()

            case .failure(let error):
                Log.error("WS receive: \(error.localizedDescription)")
                self.isConnected = false
                DispatchQueue.main.async {
                    self.delegate?.transcriber(self, didChangeState: false)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.info("WS msg: unparseable: \(text.prefix(200))")
            return
        }

        if json["finished"] as? Bool == true {
            Log.info("WS msg: finished")
            return
        }

        guard let tokens = json["tokens"] as? [[String: Any]] else {
            Log.info("WS msg (no tokens): \(text.prefix(200))")
            return
        }

        var newFinal = ""
        var nonFinal = ""
        for token in tokens {
            guard let tokenText = token["text"] as? String else { continue }
            let cleaned = cleanToken(tokenText)
            if cleaned.isEmpty { continue }

            if token["is_final"] as? Bool == true {
                newFinal += cleaned
            } else {
                nonFinal += cleaned
            }
        }

        // Accumulate final tokens (these never change)
        accumulatedFinal += newFinal

        // Full text = all finals so far + current non-final tail
        let fullText = accumulatedFinal + nonFinal

        // Only type the new characters (delta)
        if fullText.count > typedLength {
            let delta = String(fullText.dropFirst(typedLength))
            typedLength = fullText.count
            Log.info("Typing delta: \"\(delta)\" (total \(typedLength) chars)")
            self.delegate?.transcriber(self, didProduceText: delta)
        }
    }

    private func cleanToken(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<fin>", with: "", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "</fin>", with: "", options: .caseInsensitive)
        if let regex = try? NSRegularExpression(pattern: "<[^>]*>") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result
    }
}
