# scan-decisions Specification

## Purpose
Turns an accepted live scan into the current item selection and its keep/sell decision from the shared engine, recorded once in activity history and fenced so stale or repeated scan results never become current advice.

## Requirements

### Requirement: An accepted scan becomes the current selection
When a scan is published as accepted for item X, the app SHALL make X the current selection: the answer strip SHALL show X and its decision on Scanner and on Map, and the Scanner's Why and Prices sections SHALL show X's needs and prices. The newest selection SHALL win: an accepted scan, a manual selection, a history selection and a picked scan correction each replace whatever was shown, in the order they happened.

#### Scenario: Accepted scan replaces a manual selection
- **WHEN** the user has manually selected item A and a scan is then accepted for item B
- **THEN** the answer strip shows item B and its decision

#### Scenario: Manual selection after a scan
- **WHEN** a scan was accepted for item B and the user then manually selects item A
- **THEN** the answer strip shows item A, and a later refresh does not bring back item B

#### Scenario: Accepted scan while a history row is open
- **WHEN** the user has a history row for item A open and a scan is accepted for item B
- **THEN** the history view closes and the answer strip shows item B in the live mode

#### Scenario: Accepted scan after a correction
- **WHEN** the user picked item C from a scan's correction offer and a scan is then accepted for item B
- **THEN** the answer strip shows item B as an accepted scan, no longer labelled as corrected

### Requirement: Scan decisions come from the shared engine
The decision for a scanned item SHALL be the shared decision engine's result for that item, using the current live-mode catalog, session progress and the winning inspection's detected FIR unless the user overrides it. Unknown evidence SHALL remain Unknown. Every precedence rule SHALL give the same outcome as a manual selection with identical inputs. FIR uncertainty SHALL NOT change item-identity acceptance or request another capture.

#### Scenario: Confirmed current need
- **WHEN** a scan is accepted for an item with a confirmed active quest need that does not require FIR
- **THEN** the decision is Keep and shows the need

#### Scenario: Unknown progress
- **WHEN** a scan is accepted for an item with no need found and progress unavailable
- **THEN** the decision is Check and names progress as the missing fact, never Flea or Trader

#### Scenario: Every precedence rule
- **WHEN** fixture items for each of the six precedence rules (Keep, Keep for later, Check, Flea, Trader, Price Unavailable) are accepted by scan with known FIR evidence or a manual FIR override
- **THEN** each decision equals the engine's decision for the same item selected by hand with the same catalog, progress and effective FIR

#### Scenario: Winning inspection supplies FIR
- **WHEN** an accepted outcome chooses the second inspection with detected No while the frame's first inspection has detected Yes
- **THEN** the decision uses No, never the first inspection's Yes

#### Scenario: Unreadable FIR does not reject an item
- **WHEN** a title passes the existing acceptance gates but its picture corner is cut off or unreadable
- **THEN** the item remains accepted, its decision uses FIR Unknown, and no additional capture or fallback is started for FIR

#### Scenario: Detected FIR controls a FIR-only quest need
- **WHEN** an accepted scan concerns one incomplete active FIR-only task, with fresh matching catalog/progress, no other needs, no Flea eligibility and a valid RUB trader offer
- **THEN** detected Yes gives Keep with an actionable need, detected No gives Trader with that need irrelevant, and detected Unknown gives Check with that need unresolved
- **AND** each case's immutable acceptance snapshot and recorded history verdict equal that initial detected-input verdict

### Requirement: Unaccepted scans never change the selection
A scan that ends rejected or failed SHALL NOT change the current selection, the decision, the FIR value or the history, even when it has a best candidate.

#### Scenario: Rejected scan with a candidate
- **WHEN** item A is selected and a scan ends rejected with best candidate C
- **THEN** the answer strip still shows item A, and no history entry for C is added

#### Scenario: Failed scan after an accepted one
- **WHEN** a scan was accepted for item B and the next scan fails at capture
- **THEN** the answer strip still shows item B with the FIR value the user set

### Requirement: Each accepted scan is consumed once
Each accepted scan SHALL become the selection at most once and SHALL be recorded in history at most once. Re-publication, a listener notification without a new accepted scan, a catalog or progress refresh, the periodic age update and opening history SHALL NOT be taken as a new accepted scan.

#### Scenario: Refresh after an accepted scan
- **WHEN** a scan is accepted for item B, and the catalog and progress then refresh
- **THEN** history holds one entry for B from that scan, and the scan's acceptance time is unchanged

#### Scenario: Unrelated notification
- **WHEN** a scan was accepted for item B, the user then selects item A by hand, and the scanner then notifies for a phase change with no new accepted scan
- **THEN** the answer strip still shows item A

### Requirement: Scans from an older mode or session drive no decision
A scan SHALL drive a decision only when, at publication, the live mode and the game session are the same as when its trigger was taken, and its item exists in the current catalog of that mode. Otherwise the scan's evidence SHALL still be shown, the selection SHALL stay as it was, and nothing SHALL be recorded.

#### Scenario: Mode changes mid-scan
- **WHEN** a scan is triggered in PvP and the live mode changes to PvE before the scan is published as accepted
- **THEN** the selection is unchanged and no history entry is added

#### Scenario: Session changes mid-scan
- **WHEN** a scan is triggered and the game session changes before the scan is published as accepted
- **THEN** the selection is unchanged and no history entry is added

#### Scenario: Item missing from the current catalog
- **WHEN** a scan is accepted for an item that the current catalog of the live mode does not hold
- **THEN** the selection is unchanged and no history entry is added

### Requirement: Accepted scans are recorded in history as scans
Each accepted scan that drives a decision SHALL record activity for its item in the live mode, with source `scan` and the acceptance time. The entry is one per item and mode, revised on each accepted scan. If recording fails, the decision SHALL still be shown, together with an error saying the scan was not recorded.

#### Scenario: Two scans of the same item
- **WHEN** two scans are accepted for item B in PvP
- **THEN** history holds one PvP entry for B with source `scan`, at revision 2, observed at the second acceptance time

#### Scenario: History write fails
- **WHEN** a scan is accepted for item B and the history write fails
- **THEN** the answer strip shows item B with an error that the scan was not recorded

### Requirement: FIR resets on every new accepted scan
Each accepted scan that drives a decision SHALL discard the previous manual FIR override and initialise FIR from its own detection, even for the same item. A picked correction and a mode/session change SHALL reset FIR to Unknown. A manual override SHALL affect only the current selection. Repeated publication SHALL NOT reapply detection or clear an override.

#### Scenario: Same item scanned again
- **WHEN** a scan is accepted for item B, the user overrides FIR to Yes, and a second scan is accepted for B with detected No
- **THEN** FIR is No from the second scan and the decision uses No

#### Scenario: Session change
- **WHEN** a scan is accepted for item B, the user sets FIR to Yes, and the game session then changes
- **THEN** FIR is Unknown and the scan/override no longer supplies current advice

#### Scenario: Correction to the item already shown
- **WHEN** a scan is accepted for item B, the user sets FIR to Yes, and the user then picks B from a later scan's correction offer
- **THEN** FIR is Unknown and the decision is computed with FIR Unknown

#### Scenario: Duplicate report after an override
- **WHEN** a scan has detected Yes, the player overrides FIR to No and the same accepted report is published again
- **THEN** effective FIR remains manual No and neither history nor acceptance time changes

### Requirement: Scan advice shows its age and stops being current on a mode or session change
The selection SHALL keep each accepted scan's item, mode, catalog revision, acceptance time and decision at acceptance unchanged. The answer strip SHALL show the current decision for it, and its provenance line SHALL say how long ago it was scanned (workspace-shell). After a mode or session change the scanned item SHALL no longer be shown as current advice.

#### Scenario: Prices go stale after a scan
- **WHEN** a scan detects FIR Yes for item B with fresh authorities and no needs, initially shows Flea, and B's Flea quote then becomes older than one hour
- **THEN** the strip shows Check for B while its original acceptance time, immutable Flea decision at acceptance and recorded Flea history verdict remain unchanged

#### Scenario: Mode changes after a scan
- **WHEN** a scan is accepted for item B in PvP and the live mode then changes to PvE
- **THEN** the strip no longer shows B as current advice and no history entry is added for PvE

### Requirement: FIR source and override are visible beside the control
On Map and Scanner the shared FIR control SHALL show whether its effective value comes from the scan or a manual override. Scan-derived Unknown SHALL name cut-off or unreadable evidence. Choosing any segment, including Unknown, SHALL set a manual override. Manual/history selections and picked corrections SHALL start Unknown without claiming scan detection. No FIR choice SHALL persist to history or settings.

#### Scenario: Override a detected value
- **WHEN** an accepted scan detects Yes and the player chooses No
- **THEN** the control shows No with a manual-override source and the shared engine recomputes using No, while the scan's immutable detection remains Yes

#### Scenario: Explicit Unknown override
- **WHEN** the player chooses Unknown after an accepted scan detected Yes
- **THEN** the decision uses Unknown with manual provenance rather than reverting to the detected Yes

#### Scenario: Choose the already selected automatic Yes
- **WHEN** an accepted scan detects Yes and the player activates the already selected Yes segment, then the same selection's data refreshes
- **THEN** Yes remains visibly selected with manual-override text and semantics, the decision still uses Yes and immutable scan detection remains Yes

#### Scenario: Choose the already selected automatic Unknown
- **WHEN** an accepted scan has FIR Unknown and the player activates the already selected Unknown segment, then the same selection's data refreshes
- **THEN** Unknown remains visibly selected with manual-override text and semantics, the decision still uses Unknown and immutable scan evidence remains unchanged

#### Scenario: Explain automatic Unknown
- **WHEN** an accepted scan's corner was cut off or unreadable
- **THEN** the control shows Unknown and the corresponding reason beside it on both work areas

#### Scenario: Manual and history isolation
- **WHEN** the player leaves an accepted scan and selects another item manually or from history
- **THEN** FIR starts Unknown without scan provenance or the previous override, and reopening the app restores neither detected nor manual FIR

### Requirement: Data refresh preserves the current FIR context
While the same selection remains current, catalog/progress refresh and age updates SHALL preserve detected FIR, a manual override and their source, while recomputing advice. If the current scanned item disappears, it SHALL cease supplying current advice. Mode/session changes and new selections SHALL continue to apply their own reset rules.

#### Scenario: Refresh with an override
- **WHEN** the player overrides a scan's detected Yes to No and the same-mode catalog/progress refresh or age update runs
- **THEN** effective FIR stays manual No, the immutable scan detection stays Yes and advice uses the refreshed authorities

#### Scenario: Item disappears during refresh
- **WHEN** a catalog refresh removes the current scanned item's ID
- **THEN** no decision for that missing item is shown, and its FIR is not applied to another selection

