import 'dart:io';

import 'pack.dart';

const usage = '''Independent offline map preparation (standalone Dart)
  dart run tool/maps/prepare.dart acquire --raw <fresh-directory>
  dart run tool/maps/prepare.dart rebuild --raw <frozen-directory> --candidate <fresh-directory>
  dart run tool/maps/prepare.dart normalize --raw <frozen-directory> --candidate <fresh-directory>
  dart run tool/maps/prepare.dart compile --candidate <normalized-directory>
  dart run tool/maps/prepare.dart validate --candidate <compiled-directory>
  dart run tool/maps/prepare.dart promote --candidate <compiled-directory> --packs <pack-root>
  dart run tool/maps/prepare.dart assets --packs <repo-relative-pack-root>

Preparation v3 requires the complete canonical inventory:
factory, customs, woods, shoreline, interchange, thelab, reserve, lighthouse,
streetsoftarkov, groundzero, terminal, icebreaker and labyrinth.
Artwork, metadata, marker/task/trader dictionaries, translations and published
terms are acquired into a fresh hash-locked raw generation. Source IDs are not
selector aliases: Labs uses the-lab, Streets streets-of-tarkov, Ground Zero
ground-zero and Labyrinth the-labyrinth upstream.

The selected SVGs use their original source viewBox, ordered floor groups and
publisher-declared attachments. Labs retains the original 2800-square display
frame, revision-one pins and the 256/175 display-to-native pixel conversion.
Icebreaker retains its original 4096-square frame and all 16 floor grids.
Customs and Reserve use tarkov.dev's default Abstract rendition: the publisher
SVG, with the tile-only floors (Customs fourth, Reserve second-through-fifth)
packaged as raster overlays in their own z4 tile frame and placed over the SVG
through the shared metadata transform. The SVG frame is the original
revision-zero pin basis, so stored pin coordinates are unchanged.
Ground Zero packages all four metadata-declared alternative raster grids; they
are not embedded SVG overlays and are not painted twice. Labyrinth uses the
actual interactive tiled backing; its selected metadata declares no SVG wrapper.

Unknown floors, source/frame/calibration changes, unsafe or non-local
references, missing paint targets and missing or malformed raster dependencies
fail explicitly. A <use> whose target is one of the known publisher-deleted
symbols (Customs path493, Streets stairs) is dropped, matching browser
rendering; any other missing symbol fails and none is synthesized. No partial
inventory or uncompiled-vector promotion is supported. Acquisition alone is
not evidence of source closure or independent placement/redistribution
qualification.

acquire is the only network operation. normalize preserves dependency-closed
source SVG and native effect metadata without compiler execution. compile is a
separate pinned pure-Dart adapter. rebuild performs normalize+compile offline.
validate/promote bind canonical vector component paths and actual compiled
payloads to dependency-closed source SVGs. Reviewed Interchange compiler/payload
identities avoid recompilation during validation; a new source is compiled once
per input identity and process with the pinned adapter flags. Preparation v3
preserves v2's content-addressed original PNG witnesses for transparent tiles;
empty records are decoded and hash-bound just like visible tiles, not inferred
from byte size or trusted from the manifest. Crops must remain wholly inside
the unchanged original artwork frame. Existing v1 packs lacking empty witnesses
must be rebuilt offline before this validator can promote them.
Existing published preparation-v2 three-map packs remain readable and validate
against their own frozen calibration/source evidence, not newer calibrations.
New rebuilds require v3's complete inventory; old raw partial inputs do not
silently become complete candidates.
promote retains prior versions and atomically replaces only active.json.
No command mutates an active version.
assets prints the complete pubspec assets section for the promoted generation;
Flutter directory declarations do not recursively include nested tiles.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.singleOrNull == '--help') {
    stdout.write(usage);
    return;
  }
  try {
    final command = arguments.first;
    final values = <String, String>{};
    for (var i = 1; i < arguments.length; i += 2) {
      if (i + 1 >= arguments.length ||
          !arguments[i].startsWith('--') ||
          values.containsKey(arguments[i])) {
        throw const FormatException('Expected unique --key value arguments');
      }
      values[arguments[i]] = arguments[i + 1];
    }
    final required = switch (command) {
      'acquire' => {'--raw'},
      'rebuild' || 'normalize' => {'--raw', '--candidate'},
      'compile' || 'validate' => {'--candidate'},
      'promote' => {'--candidate', '--packs'},
      'assets' => {'--packs'},
      _ => throw FormatException('Unknown operation $command'),
    };
    if (values.keys.toSet().difference(required).isNotEmpty ||
        required.difference(values.keys.toSet()).isNotEmpty) {
      throw FormatException(
        'Required arguments for $command: ${required.join(' ')}',
      );
    }
    switch (command) {
      case 'acquire':
        await acquireInputs(Directory(values['--raw']!));
      case 'rebuild' || 'normalize':
        final manifest = await rebuildCandidate(
          Directory(values['--raw']!),
          Directory(values['--candidate']!),
          compileVectors: command == 'rebuild',
        );
        stdout.write(
          canonicalJson({
            'operation': command,
            'maps': (manifest['maps'] as List).length,
            'vectorsCompiled': manifest['vectorsCompiled'],
          }),
        );
      case 'compile':
        await compileCandidate(Directory(values['--candidate']!));
      case 'validate':
        await validateCandidate(Directory(values['--candidate']!));
      case 'promote':
        final version = await promoteCandidate(
          Directory(values['--candidate']!),
          Directory(values['--packs']!),
        );
        stdout.write(
          canonicalJson({
            'version': version,
            'manifest': 'versions/$version/manifest.json',
          }),
        );
      case 'assets':
        final root = values['--packs']!.replaceAll('\\', '/');
        if (root.startsWith('/') ||
            root.contains(':') ||
            root
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..')) {
          throw const FormatException(
            'Asset declarations require a repo-relative pack root',
          );
        }
        final directories = await preparedAssetDirectories(Directory(root));
        stdout.writeln('  assets:');
        for (final directory in directories) {
          stdout.writeln('    - $root/$directory');
        }
    }
  } catch (error) {
    stderr.writeln('Map preparation failed: $error');
    exitCode = 1;
  }
}
