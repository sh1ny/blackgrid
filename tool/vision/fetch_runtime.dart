import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const defaultLockPath = 'windows/vision/third_party.lock.json';
const defaultCachePath = '.dart_tool/blackgrid_vision_inputs';
const defaultTimeout = Duration(seconds: 120);
const _maxRedirects = 10;

const helpText =
    '''
Fetch pinned third-party vision inputs into the verified cache.

Usage: dart run tool/vision/fetch_runtime.dart [--lock <path>] [--cache <dir>]

Reads $defaultLockPath, downloads each input over HTTPS (120 s per request,
capped at the pinned size), checks its SHA-256 and places it atomically at
$defaultCachePath/<sha256>/<name>. Nupkg members are extracted and checked
against their own pins. Already cached inputs are re-verified and skipped.

The cache grows only when pins change. "flutter clean" deletes .dart_tool/,
so re-run "mise run vision:fetch" after a clean.
''';

/// A pinned input failed to download or verify. Nothing was cached for it.
class FetchException implements Exception {
  FetchException(this.id, this.message, {this.expected, this.actual});

  final String id;
  final String message;
  final String? expected;
  final String? actual;

  @override
  String toString() {
    final hashes = expected == null
        ? ''
        : ' (expected sha256 $expected, actual ${actual ?? 'unknown'})';
    return 'Input "$id": $message$hashes';
  }
}

class FetchResult {
  FetchResult({required this.downloaded, required this.reused});

  /// Ids placed in the cache by this run.
  final List<String> downloaded;

  /// Ids already present and re-verified in the cache.
  final List<String> reused;
}

class _Input {
  _Input(Map<String, Object?> json)
    : id = json['id']! as String,
      name = json['name']! as String,
      sha256 = json['sha256']! as String,
      size = json['size']! as int,
      urls = [...(json['urls'] as List<Object?>? ?? const []).cast<String>()],
      extractFrom = json['extractFrom'] as String?,
      path = json['path'] as String?;

  final String id;
  final String name;
  final String sha256;
  final int size;
  final List<String> urls;
  final String? extractFrom;
  final String? path;
}

String _hex(List<int> bytes) => sha256.convert(bytes).toString();

Future<FetchResult> fetchInputs({
  required File lockFile,
  required Directory cacheDir,
  HttpClient? client,
  Duration timeout = defaultTimeout,
  bool allowLoopbackHttp = false,
}) async {
  final lock = jsonDecode(await lockFile.readAsString());
  if (lock is! Map<String, Object?> || lock['format'] != 1) {
    throw FetchException('lock', 'unsupported lock file format');
  }
  final inputs = [
    for (final entry in lock['inputs']! as List<Object?>)
      _Input(entry! as Map<String, Object?>),
  ];
  final byId = {for (final input in inputs) input.id: input};
  final ownsClient = client == null;
  final http = client ?? HttpClient();
  final downloaded = <String>[];
  final reused = <String>[];
  try {
    for (final input in inputs) {
      if (await _isCachedAndValid(cacheDir, input)) {
        reused.add(input.id);
        continue;
      }
      final from = input.extractFrom;
      if (from == null) {
        await _download(
          input,
          cacheDir,
          http,
          timeout,
          allowLoopbackHttp: allowLoopbackHttp,
        );
      } else {
        final parent = byId[from];
        if (parent == null) {
          throw FetchException(input.id, 'extractFrom "$from" is not in lock');
        }
        await _extract(input, parent, cacheDir);
      }
      downloaded.add(input.id);
    }
  } finally {
    if (ownsClient) http.close(force: true);
  }
  return FetchResult(downloaded: downloaded, reused: reused);
}

File _cacheFile(Directory cacheDir, _Input input) =>
    File('${cacheDir.path}/${input.sha256}/${input.name}');

Future<bool> _isCachedAndValid(Directory cacheDir, _Input input) async {
  final file = _cacheFile(cacheDir, input);
  if (!file.existsSync() || file.lengthSync() != input.size) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == input.sha256;
}

Uri _checkUrl(_Input input, Uri uri, bool allowLoopbackHttp) {
  if (uri.scheme == 'https') return uri;
  if (allowLoopbackHttp && uri.scheme == 'http') {
    final address = InternetAddress.tryParse(uri.host);
    if (uri.host == 'localhost' || (address?.isLoopback ?? false)) return uri;
  }
  throw FetchException(input.id, 'refusing non-HTTPS URL $uri');
}

Future<void> _download(
  _Input input,
  Directory cacheDir,
  HttpClient client,
  Duration timeout, {
  required bool allowLoopbackHttp,
}) async {
  if (input.urls.isEmpty) {
    throw FetchException(input.id, 'lock entry has no urls');
  }
  final errors = <String>[];
  for (final raw in input.urls) {
    try {
      final uri = _checkUrl(input, Uri.parse(raw), allowLoopbackHttp);
      await _downloadOne(
        input,
        uri,
        cacheDir,
        client,
        timeout,
        allowLoopbackHttp,
      );
      return;
    } on FetchException catch (error) {
      // A pin mismatch is never retried against another mirror.
      if (error.expected != null || input.urls.length == 1) rethrow;
      errors.add(error.message);
    }
  }
  throw FetchException(input.id, 'all urls failed: ${errors.join('; ')}');
}

Future<void> _downloadOne(
  _Input input,
  Uri start,
  Directory cacheDir,
  HttpClient client,
  Duration timeout,
  bool allowLoopbackHttp,
) async {
  final target = _cacheFile(cacheDir, input);
  final temp = File(
    '${target.parent.path}/.${input.name}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  HttpClientRequest? active;
  final expired = Completer<void>();
  var tempCreated = false;
  var placed = false;
  // Every await races the timer: before a request exists (DNS, TCP or TLS
  // still connecting) there is nothing for the timer to abort.
  Future<T> bounded<T>(Future<T> work) => Future.any([
    work,
    expired.future.then<T>(
      (_) => throw FetchException(input.id, 'timed out after $timeout'),
    ),
  ]);
  // Once the response exists abort() no longer applies, so a body is read
  // (or discarded) chunk by chunk against the timer; cancelling the stream on
  // expiry closes the connection.
  Future<bool> next(StreamIterator<List<int>> chunks) async {
    final more = await Future.any([
      chunks.moveNext(),
      expired.future.then((_) => false),
    ]);
    if (expired.isCompleted) {
      unawaited(chunks.cancel());
      throw FetchException(input.id, 'timed out after $timeout');
    }
    return more;
  }

  Future<void> discard(HttpClientResponse response) async {
    final chunks = StreamIterator(response);
    while (await next(chunks)) {}
  }

  Future<String> transfer() async {
    var uri = start;
    for (var hop = 0; ; hop++) {
      final request = await bounded(client.getUrl(uri));
      active = request;
      if (expired.isCompleted) {
        request.abort();
        throw FetchException(input.id, 'timed out after $timeout');
      }
      request.followRedirects = false;
      final response = await bounded(request.close());
      if (response.isRedirect) {
        await discard(response);
        if (hop >= _maxRedirects) {
          throw FetchException(input.id, 'too many redirects from $start');
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw FetchException(input.id, 'redirect without location');
        }
        uri = _checkUrl(input, uri.resolve(location), allowLoopbackHttp);
        continue;
      }
      if (response.statusCode != 200) {
        await discard(response);
        throw FetchException(input.id, 'HTTP ${response.statusCode} from $uri');
      }
      if (response.contentLength > input.size) {
        throw FetchException(
          input.id,
          'server announces ${response.contentLength} bytes, over pinned size ${input.size}',
        );
      }
      target.parent.createSync(recursive: true);
      tempCreated = true;
      final sink = temp.openWrite();
      final digestSink = _DigestCapture();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      try {
        final chunks = StreamIterator(response);
        while (await next(chunks)) {
          final chunk = chunks.current;
          received += chunk.length;
          if (received > input.size) {
            throw FetchException(
              input.id,
              'download exceeds pinned size ${input.size}',
            );
          }
          hasher.add(chunk);
          sink.add(chunk);
        }
        hasher.close();
      } finally {
        await sink.close();
      }
      final actual = digestSink.value.toString();
      if (actual != input.sha256) {
        throw FetchException(
          input.id,
          'sha256 mismatch',
          expected: input.sha256,
          actual: actual,
        );
      }
      if (received != input.size) {
        throw FetchException(
          input.id,
          'size mismatch: expected ${input.size}, received $received',
        );
      }
      return actual;
    }
  }

  var timedOut = false;
  final timer = Timer(timeout, () {
    timedOut = true;
    expired.complete();
    active?.abort();
  });
  try {
    try {
      await transfer();
    } finally {
      timer.cancel();
    }
    if (timedOut) throw FetchException(input.id, 'timed out after $timeout');
    await temp.rename(target.path);
    placed = true;
  } on FetchException {
    rethrow;
  } on Object catch (error) {
    throw FetchException(
      input.id,
      timedOut ? 'timed out after $timeout' : 'download failed: $error',
    );
  } finally {
    if (tempCreated) {
      if (temp.existsSync()) temp.deleteSync();
      if (!placed &&
          target.parent.existsSync() &&
          target.parent.listSync().isEmpty) {
        target.parent.deleteSync();
      }
    }
  }
}

Future<void> _extract(_Input input, _Input parent, Directory cacheDir) async {
  final archiveFile = _cacheFile(cacheDir, parent);
  if (!await _isCachedAndValid(cacheDir, parent)) {
    throw FetchException(
      input.id,
      'source archive "${parent.id}" is not in the verified cache',
    );
  }
  final memberPath = input.path;
  if (memberPath == null) {
    throw FetchException(input.id, 'lock entry has no path');
  }
  final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
  final member = archive.findFile(memberPath);
  if (member == null) {
    throw FetchException(input.id, '"$memberPath" not found in ${parent.id}');
  }
  final bytes = Uint8List.fromList(member.readBytes()!);
  final actual = _hex(bytes);
  if (actual != input.sha256) {
    throw FetchException(
      input.id,
      'sha256 mismatch for member "$memberPath"',
      expected: input.sha256,
      actual: actual,
    );
  }
  if (bytes.length != input.size) {
    throw FetchException(
      input.id,
      'size mismatch: expected ${input.size}, extracted ${bytes.length}',
    );
  }
  final target = _cacheFile(cacheDir, input);
  target.parent.createSync(recursive: true);
  final temp = File(
    '${target.parent.path}/.${input.name}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
  } finally {
    if (temp.existsSync()) temp.deleteSync();
  }
}

class _DigestCapture implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Future<void> main(List<String> args) async {
  var lockPath = defaultLockPath;
  var cachePath = defaultCachePath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--help' || '-h':
        stdout.write(helpText);
        return;
      case '--lock' when i + 1 < args.length:
        lockPath = args[++i];
      case '--cache' when i + 1 < args.length:
        cachePath = args[++i];
      default:
        stderr.writeln('Unknown argument: ${args[i]}\n\n$helpText');
        exitCode = 64;
        return;
    }
  }
  try {
    final result = await fetchInputs(
      lockFile: File(lockPath),
      cacheDir: Directory(cachePath),
    );
    stdout.writeln(
      'vision inputs: ${result.downloaded.length} fetched, '
      '${result.reused.length} already cached ($cachePath)',
    );
  } on FetchException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
