import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../domain/catalog.dart';
import 'catalog_normalizer.dart';

class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CatalogClient {
  CatalogClient({required this._client, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _clock;
  Future<String> _get(String route, String dataset) async {
    final request = http.Request(
      'GET',
      Uri.https('json.tarkov.dev', '/$route/$dataset'),
    )..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (response.statusCode != 200) {
        throw const CatalogException('Catalog download failed');
      }
      return response.body;
    } on CatalogException {
      rethrow;
    } on Object {
      throw const CatalogException('Catalog transport unavailable');
    }
  }

  Future<CatalogSnapshot> fetch(GameMode mode) async {
    final route = mode.catalogRoute;
    if (route == null) {
      throw const CatalogException('Choose a mode before refreshing');
    }
    final datasets = <String, String>{};
    await Future.wait(
      catalogDatasets.map((key) async {
        datasets[key] = await _get(route, key);
      }),
    );
    final localization = <String, String>{};
    final errors = <String>[];
    await Future.wait(
      catalogTranslations.map((key) async {
        try {
          localization[key] = await _get(route, '${key}_en');
        } on Object {
          errors.add(key);
        }
      }),
    );
    final wire = CatalogWireCandidate(
      mode: mode,
      observedAt: _clock(),
      datasets: datasets,
      localization: localization,
      localizationErrors: errors,
    );
    try {
      return await _normalizeOffRender(wire);
    } on Object {
      throw const CatalogException('Catalog validation failed');
    }
  }
}

// The client's async scope also owns HTTP callbacks. Capture only the completed
// wire candidate here, never a client or its caller's database/widget context.
Future<CatalogSnapshot> _normalizeOffRender(CatalogWireCandidate wire) =>
    Isolate.run(() => normalizeCatalog(wire));
