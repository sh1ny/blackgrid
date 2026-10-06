import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class StallingHttpClient extends http.BaseClient {
  StallingHttpClient({
    required this.stallPath,
    required this.body,
    required this.responses,
  });
  final String stallPath;
  final bool body;
  final Map<String, dynamic> responses;
  bool stall = true;
  int aborts = 0;
  final List<void Function()> _cancel = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = request.url.pathSegments.last;
    if (!stall || key != stallPath) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(responses[key]))),
        200,
      );
    }
    final pending = Completer<http.StreamedResponse>();
    final stream = StreamController<List<int>>();
    var cancelled = false;
    void cancel() {
      if (cancelled) return;
      cancelled = true;
      if (body) {
        stream.addError(http.RequestAbortedException());
        unawaited(stream.close());
      } else {
        pending.completeError(http.RequestAbortedException());
      }
    }

    _cancel.add(cancel);
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        aborts++;
        cancel();
      });
    }
    if (body) return http.StreamedResponse(stream.stream, 200);
    return pending.future;
  }

  @override
  void close() {
    for (final cancel in _cancel) {
      cancel();
    }
  }
}
