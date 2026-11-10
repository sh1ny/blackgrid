import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds [builder] on a fixed period, so relative ages keep moving on.
///
/// The widget owns one [Timer.periodic] started in `initState` and cancelled
/// in `dispose`. It reads the time from [clock] on every build, so a test can
/// inject both the clock and a short [period] and never wait.
class AgeTick extends StatefulWidget {
  /// Creates a ticking builder reading time from [clock].
  const AgeTick({
    super.key,
    required this.clock,
    required this.builder,
    this.period = const Duration(seconds: 5),
  });

  /// The source of the current time, as the selection controller's clock.
  final DateTime Function() clock;

  /// Builds the content for the current time, in UTC.
  final Widget Function(BuildContext context, DateTime now) builder;

  /// How often the content is rebuilt.
  final Duration period;

  @override
  State<AgeTick> createState() => _AgeTickState();
}

class _AgeTickState extends State<AgeTick> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(AgeTick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _timer?.cancel();
      _start();
    }
  }

  void _start() {
    _timer = Timer.periodic(widget.period, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.clock().toUtc());
}
