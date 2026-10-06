import 'dart:convert';

import 'package:blackgrid/data/credential_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native unprotect owns a writable buffer rather than borrowed read-only transport', () async {
    const codec = StandardMethodCodec();
    const token = 'SYNTHETIC_TRANSPORT_ONLY';
    final envelope = codec
        .encodeSuccessEnvelope(Uint8List.fromList(utf8.encode(token)))
        .asUnmodifiableView();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      WindowsCredentialProtector.channel.name,
      (_) async => envelope,
    );
    addTearDown(
      () => messenger.setMockMessageHandler(
        WindowsCredentialProtector.channel.name,
        null,
      ),
    );
    final bytes = await const WindowsCredentialProtector().unprotect(
      Uint8List.fromList([1]),
    );
    expect(utf8.decode(bytes), token);
    bytes.fillRange(0, bytes.length, 0);
    expect(bytes.every((byte) => byte == 0), isTrue);
    expect(utf8.decode(codec.decodeEnvelope(envelope) as Uint8List), token);
  });
}
