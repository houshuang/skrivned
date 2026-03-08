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

    private var isHolding = false
    private var isToggled = false
    private var isCleanMode = false
    private var isReady = false
    private var lastHoldKeyUpTime: Date?
    private var holdReleaseTimer: Timer?
    private var cleanAccumulator = ""
    private var activeProject: String?
    private let doubleTapInterval: TimeInterval = 0.3

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("App launching")
        statusBar = StatusBarController()
        floatingIndicator = FloatingIndicator()
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
            Log.info("Gemini key loaded — clean mode available")
        } else {
            Log.info("No GEMINI_KEY in .env — clean mode disabled")
        }

        Permissions.ensureMicrophone()

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
            keyCode: config.holdHotkey.keyCode,
            modifiers: config.holdHotkey.modifierFlags,
            onKeyDown: { [weak self] in self?.handleHoldDown() },
            onKeyUp: { [weak self] in self?.handleHoldUp() }
        )
        manager.addBinding(
            keyCode: config.cleanHotkey.keyCode,
            modifiers: config.cleanHotkey.modifierFlags,
            onKeyDown: { [weak self] in self?.handleCleanDown() },
            onKeyUp: { [weak self] in self?.handleCleanUp() }
        )
        manager.start()
        hotkeyManager = manager

        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()

        let holdDesc = KeyCodes.describe(keyCode: config.holdHotkey.keyCode, modifiers: config.holdHotkey.modifiers)
        let cleanDesc = KeyCodes.describe(keyCode: config.cleanHotkey.keyCode, modifiers: config.cleanHotkey.modifiers)
        Log.info("Ready — hold \(holdDesc) to dictate, \(cleanDesc) for clean mode")
    }

    func reloadConfig() {
        config = Config.load()
        vocabulary = VocabularyData.load()
        ProjectDetector.reloadMappings()
        guard let apiKey = Config.loadApiKey() else {
            Log.error("No Soniox API key")
            return
        }

        stopSession()
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

    // MARK: - Hold with double-tap toggle (normal dictation)

    private func handleHoldDown() {
        guard isReady, !isCleanMode else { return }

        holdReleaseTimer?.invalidate()
        holdReleaseTimer = nil

        let isDoubleTap: Bool
        if let lastUp = lastHoldKeyUpTime, Date().timeIntervalSince(lastUp) < doubleTapInterval {
            isDoubleTap = true
        } else {
            isDoubleTap = false
        }

        Log.info("Hold DOWN — doubleTap=\(isDoubleTap) isHolding=\(isHolding) isToggled=\(isToggled)")

        if isToggled {
            isToggled = false
            floatingIndicator.hide()
            stopSession()
        } else if isDoubleTap {
            isHolding = false
            isToggled = true
            floatingIndicator.show()
        } else {
            isHolding = true
            startSession(clean: false)
        }
    }

    private func handleHoldUp() {
        lastHoldKeyUpTime = Date()
        Log.info("Hold UP — isHolding=\(isHolding) isToggled=\(isToggled)")

        if isHolding {
            isHolding = false
            holdReleaseTimer = Timer.scheduledTimer(withTimeInterval: doubleTapInterval, repeats: false) { [weak self] _ in
                self?.holdReleaseTimer = nil
                self?.stopSession()
            }
        }
    }

    // MARK: - Clean mode (toggle: tap on, tap off)

    private func handleCleanDown() {
        guard isReady, !isHolding else { return }

        // If normal toggle is active, ignore clean key
        if isToggled && !isCleanMode { return }

        guard textCleaner != nil else {
            Log.error("Clean mode: no GEMINI_KEY configured")
            return
        }

        Log.info("Clean DOWN — isCleanMode=\(isCleanMode)")

        if isCleanMode {
            // Second tap: stop recording and clean
            // Keep isCleanMode=true until finalization completes so late tokens accumulate
            stopCleanSession()
        } else {
            // First tap: start recording
            isCleanMode = true
            floatingIndicator.show(color: .systemBlue)
            startSession(clean: true)
        }
    }

    private func handleCleanUp() {
        // Nothing to do on key up for toggle mode
    }

    // MARK: - Session management

    private func startSession(clean: Bool) {
        // Detect project from iTerm2
        activeProject = ProjectDetector.detectProject()
        if let proj = activeProject {
            Log.info("Detected project: \(proj)")
        }

        let terms = vocabulary.sonioxTerms(project: activeProject)

        if clean {
            isCleanMode = true
            cleanAccumulator = ""
            Log.info("Session START (clean mode, \(terms.count) terms)")
            statusBar.state = .cleanListening
        } else {
            Log.info("Session START (\(terms.count) terms)")
            statusBar.state = .listening
        }

        transcriber.connect(terms: terms)
        do {
            try audioStreamer.start()
            Log.info("Audio streaming started")
        } catch {
            Log.error("Audio error: \(error.localizedDescription)")
            statusBar.state = .error
            transcriber.disconnect()
            isCleanMode = false
        }
    }

    private func stopSession() {
        Log.info("Session STOP")
        audioStreamer.stop()
        transcriber.finalize { [weak self] in
            self?.transcriber.disconnect()
            DispatchQueue.main.async {
                self?.statusBar.state = .idle
                Log.info("Session ended, idle")
            }
        }
    }

    private func stopCleanSession() {
        Log.info("Clean session STOP — accumulated \(cleanAccumulator.count) chars")
        audioStreamer.stop()

        // Switch indicator to yellow while LLM processes
        DispatchQueue.main.async {
            self.floatingIndicator.changeColor(.systemYellow)
            self.statusBar.state = .cleaning
        }

        transcriber.finalize { [weak self] in
            self?.transcriber.disconnect()

            guard let self = self else { return }
            let text = self.cleanAccumulator
            self.isCleanMode = false

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.info("Clean mode: nothing to clean")
                DispatchQueue.main.async {
                    self.floatingIndicator.hide()
                    self.statusBar.state = .idle
                }
                return
            }

            let allTerms = self.vocabulary.allTerms(project: self.activeProject)
            self.textCleaner?.clean(text: text, vocabulary: allTerms) { [weak self] cleaned in
                self?.inserter.insert(text: cleaned)
                DispatchQueue.main.async {
                    self?.floatingIndicator.hide()
                    self?.statusBar.state = .idle
                    Log.info("Clean text inserted, idle")
                }
            }
        }
    }

    // MARK: - SonioxTranscriberDelegate

    func transcriber(_ transcriber: SonioxTranscriber, didProduceText text: String) {
        if isCleanMode {
            cleanAccumulator += text
        } else {
            inserter.insert(text: text)
        }
    }

    func transcriber(_ transcriber: SonioxTranscriber, didChangeState connected: Bool) {
        Log.info("Transcriber connected=\(connected)")
    }
}
