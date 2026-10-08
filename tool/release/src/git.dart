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
  const CommandResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Seam for every external effect (git, mise gates, dart, gh, git-cliff).
abstract class CommandRunner {
  /// Runs [executable]. With [stream], output goes straight to the console
  /// and the result has empty stdout/stderr.
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
  });
}

class ProcessCommandRunner implements CommandRunner {
  const ProcessCommandRunner({this.environment});

  /// Extra environment variables merged over the inherited environment.
  final Map<String, String>? environment;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
  }) async {
    if (stream) {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        mode: ProcessStartMode.inheritStdio,
      );
      return CommandResult(await process.exitCode, '', '');
    }
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    return CommandResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }
}

/// Thin git wrapper over a [CommandRunner], bound to one repository.
class Git {
  const Git(this.runner, this.directory);

  final CommandRunner runner;
  final Directory directory;

  Future<CommandResult> run(List<String> arguments) =>
      runner.run('git', arguments, workingDirectory: directory.path);

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
