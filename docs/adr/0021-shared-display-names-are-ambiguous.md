# 0021 - Shared display names are ambiguous: same-name items are listed as candidates and told apart in the correction offer

- Status: accepted
- Date: 2026-10-20 (M4 change `qualify-scanner-latency`)
- Supersedes: 0018, its "The matcher keeps a distinct-name top 5" bullet, for same-name groups only. Distinct-name ranking is unchanged everywhere else.
- Source: change `qualify-scanner-latency` (design D4, D5, D6); [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

The inspection corpus has one standing false positive: scans 0012/0013 show the no-flea Weapon case, and the scanner accepts the flea-listable one. Both are named "Weapon case" in game, so no OCR improvement can separate them. The matcher picks the flea-listable variant only because the catalog gives the other the slug `weapon-case-1`: the base slug scores 1.0 against about .909, and the margin passes the .05 gate. The current catalog has 46 such shared display names (ammo packs, cases, dogtags, gear crates, Twitch drop cases), in groups of two to fifty items.

The decision differs per ID (flea status, quest and hideout needs), so accepting the wrong variant can give the wrong keep or sell. The reference fork accepts the base-slug variant.

## Decision

- **A shared display name makes an otherwise accepted match `ambiguous` (D4).** An item's display name is `normaliseTitle(item.name)`. `TitleMatchIndex.build` groups index positions by display name once per snapshot, in ID order. In `matchTitle`, after the gates accept the best candidate, a best with a non-empty same-name group becomes `TitleRejected(ambiguous)` with the same best, runner-up and margin. A result below the similarity gate stays `belowSimilarity`. The rule is the same for targeted and fallback evidence, so `rankOutcome` is unchanged: an ambiguous targeted entry falls through to the fallback, and the scan ends `ambiguous` with a correction offer.
- **Same-name items lead the candidates (D4).** The candidates are the best, then every other item of its group in ID order with its own similarity, then the usual distinct-name ranking, at most 5. Same-name items are listed even when their normalised names are equal. The runner-up and margin stay as computed by the distinct-name rule.
- **The correction offer tells same-name rows apart (D5).** `ItemDecisionCard` compares display names with `normaliseTitle` across every row the offer lists, candidates and search results together. A row whose display name another listed row shares shows its flea status and the last 6 characters of its ID: `'<name> · <flea status> · <last 6 of id> • <score>'` for candidates, the same without the score for search rows. Flea status is `flea` (`noFlea == false`), `no flea` (`noFlea == true`) or `flea unknown` (`noFlea == null`); unknown is never shown as `flea`. Other rows are unchanged. The search reaches variants of groups larger than the 5 candidates.
- **Stricter than the reference fork on purpose.** The user chose on 2026-10-20 to pay a correction click for shared names rather than accept the wrong variant. The fork-parity default does not apply to this rule.

## Rejected alternatives

- **Prefer the flea-listable variant** (status quo and the fork): it is the false positive this decision removes.
- **Apply the rule only to groups whose `noFlea` differs:** quest and hideout needs are per ID, so a same-name pair with equal flea status can still give the wrong decision.
- **Disambiguate by icon or a second OCR read:** nothing in the inspect window's title differs, and icon matching is M4.5 scope.
- **Show the slug (`normalizedName`) or the short name in the offer:** `weapon-case-1` tells the user nothing, and the short names are identical in the observed groups.

## Consequences

- **Scanning one of the 46 shared-name items offers a correction instead of accepting at once.** These scans pay the full fallback before the offer, because an ambiguous targeted result falls back.
- **Corpus coverage can drop** where a labelled case expects the base-slug variant. Open decision: the M4 corpus criterion ("at least the reference's"; strategy §6 and §12) is judged unmodified until the user decides whether a regression to an ambiguous reject within a same-name group, with the expected item offered as a candidate, counts against coverage. If the user amends the criterion, a superseding ADR records it. Until then, same-name regressions are listed separately in the M4 evidence and the criterion is not marked met on their basis.
- **Follow-up:** the inspect window's "CANNOT BE LISTED ON FLEA MARKET" banner could resolve pairs whose flea status differs without a click (M4.5 or later). Groups with equal flea status still need this rule.
- **Reversal cost:** low. One rule in the matcher and one labelling rule in the card.
