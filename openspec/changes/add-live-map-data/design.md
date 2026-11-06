# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components | yes | New map-data controller/client/store and shared normalizer connect AppServices, map, Settings and offline builder. |
| T2 State | yes | `lib/data/database.dart:195-255` has mode caches; this adds persistent snapshots and refresh states. |
| T3 Concurrency | yes | Startup, mode switches, HTTP, database and isolate normalization overlap (`lib/application/app_services.dart:272-298`). |
| T4 Boundaries | yes | Six external JSON resources, SQLite migration, isolate messages and shared offline/runtime normalization. |
| T5 Volume | yes | Upstream collections can grow; transfer and work must be bounded. |
| T6 Risk | yes | SQLite contains irreplaceable pins and other user data, so a cache migration must preserve them. |

TIER: FULL

## Context

See `proposal.md` for scope and the three delta specifications for normative behavior. `PreparedMapPackLoader` loads the active bundled generation and its map inventory (`lib/maps/prepared_map_loader.dart:28-149`); `PreparedMap` combines scene properties and markers (`lib/maps/prepared_map.dart:300-360`). `MapController` binds these and caches projected marker positions (`lib/application/map_controller.dart:155-224`); `map_workspace.dart` uses it for browsing and rendering. `CatalogController` already demonstrates per-mode singleflight and generation fences (`lib/application/catalog_controller.dart:33-167`); `AppServices` owns background refresh and lifetime, and `settings_dialog.dart:189-237` provides the existing separate item-data action. `database.dart:195-255` shows transactional mode cache persistence. `tool/maps/pack.dart:1220-1285,2050-2310` already derives quests and marker facts from the six sources. The active bundled pack remains indispensable for artwork and is never replaced by a cache.

A live regular-mode probe supplied by the orchestrator observed six HTTP 200 JSON responses with ETags followed by 304 on revalidation: maps 9,053,178 bytes, maps_en 24,204, tasks 2,116,046, tasks_en 252,682, traders 58,898 and traders_en 3,537. The maps root has `data.maps`; tasks has `data.tasks` and `data.questItems`; trader data is an object keyed by IDs, not `data.traders`; English `data` values are dictionaries. Other observed roots and keys are not themselves required merely because present. Probe evidence is not a frozen content contract.

## Decisions

### S1: Effective-mode snapshots
- **Choice:** Independent regular, PvE and seasonal PvP snapshots, with honestly labelled regular bundled fallback.
- **Rejected:** One regular snapshot for every mode because it misstates the selected mode's facts.
- **Reversal cost:** medium.
- **Important:** yes, visible behavior and future contract.
- **Chosen by:** user.

### S2: Last-good without expiry
- **Choice:** Compatible last-good data remains usable regardless of age; otherwise use the bundle.
- **Rejected:** Expire or discard old data on failure, which loses valid offline information.
- **Reversal cost:** low.
- **Important:** yes, visible behavior.
- **Chosen by:** user.

### S3: Immediate coherent activation
- **Choice:** Publish complete content immediately, preserve view and user state, clear marker selection on content replacement.
- **Rejected:** Wait for restart, leaving corrected data unapplied.
- **Reversal cost:** medium.
- **Important:** yes, visible behavior and publication contract.
- **Chosen by:** user.

### S4: Independent refresh and status
- **Choice:** Background startup/mode refresh and separate Settings action/status; no polling, auto-retry or toggle.
- **Rejected:** Combined item/map control, which conflates independent failures.
- **Reversal cost:** low.
- **Important:** yes, visible behavior.
- **Chosen by:** user.

### S5: Prepared artwork boundary
- **Choice:** Only metadata refreshes; artwork inventory, calibration and labels remain prepared.
- **Rejected:** Runtime artwork acquisition or automatic new-map integration, which crosses the calibrated-art boundary.
- **Reversal cost:** high; this is a user-approved scope and boundary rather than a weak-evidence choice.
- **Important:** yes, binds future changes.
- **Chosen by:** user.

### S6: Upstream owns metadata content
- **Choice:** Admit structurally valid current metadata changes in both runtime and offline workflows; make historical floor overrides conditional.
- **Rejected:** Historical identities, counts, coordinates or hashes as admission criteria, which reject legitimate upstream changes.
- **Reversal cost:** medium.
- **Important:** yes, visible behavior and future contract.
- **Chosen by:** user.

### S7: Shared runtime facts
- **Choice:** Keep complete immutable facts once per runtime snapshot and let lightweight per-occurrence markers reference them locally, preserving source identities for later quest work without adding quest tracking.
- **Rejected:** Continue expanded per-marker copies, raise the approved resource caps or accept rejection of the complete baseline dataset.
- **Reversal cost:** medium; runtime encoding and local fact resolution.
- **Important:** yes, binds future changes and resource behavior.
- **Chosen by:** user.

### D1: Transactional mode cache
- **Choice:** Add versioned Drift cache records storing the six raw bodies, validators, normalized snapshot, integrity evidence and compatibility fingerprint per mode; commit atomically separately from user records.
- **Rejected:** Separate cache files and pointer, requiring another atomicity/recovery protocol beside SQLite.
- **Reversal cost:** medium.
- **Important:** yes, stored data and compatibility contract.
- **Chosen by:** user.

### D2: Shared pure normalization
- **Choice:** Extract the existing marker and quest normalization from `tool/maps/pack.dart` to a runtime-safe pure Dart module used by both builder and runtime; apply conditional overrides there.
- **Rejected:** A new runtime-only parser, which would diverge on label rules, boss multiplicity and floor handling.
- **Reversal cost:** medium.
- **Important:** yes, shared boundary and output contract.
- **Chosen by:** user.

### D3: Six-source conditional transaction
- **Choice:** Revalidate each of six mode endpoints with ETag, otherwise Last-Modified, otherwise unconditional; reuse a usable cached body for 304 only, then normalize and commit the complete candidate.
- **Rejected:** Independent per-source activation or full unconditional downloads, which risk mixed generations or waste repeated transfers.
- **Reversal cost:** medium.
- **Important:** yes, external/cache protocol.
- **Chosen by:** user.

### D4: Supersede only obsolete ADR boundaries
- **Choice:** During apply record a new ADR partly superseding ADR-0005's offline-only marker boundary and ADR-0034's runtime-data prohibition and historical marker-preservation gate, and update the architecture index. Retain artwork preservation and ADR-0033 frozen reproduction.
- **Rejected:** Rewrite accepted ADRs or retain their contradictory marker restrictions, which destroys history or prevents the approved change.
- **Reversal cost:** medium.
- **Important:** yes, durable architectural boundary.
- **Chosen by:** user.

### D5: Compact runtime facts with incremental budgets
- **Choice:** Normalize directly into lightweight runtime marker records referencing a snapshot-owned immutable fact pool. Retain complete source and derived facts, logical marker IDs and quest/objective/item identity, local detail lookup and the unchanged frozen offline format. Keep the 256 MiB materialization and 64 MiB serialization limits, enforced before allocation at every runtime stage.
- **Rejected:** Retain the expanded runtime representation or raise its cap: full frozen-data qualification demonstrated that valid baseline data cannot fit the approved bound even after temporary reservation lifetimes were repaired. Expanding first and compacting afterward, or reconstructing full per-marker trees when reading a compact cache, retains the same failure.
- **Reversal cost:** medium.
- **Important:** yes, user-visible resource failures and cache/publication contract.
- **Chosen by:** user.

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|---|
| S1 | Mode | Independent snapshots and honest fallback | One regular snapshot | medium | yes | user |
| S2 | Fallback | Last-good regardless of age | Expiry or discard | low | yes | user |
| S3 | Activation | Immediate coherent swap | Restart activation | medium | yes | user |
| S4 | Scheduling | Separate background/manual status | Combined item refresh | low | yes | user |
| S5 | Artwork | Prepared-only artwork and labels | Runtime artwork admission | high | yes | user |
| S6 | Content | Accept structurally valid upstream evolution | Historical content gates | medium | yes | user |
| S7 | Runtime facts | Shared immutable records and local marker references | Expanded copies or a higher cap | medium | yes | user |
| D1 | Cache | Atomic Drift mode snapshots | Separate files | medium | yes | user |
| D2 | Parser | Shared pure normalizer | Parallel parsers | medium | yes | user |
| D3 | HTTP | Six conditional bodies as one transaction | Partial activation/unconditional only | medium | yes | user |
| D4 | ADR | Superseding ADR and index | Rewrite or retain conflict | medium | yes | user |
| D5 | Representation | Direct compact runtime facts plus unchanged incremental budgets and frozen offline output | Expanded runtime copies, expand-then-compact or raising the cap | medium | yes | user |

## Diagrams (FULL)

### T1: Components
```mermaid
flowchart LR
  UI[Settings and map UI] --> MC[MapController]
  AS[AppServices] --> DC[Map-data controller]
  UI --> DC
  DC --> HTTP[Conditional map client]
  DC --> DB[(Drift mode cache)]
  HTTP --> N[Shared pure normalizer]
  N --> DC --> MC
  Pack[Prepared pack loader] --> MC
  Tool[Offline pack builder] --> N
  HTTP --> Upstream[json.tarkov.dev]
```

### T2: State
```mermaid
stateDiagram-v2
  [*] --> Fallback: bundle loaded, no compatible cache
  [*] --> LastGood: compatible cache loaded
  Fallback --> Refreshing: automatic or manual
  LastGood --> Refreshing: automatic or manual
  Refreshing --> LastGood: all validated and committed
  Refreshing --> LastGood: failure with last-good
  Refreshing --> Fallback: failure without last-good
  LastGood --> Fallback: mode change without compatible cache
```

### T3: Concurrency
```mermaid
sequenceDiagram
  participant A as AppServices
  participant C as Map-data controller
  participant H as HTTP
  participant I as Normalizer isolate
  participant D as Drift
  participant M as MapController
  A->>C: select mode / background refresh
  C->>M: compatible cache or bundled fallback
  C->>H: bounded conditional six-source acquisition
  H-->>C: complete bodies or failure
  C->>I: validate and normalize off UI isolate
  I-->>C: candidate
  C->>D: atomic per-mode commit
  D-->>C: committed
  C->>M: publish only if selected generation still current
```

### T4: Data boundary
```mermaid
flowchart TD
  B[Six HTTP bodies + validators] --> V[Structure and parser validation]
  P[Prepared map mapping and calibration] --> N[Shared normalization + conditional overrides]
  V --> N
  N --> C[(Atomic raw bodies + hashes + normalized data)]
  C --> G[Active coherent marker generation]
  F[Frozen offline source closure] --> V
  N --> O[Prepared metadata candidate]
  O --> R[Reproduce against candidate source]
  Art[Baseline artwork and calibration] --> R
```

## State & Ownership (FULL)

| State | Owner (sole writer) | Lifetime | Invalidation / rebuild | Authoritative copy |
|---|---|---|---|---|
| Mode cache: bodies, validators, hashes, normalized data, compatibility, check time | Map-data controller through Drift transaction | Durable, one per supported mode | Replace only as complete transaction; reject corrupt/incompatible records and reacquire | Committed SQLite row/set for that mode |
| Effective mode and refresh operation/status | Map-data controller, composed by AppServices | App lifetime | Selection generation changes; dispose cancels/ignores late work | Controller for current mode; cache is durable evidence |
| Active marker generation and projections | MapController | App lifetime | Atomically swap inventory; clear position cache, selection and linked highlights; recompute all queries | Current immutable snapshot, or loaded bundle fallback |
| Map view, selected floor and pin/filter settings | Existing map/settings owners | Session or existing durable lifetime | Existing user actions only; metadata replacement does not reset | Existing settings/SQLite and view state |
| Artwork, map geometry and calibration | Offline pack tooling | Bundled generation | Existing explicit validated promotion | `active.json` and its generation |
| Frozen metadata source closure | Offline pack tooling | Candidate/generation | New acquisition or explicit rebuild | Candidate's carried source bytes and hashes |

**Compatibility and cache integrity.** Fingerprint the stored serialization format and normalizer version plus actual map-ID mapping, floor/override assumptions and calibration fields needed to project or assign markers. Do not key on compiler package versions, bundle generation hash or artwork-only changes. Bind each raw body and normalized payload to recorded digests; require all six mode-matching bodies, their validator records (which may contain no validator) and a fully decodable normalized inventory. Reject altered, truncated or inconsistent cache data, not merely a bad version. When compatibility changes, discard cache authority and validators, use bundle, and rebuild only through a fresh complete acquisition. SQLite migration adds only cache tables/schema snapshots; preserve preferences, pins, history and other existing records. Rollback leaves the prior snapshot usable.

**Shared normalization and offline cutover.** Separate source decoding/normalization from file I/O and compiler-dependent code in `tool/maps/pack.dart`; both callers pass the six bodies and prepared mapping/calibration inputs. Validate only roots, keys and field types actually needed by the parser. Present-but-empty collections and dictionaries are valid. An absent member in a valid dictionary or a removed referenced quest, trader, item or translation ID is content evolution, not an absent required root or a historical referential-completeness failure: retain existing unavailable-name or optional-fact omission behavior and never invent facts. Fail on malformed present consumed records; do not drop them silently. Supported artwork inventory drives display: absent source map yields empty markers; unsupported source maps do not become display maps. Retain existing category and translated-name derivation, quest and trader linkage, deterministic IDs and every source boss position occurrence, including duplicates. Validate candidate output against its own source, not against historical semantic facts.

For historical overrides, find the marker in the new normalized source, then match the reviewed identity and placement evidence. Interchange's console requires the matching complete `sourceVolume`/outline; Icebreaker Helicopter and C-1, which lack that volume, require matching bundled reviewed identity and position/height and relevant source/key identity evidence (`docs/qualification/m3/PLACEMENT_CONTROLS.md:35-44,90-113`). A missing or changed record gets no override and uses `MapFloorSelection`'s existing floor/height policy. Do not insert a marker because an override exists or reject a candidate because the override no longer applies. Retain provenance for matching overrides; source parity is not independent placement proof.

Update offline metadata renewal, validation, preservation and fresh-artwork staging entry points in `tool/maps/pack.dart` to stop treating source-map completeness and reviewed marker ownership as historical metadata gates. Preserve independent complete artwork identity/admission, verified active baseline, six-source replacement, nonmetadata bytes/properties, source closure, hashes and exact-candidate promotion. Frozen checks compare each candidate to its own recorded bytes, and reproduction remains byte-for-byte; they never compare a fresh response to old content hashes. Existing builder fixtures and regression assertions that freeze historical marker content must be revised to test source fidelity and S6 instead.

**Compact runtime representation.** The user approved compaction after full frozen-data qualification exposed the expanded representation's resource mismatch. One snapshot owns immutable fact records; lightweight marker records reference those records instead of recursively duplicating source tasks, objectives, traders, items, locations and other nested facts. Reuse only identical complete facts; do not merge markers or distinct source identities. Marker occurrence IDs, category/filter keys, display names, positions, outlines, height/floor policy, source paths and complete `source.originalIdentity` tuples remain logically unchanged. Pool references are snapshot-local storage identities, never quest or other business identities. Preserve omitted optional fields, unknown source fields and exact string code units. No quest-tracking feature is added.

A shared semantic marker traversal supplies two output sinks: the existing frozen offline representation and direct compact runtime construction. Do not introduce a parallel parser or allocate an expanded serialized runtime inventory as an intermediate. A versioned runtime codec owns unambiguous reference encoding, pool validation and immutable local fact resolution. Validate all references, map coverage, marker identities and container shapes; reject missing/out-of-range targets, cycles or ambiguous tags without authority changes. Treat source dictionaries as data, never reference instructions. Bump runtime format compatibility so obsolete expanded caches and their validators are rejected and reacquired; do not add a legacy shim or change the SQLite user schema merely for a BLOB format change.

The worker should decode the bounded raw bodies in its own isolate rather than keep a redundant decoded source graph in the caller while copying it into the worker. Account raw transfer copies, source graphs, compact tables, reference slots, transient encoding/decoding buffers, validation and concurrently retained generations. Transfer only bounded owned output. Publish immutable shared records directly: nested map/list access used by popups, recursive search, quest/trader filters, switch links and raid aliases resolves locally without a network request or a deep copy for every marker. Equality compares logical facts, not pool indices or record ordering, and remains solely a selection-clearing decision. Include retained pools once per actual owned representation and charge every genuinely copied node/reference/container; compact storage is not permission to discount an expanded intermediate.

**Derived consumer state.** Search must also remain compact: replace eager per-marker flattened `searchText` strings with a fact-aware shared search representation or bounded traversal over shared text segments. Retain exactly the existing searchable scalar facts, geometry exclusions, case-insensitive substring/phrase behavior and comma-separated OR semantics, including matches crossing the spaces between scalar values. Do not drop complete task or unknown source facts from search to save memory. Shared normalized text/segments belong to one immutable inventory generation; bound query memoization to the current query rather than accumulating past queries. Retire derived state with that generation and fence stale results. Charge genuinely owned normalized strings, segment/reference collections, query metadata, projection records and transient construction buffers before allocation, including overlapping old/new derived generations, under the same 256 MiB budget. Large shared searchable facts must remain shared through real publication and search; genuinely oversized distinct derived state must reject before durable commit or activation.

**Publication.** AppServices loads the bundle as before and starts background work without awaiting network. After pack load, resolve effective mode and load compatible cached data; a generation fence prevents an older cache read from replacing a newer successful refresh. Unknown mode makes no mode-specific request and shows labelled regular bundled fallback until effective mode becomes known. On selected-mode changes, immediately remove the previous mode's authority and use its own compatible cache or fallback, then schedule refresh. Commit may complete for an obsolete mode as that mode's last-good data, but cannot publish into the current display. `MapController` swaps one immutable inventory across maps, rebuilds derived categories/projections and invalidates `_markerPositions` even if map ID is unchanged; all marker lookup, browser, hit tests, filters and popup metadata read that same generation. Preserve map, transform, floor, pins and filter preferences. Clear selection only on content replacement, not a 304 check with unchanged content; stale browser results are generation-fenced. Do not reload artwork or conceal pack load errors.

## Failure & Visibility (FULL)

| Component | Fails / dies mid-operation → | Recovery | Retry safe? | Who finds out |
|---|---|---|---|---|
| Bundle loader | Missing/incompatible active pack → map unavailable, not replaced by metadata cache | Existing pack repair/reinstall | Existing loader retry | User sees map load error |
| Cache read/integrity | Corrupt or incompatible cache → ignore snapshot and validators, show bundled fallback | Fresh explicit/automatic refresh | Yes; no automatic retry after failure | User sees source and cache failure in map-data status |
| HTTP client | Request, limit, redirect, deadline or unusable 304 → abort candidate | Keep last-good or bundle; next user trigger/mode selection | Yes, explicit next trigger only | User sees map-data failure and last check |
| Normalizer/isolate | Missing required shape, invalid record, expanded-data budget exceeded or worker failure → discard candidate before commit | Keep last-good or bundle and existing active markers | Yes with new source or explicit trigger | User sees source-specific or resource error |
| Drift transaction | Commit error or interruption → rollback six sources and normalized snapshot | Existing last-good remains; restart reads committed state | Yes | User sees storage failure |
| Controller/disposal | Mode superseded or disposed while work runs → no stale publication | New mode selection starts its own work; cancel resources | Yes, new trigger only | Status stays specific to current mode |
| Offline tooling | Invalid frozen input, source mismatch or artwork drift → no promotion | Correct offending input/config and rebuild | Yes | Operator gets offending path/property and active generation remains |

## Resource Bounds (FULL)

Normative HTTP limits are owned by `runtime-map-data`'s acquisition resource-bound requirement; conditional request behavior is owned by its conditional acquisition requirement. Limits apply to decoded transfer bytes, including reused cached bodies in the total, and are enforced while streaming, not after allocating an unlimited body. Deadline includes waiting for the refresh admission slot, all requests, normalization and commit. A timed-out/cancelled isolate is terminated or drained without holding the admission slot for unlimited time; a transaction already begun is awaited to its atomic outcome and never publishes after its fence. Use cancellable requests and close response streams on failure/disposal.

The expanded-data limits are owned by `runtime-map-data`'s expanded marker data requirement and remain 256 MiB materialized and 64 MiB serialized. Use injectable budget counters before allocating compact fact records, marker/reference slots, copied source graphs, immutable conversion and serialized buffers. Account conservatively using fixed per-object/container and per-entry overhead, UTF-16 string code units and scalar overhead. A fact physically retained once in the compact pool is charged once plus its reference slots; a recursively expanded or copied occurrence is charged in full. Count concurrently retained source, intermediate, old and candidate representations before their overlapping allocation; release a reservation only when its represented temporary is no longer retained. Avoid redundant decoded source graphs across the isolate handoff. Validate and retain shared immutable facts without expanding all markers on cache read, storage preparation, comparison or publication. Include derived search/projection/metadata state and transient buffers in pre-allocation reservations; shared facts must not become duplicated occurrence-owned search strings. Derived state is snapshot-owned, query caches do not grow across queries, and old/new derived generations are counted while both are retained. Count serialized UTF-8, including escaping and punctuation, with a bounded SDK sink before full output allocation and check stored payload size before decoding. Reference validation and traversal must be cycle-safe and bounded. A budget failure discards the candidate before transaction/publication and preserves durable and active authority. Prove fitting repeated facts remain compact, genuinely oversized distinct facts still fail before allocation/commit, and the complete active frozen source closure passes acquisition, publication, conditional revalidation and cache reload under unchanged defaults. These are resource bounds, not historical content/count gates; frozen offline marker bytes and candidate-own-source fidelity remain unchanged.

| Queue / buffer / cache / transfer | Bound | At the bound | Timeout | At 10x / 100x |
|---|---|---|---|---|
| Transfers | Spec's per-body and aggregate caps; six bodies only | Abort candidate, preserve last-good | Spec's request and overall deadlines | The observed ~9 MiB maps body would exceed the cap at 10x or 100x: explicit resource rejection, not a claim that content is semantically invalid. |
| Global refresh admission | One active refresh across modes, plus at most one pending current-mode request; same-mode calls join | Replace obsolete pending work; cancel superseded active work where possible; current mode progresses after cleanup | Same overall deadline includes queue time | Mode churn cannot multiply six-body buffers or isolates. |
| Normalization | One disposable worker; expanded serialized and materialized budgets as specified above | Incremental reservation failure aborts before oversized allocation; retain authority | Overall deadline | Repeated nested details at 10x/100x cannot grow output past the applicable budget, even when transfer fits. |
| Durable cache | One complete snapshot per each of three modes; each normalized payload subject to serialized budget; no history | Atomic replacement, no age eviction | Storage transaction is fenced by operation deadline | Oversized normalized output never reaches commit. |
| In-memory inventories and projections | Current inventory plus in-flight candidate and at most one selected-mode cache load; recursive candidate and conversion copies subject to materialized budget | Discard oversize or superseded candidate/read result | Overall deadline for refresh | Nested expansion is charged per occurrence rather than assumed bounded by source size. |

## Flow & State Gaps (FULL)

- **Partial responses:** Keep per-response bodies and validators private until every response has completed, passed source checks and normalized. No earlier HTTP success changes cache or UI. A 304 with missing, corrupt or incompatible exact cache body fails without retry. A 200 replaces both body and corresponding validators, including clearing an absent validator; a 304 updates only validators actually returned while retaining the body.
- **Singleflight and global budget:** Concurrent same-mode requests join one result. The admission owner serializes work across modes; pending current-mode intent is replaceable, never a growing FIFO. Cancellation must close active streams and dispose worker; a late answer cannot publish or overwrite a newer same-mode commit. Manual joining reports the same outcome.
- **Mode switch and late loads:** Advance the selection generation before asynchronous reads; fence cache read, refresh result, status and map publication independently. A prior mode may commit a complete result for itself only if still the latest operation for that mode. A cache read started before a newer commit cannot revert the active generation.
- **Restart or disposal:** Before commit, candidate data is disposable. During commit SQLite recovers all-or-nothing; after commit, next startup reads the complete result. Dispose stops admission, cancels network/worker, closes listeners before database/client shutdown, and suppresses stale notifications.
- **Unchanged versus changed content:** Compare normalized inventories within the newly validated candidate and current active inventory to decide whether marker content was replaced. This comparison controls selection clearing only, never admission. Update successful last-check/status even when content is unchanged. A failed check changes status, not authority.
- **Modes and pack errors:** Unknown effective mode uses explicitly labelled regular fallback, no guessed endpoint. Any active-pack load error remains visible even if metadata cache exists. No older asset generation is loaded.

## Mechanism Ledger (FULL)

| Mechanism | Built? | Why (harm nobody catches / expensive later) | Evidence that would change the call |
|---|---|---|---|
| One SQLite transaction and schema migration | yes | Partial bodies/normalized records can appear complete after crash; user data must survive migration. | A different durable storage architecture. |
| Per-body hashes and compatibility fingerprint | yes | Damaged or differently normalized cached records could be published silently; stored format hard to retrofit. | Equivalent end-to-end integrity/compatibility proof. |
| Per-mode singleflight, global admission, generation fences | yes | Mode switches and delayed cache/network responses can publish the wrong mode or multiply memory. | Demonstrably serialized lifecycle and bounded acquisition without them. |
| Streaming byte/time caps and disposal | yes | External inputs and stalled streams can exhaust memory or hang the refresh. | Measured resource limits and a replacement bounded transport. |
| Incremental expanded-data accounting | yes | One small source task can be duplicated across many position markers and exhaust memory before a post-encoding check. | A user-approved alternative that proves an equivalent bound without changing frozen output. |
| Shared parser and candidate-source fidelity | yes | Two normalization conventions diverge and valid corrupt output could be accepted. | A separately specified equivalent shared contract with proof. |
| Conditional reviewed overrides | yes | Old floor ownership can misplace or recreate changed markers; rejecting all changes violates S6. | New independent reviewed floor evidence for changed identities. |
| Historical content equality, count thresholds or old hashes | no | They cannot distinguish legitimate upstream changes from corruption; frozen candidate integrity already detects mutation. | A separately user-approved content-authority contract. |
| Polling, auto-retry, expiring cache and toggle | no | Not required and would introduce extra traffic or user-visible authority changes. | New approved product requirement. |
| Separate offline promotion transaction | no | Existing promotion already protects active assets and supports recovery. | Evidence existing transaction cannot enforce the preservation boundary. |

## Risks / Trade-offs

- Upstream changes can be structurally valid but wrong → display sourced facts honestly; no historical semantic gate can establish truth. User can see source/check/error; artwork remains separately reviewed.
- A stale but valid cache may remain old indefinitely → expose last check and separate manual refresh rather than silently expiring it.
- Shared extraction can perturb frozen output → retain candidate-source fidelity and byte-identical frozen rebuild; regression tests cover categories, quests, duplicate boss positions, empty map/task collections and dictionaries, changed or missing translation/reference IDs, and all three conditional overrides with reviewed markers unchanged, removed, moved and with changed volume.
- Resource caps reject sufficiently large valid datasets → report resource failure and preserve last-good, not historical content gates. At the normalizer/store seam, prove many positions retain complete shared facts compactly within injected limits, and genuinely oversized distinct facts or reference/marker counts fail before oversized allocation, encoding or commit while durable and active authority remains unchanged. Qualify the complete active frozen source closure under unchanged defaults, including initial publication, conditional revalidation, cache reload and local consumer parity. Use handwritten fakes, no sleeps or app launch.
- Mode churn and cache reads can race publication → bounded global admission plus selection and per-mode commit generations; deterministic tests use handwritten fakes and controllable futures, no sleeps.
- Schema migration threatens user data if implemented incorrectly → additive migration and pinned migration checks, testing preservation of existing user rows at the lowest practical layer.

## ADRs

- **In force, constraining this change:** ADR-0002 (composition and fences), ADR-0003 (single transactional Drift store), ADR-0004 (bulk work off UI), ADR-0005 and ADR-0033 (prepared artwork and immutable active pack), ADR-0034 (six-source frozen renewal and nonmetadata preservation, except portions to be superseded).
- **To record during apply:** A new accepted ADR partly superseding ADR-0005's offline-only marker-data boundary and ADR-0034's runtime-data prohibition and historical marker-preservation requirement, while retaining its nonmetadata preservation and frozen-source guarantees. Update `openspec/architecture.md` and the ADR index; do not edit accepted ADRs.

## Open Questions

None affecting the approved scope or approach.
