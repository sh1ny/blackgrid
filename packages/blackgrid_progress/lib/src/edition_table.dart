import 'edition_rules.dart';

/// The reviewed edition vocabulary and task restrictions, version 1.
const editionTable = EditionTable(
  version: 1,
  editions: {
    'standard',
    'left-behind',
    'prepare-for-escape',
    'edge-of-darkness',
    'unheard',
  },
  entries: {
    '666314b4d7f171c4c20226c3': EditionRule.allowed(
      {'edge-of-darkness', 'unheard'},
      source:
          'https://escapefromtarkov.fandom.com/wiki/The_Good_Times_-_Part_1; '
          'owner confirmed Unheard access on 2026-11-12',
    ),
  },
);
