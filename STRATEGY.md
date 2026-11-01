---
name: Blackgrid
last_updated: 2026-11-01
---

# Blackgrid Strategy

## Purpose

During a raid, a player looting under time and inventory pressure must decide whether an item is worth keeping in the bag. That decision is difficult because item identity, quest and hideout needs, FIR rules, Flea restrictions and prices, and trader values are spread across sources and must be combined mentally.

## Positioning

Blackgrid puts the raid-time keep/check/sell decision first and biases toward preserving player options under uncertainty. A confirmed current need wins Keep; a known future need wins Keep for later, with unrelated uncertainty still visible. Otherwise, unknown FIR status, progression relevance, or market freshness means Check / May Need with an explicit reason, never a confident Sell.

## Users

**Primary:** Active Escape from Tarkov players looting during a raid — they hire Blackgrid to answer “is this worth keeping in my bag?” quickly, with quest/hideout relevance and eventual sale value supporting that decision.

Stash management is secondary.

## Boundaries

- Windows desktop releases only in this phase; no macOS or Linux parity. Web and mobile apps come late, after an optional sync service (roadmap M17–M19), and never get live map position or the scanner
- Map and Scanner only as initial primary areas; configuration through supporting controls, no Database browsing yet. A local progress tracker (quests, objectives, hideout) arrives in M9
- Blackgrid tracks quest and hideout progress itself, locally and offline, from the game's logs and the player's own input (user decision 2026-11-01; M9). The existing read-only tarkovtracker.org token integration stays until the local tracker replaces it, then is retired. Blackgrid never writes to tarkovtracker.org; the 2026-10-30 plan for task-state writes is withdrawn
- No overlay: nothing is drawn over the game, so no transparent, borderless or click-through map and no global in-game hotkeys that only drive one. "Stay on top" for Blackgrid's own opaque, bordered window is allowed (user decision 2026-11-01)
- No squad features (shared positions, squad item needs, squad raid planning) and no phone or tablet map with live position (user decision 2026-11-01)
- No WebView/WebView2 map renderer, or runtime/architectural dependency on the old application
- Independently recreate useful behavior in Dart/Flutter; no copied reference code or old runtime shipped. The user maintains a private reference companion (a modified fork of a C# desktop program) and owns their contributions, not all upstream or third-party contents
- Repository work targets only the user's own repositories, never the reference companion's original upstream project. The user's fork was intentionally detached from that upstream; do not restore the fork relationship or open PRs there
- The user's intent is for Blackgrid to be open source when functional. No license has been selected and this intent does not authorize making the current private repository public now
- The desktop app needs no Blackgrid backend or account and sends no telemetry; everything works on one machine, offline once data is downloaded. An optional Blackgrid Service with accounts (roadmap M17) may later sync progress for the web and mobile apps; it holds only the progress event history, and the desktop app works fully without it. Existing third-party data/progression access is not a Blackgrid account system
- Proven OpenCV/Tesseract item-recognition approach retained until parity; no novelty-driven engine substitution
- Blackgrid owns the scanner pipeline in Dart; no RatScanner/RatEye/RatStash code or C# bridge is integrated. Native bindings/FFI remain for selected OpenCV/Tesseract primitives and Windows APIs
- Map artwork comes from `tarkov.dev` downloads for local caching/rendering rather than repeated remote requests; retain applicable asset terms and include required notices with public or distributed material
- Useful Map/Scanner behavioral and correctness parity, not visual, architectural, implementation, or bug-for-bug parity
- Mockups guide style and arrangement, not functionality; no hidden feature commitments from screenshot controls or sample numbers
- **Agent testing boundary:** no AI agent may launch or verify the app while Escape from Tarkov is running. Game-dependent testing is user-only; agents must ask for user testing or explicit approval to skip confirmation. Written tests and app verification with the game closed are allowed; see [AGENTS.md](AGENTS.md).

_Resist a change when:_ it weakens raid-time decision trust, diverts initial scope to secondary workflows, or recreates coupling to the old application.

## Key metrics

- **Decision latency** — trigger to actionable result in local benchmark traces; initial goals ≤300 ms p95 targeted, fallback visibly underway by approximately 300 ms and ≤1.5 s p95 total, after recording the reference baseline
- **Recognition accuracy and coverage** — correct automatic identity matches, readable-item coverage, and false positives on a fixed screenshot corpus; coverage at least the reference, false positives no worse
- **Recommendation correctness** — keep/later/check/Flea/trader decisions on fixture cases covering quest, hideout, FIR, restrictions, market, and trader edge cases; local regression reports
- **Uncertainty safety** — unknown or stale decision-critical inputs block unsafe Sell, yielding Check / May Need when no confirmed keep reason decides the outcome; local safety-fixture reports
- **Interaction cost** — clicks, keystrokes, and elapsed time to obtain the raid-time answer; structured play checks, not telemetry

## Tracks

### Raid-time Decision Quality

Make keep/check/sell advice fast, conservative under uncertainty, and easy to trust.

_Why it serves the approach:_ the primary outcome is a useful bag decision, not merely a recognized item or a price.

### Recognition & Capture Reliability

Make item detection fast and robust across resolutions, DPI, and real play conditions.

_Why it serves the approach:_ speed cannot come from accepting the wrong item or refusing readable items that the reference recognizes.

### Native Tactical Map Experience

Replace WebView2 with a responsive Flutter map that makes location, extracts, quests, hazards, floors, and current-player context easy to read during play.

_Why it serves the approach:_ useful map behavior remains available without preserving browser rendering or overlay coupling.

### Product Foundation & UX

Build the shared Material design system, state/data architecture, persistence, performance boundaries, and narrow Windows platform seams.

_Why it serves the approach:_ Map and Scanner remain one understandable product rather than coupled legacy subsystems behind a new UI.

Technical choices, migration classification, validation gates, and replacement criteria live in the [implementation strategy](docs/IMPLEMENTATION_STRATEGY.md).

## Brand

**One-liner:** A desktop tactical companion for raid-time decisions.

**Key message:** Blackgrid is the product name; the name and application branding must not contain “Tarkov”. Dark Material 3, charcoal surfaces, restrained gold accents, green healthy/ready/success states, and clear typography — no military decoration or visual clutter.
