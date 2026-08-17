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

The agent loop (`AXAssistant/LLM/AgentLoop.swift`) runs at most 3 tool iterations per
request. A malformed call is echoed back to the model as a failure response so it can
retry once.

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
