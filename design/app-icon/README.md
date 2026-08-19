# Bottleship — app icon

**Concept** (Jordan's): a message in a bottle. A model checkpoint is a sealed,
self-contained snapshot of human knowledge and capability, cast adrift and
carried in your pocket. No cloud, no tether.

**Name: Bottleship.** Four icon designers, working independently, all proposed
it; the judge endorsed it. A coined compound — ownable, memorable, near-zero
App Store collision — and the pun works: you *ship* models, sealed in a
bottle, on-device. Backup name: Driftglass.

## Files

- `bottleship.svg` — winning icon, master source (1024×1024 viewBox, full-bleed,
  no text, no baked corner radius — iOS applies the squircle mask)
- `bottleship-1024.png` — App Store / asset-catalog master, exact 1024×1024
- `candidates/` — the three other directions from the four-way exploration,
  plus the size-comparison gallery used for judging

## How it was chosen

Four sub-agents each implemented a distinct direction (cinematic night sea,
flat constellation, Win-95 pixel, dawn horizon). All four were rendered at
400/180/120/64 px in iOS squircles on dark and light grounds; a judge agent
scored them with 64 px readability and home-screen distinctiveness weighted
double. The flat constellation won (54/70) — the only candidate where both the
bottle silhouette and the AI signal (a node-graph constellation sealed in
glass) survive at 64 px. It then received a refinement pass from the judge's
notes: bolder constellation (8 nodes / 6 edges, dominant north star), larger
highlighted cork, darkened corners with a warm halo, and a faint pixel-grain
dither in the field as a quiet Win-95 nod to the app's UI.

To regenerate the PNG from the SVG: render `bottleship.svg` at 1024×1024 in
any browser and export — it is fully self-contained (inline gradients only).
