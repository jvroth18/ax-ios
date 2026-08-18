# AX — an open-source, fully on-device voice agent for iPhone

Press your **Action Button**, speak, and a language model running **entirely on your
iPhone** takes action: reminders, calendar events, calls, messages, music, your
Shortcuts. No cloud. No accounts. No telemetry. Audio and text never leave the device.

```
┌─ Action Button ─┐
│  🎤 record       │
└───────┬─────────┘
        ▼
  SpeechTranscriber (on-device STT, iOS 26)
        ▼
  Qwen3-1.7B 4-bit (on-device, MLX)
        ▼  <tool_call> JSON
  Tool registry ──► EventKit · Contacts · Music · URL schemes · your Shortcuts
```

## Status

Early development. See milestones below. Built for iPhone 15 Pro or newer
(Action Button required), iOS 26.

## What it can and cannot do

iOS sandboxing means a normal app **cannot** tap around inside other apps. AX is honest
about this and ships in two layers:

- **AXAssistant** (this app): does everything Apple's frameworks and the Shortcuts
  ecosystem legitimately allow. Anything you can put in a Shortcut, AX can trigger by voice.
- **[AXDriver](AXDriver/README.md)** (optional, experimental, build-from-source only):
  true see-the-screen-and-tap automation via a WebDriverAgent runner + an on-device
  vision model. Never App Store distributable; read its README before touching it.

Things iOS will never let any app do (including this one): send a message with zero user
interaction, start recording from the background without foregrounding, or control
another app's UI from an App Store build.

## Getting started

1. **Xcode 26+** on macOS 15+, an Apple ID (free account is fine —
   [read this first](docs/FREE-ACCOUNT.md)), `brew install xcodegen`.
2. ```bash
   git clone <this repo> && cd ax-ios
   xcodegen generate
   open ax-ios.xcodeproj
   ```
3. Select your Personal Team under Signing & Capabilities, plug in your iPhone, ⌘R.
4. On first launch the app downloads **Qwen3-1.7B-4bit (~1.1 GB)** from Hugging Face —
   Wi-Fi recommended. Weights live in the app's Documents folder (visible and deletable
   in the Files app), excluded from iCloud backup.
5. Assign the Action Button: **Settings → Action Button → Shortcut → Ask AX**.

## Roadmap

- [x] M0 — repo scaffold, AXCore (tool-call parser + prompt builder) with unit tests;
      full app compiles for iOS 26 in CI
- [ ] M1 — model download + on-device chat (code complete, needs on-device validation)
- [ ] M2 — voice pipeline + Action Button
- [ ] M3 — tool-calling agent + initial action catalog
- [ ] M4 — history, settings, Live Activity, onboarding
- [ ] M5 — AXDriver (experimental)

## Architecture

- `Packages/AXCore` — platform-free agent logic (tool schemas, `<tool_call>` parsing,
  prompt building). Runs on macOS: `cd Packages/AXCore && swift test`.
- `AXAssistant/` — the app: SwiftUI, AppIntents (Action Button), `SpeechAnalyzer` STT,
  [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) inference, SwiftData history.
- `AXDriver/` — the experimental UI-automation module, off by default (`AX_DRIVER` flag).
- Docs: [tool calling](docs/TOOL-CALLING.md) · [free account](docs/FREE-ACCOUNT.md) ·
  [memory budget](docs/MEMORY.md)

## Safety model

- Tools are declared `.safe` or `.confirm`; `.confirm` actions (calendar writes, calls,
  running Shortcuts) always show a confirmation sheet before executing.
- The model can only run Shortcuts you explicitly register by name in Settings, and can
  only call HTTPS endpoints you registered in Settings > Connectors — by name, never by
  raw URL.
- Every action is logged to on-device history.

## Contributing

Add a tool in one file (see [docs/TOOL-CALLING.md](docs/TOOL-CALLING.md)), keep
`AXCore` covered by tests, run `swiftlint` before PRs. MIT licensed.
