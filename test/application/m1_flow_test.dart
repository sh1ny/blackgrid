import 'dart:io';

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/legacy_import.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/legacy/legacy_fixture.dart';
import '../support/m1_harness.dart';

void main() {
  test('Unknown startup makes no request; complete refresh inspection history import and restart cross real SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('blackgrid-m1-flow-');
    final file = File('${dir.path}/blackgrid.sqlite');
    var h = M1Harness(database: BlackgridDatabase(NativeDatabase(file)));
    await h.services.initialize();
    expect(h.services.catalog.mode, GameMode.unknown);
    expect(h.requests, isEmpty);
    await h.services.setMode(GameMode.pve);
    await h.services.catalog.refresh();
    expect(h.services.catalog.status, CatalogStatus.current);
    final revision = h.services.catalog.snapshot!.revision;
    h.services.selection.setQuery('Component');
    await h.services.selection.selectManual(h.services.selection.results.first);
    h.services.selection.setFir(FirState.yes);
    expect(h.services.history.rows.length, 1);
    final history = h.services.history.rows.single;
    h.failNetwork = true;
    await h.services.catalog.refresh();
    expect(h.services.catalog.status, CatalogStatus.stale);
    expect(h.services.catalog.snapshot!.revision, revision);
    expect(h.services.selection.fir, FirState.unknown);
    await h.services.setMode(GameMode.pvp);
    await h.services.selection.openHistory(history);
    expect(h.services.selection.inspectionMode, GameMode.pve);
    expect(h.services.catalog.mode, GameMode.pvp);
    final preview = parseLegacySources(
      legacyBytes(settings: syntheticSettings(), history: syntheticHistory()),
    );
    await h.services.importer.commit(preview, replaceExisting: false);
    await h.services.reloadAfterImport();
    expect(h.services.history.rows.length, 2);
    expect(h.services.settings.pins.length, 1);
    await h.dispose();
    h = M1Harness(database: BlackgridDatabase(NativeDatabase(file)));
    await h.services.initialize();
    expect(h.services.catalog.mode, GameMode.pvp);
    expect(h.services.history.rows.length, 2);
    expect(h.services.settings.pins.length, 1);
    expect(h.services.selection.selectedId, isNull);
    expect(h.services.selection.fir, FirState.unknown);
    expect(h.services.progress.snapshot, isNull);
    expect(h.services.scans.hasAcceptedScan, isFalse);
    expect((await h.db.loadCatalog(GameMode.pve))!.revision, revision);
    await h.dispose();
    await dir.delete(recursive: true);
  });
}
