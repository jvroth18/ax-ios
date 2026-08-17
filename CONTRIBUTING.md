# Contributing to AX

Thanks for helping build an honest, fully on-device iPhone agent.

## Ground rules

- **On-device only.** PRs that add network calls beyond the one-time Hugging Face model
  download (or the OS-managed speech assets) will not be merged. No telemetry, ever.
- **Honesty about iOS limits.** Don't ship features that pretend to do what the sandbox
  forbids. If iOS shows its own consent UI (e.g. Messages send), the tool result must
  say so.
- **Safety surfaces stay.** New tools that create, modify, or send anything are
  `risk: .confirm`. Don't downgrade existing tools without discussion.

## Workflow

1. `Packages/AXCore` must stay green: `cd Packages/AXCore && swift test` (any Mac, no
   Xcode project needed — CI runs this on every PR).
2. The app builds via XcodeGen: `xcodegen generate && open ax-ios.xcodeproj`. Never
   commit an `.xcodeproj`.
3. Run `swiftlint` before opening a PR.
4. Adding a tool? One file in `AXAssistant/Tools/Actions/`, register it in
   `ToolRegistry.standard`, and read [docs/TOOL-CALLING.md](docs/TOOL-CALLING.md).

## Good first contributions

- New tools (weather via a registered Shortcut, notes, timers via AlarmKit)
- Entries for `OpenAppTool.knownApps`
- Prompt tweaks that improve 1.7B tool-selection accuracy (include before/after transcripts)
- Memory/tok-s measurements for `docs/MEMORY.md` on hardware we haven't covered
