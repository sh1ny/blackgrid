import 'dart:io';

/// A refusal or failure with the exit code the CLI should use.
class ReleaseException implements Exception {
  const ReleaseException(this.message, {this.exitCode = 1});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

class CommandResult {
  const CommandResult(
    this.exitCode,
    this.stdout,
    this.stderr, {
    this.timedOut = false,
  });

  /// A child killed, with its process tree, when its timeout expired.
  const CommandResult.timedOut(this.stdout, this.stderr)
    : exitCode = -1,
      timedOut = true;

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Whether the child was killed because its timeout expired; [exitCode] is
  /// then `-1`.
  final bool timedOut;
}

/// Seam for every external effect (git, mise gates, dart, gh, git-cliff).
abstract class CommandRunner {
  /// Runs [executable]. With [stream], output goes straight to the console
  /// and the result has empty stdout/stderr.
  ///
  /// With a [timeout], a child still running when it expires is killed with
  /// its whole process tree, and the result is [CommandResult.timedOut].
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
    Duration? timeout,
  });
}

class ProcessCommandRunner implements CommandRunner {
  const ProcessCommandRunner({this.environment});

  /// Extra environment variables merged over the inherited environment.
  final Map<String, String>? environment;

  /// With a per-call [call] environment (the fenced credential environment),
  /// the child gets the parent environment minus any inherited GitHub tokens,
  /// then this runner's extras, then [call]. Without one, the parent
  /// environment is inherited unchanged plus this runner's extras.
  Map<String, String>? _environmentFor(Map<String, String>? call) {
    if (call == null) return environment;
    return {
      for (final e in Platform.environment.entries)
        if (e.key.toUpperCase() != 'GH_TOKEN' &&
            e.key.toUpperCase() != 'GITHUB_TOKEN')
          e.key: e.value,
      ...?environment,
      ...call,
    };
  }

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final env = _environmentFor(environment);
    final includeParent = environment == null;
    // flutter is a .bat shim on Windows, which only a shell can launch.
    final shell = Platform.isWindows && executable == 'flutter';
    if (!stream && timeout == null) {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: env,
        includeParentEnvironment: includeParent,
        runInShell: shell,
      );
      return CommandResult(
        result.exitCode,
        result.stdout as String,
        result.stderr as String,
      );
    }
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: env,
      includeParentEnvironment: includeParent,
      runInShell: shell,
      mode: stream ? ProcessStartMode.inheritStdio : ProcessStartMode.normal,
    );
    final out = stream
        ? Future.value('')
        : process.stdout.transform(systemEncoding.decoder).join();
    final err = stream
        ? Future.value('')
        : process.stderr.transform(systemEncoding.decoder).join();
    if (timeout == null) {
      return CommandResult(await process.exitCode, await out, await err);
    }
    final exit = await process.exitCode
        .then<int?>((code) => code)
        .timeout(timeout, onTimeout: () => null);
    if (exit != null) return CommandResult(exit, await out, await err);
    await _killTree(process);
    return CommandResult.timedOut(await out, await err);
  }

  /// Kills [process] and every process it started, then waits for it to exit.
  ///
  /// A plain kill would leave the children running: Inno Setup's `setup.exe`,
  /// for one, hands its work to a child `setup.tmp`.
  static Future<void> _killTree(Process process) async {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    }
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}

/// Thin git wrapper over a [CommandRunner], bound to one repository.
class Git {
  const Git(this.runner, this.directory);

  final CommandRunner runner;
  final Directory directory;

  Future<CommandResult> run(
    List<String> arguments, {
    Map<String, String>? environment,
  }) => runner.run(
    'git',
    arguments,
    workingDirectory: directory.path,
    environment: environment,
  );

  /// Runs git and returns trimmed stdout; throws [ReleaseException] with
  /// [failure] and git's stderr on a non-zero exit.
  Future<String> output(List<String> arguments, {String? failure}) async {
    final r = await run(arguments);
    if (r.exitCode != 0) {
      throw ReleaseException(
        '${failure ?? 'git ${arguments.join(' ')} failed'}: '
        '${r.stderr.trim()}',
      );
    }
    return r.stdout.trim();
  }
}
