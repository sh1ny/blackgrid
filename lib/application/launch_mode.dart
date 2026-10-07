/// Command-line flag that selects the vision self-check.
const String visionSelfCheckFlag = '--vision-self-check';

enum LaunchMode { ui, visionSelfCheck }

/// Resolves the launch mode from the process arguments. Anything other than
/// the self-check flag as the first argument (including unknown arguments)
/// selects the normal UI.
LaunchMode resolveLaunchMode(List<String> args) =>
    args.isNotEmpty && args.first == visionSelfCheckFlag
    ? LaunchMode.visionSelfCheck
    : LaunchMode.ui;

/// Runs the selected launch path. Resolved before any Flutter binding is
/// created, so self-check mode shows no window and opens no database, and UI
/// mode never touches the vision runtime.
Future<void> dispatchLaunch(
  List<String> args, {
  required void Function() runUi,
  required Future<int> Function(List<String> args) selfCheck,
  required void Function(int code) exitProcess,
}) async {
  switch (resolveLaunchMode(args)) {
    case LaunchMode.ui:
      runUi();
    case LaunchMode.visionSelfCheck:
      exitProcess(await selfCheck(args));
  }
}
