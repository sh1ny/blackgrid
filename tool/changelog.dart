import 'dart:convert';
import 'dart:io';

import 'release/src/semver.dart';

/// Renders the changelog with git-cliff in two stages.
///
/// Stage 1 asks git-cliff for the JSON context of the selected range. Dart
/// then drops every commit that is not on the first-parent line of HEAD, so
/// commits that reached main only through a merged branch are not listed and
/// each merged PR stays one entry. Stage 2 renders the filtered context.
///
/// Usage: dart run tool/changelog.dart [range] [--tag|-t <tag>]
/// [--unreleased|-u] [--latest|-l] [--output|-o <file>] [--strip|-s <part>]
/// [--prepend|-p <file>]
///
/// `--unreleased` and `--latest` are translated to ranges between final
/// (non-prerelease) tags, ordered by SemVer precedence.
Future<void> main(List<String> arguments) async {
  final _Options options;
  try {
    options = _Options.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('changelog: ${error.message}');
    exitCode = 2;
    return;
  }

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

  // git-cliff cannot traverse an unborn branch. Render an empty context.
  var context = '[]';
  if (head.exitCode == 0) {
    final selection = await _selection(options);
    if (selection == null) return;
    final filtered = await _filteredContext(selection);
    if (filtered == null) return;
    context = filtered;
  }

  await _render(context, options.render);
}

const _baseArguments = ['--offline', '--config', 'cliff.toml'];

class _Options {
  _Options(this.range, this.tag, this.unreleased, this.latest, this.render);

  final String? range;
  final String? tag;
  final bool unreleased;
  final bool latest;
  final List<String> render;

  static const _selectionValues = {'--tag', '-t'};
  static const _renderValues = {
    '--output',
    '-o',
    '--strip',
    '-s',
    '--prepend',
    '-p',
  };

  static _Options parse(List<String> arguments) {
    String? range;
    String? tag;
    var unreleased = false;
    var latest = false;
    final render = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      var argument = arguments[i];
      String? inline;
      if (argument.startsWith('--') && argument.contains('=')) {
        final split = argument.indexOf('=');
        inline = argument.substring(split + 1);
        argument = argument.substring(0, split);
      }
      String value() {
        if (inline != null) return inline;
        if (i + 1 >= arguments.length) {
          throw FormatException('option $argument requires a value');
        }
        return arguments[++i];
      }

      if (_selectionValues.contains(argument)) {
        tag = value();
      } else if (_renderValues.contains(argument)) {
        render.addAll([argument, value()]);
      } else if (argument == '--unreleased' || argument == '-u') {
        unreleased = true;
      } else if (argument == '--latest' || argument == '-l') {
        latest = true;
      } else if (argument.startsWith('-')) {
        throw FormatException('unsupported option $argument');
      } else if (range != null) {
        throw FormatException('only one range may be given');
      } else {
        range = argument;
      }
    }
    if (unreleased && latest) {
      throw const FormatException('--unreleased and --latest are exclusive');
    }
    if ((unreleased || latest) && range != null) {
      throw const FormatException(
        '--unreleased and --latest cannot be combined with a range',
      );
    }
    return _Options(range, tag, unreleased, latest, render);
  }
}

/// What stage 1 asks git-cliff for. [onlyVersion] keeps just that release.
class _Selection {
  const _Selection(this.arguments, [this.onlyVersion]);

  final List<String> arguments;
  final String? onlyVersion;
}

/// The stage 1 selection, or null after reporting a failure.
Future<_Selection?> _selection(_Options options) async {
  final tag = options.tag;
  if (!options.unreleased && !options.latest) {
    return _Selection([
      ?options.range,
      if (tag != null) ...['--tag', tag],
    ]);
  }

  final tags = await Process.run('git', ['tag', '--merged', 'HEAD']);
  if (tags.exitCode != 0) {
    stderr.write(tags.stderr);
    exitCode = tags.exitCode;
    return null;
  }
  final finals = <(SemVer, String)>[
    for (final name in LineSplitter.split(tags.stdout as String))
      if (releaseTagPattern.hasMatch(name.trim()))
        if (SemVer.tryParse(name.trim().substring(1)) case final version?
            when version.preRelease.isEmpty)
          (version, name.trim()),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  if (options.unreleased) {
    // Everything since the latest final tag; all of HEAD when there is none.
    return _Selection([
      if (finals.isNotEmpty) '${finals.last.$2}..HEAD',
      if (tag != null) ...['--tag', tag],
    ]);
  }
  if (finals.isEmpty) {
    stderr.writeln('changelog: --latest needs a final release tag (vX.Y.Z).');
    exitCode = 1;
    return null;
  }
  // The range alone renders the tag's section; adding --tag would only make
  // git-cliff warn that the tag already exists.
  final latest = finals.last.$2;
  if (finals.length > 1) {
    return _Selection(['${finals[finals.length - 2].$2}..$latest']);
  }
  // No previous final tag: git-cliff has no root-relative range, so render
  // the whole history and keep only the latest tag's section.
  return _Selection(const [], latest);
}

/// Stage 1 JSON limited to first-parent commits, or null after a failure.
Future<String?> _filteredContext(_Selection selection) async {
  final firstParent = await Process.run('git', [
    'rev-list',
    '--first-parent',
    'HEAD',
  ]);
  if (firstParent.exitCode != 0) {
    stderr.write(firstParent.stderr);
    exitCode = firstParent.exitCode;
    return null;
  }
  final onMain = LineSplitter.split(firstParent.stdout as String)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet();

  final stage1 = await Process.run(
    'git-cliff',
    [..._baseArguments, '--context', ...selection.arguments],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (stage1.exitCode != 0) {
    stderr.write(stage1.stderr);
    exitCode = stage1.exitCode;
    return null;
  }

  final releases = jsonDecode(stage1.stdout as String) as List<Object?>;
  final only = selection.onlyVersion;
  if (only != null) {
    releases.removeWhere(
      (release) => (release! as Map<String, Object?>)['version'] != only,
    );
  }
  for (final release in releases) {
    final commits = (release! as Map<String, Object?>)['commits'];
    if (commits is List<Object?>) {
      commits.removeWhere(
        (commit) => !onMain.contains((commit! as Map<String, Object?>)['id']),
      );
    }
  }
  return jsonEncode(releases);
}

Future<void> _render(String context, List<String> renderOptions) async {
  final process = await Process.start('git-cliff', [
    ..._baseArguments,
    '--from-context',
    '-',
    ...renderOptions,
  ]);
  final outputDone = Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  IOException? inputError;
  StackTrace? inputStackTrace;
  try {
    process.stdin.add(utf8.encode(context));
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
