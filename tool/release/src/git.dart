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
    Map<String, String>? environment,
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
  }) async {
    final env = _environmentFor(environment);
    final includeParent = environment == null;
    if (stream) {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: env,
        includeParentEnvironment: includeParent,
        mode: ProcessStartMode.inheritStdio,
      );
      return CommandResult(await process.exitCode, '', '');
    }
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: env,
      includeParentEnvironment: includeParent,
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
