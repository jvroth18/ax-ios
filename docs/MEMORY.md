# Memory footprint log

Fill in real measurements from Xcode's memory gauge / Instruments as milestones land.
Budget: stay under the **~3.4 GB per-process cap** measured on device. This is not a
guess: a JetsamEvent confirmed iOS killing the app at 3436 MB with reason
`per-process-limit`. A free provisioning profile cannot request
`increased-memory-limit`, so the cap is unraisable — treat it as hard.

| Config | Weights | Expected peak | Measured peak | tok/s | Device | Date |
|---|---|---|---|---|---|---|
| Qwen3-1.7B-4bit, 4k ctx | ~1.06 GB | 1.6–2.5 GB | 1781 MB (GPU peak 1405 MB) | 45.6 avg (n=11), TTFT 0.04 s, load 1.3 s | iPhone 17 | 2026-08-18 |
| Qwen2.5-1.5B-4bit, 4k ctx | ~0.9 GB | 1.4–2.2 GB | _TBD_ | _TBD_ | iPhone 17 | |
| Qwen2-VL-2B-4bit (driver) | ~1.3 GB | 2.0–3.0 GB | _TBD_ | _TBD_ | iPhone 17 | |

Notes:
- `MLX.GPU.set(cacheLimit: 256 MB)` is set in `ModelManager.load()` — raising it trades
  headroom for speed. It was lowered from 512 MB to survive the 4B on an 8 GB device.
- Single-resident-model rule: never load the VLM while the text model is resident.
- On memory warning, `handleMemoryWarning()` trims the MLX buffer cache only and
  deliberately does **not** unload the model: unloading would drop the user to the
  download screen mid-session, and if memory is truly critical the OS jetsams us anyway.
- `LLMGenerator` calls `MLX.GPU.clearCache()` after every generation so KV/scratch
  buffers don't accumulate across turns, and caps `maxTokens` at 640 to bound KV growth.
