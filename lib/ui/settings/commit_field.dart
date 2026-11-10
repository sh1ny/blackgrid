import 'dart:async';

import 'package:flutter/material.dart';

/// Lets a parent ask every [CommitField] under a [SettingsFlushScope] to
/// commit its pending text.
///
/// A field commits on the done action and on losing focus. Unmounting a field
/// removes its focus listener, so a page that closes while a field still holds
/// typed text calls [flush] first.
class SettingsFlushController {
  final _fields = <_CommitFieldState>{};

  /// Commits every field with typed, uncommitted text, one after the other.
  ///
  /// The texts are taken before this returns, so a caller may unmount the
  /// fields in the same frame and ignore the future: a field that is gone
  /// still saves its text and ignores the result. The saves run in turn, after
  /// any save a field already has in flight, because a save that starts while
  /// another one is running is refused. With no save in flight, the first
  /// [CommitField.onCommit] is called before this returns.
  Future<void> flush() async {
    final fields = _fields.toList();
    final running = [for (final field in fields) ?field._inFlight];
    final pending = [for (final field in fields) ?field._takePending()];
    if (running.isNotEmpty) await Future.wait(running);
    for (final run in pending) {
      await run();
    }
  }
}

/// Connects the [CommitField]s below it to a [SettingsFlushController].
class SettingsFlushScope extends InheritedWidget {
  /// Creates a scope that registers its descendants' fields with [controller].
  const SettingsFlushScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The controller that flushes the fields below this scope.
  final SettingsFlushController controller;

  /// The controller of the nearest scope above [context], or `null` for none.
  static SettingsFlushController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SettingsFlushScope>()
      ?.controller;

  @override
  bool updateShouldNotify(SettingsFlushScope old) =>
      controller != old.controller;
}

/// A text field that commits on the keyboard's done action and when it loses
/// focus.
///
/// [onCommit] completes with an error message to show under the field, or
/// `null` when the text was saved. A refused or unsaved edit keeps the typed
/// text, so the field never shows a value as saved when it was not. The field
/// follows [value] when it changes, so an accepted edit shows in its saved
/// form, unless newer text was typed since the last commit. An edit that
/// equals [value], or that is already being committed, is not committed again.
///
/// Inside a [SettingsFlushScope] the field also commits when the scope's
/// controller flushes.
class CommitField extends StatefulWidget {
  /// Creates a field labelled [label] that shows [value] and commits through
  /// [onCommit].
  const CommitField({
    super.key,
    required this.label,
    required this.value,
    required this.onCommit,
    this.helper,
    this.enabled = true,
  });

  /// The floating label of the field.
  final String label;

  /// Help text under the field while there is no error.
  final String? helper;

  /// The saved value the field shows and follows.
  final String value;

  /// Whether the field takes input and commits.
  final bool enabled;

  /// Saves the typed text and completes with an error message, or `null`.
  final Future<String?> Function(String text) onCommit;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final controller = TextEditingController(text: widget.value);
  final focus = FocusNode();
  SettingsFlushController? _scope;
  String? error;

  /// The text whose commit is in flight, or `null` when none is.
  String? _saving;

  /// The text last handed to [CommitField.onCommit], or `null` before any.
  String? _sent;

  /// The latest commit still running, or `null` when none is.
  Future<void>? _inFlight;

  @override
  void initState() {
    super.initState();
    focus.addListener(_onFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = SettingsFlushScope.maybeOf(context);
    if (scope == _scope) return;
    _scope?._fields.remove(this);
    _scope = scope?.._fields.add(this);
  }

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    // Text typed after the last commit is a newer edit: it stays.
    final text = controller.text;
    if (text == _sent || text.trim() == old.value) {
      controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _scope?._fields.remove(this);
    focus.removeListener(_onFocus);
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!focus.hasFocus) unawaited(commit());
  }

  /// Commits the typed text unless it equals the saved value.
  Future<void> commit() => _takePending()?.call() ?? Future.value();

  /// Claims the typed text and returns the function that commits it, or `null`
  /// when there is nothing to commit.
  ///
  /// The returned function works after the field is unmounted.
  Future<void> Function()? _takePending() {
    if (!mounted || !widget.enabled) return null;
    if (controller.text.trim() == widget.value) {
      if (error != null) setState(() => error = null);
      return null;
    }
    final text = controller.text;
    // Leaving the field and then a flush can both ask to commit the same text.
    if (_saving == text) return null;
    _saving = text;
    _sent = text;
    final onCommit = widget.onCommit;
    return () {
      late final Future<void> run;
      run = () async {
        final String? result;
        try {
          result = await onCommit(text);
        } finally {
          if (_saving == text) _saving = null;
          if (identical(_inFlight, run)) _inFlight = null;
        }
        // A newer edit replaced the text this result belongs to.
        if (!mounted || controller.text != text) return;
        setState(() => error = result);
      }();
      return _inFlight = run;
    };
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focus,
    enabled: widget.enabled,
    onChanged: (_) {
      if (error != null) setState(() => error = null);
    },
    onSubmitted: (_) => unawaited(commit()),
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      errorText: error,
    ),
  );
}
