# Frozen tarkov.dev task excerpt

- Fetch date: 2026-11-12.
- Regular source URL: https://json.tarkov.dev/regular/tasks
- PvE source URL: https://json.tarkov.dev/pve/tasks
- Format: original wire `data.tasks` objects. Only `zones`, `position`, `outline` and `translations` were removed recursively. No task facts were edited. One task per JSON line keeps both mode files below 150 KB.
- Traders: `traders.json` contains every trader ID referenced by the excerpt, copied from the task source (assigning traders, trader requirements, objectives and dialogue). References remain real IDs, not synthetic stand-ins.
- Selection: one seed per gate below, then the transitive closure of prerequisite, fail-condition task-status and objective task-status references. Regular is filled out with small real tasks and their reference closures to keep the per-mode excerpt in the 30–50-task range. Regular has 40 tasks; PvE has 39.
- Reproduction: fetch the two URLs, select the following IDs in their respective modes, recursively include those task references until none remain, and remove only the four geometry/translation keys above. Preserve source order and every remaining field. The exact selected IDs are the keys in each committed file.

## Selection by gate

| Gate | Regular seed | PvE seed |
|---|---|---|
| level | `59c9392986f7742f6923add2` | `59c9392986f7742f6923add2` |
| loyalty | `59c9392986f7742f6923add2` | `59c9392986f7742f6923add2` |
| complete | `5a68663e86f774501078f78a` | `5a68663e86f774501078f78a` |
| failed | `59c93e8e86f7742a406989c4` | `59c93e8e86f7742a406989c4` |
| active | `597a160786f77477531d39d2` | `597a160786f77477531d39d2` |
| alternative | `597a0f5686f774273b74f676` | `597a0f5686f774273b74f676` |
| faction | `639136df4b15ca31f76bc31f` | `639136df4b15ca31f76bc31f` |
| mode | `6761ff17cdc36bd66102e9d0` | `6834287b7559f4e6d50bc0fa` |
| global | `64f5deac39e45b527a7c4232` | `64f5deac39e45b527a7c4232` |
| dialogue | `657315ddab5a49b71f098853` | `657315ddab5a49b71f098853` |
| delay | `63966fbeea19ac7ed845db2e` | `63966fbeea19ac7ed845db2e` |
| prestige | `6761ff17cdc36bd66102e9d0` | `not present in PvE source` |
| reputation | `66d9cbb67b491f9d5304f6e6` | `66d9cbb67b491f9d5304f6e6` |
| edition | `666314b4d7f171c4c20226c3` | `666314b4d7f171c4c20226c3` |

## Edition provenance

The Good Times - Part 1 (`666314b4d7f171c4c20226c3`) is present in both source excerpts. tarkov.dev does not provide edition gates; the reviewed package table supplies this one. Source: https://escapefromtarkov.fandom.com/wiki/The_Good_Times_-_Part_1 and owner confirmation on 2026-11-12 that Edge of Darkness and Unheard can take it (design D4). Small Business - Part 3 has no table entry, by the owner's decision.

## Coverage and preservation

Tests use real gate-bearing tasks with synthetic player progress to provoke checked failures and unchecked reasons. Game-mode restrictions are tested by evaluating a restricted real task in a different mode; the mode-scoped excerpt itself is not altered. Unknown requirement types and malformed/absent fields are synthetic boundary tests, because inventing them inside a real excerpt would falsify its provenance. The parser resolves every task reference against the committed closure. Fetching is not part of tests; no game or application is launched.
