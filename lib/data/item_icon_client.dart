import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Largest icon body the client accepts, in bytes.
const itemIconMaxBytes = 256 * 1024;

/// Image formats the icon cache stores.
enum IconFormat {
  webp('webp'),
  png('png'),
  jpg('jpg');

  const IconFormat(this.extension);

  /// File extension, without a dot, used to name the cached file.
  final String extension;

  /// Detects the format from the leading bytes, or null when not an image.
  static IconFormat? sniff(List<int> b) => switch (b) {
    [0x52, 0x49, 0x46, 0x46, _, _, _, _, 0x57, 0x45, 0x42, 0x50, ...] =>
      IconFormat.webp,
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...] => IconFormat.png,
    [0xFF, 0xD8, 0xFF, ...] => IconFormat.jpg,
    _ => null,
  };

  /// Whether [b], already sniffed as [format], reaches the format's end.
  ///
  /// A cut-off body keeps its signature but loses its end: a WebP's RIFF
  /// size then exceeds the body, a PNG lacks its `IEND` chunk, and a JPEG
  /// lacks its end-of-image marker.
  static bool isComplete(IconFormat format, List<int> b) => switch (format) {
    webp =>
      b.length >= 8 &&
          (b[4] | b[5] << 8 | b[6] << 16 | b[7] << 24) + 8 <= b.length,
    png => _endsWith(b, const [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]),
    jpg => _endsWith(b, const [0xFF, 0xD9]),
  };

  static bool _endsWith(List<int> b, List<int> tail) {
    if (b.length < tail.length) return false;
    for (var i = 0; i < tail.length; i++) {
      if (b[b.length - tail.length + i] != tail[i]) return false;
    }
    return true;
  }
}

/// Why an icon request failed.
enum IconFailureKind {
  timeout,
  transport,
  status,
  redirect,
  oversize,
  notImage,
}

/// Outcome of one [ItemIconClient.fetch] call.
sealed class ItemIconFetchResult {
  const ItemIconFetchResult();
}

/// A complete, signature-checked image body.
final class IconFetched extends ItemIconFetchResult {
  const IconFetched(this.bytes, this.format, {this.etag});
  final Uint8List bytes;
  final IconFormat format;

  /// The `ETag` response header, if the server sent one.
  final String? etag;
}

/// The server answered 304 to a conditional request.
final class IconNotModified extends ItemIconFetchResult {
  const IconNotModified();
}

/// The request failed for [kind]; the caller applies its retry backoff.
final class IconFailed extends ItemIconFetchResult {
  const IconFailed(this.kind);
  final IconFailureKind kind;
}

/// The caller's cancel signal fired. This is never a failure.
final class IconCancelled extends ItemIconFetchResult {
  const IconCancelled();
}

/// Downloads one item icon with a bounded, redirect-free GET.
class ItemIconClient {
  ItemIconClient({
    required this._client,
    this.timeout = const Duration(seconds: 15),
    this.userAgent = 'Blackgrid/0.1.0',
  });
  final http.Client _client;

  /// Time allowed for the whole request, headers and body.
  final Duration timeout;
  final String userAgent;

  /// Fetches [link] once. Never throws: every outcome is a result.
  ///
  /// Completing [cancel] aborts the request and yields [IconCancelled].
  Future<ItemIconFetchResult> fetch(
    Uri link, {
    String? etag,
    Future<void>? cancel,
  }) async {
    final abort = Completer<void>();
    var cancelled = false;
    var timedOut = false;
    var finished = false;
    void abortNow() {
      if (!abort.isCompleted) abort.complete();
    }

    final timer = Timer(timeout, () {
      timedOut = true;
      abortNow();
    });
    unawaited(
      cancel?.then<void>((_) {
        if (finished) return;
        cancelled = true;
        abortNow();
      }, onError: (Object _) {}),
    );
    try {
      final request = http.AbortableRequest(
        'GET',
        link,
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers.addAll({'User-Agent': userAgent, 'If-None-Match': ?etag});
      final response = await _client.send(request);
      final result = await _read(response, abortNow);
      if (cancelled) return const IconCancelled();
      if (timedOut) return const IconFailed(IconFailureKind.timeout);
      return result;
    } on Object {
      if (cancelled) return const IconCancelled();
      if (timedOut) return const IconFailed(IconFailureKind.timeout);
      return const IconFailed(IconFailureKind.transport);
    } finally {
      finished = true;
      timer.cancel();
      abortNow();
    }
  }

  Future<ItemIconFetchResult> _read(
    http.StreamedResponse response,
    void Function() abortNow,
  ) async {
    final status = response.statusCode;
    if (status == 304) return const IconNotModified();
    if (status >= 300 && status < 400) {
      abortNow();
      return const IconFailed(IconFailureKind.redirect);
    }
    if (status != 200) {
      abortNow();
      return const IconFailed(IconFailureKind.status);
    }
    if ((response.contentLength ?? 0) > itemIconMaxBytes) {
      abortNow();
      return const IconFailed(IconFailureKind.oversize);
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      body.add(chunk);
      if (body.length > itemIconMaxBytes) {
        abortNow();
        return const IconFailed(IconFailureKind.oversize);
      }
    }
    final bytes = body.takeBytes();
    final format = IconFormat.sniff(bytes);
    if (format == null || !IconFormat.isComplete(format, bytes)) {
      return const IconFailed(IconFailureKind.notImage);
    }
    return IconFetched(bytes, format, etag: response.headers['etag']);
  }
}
