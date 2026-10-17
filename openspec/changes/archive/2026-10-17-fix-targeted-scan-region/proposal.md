# Proposal

## Why

Since the 50 ms settle wait landed (2026-10-10), it has accepted nothing: in the 2026-10-14 recording all 30 accepts came from the full-client fallback, and the 2026-10-17 retest repeated it (6 of 6, published in 400–430 ms). Its only two accepts, on 2026-10-10 before the settle wait, came from clicks that happened to land on a title, and one of them ("Grenade case") was a container window accepted as an item. The targeted marker scores were 0.15–0.71, against the .82 gate. The targeted region is the fork's cursor strip, `(x - m/2, y - m/2, m + r, m)` with `m = 50s` and `r = 600s` around the release point (ADR-0010). It holds the inspect window's title only when the click lands on that title. The inspect window does not open at the cursor: a direct inspect opens centred on the client, which the user confirmed on 2026-10-17. Every scan therefore pays the 200 ms fallback wait and a whole-client recognition, which puts the M4 latency gate out of reach.

This change serves **M4 - complete raid-time Scanner slice** (change 1). It advances these exit criteria:
- "The targeted pass accepts scans: … most accepts come from the targeted pass, not the full-client fallback."
- "targeted ≤300 ms p95 from trigger to decision, fallback visibly underway by about 300 ms, ≤1.5 s p95 total."

The recorded frames add a fact the roadmap entry did not have. An inspect opened from inside a container window (frames `20261017-130909-0019` and `-0023`) cascades from that window: the window sits 150–250 px right of centre at 3440×1440, and one or more container title bars, each with its own magnifier marker, stay visible beside it. The new region has to allow for that offset. Its recognition cannot assume a single marker.

## What Changes

- **The targeted region becomes a fixed band where the inspect window opens.** The band is placed around the client centre and scaled by `s = min(w/1920, h/1080)`. It is wide enough for the window plus a cascade margin, and it runs from the top of the client to just below its vertical centre. The region no longer depends on the cursor. The trigger point must still lie inside the client (an identity guard, unchanged). It stays in physical pixels, DPI-independent and clip-not-pad. **BREAKING** for the capture spec's region formula and for `CapturePlan` sizes. The fork's cursor strip is dropped on purpose.
- **Targeted recognition lists every marker peak in the region,** as the full-client pass does (at most 8 after suppression), instead of the single best match. A cascade of container windows puts several markers inside the band.
- **Ranking orders the targeted entries among themselves first.** The best-ranked targeted entry (acceptance, similarity, marker score, peak order) wins when it is accepted, and the fallback then does not run. Otherwise the fallback runs as today, and all entries are ranked together.
- **The settle and fallback waits stay at 50 ms and 200 ms (ADR-0014 unchanged).** The recorded targeted strips show the inspect window already drawn at the 50 ms settle (`-0003`, `-0006`), so no new deadline is introduced. The design records this as the evidence behind keeping it.
- **The full-client fallback stays** with its eligibility list unchanged (ADR-0013). It still covers windows dragged or cascaded outside the band.
- **A new ADR (0016)** records the centred region and the multi-peak targeted pass. It supersedes ADR-0010's region formula only (physical pixels, DPI independence and clipping stay). This differs from the roadmap's wording, which named ADR-0014: the region rule lives in ADR-0010, and the waits do not change.
- **Offline qualification over the recorded frames.** The 70 recorded scans in `%LOCALAPPDATA%\Blackgrid\scan-frames\` are replayed through the corpus runner with the new region, with the game not running, and compared with what the fallback accepted on the same frames. The runner already plans `targeted` cases with `planTargeted`. Live latency and the share of targeted accepts remain user-verified.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `inspection-capture`: "Targeted region is planned in physical client pixels" changes from the cursor strip to the centred band, with new resolution, negative-origin and clipping scenarios. The clipping and frame-layout scenarios that use the strip's sizes change with it.
- `inspection-recognition`: "Targeted recognition finds the best marker" becomes a multi-peak search over the targeted frame, with the same gate, suppression and 8-peak cap as the full-client pass.
- `item-title-matching`: "Targeted and fallback evidence are ranked into one outcome" ranks several targeted entries among themselves before the targeted pass may win alone.
- `scan-frame-recording`: the scenario sizes of the written targeted image follow the new region (the requirement text is unchanged).

## Impact

- **Code:** `lib/data/capture/capture_geometry.dart` (`planTargeted`), `lib/data/vision/inspection_recognition.dart` (targeted branch), `lib/domain/title_matching.dart` (`rankOutcome`) and their tests. `test/qualification/support/inspection_corpus.dart` picks up the region through `planTargeted`; its offline support tests change their expected crop sizes.
- **Latency:** the targeted pass now searches roughly a quarter to a third of the client instead of a 650×50 strip. This adds marker-search time but removes the 200 ms fallback wait and the whole-client pass on most scans.
- **Docs:** ADR-0016, the architecture's in-force ADR index (0016 row added, 0010 row marked as partly superseded), `docs/qualification/m2/CORPUS.md` (the targeted crop rule).
- **Not affected:** native capture DLL and its ABI, vision ABI (the peak primitive already exists), timing log schema v1, recording format v1, the scan coordinator's flow and waits, Scanner UI.
- **Verification boundary:** agent checks are unit tests and the offline replay of saved recordings. The live share of targeted accepts and the p95 latency need the game. They belong to the user and stay unverified until the user reports them.
