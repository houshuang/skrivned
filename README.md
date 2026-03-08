# Skrivned

Voice-to-text for macOS. Hold a key, speak, and text appears character-by-character in the focused app — no clipboard, no paste artifacts.

Uses [Soniox](https://soniox.com) streaming speech-to-text with support for multiple languages, and optionally [Google Gemini](https://ai.google.dev/) for a "clean mode" that removes filler words and fixes grammar before inserting text.

## How it works

```
Hotkey press → AudioStreamer (AVAudioEngine, 16kHz PCM)
                    ↓
             SonioxTranscriber (WebSocket streaming STT)
                    ↓
              TextInserter (CGEventPost keystroke injection)
                    ↓
              Text appears in focused app
```

Audio streams to Soniox in real-time over a WebSocket. Text is inserted character-by-character using macOS accessibility APIs (CGEvent keystroke simulation), so it works in any text field — editors, chat apps, browsers, terminals.

The WebSocket connects on-demand when you start speaking and disconnects when done — no persistent connection, no idle resource usage.

**Clean mode** records the full utterance, then sends it through Gemini Flash to remove filler words ("um", "uh", "like"), fix grammar, and correct proper nouns before inserting the cleaned text.

## Requirements

- macOS 13+
- Swift 5.9+ (included with Xcode 15+)
- [Soniox](https://soniox.com) API key (for speech-to-text)
- [Google Gemini](https://ai.google.dev/) API key (optional, for clean mode)
- iTerm2 (optional, for automatic project detection)

## Setup

### 1. Build and install

```bash
git clone https://github.com/houshuang/skrivned.git
cd skrivned
swift build -c release
cp .build/release/skrivned ~/.local/bin/
```

Or build in debug mode for development:

```bash
swift build
.build/debug/skrivned start
```

### 2. Add API keys

```bash
mkdir -p ~/.config/skrivned
cat > ~/.config/skrivned/.env << 'EOF'
SONIOX_KEY=your_soniox_api_key_here
GEMINI_KEY=your_gemini_api_key_here
EOF
```

- `SONIOX_KEY` — required. Get one at [soniox.com](https://soniox.com).
- `GEMINI_KEY` — optional. Enables clean mode. Get one at [ai.google.dev](https://ai.google.dev/).

### 3. Grant permissions

On first launch, skrivned will prompt for two macOS permissions:

- **Accessibility** — required for keystroke injection (typing text into apps) and global hotkey capture. Grant in System Settings → Privacy & Security → Accessibility.
- **Microphone** — required for audio capture.

## Usage

```bash
skrivned start              # Start the menubar daemon
skrivned status             # Show current configuration
skrivned set-hotkey <key>   # Set the hold-to-speak hotkey
skrivned --help             # Show help
```

Running `skrivned` with no arguments also starts the daemon.

### Dictation modes

**Hold mode** — Hold the hotkey, speak, release to stop. Text streams into the focused app in real-time as you speak.

**Toggle mode** — Double-tap the same hotkey to start dictating hands-free. Single tap to stop. A pulsing red orb appears in the top-right corner while toggle mode is active.

**Clean mode** — Uses a separate hotkey (default: F5) with tap-to-toggle: tap once to start recording, tap again to stop. The recorded speech is sent through Gemini to clean up filler words, fix grammar, and correct proper nouns before inserting. A pulsing blue orb appears while recording; it turns yellow while the LLM is processing.

### Menu bar

Skrivned runs as a menubar app with a colored "S" icon:

- **Green** — idle, ready
- **Pulsing red** — listening (normal dictation)
- **Pulsing blue** — listening (clean mode)
- **Blue ⋯** — cleaning text via Gemini
- **Yellow !** — error (check `~/.config/skrivned/skrivned.log`)

Right-click the menubar icon to reload configuration, open config files, or edit vocabulary.

## Configuration

All configuration lives in `~/.config/skrivned/`. Files are created automatically on first run.

### config.json

Edit `~/.config/skrivned/config.json`:

```json
{
  "holdHotkey": { "keyCode": 63, "modifiers": [] },
  "cleanHotkey": { "keyCode": 96, "modifiers": [] },
  "languageHints": ["en"]
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `holdHotkey` | Globe/fn key (63) | Hold-to-speak key for normal dictation |
| `cleanHotkey` | F5 (96) | Tap-to-toggle key for clean mode dictation |
| `languageHints` | `["en"]` | Languages for Soniox recognition (e.g. `["en", "no"]`) |

Set the hold hotkey from the CLI:

```bash
skrivned set-hotkey globe             # Globe/fn key (default)
skrivned set-hotkey rightoption        # Right Option key
skrivned set-hotkey ctrl+space         # Ctrl + Space
```

### Vocabulary

Skrivned supports custom vocabulary to improve transcription accuracy for proper nouns, technical terms, and domain-specific words. Vocabulary terms are sent to Soniox as context hints and also used by clean mode to correct spelling.

Edit `~/.config/skrivned/vocabulary.json`:

```json
{
  "global": [
    "Kubernetes",
    "PostgreSQL",
    "WebSocket"
  ],
  "projects": {
    "myapp": [
      "MyApp",
      "UserProfile",
      "AuthToken"
    ],
    "blog": [
      "Markdown",
      "frontmatter"
    ]
  }
}
```

- **`global`** — terms used in all dictation sessions regardless of context.
- **`projects`** — project-specific terms, keyed by project name. These are only included when the matching project is detected (see Project Detection below).

Project-specific terms take priority and are listed before global terms. The combined list is capped at ~9,000 characters for the Soniox API. Clean mode uses the full uncapped list.

You can also edit vocabulary from the menubar: click the Skrivned icon → "Edit Vocabulary".

#### Configuring vocabulary with Claude Code

You can ask Claude Code to manage your vocabulary:

```
# Add global terms
"Add these words to my skrivned global vocabulary: Kubernetes, PostgreSQL, Terraform"

# Add project-specific terms
"Add these terms to my skrivned vocabulary under the 'myapp' project: UserProfile, AuthToken, SessionManager"

# Review current vocabulary
"Show me my skrivned vocabulary configuration"
```

Claude Code can read and edit `~/.config/skrivned/vocabulary.json` directly.

### Project detection

Skrivned can automatically detect which project you're working on by querying iTerm2's current working directory. When a known project path is detected, project-specific vocabulary is loaded alongside global terms.

Configure project path mappings in `~/.config/skrivned/projects.json`:

```json
[
  { "prefix": "src/myapp", "project": "myapp" },
  { "prefix": "src/blog", "project": "blog" },
  { "prefix": "work/client-project", "project": "client" }
]
```

Each entry maps a path prefix (relative to your home directory) to a project key in `vocabulary.json`. When your iTerm2 session's working directory matches a prefix, the corresponding project vocabulary is activated.

Project detection only works when iTerm2 is the frontmost application.

#### Configuring projects with Claude Code

```
# Add a project mapping
"Add a skrivned project mapping: when I'm in src/myapp, use the 'myapp' vocabulary"

# Set up a new project with vocabulary
"Create a skrivned project called 'api-server' for ~/src/api-server with terms: FastAPI, Pydantic, SQLAlchemy"
```

### Configuration files summary

| File | Purpose |
|------|---------|
| `~/.config/skrivned/.env` | API keys (SONIOX_KEY, GEMINI_KEY) |
| `~/.config/skrivned/config.json` | Hotkeys and language settings |
| `~/.config/skrivned/vocabulary.json` | Global and project-specific vocabulary |
| `~/.config/skrivned/projects.json` | Project path detection mappings |
| `~/.config/skrivned/skrivned.log` | Runtime log (truncated on each launch) |

## Auto-start on login

Create a launchd plist to start skrivned automatically:

```bash
cat > ~/Library/LaunchAgents/com.skrivned.agent.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.skrivned.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOU/.local/bin/skrivned</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
```

Replace `/Users/YOU` with your home directory path, then load it:

```bash
launchctl load ~/Library/LaunchAgents/com.skrivned.agent.plist
```

## Architecture

| File | Responsibility |
|------|---------------|
| `main.swift` | CLI entry point, argument parsing |
| `AppDelegate.swift` | Session orchestration, hotkey → record → transcribe → insert flow |
| `Config.swift` | Configuration and API key loading |
| `Vocabulary.swift` | Global + project-specific vocabulary management |
| `ProjectDetector.swift` | iTerm2 working directory detection via AppleScript |
| `HotkeyManager.swift` | Global hotkey capture via CGEventTap |
| `AudioStreamer.swift` | Microphone capture via AVAudioEngine (16kHz mono PCM) |
| `SonioxTranscriber.swift` | WebSocket client for Soniox streaming STT |
| `TextInserter.swift` | Text insertion via CGEvent keystroke simulation |
| `TextCleaner.swift` | Gemini Flash API for filler word removal and grammar cleanup |
| `StatusBarController.swift` | Menubar icon, state display, and context menu |
| `FloatingIndicator.swift` | Pulsing colored orb overlay (red=dictating, blue=clean recording, yellow=processing) |
| `KeyCodes.swift` | Key name ↔ keycode mapping |
| `Permissions.swift` | Accessibility and microphone permission checks |
| `Log.swift` | File-based logging |

## License

MIT
