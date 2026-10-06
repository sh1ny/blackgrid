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

The locked families are current Interchange SVG, Labs z4 tiles and all 16
Icebreaker z4 floors. Interchange uses the 1127.6852 x 947.02582 source frame,
not the older 977.09998-square artwork. acquire requires a new raw generation;
existing Streets raw/candidate directories are not inputs for this selection.

acquire is the only network operation. normalize preserves dependency-closed
source SVG and native effect metadata without compiler execution. compile is a
separate pinned pure-Dart adapter. rebuild performs normalize+compile offline.
validate/promote bind canonical vector component paths and actual compiled
payloads to dependency-closed source SVGs. Reviewed Interchange compiler/payload
identities avoid recompilation during validation; a new source is compiled once
per input identity and process with the pinned adapter flags. Preparation v2
bundles content-addressed original PNG witnesses for transparent source tiles;
empty records are decoded and hash-bound just like visible tiles, not inferred
from byte size or trusted from the manifest. Crops must remain wholly inside
the unchanged original artwork frame. Existing v1 packs lacking empty witnesses
must be rebuilt offline before this validator can promote them.
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
