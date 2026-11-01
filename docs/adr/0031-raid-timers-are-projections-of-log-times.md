# 0031 - Raid timers are projections of log times

- Status: accepted
- Date: 2026-11-02 (change `add-raid-timers`)
- Source: change `add-raid-timers` (design D1, D3, D4, D5, D6, D7)

## Context and problem

M7 shows time in raid, the run-through countdown and the scav cooldown in Blackgrid's own window. `RaidLifecycleController` (ADR-0030) already follows the raid phase from the game's logs and publishes raid transitions with their log times; the bind-time replay of the newest session folder re-publishes the same transitions after every restart.

TarkovMonitor, the tool players compare against, counts from when it saw an event, works out the scav cooldown length once, and forgets a running cooldown when it closes. A late read, a restart mid-raid or a changed input then shows the wrong time. Blackgrid must survive the same events: a replay, a restart, missed ticks, a settings save that races a recorded cooldown, a settings record it could not read, and item data that lacks the cooldown inputs.

## Decision

- **Timers are computed from log times and the clock, never accumulated (D1, D7).** A pure function in `lib/domain/raid_timers.dart` computes every shown value from the lifecycle state, the stored settings, the cooldown inputs and one clock reading. `RaidTimersController` only gathers inputs, reads its injected clock and notifies. It owns one `Timer.periodic`, armed only while a shown value moves; a tick only triggers a recompute. The controller subscribes to `RaidLifecycleController.transitions` in its constructor, before the reader binds, so the bind-time replay's endings are not missed.
- **Timer settings and per-mode cooldown starts live in the settings record as a separately decoded `raidTimers` block (D3, D4).** The block holds the on/off switch, the shown timers, the run-through length, the Fence reputation per mode and the scav cooldown start per mode (UTC ISO-8601). `AppSettings.fromJson` decodes it in its own `try`: a missing or malformed block gives the timer defaults and keeps every other setting; inside a valid block a bad entry drops only that entry. `SettingsController` is the only writer of cooldown starts: `recordScavCooldownStart` keeps the later time per mode in a pending map and saves at once, or right after an in-flight save ends. **Every** `save` max-merges the starts with the stored and pending ones, so no writer can move a start back. A pending start leaves the map only when a save that contained it succeeds, and the timers read stored starts merged with pending ones. While the stored record is unreadable, a recorded start is never saved automatically; the user's first save writes it.
- **Cooldown inputs are an optional block on the catalog snapshot (D5).** The normalizer reads the base scav cooldown (`items` → `data.settings.scavCooldownSeconds`), Fence's reputation levels with their cooldown modifier (`traders`) and each hideout level's `ScavCooldownTimer` bonus (`hideout`) from json.tarkov.dev's REST datasets the catalog already downloads. tarkov.dev's deprecated GraphQL API is not used. A missing or malformed part, or more than 64 levels or 256 bonuses, makes the block `null`; the catalog stays valid. The JSON key is optional on load, and `schemaVersion` and `normalizerVersion` stay 1.
- **The active mode is the effective mode (D6).** The scav cooldown shown, its catalog and progress inputs, and the Fence reputation field in Settings use the app's effective mode (`MapSessionController.effectiveMode`: the mode detected from the logs, else the mode chosen in Settings), read as `catalog.mode`. A catalog or progress snapshot is used only when its mode matches. A raid ending records its own mode's start, whatever mode is active.

## Rejected alternatives

- **A stopwatch per timer, started on a transition and decremented per tick (D1).** A late read, a replay or a restart mid-raid starts it at the wrong time, and missed ticks drift.
- **A new Drift table for cooldown starts (D3).** Three rows do not justify a schema migration; the settings record is already the durable home for per-user preferences (ADR-0003).
- **Decoding the timer block with the record's throw-on-anything rule (D3).** A bad timer field would reset every other setting.
- **Saving starts through `save(settings.copyWith(...))` from the timers controller (D4).** `save` drops writes while busy, so a raid ending during a user's save would be lost; a second writer of the `Preferences` row would overwrite the first.
- **A separate download for the cooldown inputs, or a `normalizerVersion` bump (D5).** The data is already in fetched datasets, and a version bump would make every cached catalog non-authoritative until refreshed.
- **`settings.mode` as the mode (D6).** It is unknown by default when the mode comes from the logs, and would mix one mode's start with another mode's item data.

## Consequences

- **Restart-safe.** A restart mid-raid shows the same time in raid; a replayed ending leaves a stored start unchanged; a running cooldown survives a restart of Blackgrid or the game.
- **Stored format.** The `raidTimers` key in the settings payload and the `scavCooldown` key in the catalog snapshot are stored data; moving them later means reading the old keys once.
- **Unknown is honest.** Without item data the scav entry shows "unknown" with a reason; there is no guessed fallback length. Without Tracker progress for the mode, the length has no hideout bonus and says so.
- **Known limits.** Log times are local wall times, so a raid spanning a daylight-saving change is off by an hour. A raid left current because the game closed with no ending logged keeps counting until the next session folder.
- **Reversal cost:** low for the projection, the controller and the active-mode rule (internal); medium for the stored settings and catalog keys.
