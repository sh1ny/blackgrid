import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/catalog.dart';
import '../domain/credential_store.dart';

abstract interface class CredentialProtector {
  Future<Uint8List> protect(Uint8List bytes);
  Future<Uint8List> unprotect(Uint8List bytes);
  Future<void> replace(File source, File target);
}

class WindowsCredentialProtector implements CredentialProtector {
  const WindowsCredentialProtector();
  static const channel = MethodChannel('blackgrid/credentials');
  @override
  Future<Uint8List> protect(Uint8List bytes) async {
    final value = await channel.invokeMethod<Uint8List>('protect', bytes);
    if (value == null || value.isEmpty) throw const CredentialUnavailable();
    return value;
  }

  @override
  Future<Uint8List> unprotect(Uint8List bytes) async {
    final value = await channel.invokeMethod<Uint8List>('unprotect', bytes);
    if (value == null || value.isEmpty) throw const CredentialUnavailable();
    // Platform responses may borrow read-only engine memory. Cleanup must own
    // a writable buffer rather than attempt to erase that transport view.
    return Uint8List.fromList(value);
  }

  @override
  Future<void> replace(File source, File target) => channel.invokeMethod<void>(
    'atomicReplace',
    {'source': source.path, 'target': target.path},
  );
}

class CredentialUnavailable implements Exception {
  const CredentialUnavailable();
  @override
  String toString() =>
      'Protected credentials are unavailable; no plaintext fallback is used.';
}

class DpapiCredentialStore implements CredentialStore {
  DpapiCredentialStore(this.directory, {CredentialProtector? protector})
    : protector = protector ?? const WindowsCredentialProtector();
  final Directory directory;
  final CredentialProtector protector;
  final Map<GameMode, Future<void>> _operations = {};
  Future<T> _serial<T>(GameMode mode, Future<T> Function() operation) async {
    if (mode == GameMode.unknown) throw const CredentialUnavailable();
    final prior = _operations[mode] ?? Future<void>.value();
    final result = prior.then((_) => operation());
    final barrier = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _operations[mode] = barrier;
    try {
      return await result;
    } finally {
      if (identical(_operations[mode], barrier)) _operations.remove(mode);
    }
  }

  File _file(GameMode mode) =>
      File('${directory.path}${Platform.pathSeparator}${mode.name}.dpapi');
  @override
  Future<String?> readCredential(GameMode mode) async {
    if (mode == GameMode.unknown) return null;
    return _serial(mode, () async {
      try {
        final file = _file(mode);
        if (!await file.exists()) return null;
        final bytes = await protector.unprotect(await file.readAsBytes());
        try {
          return utf8.decode(bytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      } catch (_) {
        throw const CredentialUnavailable();
      }
    });
  }

  @override
  Future<void> writeCredential(GameMode mode, String token) =>
      _serial(mode, () async {
        final plain = Uint8List.fromList(utf8.encode(token));
        File? temporary;
        try {
          if (plain.isEmpty) throw const CredentialUnavailable();
          final cipher = await protector.protect(plain);
          await directory.create(recursive: true);
          final target = _file(mode);
          temporary = File(
            '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
          );
          await temporary.writeAsBytes(cipher, flush: true);
          await protector.replace(temporary, target);
        } catch (_) {
          throw const CredentialUnavailable();
        } finally {
          plain.fillRange(0, plain.length, 0);
          if (temporary != null && await temporary.exists()) {
            await temporary.delete();
          }
        }
      });
  @override
  Future<void> removeCredential(GameMode mode) => _serial(mode, () async {
    try {
      final file = _file(mode);
      if (await file.exists()) await file.delete();
    } catch (_) {
      throw const CredentialUnavailable();
    }
  });
}
