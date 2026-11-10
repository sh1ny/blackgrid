# Spec Delta

## MODIFIED Requirements

### Requirement: One plate per verdict
Wherever a verdict is shown, which is the answer strip on both areas, the verdict word SHALL sit on a 44px plate with soft corners, in the verdict type role (Geist 600, 22px), styled by verdict as DESIGN.md X1 describes. The style SHALL come from the theme, in both rooms, and no plate SHALL use the accent colour.

#### Scenario: Each verdict has its style
- **WHEN** the answer strip shows each verdict in turn, in either room
- **THEN** Keep has a solid `ok-fill` plate with `ok-on-fill` text; Keep for later has an `ok-bg` fill, an `ok-line` border and `ok-strong` text; Check / May Need has a `warn-bg` fill, a `warn-line` border and `warn-strong` text; Flea and Trader have a `raised` plate with `ink-secondary` text; Price unavailable has no fill and a dashed `ink-tertiary` border

#### Scenario: Verdicts differ without colour
- **WHEN** the plates of Keep, Flea and Price unavailable are compared
- **THEN** Keep is a solid fill, Flea is a raised surface with no solid accent fill, and Price unavailable is dashed with no fill

#### Scenario: No plate is drawn in the accent
- **WHEN** any of the six plates is rendered in either room
- **THEN** none of its fill, border or text colours equals the room's `accent` or `accent-text` value

### Requirement: One-line verdict reason
Below every plate the answer strip SHALL show one plain-language reason, derived from the decision alone, never empty. It SHALL wrap onto further lines rather than clip, fade or truncate, at every strip width. Developer terms and internal IDs SHALL NOT appear in it.

#### Scenario: Keep names the need that decided it
- **GIVEN** a Keep decision whose first actionable need is the task "Shortage" needing 3 found-in-raid items
- **WHEN** the reason is derived
- **THEN** it reads "Needed now for Shortage: 3 found in raid"

#### Scenario: Keep with an unknown count
- **GIVEN** a Keep decision whose first actionable need is "Shortage" with no known remaining count
- **WHEN** the reason is derived
- **THEN** it reads "Needed now for Shortage", with no number

#### Scenario: Keep for later names the future need
- **GIVEN** a Keep for later decision whose first future need is the hideout station "Medstation" needing 2 items with no found-in-raid rule
- **WHEN** the reason is derived
- **THEN** it reads "Needed later for Medstation: 2"

#### Scenario: Check names the first open question
- **GIVEN** a Check / May Need decision with item data and Tracker progress current, found in raid unknown, and no unresolved need that requires a found-in-raid item
- **WHEN** the reason is derived
- **THEN** it reads "Found in raid unknown for this item"

#### Scenario: Check picks questions in a fixed order
- **GIVEN** a Check / May Need decision where several inputs are open
- **WHEN** the reason is derived
- **THEN** it names the first open input in this order: item data, Tracker progress, found in raid, an unresolved need (naming its source), Flea eligibility, price time

#### Scenario: Check wording for each open input
- **WHEN** the first open input of a Check / May Need decision is each kind in turn
- **THEN** the reason reads, for item data, "Item data missing or out of date"; for Tracker progress, "Tracker progress missing or out of date"; for an unresolved need from "Shortage", "Can't tell yet if Shortage needs it"; for Flea eligibility, "Not known if it can be sold on the Flea"; for a price time over an hour old, "Flea price is over an hour old"; and for a price time that is missing or in the future, "Flea price time unknown"

#### Scenario: Found in raid unknown outranks the needs it leaves open
- **GIVEN** a Check / May Need decision with found in raid unknown and the need "Shortage" unresolved because it needs a found-in-raid item
- **WHEN** the reason is derived
- **THEN** it reads "Found in raid unknown: Shortage needs it found in raid"

#### Scenario: Found in raid unknown names the first need that requires it
- **GIVEN** a Check / May Need decision with found in raid unknown, where the hideout need "Medstation" level 1 and then the task "Shortage" are unresolved because each requires a found-in-raid item
- **WHEN** the reason is derived
- **THEN** it reads "Found in raid unknown: Medstation level 1 needs it found in raid", naming only the first such need in the decision's reason order

#### Scenario: Needs that do not apply are skipped
- **GIVEN** a Check / May Need decision with found in raid unknown, where an optional barter and a task for the other faction that need a found-in-raid item come first and the task "Shortage" is unresolved because it needs a found-in-raid item
- **WHEN** the reason is derived
- **THEN** it reads "Found in raid unknown: Shortage needs it found in raid"

#### Scenario: Found in raid unknown with no need that requires it
- **GIVEN** a Check / May Need decision with found in raid unknown as its first open input and no need that requires a found-in-raid item
- **WHEN** the reason is derived
- **THEN** it reads "Found in raid unknown for this item"

#### Scenario: Flea and Trader compare the prices
- **GIVEN** a Flea decision with a Flea price of 38277 and the best trader Therapist at 7695, both gross prices as the engine compares them
- **WHEN** the reason is derived
- **THEN** it reads "Flea pays more than Therapist (₽7695)"

#### Scenario: Trader for each way the engine reaches it
- **GIVEN** a Trader decision whose best trader is Therapist at a gross price of 7695
- **WHEN** the item cannot be sold on the Flea, has no Flea price, or has a Flea price no higher than 7695
- **THEN** the reason reads "Can't be sold on the Flea; Therapist pays ₽7695", "No Flea price; Therapist pays ₽7695" or "Therapist pays at least the Flea (₽7695)" respectively

#### Scenario: Flea with no trader offer
- **GIVEN** a Flea decision where no trader buys the item for roubles
- **WHEN** the reason is derived
- **THEN** it reads "No trader buys it for roubles"

#### Scenario: Price unavailable
- **WHEN** the decision is Price unavailable
- **THEN** the reason reads "No Flea or trader cash price for this item"

#### Scenario: A long reason at the narrowest card
- **GIVEN** a reason whose need source name is 80 characters long
- **WHEN** the answer strip is rendered at its narrowest width in a 960px window
- **THEN** the whole reason text is laid out on two or more lines, with no ellipsis and no overflow

### Requirement: Price freshness tag
The answer strip's price block, and the Updated row of the Scanner's Prices section, SHALL each carry one tag saying how old the Flea price is, unless the item cannot be sold on the Flea. While the price time is within one hour it SHALL read "Prices <local time>" in the `ink-tertiary` role. Past one hour, or when the price time is unknown or in the future, it SHALL take the warning style (`warn-bg`, `warn-ink`) and say so in words.

#### Scenario: Current prices
- **GIVEN** a price time of 11:08 today and a current time of 11:40
- **WHEN** the strip price block is rendered
- **THEN** the tag reads "Prices 11:08" in the plain style

#### Scenario: Stale prices
- **GIVEN** a price time 3 hours and 10 minutes before now
- **WHEN** the strip price block is rendered
- **THEN** the tag reads "price 3 h old" in the warning style; and a price time 2 days old reads "price 2 d old"

#### Scenario: Unknown or future price time
- **WHEN** the item has no price time, or its price time is later than now
- **THEN** the tag reads "price time unknown" in the warning style

#### Scenario: The tag turns stale while shown
- **GIVEN** the strip shows "Prices 11:08" and nothing else changes
- **WHEN** the clock passes 12:08 and the strip's periodic age update runs
- **THEN** the tag reads "price 1 h old" in the warning style

#### Scenario: No tag when the Flea price cannot matter
- **GIVEN** a decision for an item that cannot be sold on the Flea, with no price time
- **WHEN** the strip price block is rendered
- **THEN** no freshness tag is shown in the strip or in Prices, and no warning style appears on either
