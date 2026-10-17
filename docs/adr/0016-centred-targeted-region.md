# 0016 - Centred targeted region: a fixed band around the client centre, searched for every marker peak

- Status: accepted
- Date: 2026-10-17 (M4 change `fix-targeted-scan-region`)
- Supersedes: 0010 ([ADR-0010](0010-windows-input-and-capture-boundary.md)), the region formula in its "Physical-pixel, DPI-independent ROI" bullet only. Physical pixels, DPI as metadata only, the full-client fallback and clip-not-pad stay in force, as does the rest of ADR-0010.
- Source: change `fix-targeted-scan-region` (design D1, D2, D3, D6)

## Context and problem

ADR-0010 copied the reference fork's cursor strip: with `s = min(w/1920, h/1080)`, `m = floor(50s)` and `r = floor(600s)`, the targeted region was `(x - m~/2, y - m~/2, m + r, m)` around the trigger point. The recordings of 2026-10-14 and 2026-10-17 show that strip accepted none of the 36 scans that were accepted after the settle wait (30 and 6). The inspect window does not open under the cursor. A direct inspect opens centred on the client, and inspects opened from a container window cascade to the right of and below their parent. The cursor, which sits on the clicked item, is therefore far from the title.

Measured on 3440x1440 recordings (`s = 4/3`):

- `20261017-130909-0002`: window at x 1187-2253, title at y about 358 (direct inspect, centred).
- `-0023`: window at x 1433-2494, title at y about 432 (cascade from a container).
- `-0019`: window at x 1338-2403, a tall window clamped near the top, title at y about 141, with four container title bars, each with a marker, to its left.

The window is about 800*s wide. The strips captured at the 50 ms settle already show the inspect window drawn where they overlap it (`-0003`, `-0006`), so the settle (ADR-0014) is not the cause.

## Decision

- **The targeted region is a fixed band around the client centre.** With `(cx, cy)` the client centre, `s` the exact rational above and `f(k) = floor(k*s)`, the region is `(cx - f(440), 0, f(440) + f(700), cy + f(60))`. It covers the centred window (+-400*s), a cascade margin of 300*s to the right and 40*s to the left, and every title height from the client top to 60*s below the centre. Starting at the client top rather than `cy - f(540)` keeps a tall window clamped to the top inside the band on clients taller than 16:9; on 16:9 and wider clients the two are equal. Examples: 1920x1080 gives (520, 0, 1140, 600); 3440x1440 gives (1134, 0, 1519, 800).
- **The band always lies inside the client.** `f(440) < w/2`, `f(700) < w/2` and `cy + f(60) <= h`. Only the virtual desktop can clip it, and clip-not-pad still applies. The constants live in one place, `capture_geometry.dart`.
- **The trigger point is an identity guard only.** The point must still be inside the client, but it no longer moves the region.
- **Targeted recognition lists every marker peak,** like full-client recognition: peaks at the .82 gate, `markerPeaksOverflow` on native overflow, suppression keeping 8, and the best-score query when no peak exists. The `InspectionRecognised.evidence` contract for the targeted kind is 0 to 8 entries in score order, not 0 or 1.
- **Targeted entries are ranked among themselves before the pass may win alone.** `rankOutcome` matches every targeted entry and picks the best by the existing order (acceptance, similarity, marker, peak). If that entry is accepted it wins alone and the fallback is not matched. Otherwise all targeted and fallback entries are ranked together, with a targeted entry first on a full tie.
- **Waits are unchanged.** The 50 ms settle and 200 ms fallback deadlines of ADR-0014 stay; ADR-0012 and ADR-0014 are not superseded.

## Rejected alternatives

- **Keep the cursor strip and add the band as a second targeted capture.** Capture admits one request at a time (ADR-0013), so a third pass adds a capture and a job to every miss, for a strip that accepted nothing. Reversal cost: low (one pure function and its tests).
- **Find the window first with a low-resolution marker search over the whole client.** It needs a whole-client capture on every scan, the cost the targeted pass exists to avoid. Reversal cost: medium (new capture path).
- **A narrow band at a fixed title height.** The title height follows the window height (358 in `-0002`, 141 in `-0019`), so no single row works. Reversal cost: low.
- **A single best marker match over the band.** In `-0019` the band holds five markers, and the best score can belong to a container title bar, which then rejects (costing the fallback) or matches a container item. Reversal cost: low (one branch in the job).
- **First accepted targeted entry wins.** The visit order is the marker score, so an accepted container title could beat the inspected item's better title match. Reversal cost: low.
- **Always run the fallback and rank everything.** It loses the latency the targeted pass exists for. Reversal cost: low.

## Consequences

- **Size.** The band is about a third of a 16:9 client (24 % at 3440x1440): 2280x1200 at 3840x2160. The 25,165,824 px capture cap binds first, not a width limit: the band area is about 684,000*s^2, which exceeds the cap at `s > 6.07`, about 11,650 px wide at 16:9. Beyond that the targeted capture fails with `captureTooLarge`, and the whole-client fallback fails too, as today.
- **Cost.** A targeted job now reads up to 8 titles in the single vision worker, under the existing 1.5 s deadline (ADR-0011). The expected targeted path is about 50 ms settle, capture and a job well under the 280 ms whole-client job. A superseding click is unaffected: supersession invalidates the vision request at once (ADR-0014).
- **M4 hotkey.** The region needs no cursor beyond the in-client guard, so a hotkey trigger can use it unchanged. Whether it keeps the fallback wait is still M4's call (ADR-0014).
- **Misses fall back.** A window outside the band, such as a container dragged far from the centre, ends in targeted `noMarker` or rejection and then the fallback, as before.
- **Unverified assumptions.** Only 3440x1440 was observed. On other aspect ratios the inspect window is assumed to stay centred on the client centre, and container cascades are assumed to open right of and below their parent. The offline replay over recorded scans and the user's live check test both.
- **Contracts that change.** The recorded `<id>-targeted.png` is band-sized (1519x800 at 3440x1440) instead of strip-sized; the corpus runner follows automatically because it calls `planTargeted`.
- **Reversal cost:** low. The region constants are the only tuning point, and widening the cascade margin is a one-constant change if misses cluster just outside the band.
