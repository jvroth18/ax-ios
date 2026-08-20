# Tool calling

AX uses the Hermes/Qwen convention. The system prompt lists every tool as a JSON schema
inside `<tools>…</tools>`; the model responds with:

```
<tool_call>
{"name": "create_reminder", "arguments": {"title": "Call mom", "due": "2026-08-17T17:00:00"}}
</tool_call>
```

`ToolCallParser` (in `Packages/AXCore`) extracts blocks, strips Qwen3 `<think>` blocks,
validates the call against the schema (required args, types, enums), and returns
validated `ToolCall`s plus the user-facing text. Results are fed back as:

```
<tool_response>
{"content":"Reminder \"Call mom\" created.","success":true}
</tool_response>
```

The agent loop (`AXAssistant/LLM/AgentLoop.swift`) gives the model at most 3 turns (the
`maxToolIterations` setting) to hand control back to a tool. A malformed call is echoed
back to the model as a failure response so it can retry once. A tool call on the *last*
turn is still executed — there is simply no generation left for the model to phrase the
outcome, so the tool's own result text becomes the reply. The loop never returns an empty
reply.

## Date arguments

Every tool that takes a date parses it with `DateArgument.parse` (in `Packages/AXCore`),
never with `ISO8601DateFormatter` directly — that formatter's `.withInternetDateTime`
option **requires** a timezone designator and so rejects the zone-less form the system
prompt teaches. Accepted shapes, each with an optional trailing `Z` / `±HH:MM` / `±HHMM`:

| Argument | Meaning |
| --- | --- |
| `2026-08-17T17:00:00` | 5pm on the user's own clock (no zone means local) |
| `2026-08-17T17:00` | same; models routinely drop the seconds |
| `2026-08-17 17:00` | same; models routinely drop the `T` |
| `2026-08-17` | that day, no time — reminders become untimed rather than firing at midnight |
| `2026-08-17T17:00:00Z` | 5pm UTC |
| `2026-08-17T17:00:00-04:00` | 5pm at UTC-4 |

Anything else is rejected so the model gets a failure response it can retry, rather than a
plausible wrong date. The system prompt (`PromptBuilder.systemPrompt`) tells the model to
emit the first form; `PromptBuilderTests` asserts the prompt and the parser still agree.

## Repetition and pacing

The agent loop hands control back to the model between every tool call, so a request like
"toggle the light on and off, pause, do that ten times, then call 631-645-2763" is 31
generate→execute cycles: minutes of latency, a prompt that grows every cycle, and a count
that a 1.7B has lost by step four. Two tools exist so the model doesn't have to:

- **`wait`** — pause N seconds. Makes "with a pause between" expressible at all.
- **`repeat_steps`** — run a sequence of one-argument steps, optionally repeated:
  `{"steps": "toggle_flashlight:on, wait:0.5, toggle_flashlight:off, wait:0.5", "times": 10}`

That turns the example into **two** calls (`repeat_steps`, then `call_number`) and never
comes near the iteration budget.

The step list is a flat string, not nested JSON, for two reasons: `JSONSchema` deliberately
cannot express arrays of objects, and small models emit flat strings far more reliably.
`WorkflowStep.parse` (AXCore, unit-tested) is liberal about separators — commas,
semicolons, `tool=value`, `tool(value)`, stray brackets and quotes — because those are the
shapes models actually produce when asked for the same thing.

Limits that keep a workflow from wedging the app: 50 repeats, 200 total actions, 120s of
total waiting. Steps must name a tool with exactly one required argument, and `.confirm`
tools (calls, messages, shortcuts, calendar events) are refused inside a repeat — a
confirmation sheet firing ten times is not a feature. Those go in a separate, direct call.

## Per-model system prompts

`PromptProfile` (AXCore) tunes the prompt per model family, because they fail differently:
small models drop the `<tool_call>` wrapper unless shown a worked example (measured: that
one addition moved Qwen3 1.7B from 0/9 to 9/9), while larger ones handle nuance but
over-fire tools they were merely told about. `PromptProfile.forModel(id)` picks from
`small` (≤2B), `capable` (Qwen 3B–8B), `otherVendor` (Llama/Gemma/SmolLM/LFM) and
`standard`. Fields are marked MEASURED or HYPOTHESIS in the source; the eval suite is what
turns the second kind into the first. Every `EvalReport` records which profile produced
it — without that, two runs of the same model are indistinguishable after a prompt change.

## Adding a tool

1. Create `AXAssistant/Tools/Actions/YourTool.swift` conforming to `AXTool`.
2. Give it an honest `description` (the model chooses tools from these) and mark
   `risk: .confirm` if it does anything the user would want to approve (creates events,
   places calls, runs shortcuts). `.confirm` tools automatically get the ConfirmSheet.
3. Register it in `ToolRegistry.standard`.
4. Add a golden-transcript case to `AXCoreTests` if the tool has tricky argument shapes.

Rules of thumb:
- Return a short, natural-language `ToolResult` — the model reads it verbatim to compose
  its final answer.
- Never let a tool bypass an iOS consent surface (e.g. Messages send). If iOS shows its
  own confirmation, say so in the result text so the model doesn't claim it already happened.
