# TelePrompter — Native macOS Voice-Following Teleprompter

A native macOS application that displays your script in a floating overlay and automatically follows your voice as you speak — so you can record your screen while reading naturally.

---

## What it does

- Displays a script in a floating, always-on-top overlay window
- Listens to your microphone continuously using Apple's Speech Recognition
- Detects where you are in the script and scrolls the teleprompter to follow you
- Attempts to exclude the teleprompter window from supported screen recordings
- Runs entirely locally — no account, no cloud, no server

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (arm64) for the Homebrew cask
- Microphone access (for voice following)
- Speech Recognition access (prompted on first use)
- Swift 5.9+ / Xcode Command Line Tools (for building from source)

---

## Install via Homebrew

Easiest way to install TelePrompter (no need to build from source):

```bash
brew tap purvanshh/homebrew-teleprompter
brew install --cask teleprompter
```

> On newer Homebrew versions you may be asked to trust the tap first:
> `brew trust purvanshh/teleprompter`

### First launch (unsigned build)

This build is **not notarized** (it requires an Apple Developer account + certificates), so macOS may warn that the developer cannot be verified. To open it, either:

**Option 1 — Remove the quarantine flag:**
```bash
xattr -dr com.apple.quarantine "/Applications/TelePrompter.app"
open "/Applications/TelePrompter.app"
```

**Option 2 — Right-click → Open:**
In Finder, right-click `TelePrompter.app` → click **Open** → click **Open** in the dialog.

This only needs to be done once; the app runs normally afterward.

---

## Building from source

### Prerequisites

```bash
xcode-select --install   # Install Command Line Tools if not already installed
swift --version           # Verify Swift is available
```

### Build

```bash
cd TelePrompter
bash build_app.sh
```

This produces `TelePrompter.app` in the project directory.

### Running the .app (unsigned build)

Because the app is not notarized (it requires Apple Developer account + certificates), macOS Gatekeeper will initially block it. To run:

**Option 1 — Remove quarantine flag:**
```bash
xattr -rd com.apple.quarantine TelePrompter.app
open TelePrompter.app
```

**Option 2 — Right-click → Open:**
In Finder, right-click `TelePrompter.app` → click **Open** → click **Open** in the dialog.

**What "unsigned" means:**
- The app runs on your Mac normally
- macOS just needs confirmation the first time since it has no code signature from Apple
- This does not affect functionality

---

## Using the app

### 1. Import or create a script

- Go to **Scripts** in the sidebar
- Click the **+** button to create a new script, import a file, or use the built-in test script
- Supported formats: `.txt`, `.md` (Markdown), `.pdf`
- Or paste directly into the text editor

### 2. Load the script

- Select the script in the list and click **Load** in the editor toolbar
- Or double-click the script in the list

### 3. Position the teleprompter

- Click **Show Overlay** in the Teleprompter tab to display the floating window
- Drag the window to your preferred position
- Adjust font size, background opacity, and line spacing with the sliders

### 4. Start voice following

- Click **Start Following** (or press **⌘↩**)
- Grant microphone + speech recognition permissions when prompted
- Begin speaking — the teleprompter will follow your voice

### 5. Record your screen

- Start your screen recording (QuickTime Player, Screenshot.app, etc.)
- The teleprompter overlay should be excluded from the recording

---

## Keyboard shortcuts

| Action | Shortcut |
|--------|----------|
| Start / Stop Following | ⌘↩ |
| Pause Following | Space |
| Previous Sentence | ↑ |
| Next Sentence | ↓ |
| Go to Beginning | ⌘↑ |
| Enter/Exit Recording Mode | ⌘R |

---

## Microphone & speech permissions

On first use, the app will ask for:
1. **Microphone access** — required for voice following
2. **Speech Recognition access** — required for transcription

If denied, go to:
**System Settings → Privacy & Security → Microphone** (and Speech Recognition)

The app includes a button in Settings → Speech to open this directly.

---

## Screen recording protection

**What it does:**

TelePrompter sets `NSWindow.sharingType = .none` on the overlay window. This is macOS's native window-sharing restriction API, which asks the system to exclude the window from supported screen capture mechanisms.

**What it typically protects against:**
- QuickTime Player screen recordings
- macOS Screenshot (Cmd+Shift+5) screen recordings
- ScreenCaptureKit / ReplayKit-based capture
- Any capture API that queries `NSWindowSharingType` before compositing

**What may still capture the window:**
- OBS Studio using **Display Capture** mode (captures the raw display compositor, bypassing window-level restrictions)
- Other tools that capture at the CGDisplayStream/display level rather than the window level
- AirPlay mirroring in some configurations

**For OBS users:**
Use **Window Capture** source targeting a specific application window — not **Display Capture**. Window Capture mode respects macOS window-sharing restrictions.

**This is a platform limitation, not a bug.** The implementation uses the strongest window-level protection available via Apple's public APIs.

> ⚠️ Screen recording protection is not guaranteed against every possible capture technology.

**Testing protection:**
1. Show the teleprompter overlay
2. Start a QuickTime Player → New Screen Recording
3. Record for several seconds
4. Stop and review the file — the teleprompter should not appear

---

## Privacy

- Your script text **never leaves your Mac**
- Microphone audio is processed by Apple's on-device Speech Recognition when possible
- No analytics, no telemetry, no network requests from the app itself
- No account required
- All data is stored in `~/Library/Application Support/TelePrompter/`

If Apple's speech recognition requires network access for your selected language (when on-device recognition is unavailable), that processing happens within Apple's own infrastructure — the app itself does not send data to any third-party server.

To prefer on-device recognition: **Settings → Speech → Prefer on-device recognition** (enabled by default).

---

## Architecture overview

```
TelePrompter/
├── Sources/TelePrompter/
│   ├── App/
│   │   ├── TelePrompterApp.swift      — @main entry point, SwiftUI App + AppDelegate
│   │   └── SessionController.swift   — Central coordinator (speech → alignment → UI)
│   ├── Models/
│   │   ├── Script.swift               — Script data model (Codable, Identifiable)
│   │   ├── ScriptSegment.swift        — ScriptWord, ScriptSentence, ScriptParagraph, ScriptDocument
│   │   ├── TeleprompterState.swift    — Observable state (position, following state, audio)
│   │   └── AppSettings.swift         — UserDefaults-backed settings
│   ├── Views/
│   │   ├── MainWindowView.swift       — Root NavigationSplitView
│   │   ├── ScriptLibraryView.swift    — Script list + CRUD
│   │   ├── ScriptEditorView.swift     — Text editor with autosave
│   │   ├── TeleprompterControlView.swift — Control panel
│   │   ├── TeleprompterOverlayView.swift — The floating overlay (rendered in NSPanel)
│   │   ├── SettingsView.swift         — Tabbed settings
│   │   └── Onboarding/
│   │       └── OnboardingView.swift   — First-launch experience
│   ├── Services/
│   │   ├── ScriptParser.swift         — TXT/Markdown/PDF import + segmentation
│   │   ├── ScriptStorage.swift        — Local JSON persistence + autosave + crash recovery
│   │   ├── SpeechRecognitionService.swift — AppleSpeechRecognitionProvider + protocol
│   │   ├── SpeechAlignmentEngine.swift   — Fuzzy script position tracking
│   │   └── AudioInputService.swift    — Microphone device listing + permissions
│   ├── Window/
│   │   ├── TeleprompterWindowController.swift — NSPanel management (always-on-top, click-through)
│   │   ├── ScreenCaptureProtection.swift     — NSWindow.sharingType = .none
│   │   └── WindowManager.swift               — Multi-monitor support
│   └── Utilities/
│       ├── TextNormalizer.swift       — Normalization, contraction expansion, filler removal
│       └── FuzzyMatcher.swift         — Levenshtein, sequence scoring, sliding window alignment
├── Tests/
│   └── run_tests.swift                — Standalone test runner (22 tests, no framework deps)
└── build_app.sh                       — Build script → TelePrompter.app
```

**Key design decisions:**

- `SpeechRecognitionProvider` protocol allows swapping Apple Speech ↔ local Whisper without changing the alignment engine
- `SpeechAlignmentEngine` maintains a rolling buffer of recent transcript tokens and searches a local window around the current position — never comparing all tokens against the entire script
- Text normalization (lowercase, punctuation removal, contraction expansion, filler removal) happens only for matching; display text is never modified
- `NSPanel` with `.nonactivatingPanel` + `.canJoinAllSpaces` keeps the overlay visible over full-screen apps
- `NSWindow.sharingType = .none` is applied at window creation and whenever recording mode is entered

---

## Troubleshooting

### Teleprompter appears in my recording

Your capture tool captures at the display level (e.g. OBS Display Capture) and bypasses the window sharing restriction. Use **OBS Window Capture** mode or switch to QuickTime Player/Screenshot for capture that respects the exclusion.

### Voice following doesn't start

1. Check **Settings → Speech → Microphone** — confirm a device is selected
2. Verify microphone permission in **System Settings → Privacy & Security → Microphone**
3. Verify Speech Recognition permission in **System Settings → Privacy & Security → Speech Recognition**
4. Try selecting "Default" microphone
5. Check that a script is loaded

### Teleprompter follows incorrectly

- Try **Match Leniency → Strict** in Settings → Speech (smaller search window, higher confidence required)
- Use **↑/↓ arrows** to manually correct position — the engine now re-anchors so voice following continues from there
- If you deviated significantly, press **Reset** and start from the correct paragraph
- The system needs a few words to re-establish position after a pause; short ambiguous phrases alone will not jump the cursor

### High CPU usage during long sessions

- The alignment engine uses a local search window (±60 words), not the whole script
- Speech recognition runs on a background thread
- If CPU is high, try a shorter search radius by reducing Matching Sensitivity slightly
- Ensure no other speech apps are running

### App won't open (Gatekeeper)

```bash
xattr -rd com.apple.quarantine TelePrompter.app
open TelePrompter.app
```
Or right-click → Open → Open.

### Teleprompter window off-screen after monitor disconnect

The app detects screen changes and calls `ensureOnScreen()` which moves the window to the main display if it's no longer on any connected screen.

---

## Known limitations

1. **No global hotkeys** — keyboard shortcuts require the TelePrompter window to be focused. Global hotkeys would require Accessibility permission; this can be added in a future version.
2. **DOCX import not supported** — DOCX requires an XML parser. Import TXT or Markdown instead.
3. **On-device speech recognition** — Availability varies by language and macOS version. For some languages, Apple may route through their servers. Enable "Prefer on-device recognition" and check the system Speech Recognition preferences.
4. **OBS Display Capture bypass** — This is a macOS platform limitation. Window Capture mode in OBS works correctly.
5. **App is unsigned** — Requires manual Gatekeeper bypass on first launch. Add your Developer ID certificate and notarize for distribution.
6. **Swift 6 strict concurrency** — Some internal warnings may appear in strict mode. All @MainActor isolation is applied correctly for runtime safety.

---

## License

MIT License. See LICENSE file.
