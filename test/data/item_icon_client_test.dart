import 'dart:async';

import 'package:blackgrid/data/item_icon_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/stalling_http_client.dart';

const _cap = 256 * 1024;

final _webp = <int>[...'RIFF'.codeUnits, 1, 2, 3, 4, ...'WEBP'.codeUnits, 9];
final _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 7];
final _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 5];

final _link = Uri.https('assets.tarkov.dev', '/abc-icon.webp');

/// Records requests and whether each abort trigger fired.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._respond);
  final http.StreamedResponse Function(http.BaseRequest) _respond;
  final requests = <http.BaseRequest>[];
  var aborts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Abortable) {
      unawaited(request.abortTrigger?.then((_) => aborts++));
    }
    return _respond(request);
  }
}

http.StreamedResponse _streamed(
  Stream<List<int>> body,
  int status, {
  Map<String, String> headers = const {},
  int? length,
}) => http.StreamedResponse(
  body,
  status,
  headers: headers,
  contentLength: length,
);

void main() {
  group('ItemIconClient', () {
    test('a 200 WebP, PNG and JPEG are IconFetched with the etag', () async {
      for (final (body, format) in [
        (_webp, IconFormat.webp),
        (_png, IconFormat.png),
        (_jpeg, IconFormat.jpg),
      ]) {
        final client = ItemIconClient(
          client: MockClient(
            (_) async => http.Response.bytes(
              body,
              200,
              headers: {'etag': '"v1"', 'content-type': 'binary/octet-stream'},
            ),
          ),
        );
        final result = await client.fetch(_link);
        switch (result) {
          case IconFetched(bytes: final got, :final etag, format: final f):
            expect(got, orderedEquals(body));
            expect(etag, '"v1"');
            expect(f, format);
          default:
            fail('expected IconFetched, got $result');
        }
      }
      expect(IconFormat.webp.extension, 'webp');
      expect(IconFormat.png.extension, 'png');
      expect(IconFormat.jpg.extension, 'jpg');
    });

    test('sends the User-Agent, GET, and If-None-Match', () async {
      final seen = _RecordingClient(
        (_) => _streamed(const Stream.empty(), 304),
      );
      final client = ItemIconClient(client: seen, userAgent: 'Blackgrid/9.9.9');
      final result = await client.fetch(_link, etag: '"v1"');
      expect(result, isA<IconNotModified>());
      final request = seen.requests.single;
      expect(request.method, 'GET');
      expect(request.headers['User-Agent'], 'Blackgrid/9.9.9');
      expect(request.headers['If-None-Match'], '"v1"');
    });

    test('a 302 is IconFailed and not followed', () async {
      final seen = _RecordingClient(
        (_) => _streamed(
          const Stream.empty(),
          302,
          headers: {'location': 'https://elsewhere.example/icon.webp'},
        ),
      );
      final result = await ItemIconClient(client: seen).fetch(_link);
      expect(result, isA<IconFailed>());
      expect((result as IconFailed).kind, IconFailureKind.redirect);
      expect(seen.requests, hasLength(1));
      expect(seen.requests.single.followRedirects, isFalse);
    });

    test('a non-200 status is IconFailed', () async {
      final client = ItemIconClient(
        client: MockClient((_) async => http.Response('', 404)),
      );
      final result = await client.fetch(_link);
      expect((result as IconFailed).kind, IconFailureKind.status);
    });

    test('a transport error is IconFailed', () async {
      final client = ItemIconClient(
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      final result = await client.fetch(_link);
      expect((result as IconFailed).kind, IconFailureKind.transport);
    });

    group('a body over 256 KiB aborts as IconFailed', () {
      test('by Content-Length', () async {
        var pulled = false;
        final seen = _RecordingClient(
          (_) => _streamed(
            () async* {
              pulled = true;
              yield _webp;
            }(),
            200,
            length: _cap + 1,
          ),
        );
        final result = await ItemIconClient(client: seen).fetch(_link);
        expect((result as IconFailed).kind, IconFailureKind.oversize);
        expect(pulled, isFalse);
        expect(seen.aborts, 1);
      });

      test('by streaming with no Content-Length', () async {
        final seen = _RecordingClient(
          (_) => _streamed(
            Stream.fromIterable([
              [..._webp, ...List.filled(_cap - _webp.length, 0)],
              [0],
            ]),
            200,
          ),
        );
        final result = await ItemIconClient(client: seen).fetch(_link);
        expect((result as IconFailed).kind, IconFailureKind.oversize);
        expect(seen.aborts, 1);
      });

      test('by streaming with a lying Content-Length', () async {
        final seen = _RecordingClient(
          (_) => _streamed(
            Stream.fromIterable([
              [..._webp, ...List.filled(_cap, 0)],
            ]),
            200,
            length: 10,
          ),
        );
        final result = await ItemIconClient(client: seen).fetch(_link);
        expect((result as IconFailed).kind, IconFailureKind.oversize);
      });

      test('a body of exactly 256 KiB is accepted', () async {
        final bytes = [..._webp, ...List.filled(_cap - _webp.length, 0)];
        final client = ItemIconClient(
          client: MockClient((_) async => http.Response.bytes(bytes, 200)),
        );
        expect(await client.fetch(_link), isA<IconFetched>());
      });
    });

    test('a 200 HTML body is IconFailed', () async {
      final client = ItemIconClient(
        client: MockClient(
          (_) async => http.Response(
            '<html></html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      final result = await client.fetch(_link);
      expect((result as IconFailed).kind, IconFailureKind.notImage);
    });

    test('an empty or truncated-signature 200 body is IconFailed', () async {
      for (final bytes in [
        <int>[],
        [0xFF, 0xD8],
        [...'RIFF'.codeUnits, 1, 2, 3, 4, ...'WAVE'.codeUnits],
      ]) {
        final client = ItemIconClient(
          client: MockClient((_) async => http.Response.bytes(bytes, 200)),
        );
        final result = await client.fetch(_link);
        expect((result as IconFailed).kind, IconFailureKind.notImage);
      }
    });

    group('a stalled request aborts at the injected timeout as IconFailed', () {
      for (final body in [false, true]) {
        test(
          body ? 'while streaming the body' : 'before the response',
          () async {
            final stalling = StallingHttpClient(
              stallPath: 'abc-icon.webp',
              body: body,
              responses: const {},
            );
            final client = ItemIconClient(
              client: stalling,
              timeout: const Duration(milliseconds: 20),
            );
            final result = await client.fetch(_link);
            expect((result as IconFailed).kind, IconFailureKind.timeout);
            expect(stalling.aborts, 1);
          },
        );
      }
    });

    group('an external cancel', () {
      for (final body in [false, true]) {
        test(
          body
              ? 'while streaming is IconCancelled'
              : 'before the response is IconCancelled',
          () async {
            final stalling = StallingHttpClient(
              stallPath: 'abc-icon.webp',
              body: body,
              responses: const {},
            );
            final cancel = Completer<void>();
            final client = ItemIconClient(client: stalling);
            final pending = client.fetch(_link, cancel: cancel.future);
            cancel.complete();
            expect(await pending, isA<IconCancelled>());
            expect(stalling.aborts, 1);
          },
        );
      }

      test('that has already fired is IconCancelled', () async {
        final stalling = StallingHttpClient(
          stallPath: 'abc-icon.webp',
          body: false,
          responses: const {},
        );
        final result = await ItemIconClient(client: stalling)
            .fetch(_link, cancel: Future<void>.value());
        expect(result, isA<IconCancelled>());
      });
    });
  });
}
