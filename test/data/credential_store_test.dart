import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/credential_store.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:test/test.dart';

import '../support/header_protector.dart';

class SyntheticProtector implements CredentialProtector {
  bool failProtect = false, failUnprotect = false, failReplace = false;
  @override
  Future<Uint8List> protect(Uint8List bytes) async {
    if (failProtect) throw StateError('synthetic protect failure');
    return Uint8List.fromList(bytes.map((b) => b ^ 0xa5).toList());
  }

  @override
  Future<Uint8List> unprotect(Uint8List bytes) async {
    if (failUnprotect) throw StateError('synthetic unprotect failure');
    return Uint8List.fromList(bytes.map((b) => b ^ 0xa5).toList());
  }

  @override
  Future<void> replace(File source, File target) async {
    if (failReplace) throw StateError('synthetic replacement failure');
    await source.rename(target.path);
  }
}

void main() {
  late Directory directory;
  late SyntheticProtector protector;
  late DpapiCredentialStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('blackgrid-credential-');
    protector = SyntheticProtector();
    store = DpapiCredentialStore(directory, protector: protector);
  });
  tearDown(() async => directory.delete(recursive: true));
  test('mode scoped ciphertext persists without plaintext and unknown reads nothing', () async {
    const pvp = 'PVP_SYNTHETIC_LOCAL_ONLY', pve = 'PVE_SYNTHETIC_LOCAL_ONLY';
    await store.writeCredential(GameMode.pvp, pvp);
    await store.writeCredential(GameMode.pve, pve);
    expect(await store.readCredential(GameMode.pvp), pvp);
    expect(await store.readCredential(GameMode.pve), pve);
    expect(await store.readCredential(GameMode.unknown), isNull);
    final bytes = await File('${directory.path}/pvp.dpapi').readAsBytes();
    expect(utf8.decode(bytes, allowMalformed: true), isNot(contains(pvp)));
    expect((await directory.list().toList()).length, 2);
  });
  test('failed protection and replacement keep previous bytes and no temp remnants', () async {
    await store.writeCredential(GameMode.pvp, 'PVP_SYNTHETIC_OLD');
    final file = File('${directory.path}/pvp.dpapi');
    final before = await file.readAsBytes();
    protector.failProtect = true;
    await expectLater(
      store.writeCredential(GameMode.pvp, 'PVP_SYNTHETIC_NEW'),
      throwsA(isA<CredentialUnavailable>()),
    );
    expect(await file.readAsBytes(), orderedEquals(before));
    protector.failProtect = false;
    protector.failReplace = true;
    await expectLater(
      store.writeCredential(GameMode.pvp, 'PVP_SYNTHETIC_NEW'),
      throwsA(isA<CredentialUnavailable>()),
    );
    expect(await file.readAsBytes(), orderedEquals(before));
    expect((await directory.list().toList()).length, 1);
  });
  test('unprotect failure is unavailable without plaintext fallback and remove is mode isolated', () async {
    await store.writeCredential(GameMode.pvp, 'PVP_SYNTHETIC_LOCAL_ONLY');
    await store.writeCredential(GameMode.pve, 'PVE_SYNTHETIC_LOCAL_ONLY');
    protector.failUnprotect = true;
    await expectLater(
      store.readCredential(GameMode.pvp),
      throwsA(isA<CredentialUnavailable>()),
    );
    protector.failUnprotect = false;
    await store.removeCredential(GameMode.pvp);
    expect(await store.readCredential(GameMode.pvp), isNull);
    expect(
      await store.readCredential(GameMode.pve),
      'PVE_SYNTHETIC_LOCAL_ONLY',
    );
  });
  test(
    'saving over corrupt token bytes reads back the new token after reopening',
    () async {
      final header = HeaderProtector();
      final file = File('${directory.path}/pvp.dpapi');
      await file.writeAsBytes([1, 2, 3, 250, 99]);
      final damaged = DpapiCredentialStore(directory, protector: header);
      await expectLater(
        damaged.readCredential(GameMode.pvp),
        throwsA(isA<CredentialUnavailable>()),
      );
      await damaged.writeCredential(GameMode.pvp, 'PVP_SYNTHETIC_NEW');
      final reopened = DpapiCredentialStore(
        directory,
        protector: HeaderProtector(),
      );
      expect(await reopened.readCredential(GameMode.pvp), 'PVP_SYNTHETIC_NEW');
      expect((await directory.list().toList()).length, 1);
    },
  );
}
