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

  /// Starts the commit of every field with typed, uncommitted text.
  ///
  /// Each [CommitField.onCommit] is called before this returns. The future
  /// completes when every commit has finished; a caller that unmounts the
  /// fields in the same frame may ignore it, because a field that is gone
  /// ignores its save result.
  Future<void> flush() =>
      Future.wait([for (final field in _fields.toList()) field.commit()]);
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
/// form. An edit that equals [value], or that is already being committed, is
/// not committed again.
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
    if (widget.value != old.value) controller.text = widget.value;
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
  Future<void> commit() async {
    if (!mounted || !widget.enabled) return;
    if (controller.text.trim() == widget.value) {
      if (error != null) setState(() => error = null);
      return;
    }
    final text = controller.text;
    // Leaving the field and then a flush can both ask to commit the same text.
    if (_saving == text) return;
    _saving = text;
    final String? result;
    try {
      result = await widget.onCommit(text);
    } finally {
      if (_saving == text) _saving = null;
    }
    // A newer edit replaced the text this result belongs to.
    if (!mounted || controller.text != text) return;
    setState(() => error = result);
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
