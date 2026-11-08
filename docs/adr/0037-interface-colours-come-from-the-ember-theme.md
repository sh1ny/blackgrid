# 0037 - Interface colours come from the Ember theme

- Status: accepted
- Date: 2026-11-08 (change `adopt-ember-theme`)
- Source: change `adopt-ember-theme` (decisions D10 and D11)

## Context and problem

The interface took its colours from `lib/ui/theme.dart` (`GridColors`, a gold-on-black palette) and from colour literals scattered through widgets. The brand kit under `brand/` now defines the Ember palette, type and radii as generated tokens, and the M8.5 changes after this one (`add-answer-strip`, `restyle-dialogs`, `restyle-map-workspace`) all restyle screens against it. Without a stated contract, each of them could reintroduce literals, and nothing in the architecture index says where interface colour comes from.

## Decision

- **Screens take colours, type, radii and control sizes only from the Ember theme.** That means `EmberColors` and `EmberType` (generated from the brand tokens) and the Blackgrid extension that holds Blackgrid's own roles. Widgets read them through `Theme.of(context)`.
- **Blackgrid roles never go into the shared kit.** The kit under `brand/` stays product-neutral; verdict and map-related roles live in the Blackgrid extension.
- **The generated tokens are a byte-identical copy of the kit's.** `lib/ui/ember/` carries the kit output unchanged, so a kit update is a copy, not a merge. The kit generator drops its `dart:ui` `FontFeature` import (owner-approved), because `package:flutter/material.dart` already exports it.
- **An offline source check enforces the rule.** `test/ui/theme_source_test.dart` scans `lib/ui/**.dart`, except `lib/ui/ember/`, for colour literals (`Color(`, `Color.fromARGB/RGBO(`, `Colors.<name>` other than `transparent`) outside comments, and names the file and line.
- **The map palette is the named exception, and ADR-0023 owns it.** Map colours in `lib/maps/` and `lib/domain/map_zone_style.dart` stay outside the check. The map colours still built in `lib/ui` (the player marker fill, the place label colour, the extract label colours and the marker bubble's leader line) move to `lib/maps/map_palette.dart` as `Color` constants with unchanged values, and the painters read them from there. `restyle-map-workspace` is the change that may alter them.

## Rejected alternatives

- **No ADR, with DESIGN.md as the only authority:** the architecture index would say nothing about the interface layer's contract that later M8.5 changes must follow.
- **A custom analyzer lint plugin for the colour rule:** much more cost for the same guarantee as a source-scanning test.

## Consequences

- A new screen that needs a colour adds a role to the Blackgrid extension (or uses an Ember role) instead of a literal; the source check fails otherwise.
- Updating the brand kit means regenerating and copying its tokens; any Blackgrid-only need goes in the extension.
- Map colours stay changeable in one place, `lib/maps/map_palette.dart`, under ADR-0023 and the map changes.
- **Reversal cost:** low. The rule is a test and a directory convention; dropping it needs no data or format change.
