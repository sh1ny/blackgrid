# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: The decision card shows the item's icon`
- TO: `### Requirement: The answer strip shows the item's icon`

## MODIFIED Requirements

### Requirement: The answer strip shows the item's icon

The answer strip, on Scanner and on Map, in wide and narrow layouts, SHALL show the shown item's icon. It SHALL show the generic item icon while the icon loads, when it failed, when the item has no picture, or when the icon cannot be decoded. The strip SHALL NOT show the `Identity only • no artwork` label.

#### Scenario: Scanner shows the icon

- **WHEN** the answer strip on Scanner shows an item whose icon is cached
- **THEN** the strip shows that icon in place of the generic item icon

#### Scenario: Map's compact card shows the icon

- **WHEN** the answer strip on Map shows an item whose icon is cached
- **THEN** the strip shows that icon next to the item's name

#### Scenario: The generic icon shows while loading or offline

- **WHEN** the strip shows an item whose icon is still downloading or whose download failed
- **THEN** the strip shows the generic item icon

#### Scenario: An undecodable icon falls back

- **WHEN** a cached icon file cannot be decoded as an image
- **THEN** the strip shows the generic item icon and no error

### Requirement: Icons download only for shown items

Blackgrid SHALL request an item's icon only while the answer strip or a visible history row shows that item and the item has an icon link. It SHALL NOT prefetch icons in bulk, for catalog items not shown, or for an item with no icon link.

#### Scenario: Showing an uncached item downloads its icon once

- **WHEN** the answer strip shows an item with an icon link and no cached icon
- **THEN** exactly one GET is sent to that icon link, and the icon is shown after it completes

#### Scenario: A catalog refresh downloads nothing

- **WHEN** a catalog with 5,000 items that have icon links is committed and no item is shown
- **THEN** no icon request is sent

#### Scenario: An item without a picture sends no request

- **WHEN** the answer strip shows an item with no icon link
- **THEN** no icon request is sent, and the generic icon is shown

### Requirement: The previous item's icon is never shown for a new item

The icon shown with an item SHALL always be that item's own icon or the generic icon. When the shown item changes, the previous item's icon SHALL NOT be drawn for the new item, even for one frame, including when the previous item's download completes after the change.

#### Scenario: A new scan shows the generic icon until its own icon is ready

- **WHEN** the strip showed item A's icon and a newer scan shows uncached item B
- **THEN** the strip shows the generic icon until B's icon is ready, then B's icon

#### Scenario: A late download for the old item does not reach the new one

- **WHEN** the strip moves from item A to item B and A's download completes afterwards
- **THEN** the strip keeps showing B's icon or the generic icon, never A's

### Requirement: One download per item at a time

At most one icon request SHALL be in flight for an item at a time, however many places show it. Every place that shows the item SHALL receive the result of that one request.

#### Scenario: The card and a history row share one download

- **WHEN** the answer strip and a history row show the same uncached item at the same time
- **THEN** exactly one GET is sent, and both show the icon after it completes

#### Scenario: Showing the item again during a download starts no second one

- **WHEN** an item is hidden and shown again while its download is still in flight and still requested elsewhere
- **THEN** no second GET is sent for that item

### Requirement: A download nothing shows any more is cancelled

When every place that requested an item's icon stops showing that item before its download completes, Blackgrid SHALL cancel that download. A cancelled download SHALL store nothing and SHALL NOT start the 24-hour wait.

#### Scenario: A newer scan cancels the older scan's download

- **WHEN** a scan shows item A, A's download is in flight, and a newer scan shows item B before it completes
- **THEN** A's request is aborted, nothing is cached for A, and B's icon is requested

#### Scenario: A cancelled item downloads when shown again

- **WHEN** item A's download was cancelled and A is shown again later
- **THEN** one new GET is sent for A

#### Scenario: A download still shown elsewhere is not cancelled

- **WHEN** the strip moves from item A to item B while a visible history row still shows A
- **THEN** A's download continues and its icon is shown in the history row

### Requirement: History rows show the item's icon

Each Recent item activity row whose item is in the current catalog SHALL show that item's icon, with the same generic fallback as the answer strip. A row whose item is not in the current catalog SHALL show the generic icon and request nothing.

#### Scenario: A row shows its item's icon

- **WHEN** a history row's item is in the current catalog and its icon is cached
- **THEN** the row's leading icon is the item's icon

#### Scenario: A row from another mode stays generic

- **WHEN** a history row's mode differs from the current catalog's mode
- **THEN** the row shows the generic icon and no icon request is sent for it
