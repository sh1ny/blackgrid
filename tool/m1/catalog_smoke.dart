import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> arguments) async {
  final directory = await Directory.systemTemp.createTemp(
    'blackgrid-real-catalog-',
  );
  final file = File('${directory.path}/catalog.sqlite');
  final httpClient = http.Client();
  final client = CatalogClient(client: httpClient);
  var database = BlackgridDatabase(NativeDatabase(file));
  final records = <Map<String, Object?>>[];
  try {
    for (final mode in [GameMode.pvp, GameMode.pve, GameMode.seasonal]) {
      try {
        final candidate = await client.fetch(mode);
        await database.commitCatalog(candidate);
        await database.close();
        database = BlackgridDatabase(NativeDatabase(file));
        final restored = await database.loadCatalog(mode);
        if (restored == null ||
            restored.revision != candidate.revision ||
            restored.items.isEmpty) {
          throw StateError('Durable catalog roundtrip failed.');
        }
        final example = restored.items.values.first;
        if (restored.search(example.id).every((i) => i.id != example.id)) {
          throw StateError('Canonical search failed.');
        }
        records.add({
          'mode': mode.name,
          'route': mode.catalogRoute,
          'status': 'passed',
          'datasets': restored.datasetCounts,
          'itemCount': restored.items.length,
          'traderCount': restored.traders.length,
          'requirementCount': restored.requirements.length,
          'localizationErrors': restored.localizationErrors,
          'observedAt': restored.observedAt.toUtc().toIso8601String(),
          'authoritative': restored.authoritativeAt(DateTime.now().toUtc()),
          'itemsSourceUpdate': restored.sourceTimestamps['items']
              ?.toUtc()
              .toIso8601String(),
          'canonicalSearch': true,
          'durableRoundtrip': true,
        });
      } catch (failure) {
        records.add({
          'mode': mode.name,
          'route': mode.catalogRoute,
          'status': 'failed',
          'error': failure is CatalogException
              ? failure.message
              : 'Catalog smoke failed at validation or persistence boundary.',
        });
        exitCode = 1;
      }
    }
  } finally {
    await database.close();
    httpClient.close();
    await directory.delete(recursive: true);
  }
  final report = jsonEncode({
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
    'source': 'https://json.tarkov.dev',
    'records': records,
    'downloadedBytesCommitted': false,
  });
  if (arguments.length == 2 && arguments.first == '--output') {
    await File(arguments[1]).writeAsString('$report\n');
  } else if (arguments.isNotEmpty) {
    throw ArgumentError('Usage: catalog_smoke.dart [--output <report-path>]');
  }
  stdout.writeln(report);
}
