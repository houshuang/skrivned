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
        skrivned status             Show configuration
        skrivned last               Show last transcript (copies cleaned to clipboard)
        skrivned last --raw         Show last transcript (copies raw to clipboard)
        skrivned log                Open transcript log
        skrivned --help             Show this help message

    SETUP:
        mkdir -p ~/.config/skrivned
        echo 'SONIOX_KEY=your_key_here' > ~/.config/skrivned/.env
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

func cmdStatus() {
    let config = Config.load()
    let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
    let hasKey = Config.loadApiKey() != nil

    print("skrivned v\(Skrivned.version)")
    print("Config:     \(Config.configFile.path)")
    print("Hotkey:     \(hotkeyDesc)")
    print("Languages:  \(config.languageHints.joined(separator: ", "))")
    print("API key:    \(hasKey ? "configured" : "MISSING — add to ~/.config/skrivned/.env")")
}

func cmdLast(copyRaw: Bool = false) {
    guard let entry = DictationLog.lastEntry() else {
        print("No transcripts found.")
        exit(0)
    }
    print(entry.cleaned)
    if entry.cleaned != entry.raw {
        print("\n--- raw ---")
        print(entry.raw)
    }

    var meta = ""
    if let proj = entry.project { meta += "[\(proj)] " }
    if let target = entry.target { meta += "(\(target)) " }
    meta += entry.timestamp
    print("\n\(meta)")

    let textToCopy = copyRaw ? entry.raw : entry.cleaned
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(textToCopy, forType: .string)
    print("(copied \(copyRaw ? "raw" : "cleaned") to clipboard)")
}

func cmdLog() {
    let logFile = Config.configDir.appendingPathComponent("dictation_log.jsonl")
    if FileManager.default.fileExists(atPath: logFile.path) {
        NSWorkspace.shared.open(logFile)
    } else {
        print("No transcript log found at \(logFile.path)")
    }
}

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : nil

switch command {
case "start":
    cmdStart()
case "status":
    cmdStatus()
case "last":
    let copyRaw = args.contains("--raw")
    cmdLast(copyRaw: copyRaw)
case "log":
    cmdLog()
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
