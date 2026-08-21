# Engineering log — 18–20 August 2026

What changed, what it cost, and what was measured rather than assumed. Written for whoever
picks this up next, including a future version of us who has forgotten why.

The commit list is in `git log`; this file is for the parts a diff can't carry — the
constraints we discovered, the bugs whose root causes were nothing like their symptoms, and
the work deliberately left undone.

---

## 1. The constraints that shape everything

These were measured on Jordan's hardware, not inferred. They govern most design decisions
in the app, and every one of them cost real time to establish.

| Constraint | Value | How we know |
|---|---|---|
| iOS per-process memory cap | **~3.4 GB**, unraisable | JetsamEvent: OS killed the app at 3,436 MB, reason `per-process-limit` |
| Device | iPhone 17 **Pro**, 12 GB RAM | `devicectl` — the 12 GB does *not* raise the app cap |
| Qwen3 1.7B on device | 45.6 tok/s, 1,781 MB peak, 1.3 s load | M1 report, n=11 |
| Same model on the Mac (M3 Pro) | ~92–106 tok/s | CLI harness |
| Tool-mode prompt (14 schemas) | **1,658–1,683 tokens, ~1.1 s prefill** | CLI harness |
| Downloads over ~1 GB | fail on this network | every failed device download was a >1 GB file; every success was smaller |
| Kokoro-82M TTS | ~0.9× realtime on M3 Pro | CLI harness, RMS-checked audio |

Two consequences worth stating plainly, because they close off otherwise-reasonable ideas:

**Model capability is capped.** A free provisioning profile cannot request
`increased-memory-limit`, so 4B-class models sit at the edge of the ceiling and 27B is not
reachable at any quantization — 4-bit alone is ~15 GB. Everything above 4B has to live on
the Mac and arrive over the connector. Remaining leverage is in the harness, not the weights.

**Prefill, not generation, is the latency story.** That ~1.1 s is paid on *every* generation,
including every iteration of a tool chain, so a three-step chain re-reads the entire tool
catalog three times.

---

## 2. Environment and toolchain

The Mac could not build this project at all when the session started.

- macOS Tahoe 26.6.2 → **Xcode 26.6** (iOS 26.5 SDK). Xcode 16.4 was present but shipped
  the iOS 18 SDK, which cannot build an iOS 26 target.
- **The Metal compiler is a separate download in Xcode 26**: `xcodebuild -downloadComponent
  MetalToolchain`. Without it, mlx-swift's `.metal` kernels fail to compile and the error
  does not mention that a component is missing.
- CLI builds need `-skipPackagePluginValidation -skipMacroValidation` (mlx-swift's CudaBuild
  plugin and the model-loading macro trip Xcode's validation gate). The GUI shows a
  one-time **Trust & Enable** prompt instead.
- `xcode-select` may still point at the old Command Line Tools; prefix builds with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**The simulator cannot run MLX** — it aborts in MLX's C++ layer (SIGABRT) because there is
no Metal GPU to query. Use it for UI screenshots only; anything touching a model needs the
device or the Mac harness. A latent version of this bug also affected the device: metrics
sampling read `MLX.GPU.*` at launch before any model had initialized MLX, so those reads are
now gated behind a flag set on first model load.

---

## 3. Tool calling: 0/9 → 9/9

The eval scored zero. None of the three causes was the model being bad at its job.

1. **Thinking mode ate the budget.** Qwen3's chat template emits a `<think>` block that
   consumed the entire 512-token allowance before any `<tool_call>` appeared. Fixed with
   `additionalContext: ["enable_thinking": false]`, the runtime's supported switch.
2. **The runtime was intercepting our tool calls.** mlx-swift-lm parses well-formed
   `<tool_call>` blocks itself and emits them as structured `.toolCall` *events* rather than
   text. Our stream handler discarded them via `default: break` — so every time the model did
   exactly the right thing, the answer was thrown away and the turn looked empty.
3. **The parser was too strict.** Small models emit bare call-shaped JSON without the tags,
   and some finetunes emit stray `</think>` fragments around otherwise-valid calls.

Plus two prompt rules the eval surfaced: `run_shortcut` was over-firing on any request once
a shortcut name appeared in the prompt, and "remind me…" was being routed to `set_timer`.

**The generalizable lesson:** every one of these was in the harness, not the weights. When a
model scores zero, suspect the plumbing before the model.

---

## 4. Other bugs whose symptom lied

- **"The app crashes when I run prompts."** Not a crash — iOS jetsam killing the app at
  3,436 MB. The 4B model's weights plus a KV cache growing across turns crossed the ceiling.
  Mitigated by clearing the MLX cache after every generation, capping `maxTokens` at 640, and
  halving the buffer-cache limit.
- **"It keeps asking me to download the model."** The downloader (HubClient) defaults its
  cache to `Caches/`, which iOS purges *and* which is not where the app looked. Pinned to
  `Documents/huggingface/hub` with migration.
- **"Requests bounce me back to the download screen."** Self-inflicted: a memory-warning
  handler added an hour earlier called `unload()` under pressure, dropping the model
  mid-request. Memory warnings now trim the MLX cache only and never unload a model in use.
- **"The voice doesn't play."** Kokoro was loaded without a grapheme-to-phoneme processor, so
  English text hit a phoneme tokenizer and produced silence — not slowness. Proven by a Mac
  harness that generates a WAV and fails on an RMS silence check.
- **"Model downloads hang at 0%."** Single 2.26 GB files with no checkpoint. Re-sharded to
  five ≤525 MB pieces (`jtown18/Qwen3-4B-Abliterated-4bit`); each completed shard is now a
  resume point. Also added a 60 s stall watchdog, a Cancel button, and MB-level progress,
  because a transfer that dies silently at 0% is indistinguishable from a slow one.

---

## 5. What shipped

**The app is now "Bottleship"** — renamed, with a constellation-in-a-bottle icon chosen by a
four-designer + judge agent evaluation (`design/app-icon/`).

**A Windows-95 shell, structurally not cosmetically.** A permanent desktop under everything,
windows that open instantly (no slide animations, no swipe-back), a persistent taskbar with
Start menu and per-window buttons, real minimize/close semantics, draggable desktop icons
that remember where you dropped them, and a faint ASCII wordmark behind it all. A three-agent
UI audit found the crowding was mostly *duplicate* controls — the model appeared in three
places at once — so the fix was largely deletion.

**A model library, not a hardcoded list.** Eleven curated models verified two ways before
listing: `model_type` against the architectures our pinned runtime actually loads, and true
weight size from the HF API. Downloads run without switching the active model, with per-row
progress, cancel, and visible errors.

**A conversion pipeline.** Community models converted to MLX 4-bit on the Mac, published to
Hugging Face, and *scored before being listed* — which is how the catalog can say
"Qwen3.8 4B Distilled: 9/9" and mean it. Measured results:

| Model | Tool-calling score | Verdict |
|---|---|---|
| Qwen3.8 4B Distilled | 9/9 | best community model tested |
| Qwen3 4B Abliterated (Josiefied) | 9/9 | properly uncensored, capability intact |
| DiStil 1.7B "uncensored" | 3/9 | distillation kept the teacher's refusals *and* broke instruction-following — removed |
| Qwen3.8 2B | 0/9 | chats, never calls tools |
| Qwen3.8 9B | 0/9 at 21 tok/s | rejected |

**Voice.** Kokoro-82M as a toggleable open TTS with nine voices, sentence-pipelined so speech
starts after roughly one sentence instead of the whole reply. The system voice remains the
fallback, and the audio session is released properly so podcasts resume.

**Metrics.** A System Monitor fed by the runtime's own generation stats — needle gauges and
Task-Manager-style history for throughput and memory, sampled app-wide and persisted across
launches, plus a one-tap M1 report.

**Workflows.** `wait` and `repeat_steps` exist because the agent loop hands control back to
the model after every call, making "toggle the light ten times then call a number" 31
generate→execute cycles. One `repeat_steps` call collapses the repetitive part into two.
Guards: 50 repeats, 200 actions, 120 s total wait, one-argument tools only, no `.confirm`
tools inside a repeat — a confirmation sheet firing ten times is not a feature.

**Per-model prompting.** `PromptProfile` selects prompt content by model family, since they
fail differently. Fields are marked MEASURED or HYPOTHESIS in the source, and every eval
report records which profile produced its score.

**The last eight commits** were a focused reliability/latency batch: cancellable turns with a
Stop button; concurrent execution of read-only calls with a turn-scoped result cache;
`ToolArgumentRepair` for information-preserving argument mistakes; latency in eval reports;
a prompt-narrowing `ToolRouter`; persistent user memory with a `remember` tool; and a CI gate
on the scoring path.

---

## 6. Testing

`Packages/AXCore` holds everything platform-free and is covered by **125 tests** under
`swift test` — matchers, contracts, the workflow step parser, argument repair, the router,
report rendering. The eval suite is 48 cases across seven classes (single-tool, date
extraction, negative, multi-step, ambiguity, spurious-extra, workflow); multi-step and
workflow cases run the *real* `AgentLoop` over a stub registry with real specs and canned
results.

**Adding a tool means updating three places** or the tests fail, by design:
`EvalToolCatalog.specs` (drift detection), `ContractValidator.axAssistant` (platform-free
contract), and `AppToolValidator` (device dry-run). This caught two tools shipping with no
dry-run coverage that would otherwise have been scored blind.

Two tests changed implementations rather than the reverse — worth recording as evidence the
suite does real work. The router narrowed *"what do you think about all this?"* to four tools
because `create_reminder`'s parameter description reads "What to remind the user **about**":
ordinary English scoring as evidence. Only identifiers can trigger narrowing now.

CI gates `swift test` plus the scoring path end-to-end against a hand-written fixture. It
explicitly **cannot** gate model behaviour: recorded completions are frozen text, so a prompt
change can't move them, and re-running the model needs a GPU no hosted runner has. A green
badge does not mean the assistant still works.

---

## 7. Deliberately not done

- **KV-cache prefix reuse.** The larger prefill win and the API supports it, but it requires
  escaping a non-`Sendable` `KVCache` from the `ModelContainer` actor, in the most dangerous
  code path, on a target the simulator cannot exercise. Not shipping that unvalidated.
- **Constrained decoding.** `LogitProcessor` exists in `Evaluate.swift` and would make
  malformed tool calls structurally impossible. Deprioritized *after measuring*: three layers
  already handle parse failures, so prefill is now the bigger win. Still worth doing.
- **Prompt search and history summarization.** The infrastructure is in place (profiles,
  per-report attribution), but a search is only meaningful against real model runs.
- **AXDriver.** Still blocked on a Swift compiler crash in `VLMPlanner.nextAction`; now
  diagnosable interactively since Xcode works.

---

## 8. Open threads

1. **Run the full 48-case suite on device, routing on and off.** If the `negative` and
   `ambiguity` classes hold, flip `pruneToolsInPrompt` on and every request gets ~40% less
   prompt. That is the single highest-value experiment outstanding.
2. **LoRA-finetune a 1.7B on real usage.** `HistoryStore` already records the transcripts;
   `mlx_lm` supports the training; the eval suite is the instrument to prove it helped.
3. **Hybrid routing to the Mac** for requests the memory ceiling puts out of reach.
4. Settings still uses iOS navigation for its sub-pages — the last place the Windows
   metaphor breaks. A tabbed property sheet is the period-correct fix.

---

## 9. 20 August reliability recovery

The failure report combined three independent regressions: launch work made the first screen
appear blank for several seconds, permissive intent matching turned ordinary language into
message or phone calls, and the workflow eval declared success without executing the actions
inside `repeat_steps`. The last bug is why the model could say it had blinked the flashlight
five times while the harness had observed no flashlight call at all.

**Startup.** SwiftData history setup is now lazy and only occurs when History is opened.
On an iPhone 17 Pro simulator the chat and custom keyboard were rendered in the one-second
startup capture; before the change that capture was still a blank white screen.

**Intent safety.** Exact standalone greetings are handled as conversation before generation.
Message composition now requires an SMS/text/send intent (or `message` used as a verb), and
phone calls require call/dial/ring language. Regression cases cover `Hi`, requests for jokes,
`Explain this error message`, and `How does a phone work?` as non-tool replies.

**Executable workflows.** `repeat_steps` now compiles a deterministic plan and executes the
real primitive tools through an injected registry. The shared compiler enforces an explicit
allowlist, argument contracts, 1...50 repetitions, at most 200 expanded actions, positive
waits, and a 120-second wait budget. Repeated flashlight cycles receive a 0.25-second dwell
when the model omits one so the hardware transition is visible. Execution stops at the first
failure or cancellation. The eval records and compares the exact expanded primitive trace,
so on-only, reversed, incomplete, or unexecuted workflows fail rather than receiving syntax
credit.

**Chained requests.** The small-model prompt no longer says to do exactly one thing per
reply. A successful workflow result explicitly tells the model to continue every remaining
action from the original request, and same-response mutating calls execute serially. The
suite now includes exact five- and ten-cycle flashlight workflows, ten cycles followed by a
phone call, and flashlight -> music -> timer ordering.

**Keyboard.** The in-app keyboard keeps the Windows 95 visual language but now follows native
QWERTY geometry: a centered A row, symmetric Shift/Delete, 44-point-high keys, Return as a
newline, and a separate Send action. Keys visibly depress and produce local light haptics;
Paste, tail-visible long drafts, and VoiceOver labels cover the minimum long-prompt workflow.
Full caret/selection editing for VoiceOver remains a P1 follow-up.

**Evidence.** `swift test` passes 139 tests. The current 52-case suite manifest and exact
expanded traces are committed. A cached, offline Mac run used the shipping small-model prompt
and `mlx-community/Qwen3-1.7B-4bit` revision
`3b1b1768f8f8cf8351c712464f906e86c2b8269e`; all six checks passed at each of three seeds
(18/18), including greeting/no-tool, five-cycle blink, ten-cycle blink then call, and x/y/z.
The signed iPhone build succeeded and installed over the existing app. Read-back before and
after installation showed the same 923.2 MB model snapshot and revision, so the update did not
delete or redownload user models. The phone was locked when the launch command ran, so tactile
haptic strength and visible hardware flashlight timing still require one unlocked-device smoke
test; simulator screenshots cannot prove either physical effect.

---

## 10. Morse flashlight signaling

Morse is a dedicated `signal_morse_code(text)` tool, not a prompt that asks the model to
count dots, dashes, and dozens of flashlight toggles. The model passes the original message;
shared deterministic code produces International Morse timing: one unit for a dot, three for
a dash, one between marks, three between letters, and seven between words. At the shipping
0.2-second unit, SOS is exactly 27 units and 5.4 seconds.

The executor checks cancellation before every pulse and forces the torch off on success,
cancellation, background interruption, or AVFoundation failure. There is no arbitrary input-length
or transmission-duration cap, so complex sentences can run to completion; unsupported characters
and empty text still fail before the flashlight changes state. A request-policy guard
also requires the user's own words to authorize Morse signaling, preventing a small model
from flashing arbitrary text in response to a joke or factual question.

The suite is now 55 cases and includes explicit SOS signaling, implicit source extraction
from “Turn Meet at 5 into Morse code,” and a no-tool explanation case. `swift test` passes
149 tests, including the exact pulse train, word-gap timing, normalization, punctuation, and
unbounded long-sentence behavior. The scoring-path fixture passes five known recordings. A cached offline
run of `mlx-community/Qwen3-1.7B-4bit` revision
`3b1b1768f8f8cf8351c712464f906e86c2b8269e` passed 30/30 checks across three seeds using the
shipping small-model prompt. The simulator and signed iPhone builds passed, and installation
preserved the existing 923.2 MB model snapshot. The phone was locked when foreground launch
was attempted, so observing the physical SOS flashes remains the one device-only release
check; installation alone is not evidence that the torch timing was visible on hardware.
