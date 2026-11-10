# Tasks

## Test map

Rows that start `green` ride along unchanged inside a MODIFIED requirement and already pass; their group re-runs them. Rows that start `red` are new tests or existing tests that must change because they mount a removed widget or assert changed text. A test that moves keeps its row's scenario name.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| catalog-authority → Settings shows the catalog error | Failure shown in the panel | `test/ui/settings_page_test.dart` | catalog-authority: Failure shown in the panel | green |
| catalog-authority → Settings shows the catalog error | Error cleared by a successful refresh | `test/ui/settings_page_test.dart` | catalog-authority: Error cleared by a successful refresh | green |
| catalog-authority → Settings shows the catalog error | Item names that could not be loaded | `test/ui/settings_page_test.dart` | rows > Item and map data > catalog-authority: Item names that could not be loaded | green |
| item-icons → The answer strip shows the item's icon | Scanner shows the icon | `test/ui/item_icon_surfaces_test.dart` | Scanner decision card shows the cached item icon in wide and narrow layouts | green |
| item-icons → The answer strip shows the item's icon | Map's compact card shows the icon | `test/ui/item_icon_surfaces_test.dart` | Map compact decision card shows the cached item icon | green |
| item-icons → The answer strip shows the item's icon | The generic icon shows while loading or offline | `test/ui/item_icon_test.dart` | shows the generic icon while loading and after a failure | green |
| item-icons → The answer strip shows the item's icon | An undecodable icon falls back | `test/ui/item_icon_test.dart` | an undecodable file shows the generic icon without an error | green |
| item-icons → Icons download only for shown items | Showing an uncached item downloads its icon once | `test/application/item_icon_cache_test.dart` | item icon cache > first acquire of an uncached item sends one GET and becomes ready | green |
| item-icons → Icons download only for shown items | A catalog refresh downloads nothing | `test/application/app_services_item_icons_test.dart` | committing a catalog with icon links sends no icon request | green |
| item-icons → Icons download only for shown items | An item without a picture sends no request | `test/application/item_icon_cache_test.dart` | item icon cache > an item with no icon link stays generic and sends nothing | green |
| item-icons → The previous item's icon is never shown for a new item | A new scan shows the generic icon until its own icon is ready | `test/ui/item_icon_test.dart` | switching item shows generic until the new icon is ready | green |
| item-icons → The previous item's icon is never shown for a new item | A late download for the old item does not reach the new one | `test/ui/item_icon_test.dart` | a late completion for the old item never draws on the new one | green |
| item-icons → One download per item at a time | The card and a history row share one download | `test/application/item_icon_cache_test.dart` | item icon cache > two leases on one item share one request | green |
| item-icons → One download per item at a time | Showing the item again during a download starts no second one | `test/application/item_icon_cache_test.dart` | item icon cache > re-acquiring during a held download sends no second request | green |
| item-icons → A download nothing shows any more is cancelled | A newer scan cancels the older scan's download | `test/application/item_icon_cache_test.dart` | item icon cache > releasing the last lease aborts without a wait | green |
| item-icons → A download nothing shows any more is cancelled | A cancelled item downloads when shown again | `test/application/item_icon_cache_test.dart` | item icon cache > a cancelled item sends one new request when acquired again | green |
| item-icons → A download nothing shows any more is cancelled | A download still shown elsewhere is not cancelled | `test/application/item_icon_cache_test.dart` | item icon cache > releasing one of two leases keeps the download | green |
| item-icons → History rows show the item's icon | A row shows its item's icon | `test/ui/item_icon_surfaces_test.dart` | a history row shows its item's cached icon | green |
| item-icons → History rows show the item's icon | A row from another mode stays generic | `test/ui/item_icon_surfaces_test.dart` | a history row from another mode stays generic and acquires nothing | green |
| latest-accepted-scan → The answer strip can return to the latest scan | Return after a manual selection | `test/ui/latest_scan_card_test.dart` | Back to latest scan closes history on Map and Scanner | green |
| latest-accepted-scan → The answer strip can return to the latest scan | Return closes history | `test/ui/latest_scan_card_test.dart` | Back to latest scan closes history on Map and Scanner | green |
| latest-accepted-scan → The answer strip can return to the latest scan | Return resets FIR | `test/application/selection_controller_test.dart` | showScan > showScan resets FIR | green |
| latest-accepted-scan → The answer strip can return to the latest scan | No action while the latest scan is shown | `test/ui/latest_scan_card_test.dart` | no Back action while the latest scan is shown | green |
| latest-accepted-scan → The answer strip can return to the latest scan | No action without a latest scan | `test/ui/latest_scan_card_test.dart` | no Back action without or after clearing a latest scan | green |
| latest-accepted-scan → The answer strip can return to the latest scan | Stale return is refused | `test/application/selection_controller_test.dart` | showScan > showScan refuses a stale epoch, mode or missing item | green |
| latest-accepted-scan → Map shows scans in its one answer strip | No separate panel | `test/ui/latest_scan_card_test.dart` | latest-accepted-scan: No separate panel | green |
| latest-accepted-scan → Map shows scans in its one answer strip | Scan accepted with Map open | `test/ui/latest_scan_card_test.dart` | latest-accepted-scan: Scan accepted with Map open | green |
| latest-accepted-scan → Map shows scans in its one answer strip | Scan fenced with Map open | `test/ui/latest_scan_card_test.dart` | a fenced scan with Map open changes nothing | green |
| player-facing-text → Times are shown in local time | History row time | `test/ui/history_panel_test.dart` | a row observed today shows its local time without ISO | green |
| player-facing-text → Times are shown in local time | Earlier day | `test/ui/history_panel_test.dart` | player-facing-text: Earlier day | green |
| player-facing-text → Times are shown in local time | Missing flea quote time | `test/ui/freshness_tag_test.dart` | missing price time reads price time unknown | green |
| player-facing-text → Times are shown in local time | No UTC time in the inspector | `test/ui/shell_test.dart` | main windows keep diagnostic detail out > the Scanner inspector shows no UTC time | green |
| scan-correction → An unaccepted scan with a title offers a correction | Ambiguous scan with item A shown | `test/application/scan_correction_test.dart` | offers > ambiguous scan offers a correction and keeps the selection | green |
| scan-correction → An unaccepted scan with a title offers a correction | Below-similarity scan with nothing shown | `test/application/scan_correction_test.dart` | offers > below-similarity scan offers a correction with no recommendation | green |
| scan-correction → An unaccepted scan with a title offers a correction | Rejections that offer nothing | `test/application/scan_correction_test.dart` | offers > other rejection reasons offer nothing | green |
| scan-correction → An unaccepted scan with a title offers a correction | Failed scan | `test/application/scan_correction_test.dart` | offers > failed scan offers nothing | green |
| scan-correction → An unaccepted scan with a title offers a correction | Empty OCR text | `test/application/scan_correction_test.dart` | offers > empty OCR text offers nothing | green |
| scan-correction → An unaccepted scan with a title offers a correction | Mode changed before publication | `test/application/scan_correction_test.dart` | offers > scan from an older mode offers nothing | green |
| scan-correction → The offer searches the catalog from the scan's text | Words in another order | `test/domain/catalog_search_test.dart` | CatalogSnapshot.searchWords > every word must appear, in any order | green |
| scan-correction → The offer searches the catalog from the scan's text | Edited text | `test/application/scan_correction_test.dart` | search > editing the offer text searches without changing the selection | green |
| scan-correction → The offer searches the catalog from the scan's text | No results | `test/application/scan_correction_test.dart` | search > offer search with no match leaves the selection | green |
| scan-correction → Picking a correction makes it the current selection | Pick the runner-up | `test/ui/scan_correction_card_test.dart` | the offer lists candidates in rank order without scores | green |
| scan-correction → Picking a correction makes it the current selection | Pick from search | `test/ui/scan_correction_card_test.dart` | a search pick is labelled corrected from a scan | green |
| scan-correction → Picking a correction makes it the current selection | FIR from the earlier item | `test/application/scan_correction_test.dart` | picks > correcting to the scanned item resets FIR | green |
| scan-correction → Picking a correction makes it the current selection | History view open | `test/application/scan_correction_test.dart` | picks > a pick closes an open history view | green |
| scan-correction → Picking a correction makes it the current selection | History write fails | `test/application/scan_correction_test.dart` | picks > failed correction write keeps the correction with an error | green |
| scan-correction → A correction stops being current on a mode or session change | Session change after a correction | `test/application/scan_correction_test.dart` | after a pick > session change retires a correction | green |
| scan-correction → A correction stops being current on a mode or session change | Prices go stale after a correction | `test/application/scan_correction_test.dart` | after a pick > stale Flea quote downgrades a correction to Check | green |
| scan-correction → A correction is never a new accepted scan | Correction after an accepted scan | `test/application/scan_correction_test.dart` | after a pick > a correction is never an accepted scan | green |
| scan-correction → A correction is never a new accepted scan | Refresh after a correction | `test/application/scan_correction_test.dart` | after a pick > refresh after a correction records nothing new | green |
| scan-correction → Only the newest offer is current | Newer offer | `test/application/scan_correction_test.dart` | lifecycle > a newer offer replaces the older one | green |
| scan-correction → Only the newest offer is current | Accepted scan clears the offer | `test/application/scan_correction_test.dart` | lifecycle > an accepted scan clears the offer | green |
| scan-correction → Only the newest offer is current | Failure keeps the offer | `test/application/scan_correction_test.dart` | lifecycle > a later failure keeps the offer | green |
| scan-correction → Only the newest offer is current | Manual selection clears the offer | `test/application/scan_correction_test.dart` | lifecycle > manual selection clears the offer | green |
| scan-correction → Only the newest offer is current | Closing a history view keeps the offer | `test/application/scan_correction_test.dart` | lifecycle > closing a history view keeps the offer | green |
| scan-correction → Only the newest offer is current | Dismiss | `test/application/scan_correction_test.dart` | lifecycle > dismiss clears only the offer | green |
| scan-correction → Only the newest offer is current | Session change | `test/application/scan_correction_test.dart` | lifecycle > session change clears the offer | green |
| scan-correction → Only the newest offer is current | Re-notification | `test/application/scan_correction_test.dart` | lifecycle > a dismissed offer is not offered again | green |
| scan-correction → A stale pick changes nothing | Offer replaced before the pick | `test/application/scan_correction_test.dart` | stale picks > a pick from a replaced offer changes nothing | green |
| scan-correction → A stale pick changes nothing | Item removed by a catalog refresh | `test/application/scan_correction_test.dart` | stale picks > a pick of an item no longer in the catalog changes nothing | green |
| scan-correction → A stale pick changes nothing | Mode changed before the pick | `test/application/scan_correction_test.dart` | stale picks > a pick after a mode change changes nothing | green |
| scan-correction → The offer appears with the answer strip on Scanner and Map | Offer on Map | `test/ui/scan_correction_card_test.dart` | the offer lists candidates in rank order without scores | green |
| scan-correction → The offer appears with the answer strip on Scanner and Map | Navigation keeps the offer | `test/ui/scan_correction_card_test.dart` | the shared offer and query persist across Scanner and Map | green |
| scan-decisions → An accepted scan becomes the current selection | Accepted scan replaces a manual selection | `test/application/scan_decision_feed_test.dart` | accepted scan replaces a manual selection | green |
| scan-decisions → An accepted scan becomes the current selection | Manual selection after a scan | `test/application/selection_controller_test.dart` | selectScan > manual selection after a scan stays after refresh | green |
| scan-decisions → An accepted scan becomes the current selection | Accepted scan while a history row is open | `test/application/selection_controller_test.dart` | selectScan > accepted scan closes an open history row into the live mode | green |
| scan-decisions → An accepted scan becomes the current selection | Accepted scan after a correction | `test/application/scan_correction_test.dart` | picks > accepted scan after a correction replaces it | green |
| scan-decisions → Unaccepted scans never change the selection | Rejected scan with a candidate | `test/application/scan_decision_feed_test.dart` | rejected scan with a candidate changes nothing | green |
| scan-decisions → Unaccepted scans never change the selection | Failed scan after an accepted one | `test/application/scan_decision_feed_test.dart` | failed scan keeps the scanned item and its FIR | green |
| scan-decisions → Each accepted scan is consumed once | Refresh after an accepted scan | `test/application/scan_decision_feed_test.dart` | refresh after an accepted scan records nothing new | green |
| scan-decisions → Each accepted scan is consumed once | Unrelated notification | `test/application/scan_decision_feed_test.dart` | notification without a new accepted scan keeps the manual item | green |
| scan-decisions → Accepted scans are recorded in history as scans | Two scans of the same item | `test/application/history_controller_test.dart` | durable identity activity is unique by mode and no transient fields exist | green |
| scan-decisions → Accepted scans are recorded in history as scans | History write fails | `test/application/selection_controller_test.dart` | selectScan > failed scan history write keeps the decision with an error | green |
| scan-decisions → Scan advice shows its age and stops being current on a mode or session change | Prices go stale after a scan | `test/application/selection_controller_test.dart` | selectScan > stale Flea quote downgrades the scan to Check, acceptance unchanged | green |
| scan-decisions → Scan advice shows its age and stops being current on a mode or session change | Mode changes after a scan | `test/application/scan_decision_feed_test.dart` | mode change retires the scan and records nothing | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Desktop window | `test/ui/shell_test.dart` | scan evidence panel is fully on screen at 1660x870 | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Short desktop window | `test/ui/shell_test.dart` | scan evidence panel is on screen at 1100x720 with enlarged text | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Narrow window | `test/ui/shell_test.dart` | compact layout shows evidence without the old Scanner controls | green |
| scanner-evidence → Unaccepted scan evidence never produces a recommendation | Accepted scan drives the decision card | `test/ui/scanner_screen_test.dart` | accepted scan drives the decision card | green |
| scanner-evidence → Unaccepted scan evidence never produces a recommendation | Rejected scan with a best candidate | `test/application/scan_decision_feed_test.dart` | rejected scan with a candidate changes nothing | green |
| scanner-workspace → Scanner main column sections | Wide window places Why beside Prices | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Wide window places Why beside Prices | green |
| scanner-workspace → Scanner main column sections | Narrow window stacks the sections | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Narrow window stacks the sections | green |
| scanner-workspace → Scanner main column sections | No bordered card | `test/ui/scanner_workspace_test.dart` | scanner-workspace: No bordered card | green |
| scanner-workspace → Why lists the item's needs | Needs for a selected item | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Needs for a selected item | green |
| scanner-workspace → Why lists the item's needs | No item or unavailable item data | `test/ui/scanner_workspace_test.dart` | scanner-workspace: No item or unavailable item data | green |
| scanner-workspace → Why lists the item's needs | Warning that repeats the found-in-raid question | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Warning that repeats the found-in-raid question | green |
| scanner-workspace → Why lists the item's needs | Recording stopped | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Recording stopped | green |
| scanner-workspace → Why lists the item's needs | Needs unknown | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Needs unknown | green |
| scanner-workspace → Prices breaks the price down | Item with both prices | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Item with both prices | green |
| scanner-workspace → Prices breaks the price down | Item that cannot be sold on the Flea | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Item that cannot be sold on the Flea | green |
| scanner-workspace → Prices breaks the price down | Missing prices | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Missing prices | green |
| scanner-workspace → Scan evidence follows the details | Accepted scan | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Accepted scan | green |
| scanner-workspace → Scan evidence follows the details | No scan yet | `test/ui/scanner_workspace_test.dart` | scanner-workspace: No scan yet | green |
| scanner-workspace → Scanner inspector holds recent items and the live scan note | Recent items without clipping | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Recent items without clipping | green |
| scanner-workspace → Scanner inspector holds recent items and the live scan note | Relative ages | `test/ui/history_panel_test.dart` | scanner-workspace: Relative ages | green |
| scanner-workspace → Scanner inspector holds recent items and the live scan note | Ages move on while shown | `test/ui/history_panel_test.dart` | scanner-workspace: Ages move on while shown | green |
| scanner-workspace → Scanner inspector holds recent items and the live scan note | Empty history | `test/ui/scanner_workspace_test.dart` | scanner-workspace: Empty history | green |
| scanner-workspace → Scanner inspector holds recent items and the live scan note | History read fails | `test/ui/history_panel_test.dart` | scanner-workspace: History read fails | green |
| settings-diagnostics → Main windows keep diagnostic detail out of normal use | Accepted scan on the Scanner | `test/ui/shell_test.dart` | main windows keep diagnostic detail out > main windows show no diagnostic detail for an accepted scan | green |
| settings-diagnostics → Main windows keep diagnostic detail out of normal use | Rejected scan with a correction offer | `test/ui/shell_test.dart` | main windows keep diagnostic detail out > main windows show no diagnostic detail beside a correction offer | green |
| settings-diagnostics → Main windows keep diagnostic detail out of normal use | Corrected scan subtitle | `test/ui/scan_correction_card_test.dart` | a picked correction is titled and aged as not accepted | green |
| settings-diagnostics → Problems the player must act on stay on the main windows | Rejected scan still explains itself | `test/ui/scan_evidence_panel_test.dart` | rejected report gives a plain reason with the best candidate not accepted | green |
| settings-diagnostics → Problems the player must act on stay on the main windows | Errors the player must act on stay visible | `test/ui/shell_test.dart` | main windows keep diagnostic detail out > catalog error and recording stop note stay on the Scanner | green |
| settings-diagnostics → Problems the player must act on stay on the main windows | Tracker error stays reachable | `test/ui/settings_page_shell_test.dart` | settings-diagnostics: Tracker error stays reachable | green |
| settings-page → Settings opens as a page | Open and go back | `test/ui/settings_page_shell_test.dart` | settings-page: Open and go back | green |
| settings-page → Settings opens as a page | Inspector hidden while open | `test/ui/settings_page_shell_test.dart` | settings-page: Inspector hidden while open | green |
| settings-page → Settings opens as a page | Switch area from Settings | `test/ui/settings_page_shell_test.dart` | settings-page: Switch area from Settings | green |
| settings-page → Settings opens as a page | Choose the area Settings was opened from | `test/ui/settings_page_shell_test.dart` | settings-page: Choose the area Settings was opened from | green |
| settings-page → Settings opens as a page | Item search from Settings | `test/ui/settings_page_shell_test.dart` | settings-page: Item search from Settings | green |
| settings-page → Settings opens as a page | Escape with an unsaved invalid edit | `test/ui/settings_page_shell_test.dart` | settings-page: Escape with an unsaved invalid edit | green |
| settings-page → Settings opens as a page | Map keys while Settings is open | `test/ui/settings_page_shell_test.dart` | settings-page: Map keys while Settings is open | green |
| settings-page → Settings opens as a page | Escape with a valid edit | `test/ui/settings_page_shell_test.dart` | settings-page: Escape with a valid edit | green |
| settings-page → Settings opens as a page | Scan while Settings is open | `test/ui/settings_page_shell_test.dart` | settings-page: Scan while Settings is open | green |
| settings-page → Settings opens as a page | Settings action while open | `test/ui/settings_page_shell_test.dart` | settings-page: Settings action while open | green |
| verdict-presentation → One plate per verdict | Each verdict has its style | `test/ui/verdict_plate_test.dart` | each verdict has its plate style in both rooms | green |
| verdict-presentation → One plate per verdict | Verdicts differ without colour | `test/ui/verdict_plate_test.dart` | Keep, Flea and Price unavailable differ by fill and border | green |
| verdict-presentation → One plate per verdict | No plate is drawn in the accent | `test/ui/verdict_plate_test.dart` | no plate uses accent or accent-text | green |
| verdict-presentation → One-line verdict reason | Keep names the need that decided it | `test/domain/verdict_reason_test.dart` | Keep names the first actionable need with its count | green |
| verdict-presentation → One-line verdict reason | Keep with an unknown count | `test/domain/verdict_reason_test.dart` | Keep with an unknown count has no number | green |
| verdict-presentation → One-line verdict reason | Keep for later names the future need | `test/domain/verdict_reason_test.dart` | Keep for later names the first future need | green |
| verdict-presentation → One-line verdict reason | Check names the first open question | `test/domain/verdict_reason_test.dart` | Check with only found in raid open names it | green |
| verdict-presentation → One-line verdict reason | Check picks questions in a fixed order | `test/domain/verdict_reason_test.dart` | Check names the first open input in the fixed order | green |
| verdict-presentation → One-line verdict reason | Check wording for each open input | `test/domain/verdict_reason_test.dart` | Check wording for each open input | green |
| verdict-presentation → One-line verdict reason | Found in raid unknown outranks the needs it leaves open | `test/domain/verdict_reason_test.dart` | found in raid outranks an unresolved found-in-raid need | green |
| verdict-presentation → One-line verdict reason | Found in raid unknown names the first need that requires it | `test/domain/verdict_reason_test.dart` | Found in raid unknown names the first need that requires it | green |
| verdict-presentation → One-line verdict reason | Needs that do not apply are skipped | `test/domain/verdict_reason_test.dart` | Needs that do not apply are skipped | green |
| verdict-presentation → One-line verdict reason | Found in raid unknown with no need that requires it | `test/domain/verdict_reason_test.dart` | Check with only found in raid open names it | green |
| verdict-presentation → One-line verdict reason | Flea and Trader compare the prices | `test/domain/verdict_reason_test.dart` | Flea compares gross prices with the best trader | green |
| verdict-presentation → One-line verdict reason | Trader for each way the engine reaches it | `test/domain/verdict_reason_test.dart` | Trader wording for each engine path | green |
| verdict-presentation → One-line verdict reason | Flea with no trader offer | `test/domain/verdict_reason_test.dart` | Flea with no trader offer | green |
| verdict-presentation → One-line verdict reason | Price unavailable | `test/domain/verdict_reason_test.dart` | Price unavailable wording | green |
| verdict-presentation → One-line verdict reason | A long reason at the narrowest card | `test/ui/shell_test.dart` | long catalog reason wraps fully inside the shared strip | green |
| verdict-presentation → Price freshness tag | Current prices | `test/ui/freshness_tag_test.dart` | fresh tag reads Prices and time | green |
| verdict-presentation → Price freshness tag | Stale prices | `test/ui/freshness_tag_test.dart` | stale tag uses warning style | green |
| verdict-presentation → Price freshness tag | Unknown or future price time | `test/ui/freshness_tag_test.dart` | missing price time reads price time unknown | green |
| verdict-presentation → Price freshness tag | The tag turns stale while shown | `test/ui/freshness_tag_test.dart` | tag turns stale on the age notify with a fake clock | green |
| verdict-presentation → Price freshness tag | No tag when the Flea price cannot matter | `test/ui/freshness_tag_test.dart` | no tag on the price row | green |
| workspace-shell → Selection semantics survive the new layout | Selection changes across areas | `test/ui/shell_test.dart` | workspace-shell: Selection changes across areas | green |
| workspace-shell → Selection semantics survive the new layout | History and later rejected scan | `test/ui/shell_test.dart` | workspace-shell: History and later rejected scan | green |
| workspace-shell → Answer precedes the workspace | Answer first in both areas | `test/ui/shell_test.dart` | workspace-shell: Answer first in both areas $size $room | green |
| workspace-shell → Answer precedes the workspace | Missing item and long reason | `test/ui/shell_test.dart` | workspace-shell: Missing item and long reason | green |
| workspace-shell → Answer precedes the workspace | Price and stable normal height | `test/ui/shell_test.dart` | workspace-shell: Price and stable normal height | green |
| workspace-shell → Answer precedes the workspace | Found in raid sits beside the verdict | `test/ui/shell_test.dart` | workspace-shell: Found in raid sits beside the verdict | green |
| workspace-shell → Answer precedes the workspace | Provenance line | `test/ui/shell_test.dart` | workspace-shell: Provenance line | green |
| workspace-shell → Answer precedes the workspace | Provenance age moves on | `test/ui/shell_test.dart` | workspace-shell: Provenance age moves on | green |
| workspace-shell → Answer precedes the workspace | Price block with both prices | `test/ui/shell_test.dart` | workspace-shell: Price block with both prices | green |
| workspace-shell → Answer precedes the workspace | Long reason with Found in raid at 1300px | `test/ui/real_fonts_layout_test.dart` | workspace-shell: Long reason with Found in raid at 1300px | green |
| workspace-shell → Answer precedes the workspace | Price block without a Flea price | `test/ui/shell_test.dart` | workspace-shell: Price block without a Flea price | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Wide navigation | `test/ui/shell_test.dart` | workspace-shell: Wide navigation | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Narrow navigation and disabled timers | `test/ui/shell_test.dart` | workspace-shell: Narrow navigation and disabled timers | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Anchored search results and explicit selection | `test/ui/shell_test.dart` | workspace-shell: Anchored search results and explicit selection | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Wide tools alignment | `test/ui/shell_test.dart` | workspace-shell: Wide tools alignment | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Segmented area switch | `test/ui/shell_test.dart` | workspace-shell: Segmented area switch | green |
| workspace-shell → Inspector preserves the workspace | Docked details | `test/ui/shell_test.dart` | workspace-shell: Docked details | green |
| workspace-shell → Inspector preserves the workspace | Resize with open details | `test/ui/shell_test.dart` | workspace-shell: Resize with open details | green |
| workspace-shell → Inspector preserves the workspace | Scanner history leads the inspector | `test/ui/shell_test.dart` | workspace-shell: Scanner history leads the inspector | green |
| workspace-shell → Inspector preserves the workspace | Initial inspector state follows window width | `test/ui/shell_test.dart` | workspace-shell: Initial inspector state follows window width | green |
| workspace-shell → Inspector preserves the workspace | Map inspector holds working lists | `test/ui/shell_test.dart` | workspace-shell: Map inspector holds working lists | green |
| workspace-shell → History rows show item pictures | History selection | `test/ui/history_panel_test.dart` | workspace-shell: History selection | green |
| workspace-shell → History rows show item pictures | Missing history picture | `test/ui/history_panel_test.dart` | workspace-shell: Missing history picture | green |
| workspace-shell → History rows show item pictures | Legacy history verdict | `test/ui/history_panel_test.dart` | workspace-shell: Legacy history verdict | green |
| workspace-shell → History rows show item pictures | Rows from another game mode | `test/ui/history_panel_test.dart` | workspace-shell: Rows from another game mode | green |
| workspace-shell → History rows show item pictures | Imported scan row | `test/ui/history_panel_test.dart` | an imported scan row says Imported scan | green |

## 1. Domain wording and ages

- [x] 1.1 Write failing tests in `test/domain/verdict_reason_test.dart` for `Found in raid unknown names the first need that requires it` and `Needs that do not apply are skipped`, and a test for the shared `needTitle` ("Medstation level 1" for a station level, the task name for a task). Verify they fail on today's wording.
- [x] 1.2 Add `needTitle(ItemRequirement)` in `lib/domain` and use it from `lib/domain/verdict_reason.dart` (first need with `foundInRaid == true && state == NeedState.unresolved`, in engine order) and from `lib/ui/requirement_rows.dart`. Verify `test/domain/verdict_reason_test.dart` and the requirement-rows tests pass, flip the two rows green, and re-run the green `verdict-presentation` reason rows.
- [x] 1.3 Add `relativeAgeLabel(observedAt, now)` to `lib/ui/labels.dart` ("just now" under 10 s, then "N s", "N min", "N h", "N d", floored; a future time is "just now"), test first with a unit test covering each boundary. Verify the test passes.

## 2. Answer strip

- [x] 2.1 Write failing widget tests in `test/ui/shell_test.dart` for `Found in raid sits beside the verdict`, `Price block with both prices`, `Long reason with Found in raid at 1300px`, `Price block without a Flea price`, `Price and stable normal height` (at most 100px, equal to the empty state), `Provenance line` and `Provenance age moves on` (injected clock and tick period, no sleeps). Verify each fails for the expected reason.
- [x] 2.2 Rebuild `lib/ui/answer_strip.dart` per D3: who block (icon, name, provenance line per D12), `Expanded` answer group with plate and a labelled "Found in raid" `SegmentedButton<FirState>` in a `Wrap` (14px gap) and the reason below, then the price block `flex: none` at the right end. Place the close-history and "Back to latest scan" buttons between the answer group and the price block. Add the `caption` slot inline after the control (D6), passed `null`. Add one small age-tick widget (injected period, 5 s default; clock `services.selection.clock`) used by the provenance line. Verify the 2.1 tests pass and flip their rows green.
- [x] 2.3 Move `CorrectionOfferBlock` to `lib/ui/correction_offer_block.dart` and update the strip tests that read 'Accepted scan' / 'Corrected scan' (`test/ui/latest_scan_card_test.dart`, `test/ui/scan_correction_card_test.dart`) to the provenance line. Verify those files pass, flip their `latest-accepted-scan`, `scan-correction` and `settings-diagnostics` (`Corrected scan subtitle`) rows green, and re-run the green rows of `scan-decisions`, `scan-correction` and `latest-accepted-scan` in `test/application`.

## 3. Scanner main column

- [x] 3.1 Write failing widget tests in `test/ui/scanner_workspace_test.dart` for the `scanner-workspace` rows of Scanner main column sections, Why, Prices and Scan evidence (wide 1660×870 and narrow 1100×720 with the inspector docked geometry, the content edge after padding, no bordered card, totals summary, warnings without the found-in-raid one, empty states, per-slot values). Verify they fail because the sections do not exist.
- [x] 3.2 Build the main column per D1 in `lib/ui/scanner_screen.dart`: one scroll view of flat `ScannerSection`s, `RecordingStopNote` first, Why and Prices side by side at ≥720px and stacked below, Scan evidence last; extract the `RequirementPanel` and `ScanEvidencePanel` bodies. Verify the 3.1 tests and `test/ui/scan_evidence_panel_test.dart` pass, update `test/ui/scanner_screen_test.dart` for `Desktop window` / `Short desktop window` / `Narrow window`, and flip the `scanner-workspace` and `scanner-evidence` rows green.

## 4. Scanner inspector and history rows

- [x] 4.1 Write failing tests in `test/ui/history_panel_test.dart` and `test/ui/scanner_workspace_test.dart` for `Recent items without clipping`, `Relative ages`, `Ages move on while shown` (injected clock and period), `Empty history`, `History read fails`, `Rows from another game mode`, `Imported scan row`, `History row time` and `Earlier day`. Verify they fail on today's clock-time subtitles and fixed-height box.
- [x] 4.2 Rebuild the Scanner inspector per D2 in `lib/ui/shell.dart`: `Column[Expanded(CustomScrollView(header, lazy SliverList)), pinned Live scan note]`, X14 one-line rows with relative age, the mode tag (D11) and the "Imported scan" tag (D13), sharing the age-tick widget from 2.2. Remove the `SizedBox(230)` and the three accordions and their flags. Verify the 4.1 tests pass, update `test/ui/shell_test.dart` `Docked details`, `Resize with open details` and `Scanner history leads the inspector`, and flip those rows green; re-run the green `workspace-shell` history rows and `item-icons` row tests.

## 5. Retire the card and the Sources panel

- [x] 5.1 Move the catalog-error tests from `test/ui/data_sources_panel_test.dart` to `test/ui/settings_page_test.dart` (`Failure shown in the panel`, `Error cleared by a successful refresh`, `Item names that could not be loaded`) and add `Tracker error stays reachable` and `Errors the player must act on stay visible` (status bar word opens the Settings section with the error text). Verify they fail.
- [x] 5.2 Show `catalog.error` and the localization errors as the Item data `SettingsRow` message in error ink (D10), and the Tracker error as "Tracker problem: <error>" in error ink in Tracker progress (D13). Delete `ItemDecisionCard` (with `scanAgeLabel`), `SourcePanel` and `test/ui/data_sources_panel_test.dart`. Move the tests that mounted the card to the strip and the Prices section (`test/ui/freshness_tag_test.dart`, `test/ui/item_icon_surfaces_test.dart`, `test/ui/verdict_plate_test.dart`, `test/ui/decision_card_text_test.dart`, `test/support/m1_widget_harness.dart`); the player-facing-text "Unknown found-in-raid state" test moves to the strip, and its scenario's leftover "decision card" wording waits for the later spec cleanup. Verify those files pass and flip the `catalog-authority`, `settings-diagnostics`, `verdict-presentation` freshness and `item-icons` rows green.

## 6. Top bar

- [x] 6.1 Write failing tests in `test/ui/shell_test.dart` for `Segmented area switch`, `Wide tools alignment` (search at most 480px; Stats, Import, Settings as text buttons with Settings last) and in `test/ui/settings_page_shell_test.dart` for `Choose the area Settings was opened from`; update the settings-page tests' `_settingsAction` finder from `OutlinedButton` to the new button. Verify the new tests fail.
- [x] 6.2 Implement D8 in `lib/ui/shell.dart`: `SegmentedButton<int>` keeping the `nav-map` / `nav-scanner` keys, `emptySelectionAllowed` with no selection while Settings is open, search in `ConstrainedBox(maxWidth: 480)`, `TextButton.icon` actions in the order Stats, Import, Settings. Verify `test/ui/shell_test.dart` and `test/ui/settings_page_shell_test.dart` pass and flip the `workspace-shell` top bar and `settings-page` rows green.
- [x] 6.3 Update DESIGN.md: X11 action order (Stats, Import, Settings) and segmented area switch; X14 mode and "Imported scan" tags and relative age. Verify by reading the X11 and X14 sections against D8, D11 and D13.

## 7. Integration and sign-off

- [x] 7.1 Confirm every test map row is green, each with a test by that name. Verify by listing rows still marked red and finding none.
- [x] 7.2 Run `dart format`, `mise run analyze` and `mise run test`. Verify all pass offline, with no game running and none launched.
- [x] 7.3 Run `openspec validate restyle-scanner-workspace --strict` and `mise run release-notes -- --check openspec/changes/restyle-scanner-workspace/proposal.md`; set the PR number in the Release Notes. Verify both pass.
- [ ] 7.4 [user] The owner signs off the Scanner design against the B view of `.impeccable/preview/ember-directions.html` (M8.5 exit criterion), including two deliberate departures from the mockup's who line: "Chosen by hand" (mockup: "Picked by search · just now") and "Current advice · saved …" (mockup: "History · …"). Recorded as unverified until the owner reports it.
