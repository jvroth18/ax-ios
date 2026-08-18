# AXDriver — experimental full-UI automation (sideload only)

AXDriver lets AX see the screen of **any** app, using a WebDriverAgent (WDA) runner
and an on-device vision model (Qwen2-VL-2B). It has two modes:

- **Read mode (`summarize_app` tool)** — "open X and read me my notifications": launches
  an app, screenshots (with optional scrolls), and the vision model summarizes what it
  sees. Configured per-app in Settings > Connectors. This is the *realistic* mode:
  comprehension is far more forgiving than precise tapping for a 2B model.
- **Act mode (Driver screen)** — full observe→decide→tap automation. Treat as a research
  demo; grounding accuracy at 2B is hit-or-miss.

**Read this before building it:**

- ❌ **Never distributable via the App Store or TestFlight.** WDA uses private XCTest
  APIs. This module exists for people who build from source onto their own device.
- 🔌 Starting the WDA runner reliably generally requires a **Mac tether**
  (`xcrun devicectl device process launch …` or `xcodebuild test-without-building`).
  Tapping its icon can work, but iOS may suspend it.
- 📆 On a free developer account, the runner **expires every 7 days** and counts against
  the 3-sideloaded-apps limit (AXAssistant + WDA runner = 2 of 3).
- 🧠 2B-class vision models misread UIs regularly. Every step is logged on screen with a
  stop button, and sessions are capped at 15 steps. Treat it as a research toy, not a
  reliable automator.
- 💾 Only one large model can be resident on an 8 GB device: AXAssistant unloads the text
  model before loading the VLM.

## Known issue

The `AX_DRIVER` CI leg currently fails on a Swift compiler bug ("failed to produce
diagnostic for expression") in `VLMPlanner.nextAction` — three structurally different
versions of the model call all trigger it on the Xcode 26 CI toolchain. Needs
interactive diagnosis in Xcode; tracked for M5. The default (non-driver) build is
unaffected and fully green.

## Building

1. Follow [WDA-SETUP.md](WDA-SETUP.md) to sign and install the WebDriverAgent runner.
2. In `project.yml`, append `AX_DRIVER` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` under the
   Debug config, then `xcodegen generate` and rebuild.
3. Start the WDA runner (see setup doc), confirm `http://127.0.0.1:8100/status` in Safari
   on the phone, then use the Driver screen in AX.
