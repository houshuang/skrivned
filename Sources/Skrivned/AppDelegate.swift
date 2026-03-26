import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, SonioxTranscriberDelegate {
    var statusBar: StatusBarController!
    var hotkeyManager: HotkeyManager?
    var audioStreamer: AudioStreamer!
    var transcriber: SonioxTranscriber!
    var inserter: TextInserter!
    var textCleaner: TextCleaner?
    var config: Config!
    var vocabulary: VocabularyData!
    var floatingIndicator: FloatingIndicator!

    private var isDictating = false
    private var isReady = false
    private var textAccumulator = ""
    private var activeProject: String?
    private var activeTarget: DictationTarget = .general
    private var insertionCancelled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("App launching")
        statusBar = StatusBarController()
        floatingIndicator = FloatingIndicator()
        floatingIndicator.onClose = { [weak self] in self?.abandonSession() }
        audioStreamer = AudioStreamer()
        inserter = TextInserter()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        config = Config.load()
        vocabulary = VocabularyData.load()
        Log.info("Config loaded: languages=\(config.languageHints)")
        Log.info("Vocabulary loaded: \(vocabulary.global.count) global terms, \(vocabulary.projects.count) projects")

        guard let apiKey = Config.loadApiKey() else {
            Log.error("No Soniox API key found at \(Config.envFile.path)")
            DispatchQueue.main.async {
                self.statusBar.state = .error
            }
            return
        }
        Log.info("API key loaded (\(apiKey.prefix(8))...)")

        transcriber = SonioxTranscriber(apiKey: apiKey, languageHints: config.languageHints)
        transcriber.delegate = self

        audioStreamer.onAudioData = { [weak self] data in
            self?.transcriber.sendAudio(data)
        }

        if let geminiKey = Config.loadGeminiKey() {
            textCleaner = TextCleaner(apiKey: geminiKey)
            Log.info("Gemini key loaded — post-processing enabled")
        } else {
            Log.info("No GEMINI_KEY in .env — will insert raw transcription")
        }

        Permissions.ensureMicrophone()
        audioStreamer.prepare()

        if !AXIsProcessTrusted() {
            Log.info("Accessibility: not granted, waiting...")
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
            while !AXIsProcessTrusted() {
                Thread.sleep(forTimeInterval: 2)
            }
            Log.info("Accessibility: granted")
        } else {
            Log.info("Accessibility: granted")
        }

        DispatchQueue.main.async { [weak self] in
            self?.startListening()
        }
    }

    private func startListening() {
        let manager = HotkeyManager()
        manager.addBinding(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags,
            onKeyDown: { [weak self] in self?.handleHotkeyDown() },
            onKeyUp: { }
        )
        manager.start()
        hotkeyManager = manager

        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()

        let desc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        Log.info("Ready — \(desc) to dictate")
    }

    func reloadConfig() {
        config = Config.load()
        vocabulary = VocabularyData.load()
        ProjectDetector.reloadMappings()
        guard let apiKey = Config.loadApiKey() else {
            Log.error("No Soniox API key")
            return
        }

        finishSession()
        hotkeyManager?.stop()

        transcriber = SonioxTranscriber(apiKey: apiKey, languageHints: config.languageHints)
        transcriber.delegate = self
        audioStreamer.onAudioData = { [weak self] data in
            self?.transcriber.sendAudio(data)
        }

        if let geminiKey = Config.loadGeminiKey() {
            textCleaner = TextCleaner(apiKey: geminiKey)
        }

        startListening()
        Log.info("Config reloaded")
    }

    // MARK: - Hotkey toggle (tap to start, tap to stop)

    private func handleHotkeyDown() {
        guard isReady else { return }

        Log.info("Hotkey DOWN — isDictating=\(isDictating)")

        if isDictating {
            finishSession()
        } else {
            isDictating = true
            startSession()
        }
    }

    // MARK: - Session management

    private var isRecording: Bool {
        isDictating
    }

    private func startSession() {
        // Start audio FIRST — every millisecond of delay loses speech
        do {
            try audioStreamer.start()
            Log.info("Audio streaming started")
        } catch {
            Log.error("Audio error: \(error.localizedDescription)")
            statusBar.state = .error
            return
        }

        textAccumulator = ""
        insertionCancelled = false
        statusBar.state = .listening
        floatingIndicator.show(color: .systemBlue)

        // Project + target detection + WS connect run after audio is already capturing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let target = ProjectDetector.detectDictationTarget()
            self.activeTarget = target

            let project = ProjectDetector.detectProject()
            self.activeProject = project

            if let proj = project {
                Log.info("Detected project: \(proj)")
            }
            Log.info("Dictation target: \(target.rawValue)")

            let terms = self.vocabulary.sonioxTerms(project: self.activeProject)
            Log.info("Session START (\(terms.count) terms)")
            self.transcriber.connect(terms: terms)
        }
    }

    private func finishSession() {
        Log.info("Session STOP — accumulated \(textAccumulator.count) chars")
        audioStreamer.stop()

        floatingIndicator.showProcessing()
        statusBar.state = .cleaning

        transcriber.finalize { [weak self] in
            self?.transcriber.disconnect()

            guard let self = self else { return }
            let rawText = self.textAccumulator
            self.textAccumulator = ""
            self.isDictating = false

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.info("Nothing to insert")
                DispatchQueue.main.async {
                    self.floatingIndicator.hide()
                    self.statusBar.state = .idle
                }
                return
            }

            let allTerms = self.vocabulary.allTerms(project: self.activeProject)
            let project = self.activeProject
            let target = self.activeTarget
            let skipCleaning = target == .aiApp || target == .aiCLI

            if let cleaner = self.textCleaner, !skipCleaning {
                cleaner.clean(text: rawText, vocabulary: allTerms) { [weak self] cleaned in
                    guard let self = self else { return }
                    if self.insertionCancelled {
                        DispatchQueue.main.async {
                            self.floatingIndicator.hide()
                            self.statusBar.state = .idle
                        }
                        return
                    }
                    DictationLog.record(raw: rawText, cleaned: cleaned, project: project, target: target)
                    self.inserter.insert(text: cleaned)
                    DispatchQueue.main.async {
                        self.floatingIndicator.hide()
                        self.statusBar.state = .idle
                        Log.info("Cleaned text inserted, idle")
                    }
                }
            } else {
                if self.insertionCancelled {
                    DispatchQueue.main.async {
                        self.floatingIndicator.hide()
                        self.statusBar.state = .idle
                    }
                    return
                }
                let reason = skipCleaning ? "AI target: \(target.rawValue)" : "no Gemini key"
                DictationLog.record(raw: rawText, cleaned: rawText, project: project, target: target)
                self.inserter.insert(text: rawText)
                DispatchQueue.main.async {
                    self.floatingIndicator.hide()
                    self.statusBar.state = .idle
                    Log.info("Raw text inserted (\(reason)), idle")
                }
            }
        }
    }

    func abandonSession() {
        Log.info("Session ABANDONED — accumulated \(textAccumulator.count) chars")
        audioStreamer.stop()
        transcriber?.disconnect()

        let rawText = textAccumulator
        textAccumulator = ""
        isDictating = false
        insertionCancelled = true

        if !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DictationLog.record(raw: rawText, cleaned: "(abandoned)", project: activeProject, target: activeTarget)
        }

        DispatchQueue.main.async {
            self.floatingIndicator.hide()
            self.statusBar.state = .idle
        }
    }

    // MARK: - SonioxTranscriberDelegate

    func transcriber(_ transcriber: SonioxTranscriber, didProduceFinalText text: String) {
        textAccumulator += text
    }

    func transcriber(_ transcriber: SonioxTranscriber, didUpdatePreview finalText: String, tentative: String) {
        floatingIndicator.updateText(final: finalText, tentative: tentative)
    }

    func transcriber(_ transcriber: SonioxTranscriber, didChangeState connected: Bool) {
        Log.info("Transcriber connected=\(connected)")
    }
}
