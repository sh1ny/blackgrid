import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/vision/fetch_runtime.dart';

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory temp;
  late HttpServer server;
  late Map<String, Future<void> Function(HttpResponse)> routes;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fetch_runtime_test');
    routes = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final handler = routes[request.uri.path];
      if (handler == null) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      try {
        await handler(request.response);
      } catch (_) {}
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  File writeLock(List<Map<String, Object?>> inputs) {
    final file = File('${temp.path}/lock.json');
    file.writeAsStringSync(jsonEncode({'format': 1, 'inputs': inputs}));
    return file;
  }

  Future<void> Function(HttpResponse) serve(List<int> bytes) =>
      (response) async {
        response.add(bytes);
        await response.close();
      };

  Directory cacheDir() => Directory('${temp.path}/cache');

  List<File> cacheFiles() => cacheDir().existsSync()
      ? cacheDir().listSync(recursive: true).whereType<File>().toList()
      : [];

  Future<FetchResult> run(
    File lock, {
    Duration timeout = const Duration(seconds: 5),
  }) => fetchInputs(
    lockFile: lock,
    cacheDir: cacheDir(),
    timeout: timeout,
    allowLoopbackHttp: true,
  );

  Map<String, Object?> entry(String id, List<int> pin, {int? size}) => {
    'id': id,
    'name': '$id.bin',
    'urls': [url('/$id.bin')],
    'sha256': _sha(pin),
    'size': size ?? pin.length,
  };

  test('fetch places verified input in content-addressed cache', () async {
    final bytes = utf8.encode('verified fixture bytes');
    routes['/a.bin'] = serve(bytes);

    await run(writeLock([entry('a', bytes)]));

    final cached = File('${cacheDir().path}/${_sha(bytes)}/a.bin');
    expect(cached.existsSync(), isTrue);
    expect(cached.readAsBytesSync(), bytes);
    expect(cacheFiles(), hasLength(1));
  });

  test('fetch refuses hash mismatch and leaves no cache file', () async {
    final bytes = utf8.encode('tampered bytes');
    final pinned = utf8.encode('original bytes!');
    routes['/a.bin'] = serve(bytes);
    final lock = writeLock([entry('a', pinned, size: bytes.length)]);

    await expectLater(
      run(lock),
      throwsA(
        isA<FetchException>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('a'), contains(_sha(pinned)), contains(_sha(bytes))),
        ),
      ),
    );
    expect(cacheFiles(), isEmpty);
  });

  test('fetch refuses oversize download and leaves no files', () async {
    final pinned = utf8.encode('small');
    final big = utf8.encode('this is much larger than the pinned size');
    routes['/a.bin'] = serve(big);

    await expectLater(
      run(writeLock([entry('a', pinned)])),
      throwsA(isA<FetchException>()),
    );
    expect(cacheFiles(), isEmpty);
  });

  test('fetch aborts a stalled download within the timeout', () async {
    final bytes = utf8.encode('never fully arrives');
    final stall = Completer<void>();
    routes['/a.bin'] = (response) async {
      response.add(bytes.sublist(0, 3));
      await response.flush();
      await stall.future;
    };

    final watch = Stopwatch()..start();
    await expectLater(
      run(
        writeLock([entry('a', bytes)]),
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<FetchException>()),
    );
    stall.complete();
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(cacheFiles(), isEmpty);
  });

  test('fetch times out while the connection never establishes', () async {
    final bytes = utf8.encode('never connects');
    final watch = Stopwatch()..start();
    await expectLater(
      fetchInputs(
        lockFile: writeLock([entry('a', bytes)]),
        cacheDir: cacheDir(),
        client: _NeverConnectingClient(),
        timeout: const Duration(milliseconds: 300),
        allowLoopbackHttp: true,
      ).timeout(const Duration(seconds: 5)),
      throwsA(
        isA<FetchException>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(cacheFiles(), isEmpty);
  });

  test('fetch rejects non-https URLs unless loopback is allowed', () async {
    final bytes = utf8.encode('x');
    routes['/a.bin'] = serve(bytes);
    final lock = writeLock([entry('a', bytes)]);

    await expectLater(
      fetchInputs(lockFile: lock, cacheDir: cacheDir()),
      throwsA(isA<FetchException>()),
    );
    expect(cacheFiles(), isEmpty);
  });

  test(
    'fetch skips a verified cached input and repairs a corrupt one',
    () async {
      final bytes = utf8.encode('cached bytes');
      var hits = 0;
      routes['/a.bin'] = (response) async {
        hits++;
        response.add(bytes);
        await response.close();
      };
      final lock = writeLock([entry('a', bytes)]);

      await run(lock);
      await run(lock);
      expect(hits, 1);

      File('${cacheDir().path}/${_sha(bytes)}/a.bin').writeAsStringSync('bad');
      await run(lock);
      expect(hits, 2);
      expect(
        File('${cacheDir().path}/${_sha(bytes)}/a.bin').readAsBytesSync(),
        bytes,
      );
    },
  );

  group('nupkg members', () {
    final good = utf8.encode('good dll');
    final other = utf8.encode('other dll');
    late List<int> zip;

    List<Map<String, Object?>> entries(List<int> memberPin) => [
      {
        'id': 'pkg',
        'name': 'pkg.nupkg',
        'urls': [url('/pkg.nupkg')],
        'sha256': _sha(zip),
        'size': zip.length,
      },
      {
        'id': 'dll',
        'name': 'a.dll',
        'extractFrom': 'pkg',
        'path': 'x64/a.dll',
        'sha256': _sha(memberPin),
        'size': memberPin.length,
      },
    ];

    setUp(() {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('x64/a.dll', good))
        ..addFile(ArchiveFile.bytes('x64/b.dll', other));
      zip = ZipEncoder().encode(archive);
      routes['/pkg.nupkg'] = serve(zip);
    });

    test('fetch extracts a member that matches its pin', () async {
      await run(writeLock(entries(good)));

      final member = File('${cacheDir().path}/${_sha(good)}/a.dll');
      expect(member.readAsBytesSync(), good);
      expect(
        File('${cacheDir().path}/${_sha(zip)}/pkg.nupkg').existsSync(),
        isTrue,
      );
    });

    test('fetch refuses a member whose bytes differ from its pin', () async {
      // The pin claims x64/a.dll hashes to `other`, but the archive holds
      // `good`.
      await expectLater(
        run(writeLock(entries(other))),
        throwsA(
          isA<FetchException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('dll'), contains(_sha(other)), contains(_sha(good))),
          ),
        ),
      );
      expect(
        File('${cacheDir().path}/${_sha(other)}/a.dll').existsSync(),
        isFalse,
      );
      expect(
        File('${cacheDir().path}/${_sha(good)}/a.dll').existsSync(),
        isFalse,
      );
    });
  });
}

/// Connection establishment (DNS, TCP or TLS) that never completes.
final class _NeverConnectingClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
