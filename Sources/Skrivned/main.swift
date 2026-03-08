import AppKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

enum Skrivned {
    static let version = "0.1.0"
}

func printUsage() {
    print("""
    skrivned v\(Skrivned.version) — Voice-to-text for macOS via Soniox

    USAGE:
        skrivned start              Start the dictation daemon
        skrivned set-hotkey <key>   Set the hold-to-speak hotkey
        skrivned status             Show configuration
        skrivned --help             Show this help message

    SETUP:
        mkdir -p ~/.config/skrivned
        echo 'SONIOX_KEY=your_key_here' > ~/.config/skrivned/.env

    HOTKEY EXAMPLES:
        skrivned set-hotkey globe             Globe/fn key (default)
        skrivned set-hotkey rightoption        Right Option key
        skrivned set-hotkey ctrl+space         Ctrl + Space
    """)
}

func cmdStart() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\nStopping skrivned...")
        exit(0)
    }

    app.run()
}

func cmdSetHotkey(_ keyString: String) {
    guard let parsed = KeyCodes.parse(keyString) else {
        print("Error: Unknown key '\(keyString)'")
        print("Run 'skrivned --help' for examples")
        exit(1)
    }

    var config = Config.load()
    config.holdHotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)

    do {
        try config.save()
        let desc = KeyCodes.describe(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        print("Hold hotkey set to: \(desc)")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdStatus() {
    let config = Config.load()
    let holdDesc = KeyCodes.describe(keyCode: config.holdHotkey.keyCode, modifiers: config.holdHotkey.modifiers)
    let hasKey = Config.loadApiKey() != nil

    print("skrivned v\(Skrivned.version)")
    print("Config:     \(Config.configFile.path)")
    print("Hold:       \(holdDesc)")
    let cleanDesc = KeyCodes.describe(keyCode: config.cleanHotkey.keyCode, modifiers: config.cleanHotkey.modifiers)
    print("Clean:      \(cleanDesc)")
    print("Languages:  \(config.languageHints.joined(separator: ", "))")
    print("API key:    \(hasKey ? "configured" : "MISSING — add to ~/.config/skrivned/.env")")
}

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : nil

switch command {
case "start":
    cmdStart()
case "set-hotkey":
    guard args.count > 2 else {
        print("Usage: skrivned set-hotkey <key>")
        exit(1)
    }
    cmdSetHotkey(args[2])
case "status":
    cmdStatus()
case "--help", "-h", "help":
    printUsage()
case nil:
    // Default to start
    cmdStart()
default:
    print("Unknown command: \(command!)")
    printUsage()
    exit(1)
}
