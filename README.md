# Morse — an open-source, fully on-device voice agent for iPhone

> The app ships as **Morse**; the targets, bundle id, and source prefixes are still
> `AX*` from before the rename.

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
  Qwen3-1.7B 4-bit (on-device, MLX)   ◄── swappable: 14-model catalog
        ▼  <tool_call> JSON
  Tool registry ──► EventKit · Contacts · Music · AlarmKit · URL schemes ·
                    your Shortcuts · your HTTPS connectors
        ▼
  Reply spoken by AVSpeechSynthesizer, or Kokoro-82M TTS (on-device, opt-in)
```

## Status

Working end to end on device, and **not yet trustworthy** — those are different claims.

The full loop (Action Button → STT → model → tool call → spoken reply) runs on an
iPhone 17; `docs/MEMORY.md` carries real measurements from it (1781 MB peak,
45.6 tok/s, 0.04 s TTFT on Qwen3-1.7B-4bit). Twelve tools are implemented against real
Apple frameworks.

What is *not* established is reliability. Tool-calling accuracy has only ever been
scored by a shallow 9-case harness that asserted key existence rather than argument
values — it never checked a single resolved date, never tested a negative case, and
never executed a tool. Treat any per-model score you see as provisional until it comes
from an on-device run that does. Do not hand this write access to a calendar you care
about yet.

Built for iPhone 15 Pro or newer (Action Button required), iOS 26.

## What it can and cannot do

iOS sandboxing means a normal app **cannot** tap around inside other apps. Morse is honest
about this and ships in two layers:

- **AXAssistant** (this app): does everything Apple's frameworks and the Shortcuts
  ecosystem legitimately allow. Anything you can put in a Shortcut, Morse can trigger by voice.
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
5. Assign the Action Button: **Settings → Action Button → Shortcut → Ask Morse**.

## Roadmap

- [x] M0 — repo scaffold, AXCore (tool-call parser + prompt builder) with unit tests;
      full app compiles for iOS 26 in CI
- [x] M1 — model download + on-device chat; validated on iPhone 17 (see `docs/MEMORY.md`).
      Includes the 14-model catalog, Documents-rooted weight storage, stall/cancel
      handling, and weight-integrity checks.
- [x] M2 — voice pipeline + Action Button (`SpeechAnalyzer` STT, silence watchdog,
      `AVSpeechSynthesizer` replies, optional Kokoro-82M TTS)
- [x] M3 — tool-calling agent + action catalog (12 tools, chained up to 8 iterations,
      `.confirm` sheet for anything destructive)
- [x] M4 — history, settings, connectors, onboarding, metrics/monitor
- [ ] **M4.5 — earn the reliability claim.** An eval that checks resolved dates, scores
      negative cases (no tool should fire), covers multi-step chains, and validates real
      tool arguments — run on device across the catalog, with results committed as a
      file rather than quoted in a commit message. This gates everything above it.
- [ ] M5 — AXDriver (experimental; currently does not compile — see its README)

No Live Activity exists yet; it was listed under M4 and never built.

## Architecture

- `Packages/AXCore` — platform-free agent logic (tool schemas, `<tool_call>` parsing,
  prompt building). Runs on macOS: `cd Packages/AXCore && swift test`.
- `AXAssistant/` — the app: SwiftUI, AppIntents (Action Button), `SpeechAnalyzer` STT,
  [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) inference, SwiftData history.
- `AXDriver/` — the experimental UI-automation module, off by default (`AX_DRIVER` flag).
  **Currently fails to build** on the Xcode 26 toolchain (Swift type-checker crash in
  `VLMPlanner`); its CI leg is non-blocking. Undistributable by design.
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
