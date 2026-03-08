import AppKit

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var animationTimer: Timer?
    private var pulseState = false

    enum State {
        case idle
        case listening
        case cleanListening
        case cleaning
        case error
    }

    var state: State = .idle {
        didSet {
            DispatchQueue.main.async { self.updateIcon() }
        }
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        Log.info("StatusBar: created, button=\(statusItem.button != nil)")
        updateIcon()
        buildMenu()
        Log.info("StatusBar: visible=\(statusItem.isVisible)")
    }

    func buildMenu() {
        let menu = NSMenu()
        let config = Config.load()
        let holdDesc = KeyCodes.describe(keyCode: config.holdHotkey.keyCode, modifiers: config.holdHotkey.modifiers)
        let cleanDesc = KeyCodes.describe(keyCode: config.cleanHotkey.keyCode, modifiers: config.cleanHotkey.modifiers)

        let titleItem = NSMenuItem(title: "Skrivned", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let stateText: String
        switch state {
        case .idle: stateText = "Ready"
        case .listening: stateText = "Listening..."
        case .cleanListening: stateText = "Recording (clean mode)..."
        case .cleaning: stateText = "Cleaning text..."
        case .error: stateText = "Error — check ~/.config/skrivned/skrivned.log"
        }
        let stateItem = NSMenuItem(title: stateText, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        menu.addItem(NSMenuItem.separator())

        let holdItem = NSMenuItem(title: "Dictate: \(holdDesc) (double-tap to toggle)", action: nil, keyEquivalent: "")
        holdItem.isEnabled = false
        menu.addItem(holdItem)

        let cleanItem = NSMenuItem(title: "Clean dictate: \(cleanDesc) (double-tap to toggle)", action: nil, keyEquivalent: "")
        cleanItem.isEnabled = false
        menu.addItem(cleanItem)

        let langItem = NSMenuItem(title: "Languages: \(config.languageHints.joined(separator: ", "))", action: nil, keyEquivalent: "")
        langItem.isEnabled = false
        menu.addItem(langItem)

        menu.addItem(NSMenuItem.separator())

        let reloadItem = NSMenuItem(title: "Reload Configuration", action: #selector(reloadConfiguration), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let openItem = NSMenuItem(title: "Open Configuration", action: #selector(openConfiguration), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let vocabItem = NSMenuItem(title: "Edit Vocabulary", action: #selector(openVocabulary), keyEquivalent: "v")
        vocabItem.target = self
        menu.addItem(vocabItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func reloadConfiguration() {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
        delegate.reloadConfig()
    }

    @objc private func openConfiguration() {
        let configFile = Config.configFile
        if !FileManager.default.fileExists(atPath: configFile.path) {
            let config = Config.defaultConfig
            try? config.save()
        }
        NSWorkspace.shared.open(configFile)
    }

    @objc private func openVocabulary() {
        let vocabFile = VocabularyData.vocabFile
        if !FileManager.default.fileExists(atPath: vocabFile.path) {
            let vocab = VocabularyData.defaultData
            try? vocab.save()
        }
        NSWorkspace.shared.open(vocabFile)
    }

    private func updateIcon() {
        stopAnimation()
        switch state {
        case .idle:
            setIcon(StatusBarController.drawStatusIcon(color: NSColor.systemGreen.withAlphaComponent(0.8), letter: "S"))
        case .listening:
            startPulseAnimation(color: .systemRed)
        case .cleanListening:
            startPulseAnimation(color: .systemBlue)
        case .cleaning:
            setIcon(StatusBarController.drawStatusIcon(color: .systemBlue, letter: "⋯"))
        case .error:
            setIcon(StatusBarController.drawStatusIcon(color: .systemYellow, letter: "!"))
        }
        buildMenu()
    }

    // MARK: - Pulse animation for listening

    private func startPulseAnimation(color: NSColor = .systemRed) {
        pulseState = true
        setIcon(StatusBarController.drawStatusIcon(color: color, letter: "S"))

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pulseState.toggle()
            let c: NSColor = self.pulseState ? color : color.withAlphaComponent(0.3)
            self.setIcon(StatusBarController.drawStatusIcon(color: c, letter: "S"))
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func setIcon(_ image: NSImage) {
        if let button = statusItem.button {
            button.image = image
        }
    }

    // MARK: - Icons

    static func drawStatusIcon(color: NSColor, letter: String) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Colored rounded rect background
            let bgRect = NSRect(x: 1, y: 2, width: 20, height: 14)
            color.setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()

            // White letter
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let str = NSAttributedString(string: letter, attributes: attrs)
            let strSize = str.size()
            let strX = rect.midX - strSize.width / 2
            let strY = rect.midY - strSize.height / 2
            str.draw(at: NSPoint(x: strX, y: strY))
            return true
        }
        image.isTemplate = false
        return image
    }
}
