# Tasks

## Test map

Rows record exercised offline checks against schema 8. Existing newer-database refusal coverage is reused rather than duplicated or forced to fail. No scenario requires the game, app launch or owner sign-off. The M9 real-log/checklist criterion remains at milestone close as explained in the proposal.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Local cycles and device identity survive restart | Create and reopen cycles | `test/data/local_progress_store_test.dart` | `cycles and device identity survive reopen without replacing history` | green |
| Local cycles and device identity survive restart | Wrong scope | `test/data/local_progress_store_test.dart` | `missing unknown and mismatched scopes reject atomically` | green |
| Events have a portable versioned identity | Event round trip | `test/domain/local_progress_test.dart` | `named event codec round trips every envelope field` | green |
| Events have a portable versioned identity | Unsupported or malformed envelope | `test/domain/local_progress_test.dart` | `invalid versions sources targets and values are rejected` | green |
| Accepted values remain encodable in compensation | Largest edition survives repeated undo | `test/data/local_progress_store_test.dart` | `maximum encoded edition survives undo and undo of compensation` | green |
| Accepted values remain encodable in compensation | Escaped token exceeds budget | `test/data/local_progress_store_test.dart` | `over-budget escaped tokens reject the entire batch` | green |
| Progress values are independent typed registers | Independent objective fields | `test/domain/local_progress_test.dart` | `absolute objective counts do not replace completion` | green |
| Progress values are independent typed registers | Unset and invalid counts | `test/domain/local_progress_test.dart` | `unset wins without resurrection and negative counts reject` | green |
| Replays are idempotent and batches are atomic | Duplicate batch | `test/data/local_progress_store_test.dart` | `identical replay and intra-batch duplicates store each event once` | green |
| Replays are idempotent and batches are atomic | Conflicting identity or failed commit | `test/data/local_progress_store_test.dart` | `conflicting global identity and failed commit roll back batch and heads` | green |
| Newest field value wins deterministically | Log and manual precedence | `test/domain/local_progress_test.dart` | `event permutations preserve time-first and equal-time log precedence` | green |
| Newest field value wins deterministically | Equal-time deterministic ties | `test/domain/local_progress_test.dart` | `device and event identity ties converge in either arrival order` | green |
| Current values are reproducible and isolated | Rebuild after reopening | `test/data/local_progress_store_test.dart` | `rebuild matches incremental winners across modes and cycles after reopen` | green |
| Current values are reproducible and isolated | Interrupted rebuild | `test/data/local_progress_store_test.dart` | `failed rebuild rolls back heads and preserves immutable event bytes` | green |
| Current-value pages use one revision snapshot | Stable page continuation | `test/data/local_progress_store_test.dart` | `current-value continuation returns each register at one revision` | green |
| Current-value pages use one revision snapshot | Commit races the final page | `test/data/local_progress_store_test.dart` | `second-instance commit cannot mix revisions during the final page` | green |
| Undo appends a guarded compensating event | Undo current value | `test/data/local_progress_store_test.dart` | `undo appends the predecessor value and retains original facts` | green |
| Undo appends a guarded compensating event | Undo first value and retry | `test/data/local_progress_store_test.dart` | `undo first value records unset and repeated request returns one compensation` | green |
| Undo appends a guarded compensating event | Stale undo | `test/data/local_progress_store_test.dart` | `stale undo cannot erase a later winning event` | green |
| History failures do not become partial progress | Readable cycle | `test/data/local_progress_store_test.dart` | `opening valid history returns its actual projection and history` | green |
| History failures do not become partial progress | Damaged or future event | `test/data/local_progress_store_test.dart` | `malformed future and envelope-mismatched stored events make the cycle unavailable` | green |
| Operations are bounded without discarding history | Paged history | `test/data/local_progress_store_test.dart` | `history high-water cursor excludes concurrent appends without omissions` | green |
| Operations are bounded without discarding history | Busy or oversized operation | `test/data/local_progress_store_test.dart` | `busy and record-byte-page limits reject without partial work` | green |
| Database upgrade preserves existing application behavior | Upgrade and reopen | `test/data/migration_test.dart` | `schema 7 upgrades to 8 preserving existing records and permitting scoped progress writes` | green |
| Database upgrade preserves existing application behavior | Newer database | `test/data/migration_test.dart` | existing `newer schema reaches the second query as NewerDatabaseException without byte mutation` and `newer schema refuses without downgrade reset deletion or byte mutation` | green |

## 1. Record the local-progress architecture decision

- [x] 1.1 Write ADR-0041 `docs/adr/0041-local-progress-event-ledger.md` from the reviewed decisions, and update `openspec/architecture.md` with its accepted index row, local-progress ownership/interface and planned schema-8 storage contract without changing accepted ADRs. Verify that the ADR agrees with the approved design and that the index, cycle identity, event format, conflict order, compensation, derived winners and Tracker coexistence are consistent.

## 2. Pure event model, encoding and projection

- [x] 2.1 Add failing `test/domain/local_progress_test.dart` cases named in the test map for envelope round trip, malformed inputs, independent fields, unset and ordering. Include all target/value families, same-time ties, late events and finite event permutations; verify failures identify missing behavior rather than a broken fixture.
- [x] 2.2 Implement `lib/domain/local_progress.dart` and `lib/domain/local_progress_store.dart`: typed field/value/event/cycle records, named version-1 canonical codec, pure comparator/fold, paged cursor/result types and sealed failures. Add public `///` documentation for scope, ordering, IDs, unset, retry and failure semantics. Verify the domain rows pass and turn them green; these libraries must import no Flutter, SQL or Windows APIs.
- [x] 2.3 Add codec boundary cases and enforce the reviewed identity/text token budgets, encoded event cap, exact integer range and supported timestamp width. Prove fixed-envelope headroom across valid target/value shapes, including JSON-escaped multibyte/control text and maximum-width timestamps/IDs; verify exact-boundary acceptance, one-byte-over rejection, no truncation, and compensation-shaped events below the event cap. Document these invariants beside the codec; do not add catalog/edition rules or new dependencies.

## 3. Durable ledger, paged projection and undo

- [x] 3.1 Add the failing schema-7 upgrade/reopen test in `test/data/migration_test.dart`, seeding representative preferences, pins, activity, catalog, icon, map-cache, import and statistics records. Assert retained values and empty new progress tables, then a valid scoped progress insertion and a rejected mode mismatch. Verify the test fails because the schema-8 storage/migration is absent.
- [x] 3.2 Add the reviewed progress tables, candidate keys, foreign keys and indexes to `lib/data/database.dart`; advance the explicit migration chain to schema 8 without resetting old records. Regenerate `database.g.dart`, export the new `drift_schemas/` snapshot and regenerate `test/data/generated/` fixtures using the pinned toolchain. Verify migrations from the existing supported schema fixtures, the seeded upgrade/reopen test and the existing newer-schema refusal tests; turn the migration rows green without duplicating existing protection tests.
- [x] 3.3 Add failing real-SQLite cases in `test/data/local_progress_store_test.dart` for persistent identity/cycles, rejected scopes, exact replay, contradictory IDs within/across batches and scopes, and failure rollback of both history and heads. Use temporary file databases for reopen assertions and synthetic tiny event fixtures. Verify the new tests fail on the absent local-progress behavior.
- [x] 3.4 Implement explicit cycle/device operations and validated atomic event append in `BlackgridDatabase`, including canonical duplicate comparison, global event uniqueness, winner updates, per-cycle revision and the shared busy admission gate. Use injected clock/ID generators and return the documented failures; add API documentation. Verify the corresponding store rows pass and turn them green; replay must not advance revision or alter event bytes.
- [x] 3.5 Add failing store cases for opening readable/damaged/future/envelope-mismatched history, rebuild equivalence and interruption, history high-water paging, revision-bound current pages, size/page/batch/busy rejection, and another database instance racing the final page. Build concurrency and fault fixtures from explicit completers/barriers over a real SQLite executor, not sleeps. Use a file-backed WAL fixture when a second connection must commit during a read snapshot. Verify the tests expose missing paging/integrity/rebuild behavior and the revision race without mocking returned rows.
- [x] 3.6 Implement bounded history/current/cycle queries, scoped validation/rebuild, the one-token validation cache, and snapshot-consistent revision/token checks plus decoded rows. Do not hold a transaction between calls or add a retry/operation queue. Rebuild must preserve event bytes and atomically replace only the named scope's heads. Verify all query/rebuild/failure/bounds rows pass and turn green, including changed-revision rejection before a continuation and a commit between check/read on both intermediate and final pages.
- [x] 3.7 Add failing store cases for guarded undo, first-value unset, duplicate request retry, stale targets, maximum encoded edition/identities/timestamp widths, undo of a compensation and atomic rejection of escaped over-budget input. Include retry after the compensation's result was lost and after another event subsequently wins. Verify the tests fail for absent compensation behavior, not timing.
- [x] 3.8 Implement transactional predecessor selection and linked compensation, stable request-ID replay, checked later timestamp and no history mutation. Complete the `LocalProgressStore` implementation and document its undo/read/error guarantees. Verify every remaining undo/encoding row passes and turns green; undo cannot overwrite a stale target, exceed the format budget, or resurrect an older value behind unset.
- [x] 3.9 Update existing user/developer storage documentation (README or the existing storage section) to explain locally generated progress cycles, durable event history, explicit failures and unchanged Tracker-backed behavior. Keep `proposal.md` release notes accurate and pass `mise run release-notes -- --check openspec/changes/add-progress-store/proposal.md`; no new tracker screen, reset control or token migration is implied.

## 4. Offline integration verification

- [x] 4.1 Exercise the real store interface with a temporary offline smoke script: create cycles in two modes, append out of order, replay, page, close/reopen, rebuild and undo, asserting projected values and winner IDs. Also measure bounded-memory page/rebuild behavior on synthetic 10x/100x histories using streamed batches, recording observed timings without imposing an unevidenced threshold. Keep a long-running variant outside the fast loop or tag a retained expensive test `qualification`; remove the throwaway script afterward. No app or game launch is required.
- [x] 4.2 Run `dart format` through the pinned environment, `mise run analyze` and `mise run test`; use focused mapped checks during implementation and the full required offline checks here. Verify the existing Tracker/advice/timer tests still pass without modifying their authority contracts. Run `openspec validate add-progress-store --strict` and the release-notes check, and confirm all 25 scenario rows are green with exercised evidence. Do not add a version bump: Specwright releases are disabled for this change.

### Exercised offline evidence

- Initial focused domain/migration/store suites: 44 tests passed; all 25 scenario rows above are green. Real WAL/deferred-reader barriers exercised commits between revision checks and rows on intermediate and final pages; no returned SQL rows were mocked.
- Throwaway `mise exec -- dart run .tmp/progress_smoke.dart <events>` passed at both scales on the pinned Dart 3.13.7 toolchain. It exercised two modes, out-of-order append, exact replay, history/current paging, close/reopen, scoped rebuild and guarded undo/retry through `LocalProgressStore`. The script and temporary file databases were removed afterward.
- Scale histories were streamed in batches/pages of at most 256, with 64 current registers. RSS observations include the Dart VM and native caches, not a heap cap; no unevidenced time or memory threshold was imposed. No app or game was launched.
- Final pinned `dart format` reported no changes; `mise run analyze` reported no issues; `mise run test` passed 3120 tests after PR feedback round 1, with qualification excluded. Existing Tracker/advice/timer consumers and authority contracts were not changed. `openspec validate add-progress-store --strict` and the release-notes check both passed. Initial analyzer infos were resolved with Dart LSP mechanical code actions before the successful full run; no warning was suppressed.
- Pre-ship F1 exposed malformed UTF-16 identities that JSON escaped but SQLite UTF-8 TEXT could not preserve. A real-store atomic-rejection regression and an all-identity-fields codec regression were red before the fix. Well-formed Unicode validation now rejects unpaired surrogates without normalization; valid surrogate pairs persist through history, undo and reopen. The domain/store focused suites passed 29 tests after this fix; the final full run also covers malformed high-surrogate/non-low-surrogate pairs.
- PR #110 feedback round 1: the pure fold now uses `(ProgressScope, ProgressTarget)` keys, preserving mode/cycle isolation even when histories are combined. All four callers migrated; a mixed-mode/mixed-cycle permutation regression failed with the former target-only key and then passed. The focused domain suite passed 9 tests, and the full offline validation passed 3120 tests.

| Events | Append ms | History ms | Rebuild ms | Baseline RSS bytes | Observed RSS bytes | Process max RSS bytes |
|---:|---:|---:|---:|---:|---:|---:|
| 100000 | 18640 | 1375 | 5702 | 313593856 | 321089536 | 370049024 |
| 1000000 | 205635 | 18436 | 56556 | 310374400 | 321036288 | 371326976 |

## Workflow follow-up

- Apply starts only after a new user request, under `specwright-commit`; run login: `KintsugiBot`.
- Follow the configured pre-ship review, PR and archive workflow after implementation. M9's real-log/checklist/live-scan checks remain owner-only at milestone close; this change introduces no user task and claims no live-game verification.
