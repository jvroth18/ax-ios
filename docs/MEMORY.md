# Memory footprint log

Fill in real measurements from Xcode's memory gauge / Instruments as milestones land.
Budget: stay well under the ~4 GB jetsam ceiling of an 8 GB iPhone.

| Config | Weights | Expected peak | Measured peak | tok/s | Device | Date |
|---|---|---|---|---|---|---|
| Qwen3-1.7B-4bit, 4k ctx | ~1.06 GB | 1.6–2.5 GB | 1781 MB (GPU peak 1405 MB) | 45.6 avg (n=11), TTFT 0.04 s, load 1.3 s | iPhone 17 | 2026-08-18 |
| Qwen2.5-1.5B-4bit, 4k ctx | ~0.9 GB | 1.4–2.2 GB | _TBD_ | _TBD_ | iPhone 17 | |
| Qwen2-VL-2B-4bit (driver) | ~1.3 GB | 2.0–3.0 GB | _TBD_ | _TBD_ | iPhone 17 | |

Notes:
- `MLX.GPU.set(cacheLimit: 512 MB)` is set in ModelManager — raising it trades memory for speed.
- Single-resident-model rule: never load the VLM while the text model is resident.
- On memory warning, ModelManager.unload() drops the model; it lazy-reloads on next use.
