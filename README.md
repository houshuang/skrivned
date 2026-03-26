# Skrivned

Voice-to-text for macOS. Tap a hotkey to start dictating hands-free, tap again to stop. Text is transcribed in real-time, optionally post-processed by an LLM to clean up filler words and grammar, then inserted into the focused app.

Uses [Soniox](https://soniox.com) streaming speech-to-text with [Google Gemini](https://ai.google.dev/) for post-processing (filler word removal, grammar fixes, paragraph formatting, proper noun correction). When dictating into AI tools (Claude Code, Codex, Claude desktop app), post-processing is automatically skipped — these tools handle natural speech well, and skipping saves latency.

## How it works

```
Hotkey press → AudioStreamer (AVAudioEngine, 16kHz PCM)
                    ↓
             SonioxTranscriber (WebSocket streaming STT)
                    ↓
             Live preview panel (floating overlay)
                    ↓
             Detect dictation target (AI app? AI CLI? General?)
                    ↓
          ┌─── AI target ───┐     ┌─── General target ───┐
          │  Skip cleaning   │     │  TextCleaner (Gemini) │
          └────────┬─────────┘     └──────────┬────────────┘
                   ↓                          ↓
             TextInserter (CGEventPost keystroke injection)
                    ↓
             Text appears in focused app
```

Audio streams to Soniox in real-time over a WebSocket. A floating panel at the bottom of the screen shows the transcription as it happens — confirmed words in white, tentative words in gray. When you stop recording, the app detects whether the focused application is an AI tool (Claude Code, Codex, Claude desktop app). For AI targets, raw transcription is inserted directly — these tools handle natural speech including filler words. For everything else, text is sent through Gemini Flash to remove filler words, fix grammar, add paragraph breaks, and correct proper nouns. The cleaned text is then inserted into the focused app via macOS accessibility APIs (CGEvent keystroke simulation).

The audio engine is pre-warmed at launch so recording starts with minimal latency when you press the hotkey. Project detection and WebSocket connection happen in the background while audio is already being captured and buffered.

Both raw and cleaned text are logged to `~/.config/skrivned/dictation_log.jsonl` for later analysis, along with the detected project and dictation target.

If no Gemini key is configured, raw transcription is inserted directly without post-processing.

## Requirements

- macOS 13+
- Swift 5.9+ (included with Xcode 15+)
- [Soniox](https://soniox.com) API key (for speech-to-text)
- [Google Gemini](https://ai.google.dev/) API key (recommended, for post-processing)
- iTerm2 (optional, for automatic project detection)

## Setup

### 1. Build and install

```bash
git clone https://github.com/houshuang/skrivned.git
cd skrivned
swift build -c release
cp .build/release/skrivned ~/.local/bin/
codesign -s - ~/.local/bin/skrivned
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
- `GEMINI_KEY` — recommended. Enables LLM post-processing. Get one at [ai.google.dev](https://ai.google.dev/).

### 3. Grant permissions

On first launch, skrivned will prompt for two macOS permissions:

- **Accessibility** — required for keystroke injection (typing text into apps) and global hotkey capture. Grant in System Settings → Privacy & Security → Accessibility.
- **Microphone** — required for audio capture.

## Usage

```bash
skrivned start              # Start the menubar daemon
skrivned status             # Show current configuration
skrivned last               # Show last transcript (copies cleaned to clipboard)
skrivned last --raw         # Show last transcript (copies raw to clipboard)
skrivned log                # Open transcript log file
skrivned --help             # Show help
```

Running `skrivned` with no arguments also starts the daemon.

### Dictation

Tap the hotkey (default: Right Option) to start dictating hands-free. Tap again to stop. Text is post-processed through Gemini and inserted into the focused app.

**Auto-cancel on Command shortcuts** — If you press a Command+key shortcut (e.g. ⌘C, ⌘V) while recording, the session is automatically abandoned. This prevents accidental dictation when you meant to use a keyboard shortcut.

### Floating preview panel

While recording, a dark translucent panel appears at the bottom of the screen:

- **White text** — confirmed (final) words from Soniox
- **Gray text** — tentative words that may still change
- **Pulsing blue dot** — recording active
- **"Processing..."** — text is being cleaned by Gemini (dot turns yellow)
- **× button** — click to cancel recording or processing (text is logged but not inserted)

### Menu bar

Skrivned runs as a menubar app with a colored "S" icon:

- **Green** — idle, ready
- **Pulsing blue** — listening
- **Blue ⋯** — post-processing via Gemini
- **Yellow !** — error (check `~/.config/skrivned/skrivned.log`)

Right-click the menubar icon to reload configuration, open config files, edit vocabulary, copy the last transcript, or open the transcript log.

### Transcript retrieval

If a dictation session fails (e.g. cursor was in a non-editable field), or if Gemini over-cleaned your text, you can recover it:

```bash
skrivned last          # Print last transcript and copy cleaned version to clipboard
skrivned last --raw    # Print last transcript and copy raw (pre-cleaning) version to clipboard
skrivned log           # Open the full transcript log
```

All sessions — including abandoned ones — are logged to `~/.config/skrivned/dictation_log.jsonl`. Each entry includes both raw and cleaned text, the detected project, and the dictation target (`ai_app`, `ai_cli`, or `general`).

## Configuration

All configuration lives in `~/.config/skrivned/`. Files are created automatically on first run.

### config.json

Edit `~/.config/skrivned/config.json`:

```json
{
  "hotkey": { "keyCode": 61, "modifiers": [] },
  "languageHints": ["en"]
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `hotkey` | Right Option (61) | Tap-to-toggle dictation key |
| `languageHints` | `["en"]` | Languages for Soniox recognition (e.g. `["en", "no"]`) |

### Vocabulary

Skrivned supports custom vocabulary to improve transcription accuracy for proper nouns, technical terms, and domain-specific words. Vocabulary terms are sent to Soniox as context hints and also used by post-processing to correct spelling.

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

Project-specific terms take priority and are listed before global terms. The combined list is capped at ~9,000 characters for the Soniox API. Post-processing uses the full uncapped list.

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

Configure project path mappings in `~/.config/skrivned/projects.json` (see `projects.example.json` for the format):

```bash
cp projects.example.json ~/.config/skrivned/projects.json
```

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

### Smart cleaning (AI target detection)

When you dictate into AI tools, Gemini post-processing is automatically skipped. This saves 1–3 seconds of latency and avoids the risk of the cleaning step removing intentional content (e.g. code-switching between languages, modern slang like "vibe code").

Detection works by checking the frontmost application at session start:

| Target | Detection method | Cleaning |
|--------|-----------------|----------|
| Claude desktop app | Bundle ID (`com.anthropic.claudefordesktop`) | Skipped |
| Claude Code / Codex in iTerm2 | iTerm2 session name (e.g. `"⠂ Claude Code ..."`) | Skipped |
| Claude Code / Codex in other terminals | Not yet detected (falls back to general) | Applied |
| All other apps (Slack, browser, etc.) | Default | Applied |

Note: Claude Code runs under `caffeinate` to prevent system sleep, so the terminal's foreground job name is `"caffeinate"`, not `"claude"`. Detection uses the iTerm2 session name instead, which Claude Code sets to include `"Claude Code"` in the title.

The detected target is logged in `dictation_log.jsonl` so you can verify the behavior over time.

### Configuration files summary

| File | Purpose |
|------|---------|
| `~/.config/skrivned/.env` | API keys (SONIOX_KEY, GEMINI_KEY) |
| `~/.config/skrivned/config.json` | Hotkeys and language settings |
| `~/.config/skrivned/vocabulary.json` | Global and project-specific vocabulary |
| `~/.config/skrivned/projects.json` | Project path detection mappings |
| `~/.config/skrivned/skrivned.log` | Runtime log (truncated on each launch) |
| `~/.config/skrivned/dictation_log.jsonl` | Raw and cleaned text pairs for analysis |

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
| `AppDelegate.swift` | Session orchestration, hotkey → record → transcribe → clean → insert flow |
| `Config.swift` | Configuration and API key loading |
| `Vocabulary.swift` | Global + project-specific vocabulary management |
| `ProjectDetector.swift` | iTerm2 working directory detection + AI target detection (bundle ID, job name) |
| `HotkeyManager.swift` | Global hotkey capture via CGEventTap |
| `AudioStreamer.swift` | Microphone capture via AVAudioEngine (16kHz mono PCM, pre-warmed, debounced auto-reset on sleep/wake and device changes) |
| `SonioxTranscriber.swift` | WebSocket client for Soniox streaming STT |
| `TextInserter.swift` | Text insertion via CGEvent keystroke simulation |
| `TextCleaner.swift` | Gemini Flash API for filler removal, grammar, paragraph formatting, proper nouns |
| `DictationLog.swift` | JSONL logging of raw/cleaned text pairs with project and target metadata |
| `StatusBarController.swift` | Menubar icon, state display, and context menu |
| `FloatingIndicator.swift` | Floating preview panel with live transcription and pulsing status dot |
| `KeyCodes.swift` | Key name ↔ keycode mapping |
| `Permissions.swift` | Accessibility and microphone permission checks |
| `Log.swift` | File-based logging |

## License

MIT
