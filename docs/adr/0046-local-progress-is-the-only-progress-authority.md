# 0046 - Local progress is the only progress authority

- Status: accepted
- Date: 2026-11-19 (change `retire-tracker-token`)
- Supersedes: 0007 (partly), 0031 (partly), 0041 (partly), 0044 (partly)
- Source: reviewed `retire-tracker-token` proposal and design D1, D3-D5, D7 and D10

## Context and problem

M9 gave Blackgrid its own progress: the event ledger (ADR-0041), the task catalog and availability rules (ADR-0042, ADR-0043), log ingestion into one active wipe per mode (ADR-0044, ADR-0045) and manual entry. Keep/sell advice and the scav cooldown still read a 15-minute snapshot fetched from the Tracker with a user token. Players therefore needed a token, a network call and a third-party account for advice, while the progress Blackgrid records itself went unused.

Four accepted ADRs leave that arrangement in place. ADR-0007 defines the `blackgrid/credentials` runner channel and the DPAPI token files. ADR-0031 takes the scav cooldown's hideout bonuses from Tracker progress. ADR-0041 and ADR-0044 state that Tracker remains the advice and timer authority. This change removes the Tracker integration and makes the active wipe's local progress the only source, so those statements stop being true. Accepted ADRs are immutable, so one new ADR records the cutover and the four older ones are marked "partly superseded" in the index.

## Decision

- **Advice input (D1).** A new immutable domain type `ProgressFacts` (`lib/domain/progress_facts.dart`) holds the facts advice needs for one mode: task states, objective counts and completions, station levels, player level, faction and edition. A new `ProgressAuthority` (`lib/application/progress_authority.dart`, a `ChangeNotifier`) follows the applied mode (`catalog.mode`), reads `LocalProgressAccess.readCurrent` on each mode, revision, load or availability change, and publishes `mode`, `status` (`loading`, `local`, `unavailable`) and `facts`. `DecisionEngine`, `InspectionContext` and the raid-timer code take `ProgressFacts`. `ProgressSnapshot`, `EntityProgress`, `ProgressController`, `TrackerClient` and the credential store are deleted. The engine stays synchronous and pure.
- **Unset defaults (D3).** `ProgressFacts` answers lookups with the unset defaults: a task with no state is not started, an objective count is 0 and its completion false, a station level is 0 (not built). Player level, faction and edition stay nullable. The engine follows ADR-0043's order. A finished task is satisfied. A failed task is satisfied unless the progress catalog marks it restartable, in which case it continues as not started. A started task skips the gates and is actionable. Anything else continues through the gates as not started. A hideout need is satisfied when the recorded level reaches the required one; otherwise every part counts 0 and the full item count remains. A gate minimum level of 1 or less passes without a recorded level; a higher minimum with no recorded level is unknown. An unset faction makes only faction gates unknown. Scav cooldown bonus keys `<stationId>-<level>` count when the recorded station level reaches the key's level.
- **Edition gates (D4).** A requirement whose gate lists any `editions` or `editionIds` gets an unknown gate (unresolved), whatever edition is recorded. Edition-gated needs that the Tracker's numeric edition used to decide now show Check.
- **Status during reads (D5).** `status` is `loading` from launch or a mode change until the first read for that mode ends, including while local progress is still opening. It then becomes `local` or `unavailable`. An unknown mode, a `loadError` or an unavailable mode is `unavailable`. A re-read for the same mode after a revision keeps the last facts and `local`. A failed read publishes `unavailable` and clears the facts. A newer request during a read sets a dirty flag and reads again afterwards, so one read is in flight. A generation counter drops a result whose mode changed meanwhile. While `loading` or `unavailable`, advice gets no facts and says progress is unavailable. There is no age window, because local progress is not a remote snapshot.
- **Runner channel (D7).** The runner method channel is renamed `blackgrid/local_data` and keeps only `localDataPath`. `protect`, `unprotect` and `atomicReplace` are removed. `credential_protector.{h,cpp}` become `local_data_channel.{h,cpp}` and `RegisterCredentialProtector` becomes `RegisterLocalDataChannel`. The runner keeps no DPAPI code. Saved token files are deleted at startup by Dart code (design D6), which is recorded in the change design, not here.

## Rejected alternatives

- **D1:** Synthesising a `ProgressSnapshot` from local winners and leaving the engine untouched. The Tracker fields (owner, credential session, ETag, `invalid`, the 15-minute window, `parts`) would have to be faked, and a later reader could mistake them for facts. Making `DecisionEngine` asynchronous and reading the store per evaluation was also rejected: it moves I/O into a pure domain function and into every history re-projection.
- **D3:** Keeping the engine's "entry missing, so unresolved" branches and materialising explicit zero entries for every catalog ID. That builds a map the size of the catalog per read, only to encode "unset". Running started tasks through every gate, and satisfying every failed task, were rejected in review round 1 in favour of ADR-0043's order. "Unknown until entered" for every unrecorded fact was rejected by the owner: it would leave most verdicts at Check for a player who has not replayed logs.
- **D4:** Comparing the recorded ADR-0043 edition ID with `editionIds`. Whether tarkov.dev's list means allowed or excluded editions is unverified, and a wrong "does not apply" can make a player sell a needed item.
- **D5:** Publishing `unavailable` during loading, which would show "unavailable" at every launch. Clearing facts on every re-read, which would flicker verdicts to Check after every progress tick.
- **D7:** Keeping the `blackgrid/credentials` name with one method left. It names something the app no longer does, and ADR-0007's credentials boundary would read as still in force.
- **One ADR per affected ADR:** four near-identical records.
- **Import from the site (proposal S1):** a one-time opt-in import of Tracker progress was rejected by the owner on 2026-11-19. The token is removed outright.

## Consequences

Blackgrid makes no request to the Tracker, stores no token and needs no account for advice or timers. A player who never replayed logs or entered progress sees every task as not started, so advice errs toward Keep for items already used. The release notes and the Local progress section point to log replay. Hideout items are over-counted for partly stocked levels until the level is built, which also errs toward Keep. `ProgressFacts` grows with the catalog's tasks, objectives and stations, not with time, and the store already pages reads (ADR-0041).

What this supersedes, and what stays:

- **ADR-0007:** the DPAPI current-user token protection, the credential token files and the `protect`, `unprotect` and `atomicReplace` methods. The runner-channel and standalone-FFI-DLL boundary, the `localDataPath` method and the panel-OCR DLL decisions remain, and the channel is now `blackgrid/local_data`.
- **ADR-0031:** the use of Tracker hideout progress for the scav cooldown bonuses. Timers stay projections of log times and one clock reading, and the applied mode is still `catalog.mode`.
- **ADR-0041:** the clause "Tracker coexists unchanged", including the deferral of the advice and timer cutover. The ledger, registers and winner rules are unchanged.
- **ADR-0044:** the statement that Tracker remains the advice and timer authority. Active wipes, queueing and log identities are unchanged.

The legacy settings key `trackerEnabled` is read and ignored, and trader loyalty stays out of advice, as before. Both are covered by the change design, not by this record.
