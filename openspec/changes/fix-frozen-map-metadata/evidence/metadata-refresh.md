# Frozen map metadata refresh evidence

Branch: `bugfix/fix-frozen-map-metadata`. This records the completed refresh generation, not acceptance gates for future runs. Baseline: `ed26414539f458929025f4ef2c3413d3457c7b3e5b9f2e2adfb4dc20c24bba5f`; new active/returned generation: `cefe97a6658f56550ca9466c9e261d8cbd57b044705e5ca453999d9903aa0993`.

## Acquisition and validation chronology

The initial all-index staging attempt failed before acquisition. Following user approval of the corrected plan (`FULL round 3 APPROVE`), `stage_metadata.dart` sequentially downloaded exactly six eligible metadata inputs in 9.04 seconds. Offline validation of the acquired bytes initially failed because the disposable helper selected `thelab` while the source key is `the-lab`. The parent corrected the helper to use `entry.value`; `finish_stage_metadata.dart` then revalidated those same staged bytes without refetch. Its first offline finish found raw source boss names (`bossGluhar`/`bossKolontay`) incompatible with the filter's required English dictionary translation; the parent corrected the disposable filter. Final `finish_stage_metadata.dart` succeeded in 7.28 seconds. No source records were missing; source bytes were not changed and there was no network retry. The original source index remains intact, including unused 477 sources; only six eligible metadata hashes were updated. `traders_en` remained byte-for-byte unchanged.

Exact staged inputs (URL — SHA-256):

- `https://json.tarkov.dev/regular/maps` — `42459cdf31b7d4007d08cb88ceae788ee186d6e150cb1c30a088557ddf2e131e`
- `https://json.tarkov.dev/regular/maps_en` — `debb3a5cc54a8f68a73931532712dab7d50f41ee86dd1a48ade1def85dfb982e`
- `https://json.tarkov.dev/regular/tasks` — `e0778cf624faee00840045df43d80f5a81d68ce096a3576a4bd0246b5fcfc959`
- `https://json.tarkov.dev/regular/tasks_en` — `4ef5967e0f4f2a80e0b1891b45f20055f0272f9f902b37c711fa89f89ee30b62`
- `https://json.tarkov.dev/regular/traders` — `dfd4b4bdd4be65ece0f875bad6a1bc41f7f8d9cdce931852b3b89aea89401ebd`
- `https://json.tarkov.dev/regular/traders_en` — `1d837a5d33dbde4b8860ba49488b3f885af8adbb13c5c52bcecd26637a6568c7` (unchanged bytes)

## Refresh outcome

Actual command: `mise exec -- dart run .dart_tool/blackgrid-frozen-metadata/refresh_audit_metadata.dart` — succeeded; elapsed 100.68 seconds. The independent audit reports returned ID equal to new ID, active pointer verified, generated asset declarations verified, and the baseline generation pruned. The only pruned ID was baseline `ed26414539f458929025f4ef2c3413d3457c7b3e5b9f2e2adfb4dc20c24bba5f`.

Exact actual report from `.dart_tool/blackgrid-frozen-metadata/refresh.log`:

```text
factory: manifest values changed
customs: manifest values changed
woods: manifest values changed
shoreline: manifest values changed
interchange: manifest values changed
thelab: manifest values changed
reserve: manifest values changed
lighthouse: manifest values changed
streetsoftarkov: manifest values changed
groundzero: manifest values changed
terminal: manifest values changed
icebreaker: manifest values changed
labyrinth: manifest values changed
pack: manifest values changed
other: 6 changed file(s)
Changed files:
  evidence/markers/maps.json
  evidence/markers/maps_en.json
  evidence/quests/tasks.json
  evidence/quests/tasks_en.json
  evidence/quests/traders.json
  evidence/sources.json
Changed manifest values:
  factory markers
  customs markers
  woods markers
  shoreline markers
  interchange markers
  thelab markers
  reserve markers
  lighthouse markers
  streetsoftarkov markers
  groundzero markers
  terminal markers
  icebreaker markers
  labyrinth markers
  sourceGeneration
Metadata changed: the owner must check the maps listed above in the app before merge.
```

## All 13 map records: category counts before → after

Counts include every category present on either side; omitted categories are zero. Boss count is explicitly shown for each. These are snapshot observations, not future gates.

| Map | Before → after (category=count) |
|---|---|
| factory | bosses 3→3; extracts 10→10; locks 4→4; lootContainers 167→167; lootLoose 82→81; questItems 17→17; questObjectives 38→38; spawns 119→119; transits 3→3 |
| customs | bosses 15→15; extracts 27→28; hazards 5→5; locks 37→37; lootContainers 551→551; lootLoose 306→310; questItems 54→54; questObjectives 116→116; spawns 278→278; stationaryWeapons 4→4; switches 1→1; transits 4→4 |
| woods | bosses 43→43; btrStops 8→8; extracts 20→20; hazards 64→64; locks 4→4; lootContainers 428→428; lootLoose 269→300; questItems 22→22; questObjectives 58→58; spawns 332→332; stationaryWeapons 2→2; transits 4→4 |
| shoreline | bosses 34→34; extracts 19→19; hazards 30→30; locks 34→34; lootContainers 756→756; lootLoose 441→444; questItems 33→33; questObjectives 89→89; spawns 282→282; stationaryWeapons 4→4; transits 4→4 |
| interchange | bosses 21→21; extracts 9→9; hazards 25→25; locks 15→15; lootContainers 823→823; lootLoose 483→492; questItems 16→16; questObjectives 31→31; spawns 232→232; stationaryWeapons 2→2; switches 6→6; transits 2→2 |
| thelab | bosses 168→168; extracts 7→7; locks 17→17; lootContainers 319→319; lootLoose 327→362; questItems 11→10; questObjectives 9→9; spawns 134→134; switches 15→15; transits 1→1 |
| reserve | bosses 52→69; extracts 11→11; hazards 4→4; locks 34→34; lootContainers 991→991; lootLoose 457→467; questItems 18→18; questObjectives 48→47; spawns 167→167; stationaryWeapons 8→8; switches 3→3; transits 3→3 |
| lighthouse | bosses 36→28; extracts 12→12; hazards 116→116; locks 26→26; lootContainers 533→533; lootLoose 882→844; questItems 9→9; questObjectives 48→48; spawns 213→213; stationaryWeapons 8→8; switches 2→2; transits 4→4 |
| streetsoftarkov | bosses 30→19; btrStops 6→6; extracts 19→19; hazards 56→56; locks 63→63; lootContainers 1282→1282; lootLoose 942→948; questItems 54→54; questObjectives 85→85; spawns 420→420; stationaryWeapons 9→9; transits 3→3 |
| groundzero | extracts 9→9; hazards 9→9; locks 6→6; lootContainers 523→523; lootLoose 200→184; questItems 12→12; questObjectives 16→16; spawns 192→193; stationaryWeapons 2→2; transits 1→1; bosses 0→0 |
| terminal | bosses 90→90; hazards 2→2; locks 2→2; lootLoose 13→13; spawns 109→109 |
| icebreaker | bosses 161→161; extracts 1→1; locks 11→11; lootLoose 78→78; questItems 3→3; spawns 56→56 |
| labyrinth | extracts 2→2; hazards 19→19; locks 8→8; lootContainers 35→35; lootLoose 177→176; questItems 10→10; questObjectives 8→8; spawns 19→19; switches 12→12; bosses 0→0 |

Category count equality does not imply identical facts. The independent per-marker fact comparison records all adds/changes/removals by category below; categories without a listed entry had zero fact differences. Tuple figures are `added / changed / removed`.

| Map | Changed marker facts (category: + / changed / −) |
|---|---|
| factory | bosses 3/0/3; lootLoose 47/9/48; questItems 0/17/0; questObjectives 33/5/33 |
| customs | bosses 15/0/15; extracts 1/20/0; lootLoose 218/71/214; questItems 0/54/0; questObjectives 4/112/4 |
| woods | bosses 43/0/43; lootLoose 260/19/229; questItems 0/22/0; questObjectives 1/57/1 |
| shoreline | bosses 34/0/34; lootLoose 368/73/365; questItems 0/33/0; questObjectives 2/87/2 |
| interchange | bosses 21/0/21; lootLoose 386/75/377; questItems 0/16/0; questObjectives 1/30/1 |
| thelab | lootLoose 326/36/291; questItems 0/10/1; questObjectives 0/9/0 |
| reserve | bosses 69/0/52; lootLoose 381/62/371; questItems 0/18/0; questObjectives 0/47/1; spawns 0/46/0 |
| lighthouse | bosses 28/0/36; lootLoose 690/154/728; questItems 0/9/0; questObjectives 0/48/0; spawns 120/10/120 |
| streetsoftarkov | bosses 19/0/30; lootLoose 835/96/829; questItems 0/54/0; questObjectives 0/85/0; spawns 345/68/345 |
| groundzero | lootLoose 121/20/137; questItems 0/12/0; questObjectives 0/16/0; spawns 93/93/92 |
| terminal | lootLoose 8/5/8 |
| icebreaker | questItems 0/3/0 |
| labyrinth | lootLoose 105/30/106; questItems 0/10/0; questObjectives 1/7/1 |

## Boss multiset and preservation evidence

Independent boss comparison grouped by the full tuple **(mob, resolvedName, location, x, y, z, bossWideChance)**, preserving duplicate multiplicity (occurrence counts). It did **not** compare `prepareMarkers` output as an expected oracle. Result: zero multiset mismatches across all map records. Forbidden source-index changes: none. Five of the six eligible metadata hashes changed; `traders_en` retained identical bytes. Every other indexed record stayed unchanged. Independent preservation result: `manifestSettingsMatch=true`, `mapRecordDifferences=[]`, `preservedOutputDifferences=[]`, `unchangedArtworkAndCalibration=true`. Therefore map properties/settings and every output outside the intended metadata replacement were unchanged; specifically no preserved-map/output differences. These are actual baseline-vs-new-generation results.

Snapshot-specific source facts corroborating the corrected translated-name matching (`mob`, `resolvedName`, `location`, `(x,y,z)`, `bossWideChance`, one per occurrence):
- Reserve Glukhar: `bossGluhar`, `Glukhar`, `ZoneRailStrorage`, `(-143.15,-6.866005,-131.07)`, 0.57; `ZoneRailStrorage`, `(243.125,-7.088669,-88.11)`, 0.57; `ZoneRailStrorage`, `(230.42,-6.84999847,-117.53)`, 0.57; `ZoneRailStrorage`, `(-11.76,19.022995,170.053)`, 0.57; `ZoneRailStrorage`, `(217.322,-6.91000366,-172.024)`, 0.57; `ZoneRailStrorage`, `(-11.234,19.022995,168.129)`, 0.57; `ZoneRailStrorage`, `(240.93,-7.053322,-94.94)`, 0.57; `ZoneRailStrorage`, `(216.719,-6.86700439,-176.889)`, 0.57; `ZoneRailStrorage`, `(189.99,-6.68300629,-97.79)`, 0.57; `ZoneRailStrorage`, `(219.21,-6.91000366,-173.99)`, 0.57; `ZoneRailStrorage`, `(-75.67,21.2340012,186.87)`, 0.57; `ZoneRailStrorage`, `(225.13,-6.84999847,-122.95)`, 0.57; `ZoneRailStrorage`, `(218.029,-6.91000366,-175.682)`, 0.57; `ZonePTOR2`, `(74.39,-6.746002,-41.15)`, 0.57; `ZoneBarrack`, `(226.305008,-6.829998,31.4150085)`, 0.57; `ZoneBarrack`, `(23.48,-5.10800171,-128.25)`, 0.57; `ZoneSubStorage`, `(58.35,-12.2260056,-155.19)`, 0.57.
- Streets of Tarkov Kollontay: `bossKolontay`, `Kollontay`, `ZoneClimova`, `(-155.72,0.664130151,-58.1299973)`, 0.57; `ZoneClimova`, `(-158.92,0.652098954,-27.77)`, 0.57; `ZoneClimova`, `(-147.264,0.6399956,-66.349)`, 0.57; `ZoneClimova`, `(-153.62,0.6758954,-64.64)`, 0.57; `ZoneClimova`, `(-136.07,0.6399956,-71.29)`, 0.57; `ZoneMvd`, `(-254.2,2.98599625,149.62999)`, 0.57; `ZoneMvd`, `(-253.98999,2.98599625,125.359993)`, 0.57; `ZoneMvd`, `(-258.28,2.31656575,140.75)`, 0.57. These source facts are reproducible from this generation's committed `evidence/markers/maps.json` and `evidence/markers/maps_en.json`; the prepared records are in its `manifest.json`.

## Empty source boss coverage

The independent source audit observed 54 empty-coverage occurrences. Each group below gives source key, boss, empty field, location if the source record had one, and exact occurrence indexes (bossIndex; locationIndex). No positions have been inferred or invented. `—` means no location field for a `spawnLocations` entry.

- `factory`: infectedScreamer, `spawnLocations`, —: 0; 1; 2.
- `customs`: bossBully, `positions`, ZoneDormitory: 0/0; ZoneGasStation: 0/1. infectedScreamer, `spawnLocations`, —: 3; 4; 5.
- `woods`: infectedScreamer, `spawnLocations`, —: 3.
- `shoreline`: bossSanitar, `positions`, ZonePort: 0/0; sectantPriest, `positions`, ZoneForestSpawn: 2/2; Sentry, `positions`, ZoneGateTowerRight: 3/0; infectedScreamer, `spawnLocations`, —: 5; 6; 7.
- `interchange`: infectedScreamer, `spawnLocations`, —: 2; 3; 4.
- `the-lab`: PmcBot, `positions`, BotZoneGate2: 14/0.
- `reserve`: infectedScreamer, `spawnLocations`, —: 5; 6; 7.
- `lighthouse`: infectedScreamer, `spawnLocations`, —: 7; 8; 9.
- `streets-of-tarkov`: infectedScreamer, `spawnLocations`, —: 2; 3; 4.
- `ground-zero`: infectedScreamer, `spawnLocations`, —: 0; 1; 2.
- `terminal`: blackDivision, `positions`: Zone1BDGateAmbush13 2/0; Zone2BDWarehouse19 13/0; Zone2BDColumns23 15/0; Zone1BD1HangarBD11 22/0. vsRF, `positions`, Zone2VSRFContainers24: 16/0. bossGluhar, bossKilla, bossBully, bossSanitar, bossTagilla each `positions` at Zone2ScavPort29: 23/0, 24/0, 25/0, 26/0, 27/0 respectively.
- `icebreaker`: bossKnight, `positions`, BotZoneMash_t1: 0/0. ExUsec, `positions`: BotZoneFront 1/0; BotZoneKitchen 2/0; BotZoneRoom_Eng2 38/0. bossWedge, `positions`: BotZoneRoomsThird 21/0, 25/0, 28/0, 31/0; BotZoneRoomsThirdKitchen 22/0, 24/0, 27/0, 30/0.
- `the-labyrinth`: bossTagillaAgro, `spawnLocations`, —: 0.

## Qualification and owner check

Before real acquisition, the generation-view implementation passed 68 focused regression tests and 3 targeted qualification tests on synthetic fixtures. The actual refresh and independent returned-generation audit above provide the real-pack smoke evidence. The final gates remain pending. The owner check is explicitly waiting on the user for this exact generation (task 4.4). No app/game was launched or inspected; neither in-app map readability nor the M8 readability check is claimed as passed. No release/version bump was made.
