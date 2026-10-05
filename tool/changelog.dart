import 'dart:io';

Future<void> main(List<String> arguments) async {
  final head = await Process.run('git', [
    'rev-parse',
    '--verify',
    '--quiet',
    'HEAD',
  ]);
  if (head.exitCode != 0 && head.exitCode != 1) {
    stderr.write(head.stderr);
    exitCode = head.exitCode;
    return;
  }

  final process = await Process.start('git-cliff', [
    '--offline',
    '--config',
    'cliff.toml',
    // git-cliff cannot traverse an unborn branch. Render an empty context instead.
    if (head.exitCode == 1) ...['--from-context', '-'],
    ...arguments,
  ]);
  final outputDone = Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  IOException? inputError;
  StackTrace? inputStackTrace;
  try {
    if (head.exitCode == 1) {
      process.stdin.write('[]');
    }
    await process.stdin.close();
  } on IOException catch (error, stackTrace) {
    inputError = error;
    inputStackTrace = stackTrace;
  }
  await outputDone;
  exitCode = await process.exitCode;
  if (inputError != null && exitCode == 0) {
    Error.throwWithStackTrace(inputError, inputStackTrace!);
  }
}
