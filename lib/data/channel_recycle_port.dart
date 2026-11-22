import 'package:flutter/services.dart';

import '../application/recycle_port.dart';

/// The runner channel used to recycle screenshots.
const String recycleChannelName = 'blackgrid/recycle';

/// A [RecyclePort] backed by the Windows runner.
class ChannelRecyclePort implements RecyclePort {
  /// Creates a port using [channel] or the runner's default channel.
  ChannelRecyclePort([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(recycleChannelName);

  final MethodChannel _channel;

  @override
  Future<RecycleReply> recycle(String folder, List<String> names) async {
    if (names.length > 64) return const RecycleCallFailure();
    final requested = names.toSet();
    if (requested.length != names.length) {
      return const RecycleCallFailure();
    }
    try {
      final reply = await _channel.invokeMethod<Object?>('recycle', {
        'folder': folder,
        'names': names,
      });
      if (reply is! List || reply.length != names.length) {
        return const RecycleCallFailure();
      }
      final statuses = <String, RecycleStatus>{};
      for (final entry in reply) {
        if (entry is! Map ||
            entry['name'] is! String ||
            entry['status'] is! String) {
          return const RecycleCallFailure();
        }
        final name = entry['name'] as String;
        final status = switch (entry['status']) {
          'moved' => const RecycleMoved(),
          'missing' => const RecycleMissing(),
          'notRecyclable' => const RecycleNotRecyclable(),
          'rejected' => const RecycleRejected(),
          'failed' => const RecycleFailed(),
          'cancelled' => const RecycleCancelled(),
          _ => null,
        };
        if (!requested.contains(name) ||
            statuses.containsKey(name) ||
            status == null) {
          return const RecycleCallFailure();
        }
        statuses[name] = status;
      }
      return RecycleStatuses({for (final name in names) name: statuses[name]!});
    } on PlatformException {
      return const RecycleCallFailure();
    } on MissingPluginException {
      return const RecycleCallFailure();
    }
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
