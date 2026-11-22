import 'dart:async';

import 'package:blackgrid/application/recycle_port.dart';

/// One pending call captured by [FakeRecyclePort].
final class FakeRecycleCall {
  /// Captures an immutable request.
  FakeRecycleCall(this.folder, List<String> names)
    : names = List.unmodifiable(names);

  /// The requested folder.
  final String folder;

  /// The requested basenames.
  final List<String> names;

  /// The signal that releases this call.
  final Completer<RecycleReply> completion = Completer<RecycleReply>();

  /// Completes each name with its scripted status, or a confirmed move.
  void complete([Map<String, RecycleStatus> scripted = const {}]) {
    completion.complete(
      RecycleStatuses({
        for (final name in names) name: scripted[name] ?? const RecycleMoved(),
      }),
    );
  }
}

/// A hand-written recycle port whose calls advance only through signals.
final class FakeRecyclePort implements RecyclePort {
  /// All calls in submission order.
  final List<FakeRecycleCall> calls = [];

  /// The number of cancellation requests.
  int cancellations = 0;

  final Map<int, Completer<FakeRecycleCall>> _waiting = {};

  /// Completes when call [index] has been submitted.
  Future<FakeRecycleCall> waitForCall(int index) {
    if (index < calls.length) return Future.value(calls[index]);
    return (_waiting[index] ??= Completer<FakeRecycleCall>()).future;
  }

  @override
  Future<RecycleReply> recycle(String folder, List<String> names) {
    final call = FakeRecycleCall(folder, names);
    calls.add(call);
    _waiting.remove(calls.length - 1)?.complete(call);
    return call.completion.future;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}
