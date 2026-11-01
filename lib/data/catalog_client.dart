import 'dart:async';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../domain/catalog.dart';
import 'catalog_normalizer.dart';

/// Why a catalog refresh failed, which decides the text the player sees.
enum CatalogFailure {
  /// The source could not be reached, or a dataset stalled past the timeout.
  transport,

  /// The source answered with a status other than 200.
  http,

  /// The downloaded data failed validation or normalization.
  invalid,

  /// A valid download could not be stored locally.
  ///
  /// Only the catalog controller sets this; the client never does.
  save,
}

/// A failed catalog download, carrying its [kind] and a log-safe [message].
class CatalogException implements Exception {
  /// Creates an exception of [kind] described by [message].
  const CatalogException(this.message, this.kind);

  /// The cause of the failure.
  final CatalogFailure kind;

  /// A short description that never contains response bodies.
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
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      Uri.https('json.tarkov.dev', '/$route/$dataset'),
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              abort.complete();
              throw const CatalogException(
                'Catalog transport unavailable',
                CatalogFailure.transport,
              );
            },
          );
      if (response.statusCode != 200) {
        throw const CatalogException(
          'Catalog download failed',
          CatalogFailure.http,
        );
      }
      return response.body;
    } on CatalogException {
      rethrow;
    } on Object {
      throw const CatalogException(
        'Catalog transport unavailable',
        CatalogFailure.transport,
      );
    }
  }

  Future<CatalogSnapshot> fetch(GameMode mode) async {
    final route = mode.catalogRoute;
    if (route == null) {
      throw const CatalogException(
        'Choose a mode before refreshing',
        CatalogFailure.invalid,
      );
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
      throw const CatalogException(
        'Catalog validation failed',
        CatalogFailure.invalid,
      );
    }
  }
}

// The client's async scope also owns HTTP callbacks. Capture only the completed
// wire candidate here, never a client or its caller's database/widget context.
Future<CatalogSnapshot> _normalizeOffRender(CatalogWireCandidate wire) =>
    Isolate.run(() => normalizeCatalog(wire));
