import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/credential_store.dart';

/// A [CredentialProtector] fake that rejects bytes it did not protect.
///
/// [protect] prefixes a fixed header and [unprotect] throws when the header is
/// missing, which models the real protector failing on a damaged token file.
class HeaderProtector implements CredentialProtector {
  /// The marker that every protected payload starts with.
  static const header = [0x42, 0x47, 0x48, 0x44];

  @override
  Future<Uint8List> protect(Uint8List bytes) async =>
      Uint8List.fromList([...header, ...bytes]);

  @override
  Future<Uint8List> unprotect(Uint8List bytes) async {
    final valid =
        bytes.length >= header.length &&
        [for (var i = 0; i < header.length; i++) bytes[i] == header[i]]
            .every((match) => match);
    if (!valid) throw const CredentialUnavailable();
    return Uint8List.fromList(bytes.sublist(header.length));
  }

  @override
  Future<void> replace(File source, File target) async {
    await source.rename(target.path);
  }
}
