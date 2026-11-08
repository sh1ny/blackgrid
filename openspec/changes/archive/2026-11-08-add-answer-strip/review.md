# Review

## Metadata

- **Round:** 2 (fresh FULL review of the amended design).
- **Prior round:** Round 1 approved with changes; its focused re-check resolved hotkey and recording-status placement.
- **Reviewer:** fresh-context subagent (Codex).
- **Reviewed:** `openspec/changes/add-answer-strip/{proposal.md,design.md,tasks.md,review.md,specs/workspace-shell/spec.md,specs/scanner-evidence/spec.md,specs/map-rail/spec.md,specs/local-data-durability/spec.md}`; `openspec/architecture.md`; in-force cited ADRs 0001, 0002, 0003, 0009, 0013, 0017, 0018, 0022, 0023, 0029, 0031, 0037 and 0038; DESIGN.md X4/X10/X11/X12/X14 and the approved B-view HTML; the review template and generated review instructions. Source evidence includes the tracked shell, Map, Scanner, decision card, manual controls, evidence panels, Settings dialog, selection/history controllers, database, ItemActivity codec and catalog search. Original Context anchors were also checked against tracked `main` versions because groups 1–4 have already changed those locations.
- **Skills:** Loaded `.claude/skills/dart-use-pattern-matching/SKILL.md`, `.claude/skills/dart-write-documentation/SKILL.md`, `.claude/skills/dart-add-unit-test/SKILL.md`, `.claude/skills/dart-run-static-analysis/SKILL.md`, `.claude/skills/flutter-add-widget-test/SKILL.md` and `.agents/skills/impeccable/SKILL.md` as review guidance. None failed to load. Project hand-written fakes and pinned commands take precedence over generic skill examples. No skill workflow, detector, app/game launch, test or analyzer ran.
- **Referenced stores:** `openspec list --json` resolved the planning root to `F:/Dev/Dart/blackgrid`; `openspec context --json` returned no members or unresolved references.
- **Scope:** Final artifacts include all six build-review corrections, the explicit initial inspector decision, the 50-option popup bound, and pending group 5. This is design approval, not implementation verification or confirmation of the reported build review.

## Findings

### Critical (blocking)

None.

### Moderate

None outstanding.

### Suggestions

None.

### Claims

The original Context anchors support the pre-change baseline on `main`: the horizontally constrained header and separate timer strip; mounted IndexedStack areas; Scanner configuration ahead of narrow-layout advice; Map advice beneath Active map; raw item ID and FIR placement; lazy history rows with existing ItemIcon leases and mode guards; synchronous selection projection before the three activity writes; stored-mode history inspection computing current advice; item/mode uniqueness, schema 6, tolerant row decoding and transactional revision updates; and the untargeted Settings entry point. These are baseline descriptions rather than claims that completed groups 1–4 are still absent.

Current tracked source supports the retained ownership and durability approach: selection captures verdict arguments before persistence, HistoryController routes writes to the existing transaction, schema 7 adds nullable named verdict storage, optional values decode as unknown, and history inspection remains separate from the recorded verdict. ADR-0038 agrees with D2 and the durability delta. The design preserves scan-feed/correction authority, current timer projections, icon-cache bounds and the Map rail boundary.

The final search bound was re-checked against `SelectionController.results` and `CatalogSnapshot.search` (`lib/application/selection_controller.dart:107`; `lib/domain/catalog.dart:485–492`). Existing search returns every match. The amended Resource Bounds table now explicitly retains that catalog-sized cost while limiting the popup to 50 displayed options, a lazy bounded-height viewport, a refine-search hint and keyboard navigation within displayed results. The anchored-search scenario and task 5.1 require a synthetic greater-than-50-match assertion. The earlier assumption of an inherited result cap is resolved.

The six UI corrections have assertable scenarios and corresponding offline test-map rows. The additional initial-state scenario specifies open above 1080px and closed otherwise, initialized once per shell session, with later toggles preserved across resizing. Keeping this widget state above responsive branches is compatible with the existing mounted workspace. No new application authority, capture mechanism, per-history-row decision projection or image cache is introduced.

The 47-row test map keeps the seven pending scenarios red and group 5 unticked. It covers explicit search selection and dismissal, retained Scanner functions, history-first geometry, initial inspector state, flexible tools and separators, semantic live-scan status, price/freshness and the normal 76px strip, with both rooms, text scaling and narrow widths. Long reasons may grow rather than truncate. The targeted Settings dialog is the explicit transitional owner choice; full Settings and Map restyling remain later work. Owner-only visual judgment remains unverified, and no testable scenario is delegated to a user task.

## Verdict

VERDICT: APPROVE

## Required Changes

None.

CHANGES_APPLIED: n/a

## Rebuttals

No outstanding rebuttals. The popup-bound clarification was amended and re-read during this review. Approval covers the final artifacts reviewed here; group 5 implementation and fresh pre-ship review remain required.
