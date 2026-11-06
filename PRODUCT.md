# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

**Primary:** active Escape from Tarkov players looting during a raid. They use Blackgrid to answer one question fast: "is this item worth keeping in my bag?". Quest and hideout relevance and the eventual sale value support that answer. During a raid they also check the map: where they last stood, which extracts they have this raid, and what is near them.

Stash management between raids is secondary.

Players have Blackgrid on screen in one of two ways (user, 2026-11-06):

- on a **second monitor** beside the game, glanced at mid-raid;
- on the **same screen**, alt-tabbing from the game to a full Blackgrid window and back.

Either way, attention is borrowed from a tense game for a few seconds at a time. The answer has to be readable at a glance, and the hand on the mouse is usually the game hand.

## Product Purpose

Blackgrid is a local-first desktop companion that runs next to the game. It has two areas: **Map** (interactive maps of all 13 locations, the player's last screenshot position and heading, this raid's extracts) and **Scanner** (keep/sell advice for an item, found by search or by an optional live scan of the inspected item).

A player looting under time and inventory pressure has to combine item identity, quest and hideout needs, found-in-raid (FIR) rules, Flea restrictions and prices, and trader values. Those facts live in different places. Blackgrid combines them into one plain-words decision.

Success is measured by decision latency (trigger to actionable answer), recognition accuracy, recommendation correctness, uncertainty safety and interaction cost (clicks, keys and seconds to the answer) (STRATEGY.md, Key metrics).

## Positioning

Blackgrid puts the raid-time keep/check/sell decision first and biases toward preserving the player's options under uncertainty. A confirmed current need wins **Keep**, and a known future need wins **Keep for later**. Otherwise unknown FIR status, unknown progression relevance or a stale price gives **Check / May Need** with an explicit reason, never a confident Sell. "A wrong sell costs you an item; a check costs you a second look." (README)

It does this without touching the game. It reads only the game's log files, the screenshots the player takes and, with live scan on, a small picture of the screen around the mouse.

## Operating Context

- Windows 11 x64 desktop, in the player's own opaque, bordered window. "Stay on top" for that window is allowed; drawing over the game is not.
- The verdict order is **Keep → Keep for later → Check / May Need → Flea → Trader → Price unavailable**.
- Map position updates only when the player takes an in-game screenshot. It is a snapshot, not live tracking.
- Extracts for this raid come from an **O**-panel screenshot read by Windows text recognition.
- The game mode (PvP, PvE, Seasonal) comes from the game log or from Settings. Item data comes from tarkov.dev. Read-only progress can come from a TarkovTracker token until the local progress tracker (roadmap M9) replaces it.
- Search is **Ctrl K**. The live scan key defaults to **F9**.

## Capabilities and Constraints

- **Platform note:** Blackgrid is a native Windows desktop app built with Flutter (Dart), not a website. `web` above is the nearest value impeccable's platform field accepts. No web, macOS or Linux build exists in this phase. Web and mobile apps come late (roadmap M18–M19) and never get live map position or the scanner. Every design must be buildable in Flutter.
- Map and Scanner are the only primary areas. Configuration lives in supporting controls such as Settings. There is no database browser yet. A local quest and hideout progress tracker arrives in M9.
- **No overlay:** nothing is drawn over the game, so no transparent, borderless or click-through windows, and no global in-game hotkeys that only drive one. No squad features, and no phone or tablet map with live position.
- No backend, account or telemetry. Everything works on one machine and offline once data is downloaded. Settings, pins and history stay in `%LOCALAPPDATA%\Blackgrid\`.
- Blackgrid never connects to the game, reads or changes its memory, injects anything or sends it input.
- Open source under the MIT License, in a public repository.
- **Terminology:** Map, Scanner, Keep, Keep for later, Check / May Need, Flea, Trader, FIR (found in raid), PMC / Scav / shared extracts, transits, pins, live scan, Follow logs, Read Latest.

## Brand Commitments

- The product name is **Blackgrid**. The name and application branding must not contain "Tarkov" (STRATEGY.md).
- Blackgrid is a sibling of Mythspine and uses the **Ember** brand kit (`brand/`). Someone who uses both apps should recognise them as one family (user, 2026-11-06). Ember supersedes STRATEGY.md's older brand line ("Dark Material 3, charcoal surfaces, restrained gold accents, green healthy/ready/success states"). STRATEGY.md's own wording is updated in a later plan edit.
- The hex logo with the "BLACKGRID" wordmark and the "TRACK. PLAN. SURVIVE." tagline is a brand asset. It keeps its tracked capitals and is exempt from Ember's sentence-case rule (user, 2026-11-06).
- Blackgrid ships both Ember rooms with a System/Dark/Light switch (user, 2026-11-06).
- No military decoration or visual clutter (STRATEGY.md).
- Blackgrid is a fan-made tool, not affiliated with Battlestate Games. Third-party data and artwork (tarkov.dev, TarkovTracker) keep their credits and notices.

## Evidence on Hand

- Current app screenshots: `docs/screenshots/map.png` and `docs/screenshots/scanner.png` (README), and the before-redesign record in `.impeccable/review/current/`.
- Ember brand kit: `brand/` (BRAND.md, tokens, specimen, Flutter token and theme files, fonts with their OFL licences).
- Product strategy and roadmap: `STRATEGY.md` and `openspec/roadmap.md`.
- There are no user testimonials, usage numbers, telemetry or benchmarks of user behaviour, and none may be invented. Decision-latency and recognition figures exist only as local benchmark targets in STRATEGY.md.

## Product Principles

1. **Answer first.** The keep/check/sell verdict and its reason come before everything else a screen shows.
2. **Never confidently wrong.** When an input is unknown or stale, say Check / May Need and why. Never imply a certainty, a save or a sync that did not happen.
3. **Glanceable under pressure.** A player who looks away from the game for two seconds should get the answer without reading a paragraph or hunting for it.
4. **Hands off the game.** Blackgrid observes files and pixels the player hands it, and nothing more.
5. **Local and honest.** Data stays on the player's machine, and sources and their age are shown, not hidden.

## Accessibility & Inclusion

No product-specific commitment beyond the Ember defaults has been made (user, 2026-11-06). DESIGN.md's verdict plates still differ by fill and border as well as hue, so most verdicts can be told apart without colour.
