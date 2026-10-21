# item-icons Specification

## Purpose
Shows each item's own icon from tarkov.dev on the decision card and on history rows. Icons are downloaded only when an item is shown, kept in a bounded local cache and revalidated rarely, so tarkov.dev sees about one request per item.

## Requirements

### Requirement: Icon links come only from the catalog and only from assets.tarkov.dev

The catalog SHALL keep an item's `iconLink` only when it is an HTTPS URL on host `assets.tarkov.dev` with no query, fragment, port or user info. tarkov.dev's shared `unknown-item-icon` placeholder SHALL count as no picture. Any other link SHALL be dropped without rejecting the item or the catalog.

#### Scenario: A valid asset link is kept

- **WHEN** a catalog item has `iconLink` `https://assets.tarkov.dev/5447a9cd4bdc2dbd208b4567-icon.webp`
- **THEN** the normalized item's icon link is that URL

#### Scenario: A link on another host, scheme or with a query is dropped

- **WHEN** a catalog item's `iconLink` is `http://assets.tarkov.dev/x-icon.webp`, `https://example.com/x-icon.webp` or `https://assets.tarkov.dev/x-icon.webp?v=2`
- **THEN** the normalized item has no icon link, and the item and the catalog still load

#### Scenario: The unknown-item placeholder means no picture

- **WHEN** a catalog item's `iconLink` is `https://assets.tarkov.dev/unknown-item-icon.jpg`
- **THEN** the normalized item has no icon link

#### Scenario: An item id that is unsafe in a file name writes nothing outside the cache folder

- **WHEN** a shown item's id is `../../x` or contains a backslash or `:`, and its icon link is valid
- **THEN** its icon is cached under a name that does not contain the id, and no file outside the icon folder is created, renamed or deleted

#### Scenario: A malformed link value is dropped

- **WHEN** a catalog item's `iconLink` is a number, an empty string or not a parseable URL
- **THEN** the normalized item has no icon link, and the catalog still loads

### Requirement: Stored catalogs from before icon links still load

A stored catalog projection written before icon links existed SHALL still load, with no icon link on any item. Its catalog schema and normalizer versions SHALL stay unchanged.

#### Scenario: An older projection loads without icons

- **WHEN** Blackgrid opens a stored catalog projection whose items have no `iconLink` key
- **THEN** the catalog loads with its items, and every item has no icon link

#### Scenario: The next refresh adds icon links

- **WHEN** a catalog refresh commits after an older projection was loaded
- **THEN** the active projection's items carry their accepted icon links

### Requirement: Icons download only for shown items

Blackgrid SHALL request an item's icon only while the decision card or a visible history row shows that item and the item has an icon link. It SHALL NOT prefetch icons in bulk, for catalog items not shown, or for an item with no icon link.

#### Scenario: Showing an uncached item downloads its icon once

- **WHEN** the decision card shows an item with an icon link and no cached icon
- **THEN** exactly one GET is sent to that icon link, and the icon is shown after it completes

#### Scenario: A catalog refresh downloads nothing

- **WHEN** a catalog with 5,000 items that have icon links is committed and no item is shown
- **THEN** no icon request is sent

#### Scenario: An item without a picture sends no request

- **WHEN** the decision card shows an item with no icon link
- **THEN** no icon request is sent, and the generic icon is shown

### Requirement: One download per item at a time

At most one icon request SHALL be in flight for an item at a time, however many places show it. Every place that shows the item SHALL receive the result of that one request.

#### Scenario: The card and a history row share one download

- **WHEN** the decision card and a history row show the same uncached item at the same time
- **THEN** exactly one GET is sent, and both show the icon after it completes

#### Scenario: Showing the item again during a download starts no second one

- **WHEN** an item is hidden and shown again while its download is still in flight and still requested elsewhere
- **THEN** no second GET is sent for that item

### Requirement: Cached icons have no time-based expiry

A cached icon SHALL stay usable until the item's icon link changes, until it is evicted for the size budget, or until its file is missing or unreadable. It SHALL NOT expire by age. When the icon link changes, Blackgrid SHALL download the new link the next time the item is shown and SHALL stop using the old file.

#### Scenario: An old icon is used without a download

- **WHEN** an item's icon was cached 400 days ago, was revalidated 10 days ago and is shown again with the same icon link
- **THEN** the cached icon is shown and no request is sent

#### Scenario: A changed icon link replaces the cached icon

- **WHEN** an item's cached icon came from link A and the current catalog gives link B
- **THEN** one GET is sent to B, the old icon is not shown for this item, and the cached file for A is removed after B is stored, unless B's stored file is the same file

#### Scenario: A missing icon file is downloaded again

- **WHEN** the cache's record for an item exists but its file was deleted
- **THEN** the generic icon is shown and one GET is sent to download it again

### Requirement: Shown icons are revalidated at most every 30 days

When a cached icon is shown and its last successful validation is 30 days old or older, Blackgrid SHALL send one conditional GET with the stored ETag. A `304` SHALL only refresh the validation time. A `200` SHALL replace the icon. The cached icon SHALL stay shown during revalidation and after a failed one.

#### Scenario: Revalidation inside 30 days sends nothing

- **WHEN** a cached icon validated 29 days ago is shown
- **THEN** no request is sent

#### Scenario: An unchanged icon costs a 304

- **WHEN** a cached icon validated 30 days ago is shown and the server answers `304 Not Modified` to `If-None-Match`
- **THEN** the cached icon stays shown, its validation time becomes now, and the icon file is not rewritten

#### Scenario: A changed icon replaces the cached one

- **WHEN** revalidation of a cached icon gets a `200` with a valid image
- **THEN** the new image replaces the cached icon, and its new ETag and validation time are stored

#### Scenario: A 200 with identical bytes keeps the cached file

- **WHEN** revalidation of a cached icon gets a `200` whose body is byte-identical to the cached icon
- **THEN** the icon stays shown, its file is still present, its ETag and validation time are updated, and the next show sends no request

#### Scenario: A failed revalidation keeps the cached icon

- **WHEN** revalidation of a cached icon times out or gets a `500`
- **THEN** the cached icon stays shown and stays cached

### Requirement: A failed icon request is not retried for 24 hours

After an icon download or revalidation for an item and icon link fails, Blackgrid SHALL send no request for that item and link for 24 hours, including after a restart. A different icon link for the item SHALL clear the wait. A failure is a timeout, transport error, non-`200`/`304` status, redirect, oversized body or a body that is not an image. Other items SHALL be unaffected.

#### Scenario: Showing a failed item again sends nothing

- **WHEN** an item's download got a `404`, and the item is shown 50 times in the next 23 hours
- **THEN** no further request is sent for it, and the generic icon is shown each time

#### Scenario: The wait survives a restart

- **WHEN** an item's download failed and Blackgrid restarts within 24 hours and shows the item
- **THEN** no request is sent for it

#### Scenario: After 24 hours one new attempt is made

- **WHEN** an item whose download failed 24 hours ago is shown
- **THEN** exactly one GET is sent for it

#### Scenario: A new icon link clears the wait

- **WHEN** an item's download for link A failed and, within 24 hours, the catalog gives link B and the item is shown
- **THEN** exactly one GET is sent to B

#### Scenario: A failure for one item does not block another

- **WHEN** one item's download failed and a different uncached item is shown
- **THEN** one GET is sent for the different item

### Requirement: Icon downloads are bounded

Each icon request SHALL follow no redirect, time out after 15 seconds, and stop reading at 256 KiB. At most 4 icon requests SHALL be in flight at once. A body SHALL be stored only when it is a complete WebP, PNG or JPEG image.

#### Scenario: A redirect is a failure

- **WHEN** an icon request gets a `302` with a `Location` header
- **THEN** the redirect is not followed, nothing is cached, and the item's 24-hour wait starts

#### Scenario: An oversized body is a failure

- **WHEN** an icon response body exceeds 256 KiB
- **THEN** the request is aborted, nothing is cached, and the item's 24-hour wait starts

#### Scenario: A body that is not an image is a failure

- **WHEN** an icon response is `200` with an HTML body
- **THEN** nothing is cached, and the item's 24-hour wait starts

#### Scenario: A hung request times out

- **WHEN** an icon request sends no response for 15 seconds
- **THEN** the request is aborted, nothing is cached, and the item's 24-hour wait starts

#### Scenario: More than four shown items wait their turn

- **WHEN** six uncached items are shown at once
- **THEN** at most four icon requests are in flight at any time, and all six are downloaded once

### Requirement: A download nothing shows any more is cancelled

When every place that requested an item's icon stops showing that item before its download completes, Blackgrid SHALL cancel that download. A cancelled download SHALL store nothing and SHALL NOT start the 24-hour wait.

#### Scenario: A newer scan cancels the older scan's download

- **WHEN** a scan shows item A, A's download is in flight, and a newer scan shows item B before it completes
- **THEN** A's request is aborted, nothing is cached for A, and B's icon is requested

#### Scenario: A cancelled item downloads when shown again

- **WHEN** item A's download was cancelled and A is shown again later
- **THEN** one new GET is sent for A

#### Scenario: A download still shown elsewhere is not cancelled

- **WHEN** the card moves from item A to item B while a visible history row still shows A
- **THEN** A's download continues and its icon is shown in the history row

### Requirement: The icon cache stays within 64 MB

When the cached icon files exceed 64 MB in total, Blackgrid SHALL remove the least recently shown icons until the total is at or below 64 MB. Below 64 MB, it SHALL remove no icon for space.

#### Scenario: Below the budget nothing is evicted

- **WHEN** the cache holds 63 MB of icons and a new icon is stored
- **THEN** no cached icon is removed

#### Scenario: Above the budget the least recently shown icons go first

- **WHEN** storing a new icon brings the cache above 64 MB
- **THEN** the least recently shown icons are removed until the total is at or below 64 MB, and the icon just stored is kept

### Requirement: An interrupted icon write leaves no partial icon

Blackgrid SHALL show only complete, stored icon files. A file left by an interrupted download or write, or a file the cache does not record, SHALL be removed the next time the cache starts. It SHALL never be shown.

#### Scenario: A crash mid-write leaves nothing shown

- **WHEN** Blackgrid stops after writing part of an icon and restarts
- **THEN** the partial file is removed, the item shows the generic icon, and one GET is sent when it is shown

#### Scenario: Stray files are removed at start

- **WHEN** the icon folder holds a file the cache has no record for
- **THEN** the file is removed when the cache starts

### Requirement: The decision card shows the item's icon

The decision card on Scanner, in wide and narrow layouts, and on Map SHALL show the shown item's icon. It SHALL show the generic item icon while the icon loads, when it failed, when the item has no picture, or when the icon cannot be decoded. The card SHALL NOT show the `Identity only • no artwork` label.

#### Scenario: Scanner shows the icon

- **WHEN** Scanner's decision card shows an item whose icon is cached
- **THEN** the card shows that icon in place of the generic item icon

#### Scenario: Map's compact card shows the icon

- **WHEN** Map's decision card shows an item whose icon is cached
- **THEN** the card shows that icon next to the item's name

#### Scenario: The generic icon shows while loading or offline

- **WHEN** the card shows an item whose icon is still downloading or whose download failed
- **THEN** the card shows the generic item icon

#### Scenario: An undecodable icon falls back

- **WHEN** a cached icon file cannot be decoded as an image
- **THEN** the card shows the generic item icon and no error

### Requirement: The previous item's icon is never shown for a new item

The icon shown with an item SHALL always be that item's own icon or the generic icon. When the shown item changes, the previous item's icon SHALL NOT be drawn for the new item, even for one frame, including when the previous item's download completes after the change.

#### Scenario: A new scan shows the generic icon until its own icon is ready

- **WHEN** the card showed item A's icon and a newer scan shows uncached item B
- **THEN** the card shows the generic icon until B's icon is ready, then B's icon

#### Scenario: A late download for the old item does not reach the new one

- **WHEN** the card moves from item A to item B and A's download completes afterwards
- **THEN** the card keeps showing B's icon or the generic icon, never A's

### Requirement: History rows show the item's icon

Each Recent item activity row whose item is in the current catalog SHALL show that item's icon, with the same generic fallback as the decision card. A row whose item is not in the current catalog SHALL show the generic icon and request nothing.

#### Scenario: A row shows its item's icon

- **WHEN** a history row's item is in the current catalog and its icon is cached
- **THEN** the row's leading icon is the item's icon

#### Scenario: A row from another mode stays generic

- **WHEN** a history row's mode differs from the current catalog's mode
- **THEN** the row shows the generic icon and no icon request is sent for it
