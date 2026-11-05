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
  dart run tool/maps/prepare.dart check --packs <pack-root>
  dart run tool/maps/prepare.dart refresh --packs <repo-relative-pack-root> --pubspec <pubspec.yaml>

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

acquire is the only network operation exposed by this CLI. normalize preserves
dependency-closed source SVG and native effect metadata without compiler
execution. compile is a separate step that compiles the normalized vectors.
rebuild performs normalize+compile offline. check and refresh also rebuild
offline from the exact frozen inputs carried by the active generation:
`mise run maps:rebuild` does not download fresh metadata. Each step reads
pubspec.lock once, before any write, and records the resolved xml, image,
vector_graphics_compiler, vector_graphics and vector_graphics_codec versions
as the manifest toolchain; compile replaces the normalize-time record. Every
vector is compiled twice and a build fails when the two outputs differ.
validate/promote bind canonical vector component paths and actual compiled
payloads to dependency-closed source SVGs: validation recompiles every vector
from its evidence and requires identical bytes, and every payload header must
match the manifest's vectorCodecFormat. Only preparation version 3 with a
vectorCodecFormat validates. Preparation v3
preserves v2's content-addressed original PNG witnesses for transparent tiles;
empty records are decoded and hash-bound just like visible tiles, not inferred
from byte size or trusted from the manifest. Crops must remain wholly inside
the unchanged original artwork frame. New rebuilds require v3's complete
inventory; old raw partial inputs do not silently become complete candidates.
promote atomically replaces only active.json. refresh keeps only the active
generation. No command mutates an active version.
check rebuilds the active generation offline from the inputs it carries, into
a system temp folder that is always deleted, and succeeds only when every file
and manifest value matches except the recorded toolchain. It fails before
anything else when an interrupted promotion left active.next.json or a
versions/.<id>.staging folder. A mismatch ends with the instruction to run
mise run maps:rebuild.
The CLI's refresh rebuilds the active generation from its carried inputs; it
does not acquire a new source snapshot. An explicit metadata renewal is an
apply-time staged operation through `refreshActive(metadataInputs: ...)`: verify
the active generation, acquire only the six fixed regular-mode REST responses
into a fresh stage, then derive `FrozenInputs.withMetadata` from the committed
generation-backed build-read closure. The derived index changes only those six
hashes; all other carried and missing source behavior stays unchanged, so
unused historical index entries are not materialized and artwork is not
fetched. Do not use `acquire` for this boundary or add a refresh CLI flag. The
existing refresh owner verifies the baseline and source closure, rebuilds and
validates every map, then rejects any changed preserved output or reviewed
marker floor assignment before it prints the report or promotes.

Both refresh paths fail first on an incomplete pubspec.lock, an interrupted
promotion or missing/duplicated/misordered pubspec markers. After validation,
the existing owner reports changed maps and requires the owner to check them
before merge, rewrites the pubspec lines between the "BEGIN/END generated map
pack assets" markers, promotes the candidate, prunes superseded generations
and removes the candidate. A failure after rebuilding starts keeps and names
the candidate; follow its reported recovery state rather than deleting it or
retrying blindly. Run the offline CLI refresh as mise run maps:rebuild.
assets prints the complete pubspec assets section for the promoted generation;
Flutter directory declarations do not recursively include nested tiles.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.singleOrNull == '--help') {
    stdout.write(usage);
    return;
  }
  try {
    await runPrepare(arguments);
  } catch (error) {
    stderr.writeln('Map preparation failed: $error');
    exitCode = 1;
  }
}

/// Runs one preparation operation from command-line [arguments].
///
/// Reads the resolved toolchain from [lockPath] before any write.
/// [candidateParent] is where `refresh` creates its candidate (default `.dart_tool/maps`). Throws
/// on any failure; [main] reports it.
Future<void> runPrepare(
  List<String> arguments, {
  String lockPath = 'pubspec.lock',
  Directory? candidateParent,
}) async {
  Future<Map<String, String>> readToolchain() async =>
      toolchainFromLock(await File(lockPath).readAsString());
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
    'assets' || 'check' => {'--packs'},
    'refresh' => {'--packs', '--pubspec'},
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
        await FrozenInputs.open(Directory(values['--raw']!)),
        Directory(values['--candidate']!),
        compileVectors: command == 'rebuild',
        toolchain: await readToolchain(),
      );
      stdout.write(
        canonicalJson({
          'operation': command,
          'maps': (manifest['maps'] as List).length,
          'vectorsCompiled': manifest['vectorsCompiled'],
        }),
      );
    case 'compile':
      await compileCandidate(
        Directory(values['--candidate']!),
        toolchain: await readToolchain(),
      );
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
    case 'check':
      stdout.writeln(
        await checkActive(
          Directory(values['--packs']!),
          toolchain: await readToolchain(),
        ),
      );
    case 'refresh':
      final result = await refreshActive(
        Directory(values['--packs']!),
        File(values['--pubspec']!),
        toolchain: await readToolchain(),
        assetRoot: values['--packs']!,
        candidateParent: candidateParent,
      );
      stdout.writeln('Map pack ${result.id} is now active.');
    case 'assets':
      final root = requireRepoRelativePackRoot(values['--packs']!);
      stdout.writeln('  assets:');
      for (final line in mapPackAssetLines(
        root,
        await preparedAssetDirectories(Directory(root)),
      )) {
        stdout.writeln(line);
      }
  }
}
