import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import 'no_games_scan.dart' show toPlain;

/// The repository-relative path of the release workflow.
const releaseWorkflowPath = '.github/workflows/release.yml';

/// The repository `owner/name` the scripts see as `GITHUB_REPOSITORY`.
const testRepository = 'acme/blackgrid';

/// One answer of the fake `gh`: the body it prints and the exit code it ends
/// with. A non-zero [exitCode] also prints a short error on stderr, as `gh api`
/// does for an HTTP failure.
class GhReply {
  /// Creates a reply that prints [body] and exits with [exitCode].
  const GhReply(this.body, {this.exitCode = 0});

  /// A reply that fails like an HTTP error.
  const GhReply.fail([this.body = '{"message":"Not Found"}']) : exitCode = 1;

  /// What `gh api` prints on stdout.
  final String body;

  /// The exit code of the call.
  final int exitCode;
}

/// One `gh api` call the script made.
class GhCall {
  /// Creates a record of call number [index].
  const GhCall(this.index, this.method, this.endpoint, this.payload);

  /// One-based position among all calls of the run.
  final int index;

  /// The HTTP method; `GET` when the script passed no `-X`.
  final String method;

  /// The endpoint or URL argument, exactly as the script passed it.
  final String endpoint;

  /// The bytes of the `--input` file or stdin, or null for a call without one.
  final List<int>? payload;

  /// The payload decoded as JSON, or null without a payload.
  Map<String, dynamic>? get json => switch (payload) {
    null => null,
    final bytes =>
      (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>(),
  };

  /// `METHOD endpoint`, the form the tests compare.
  String get line => '$method $endpoint';

  @override
  String toString() => line;
}

/// What a run of workflow steps did.
class ScriptRun {
  /// Creates the result of a run.
  ScriptRun({
    required this.exitCode,
    required this.log,
    required this.calls,
    required this.outputs,
  });

  /// Exit code of the last step that ran; zero when every step passed.
  final int exitCode;

  /// Stdout and stderr of every step that ran, in order.
  final String log;

  /// Every `gh api` call, in order.
  final List<GhCall> calls;

  /// The `key=value` lines the steps appended to `GITHUB_OUTPUT`.
  final Map<String, String> outputs;

  /// The calls as `METHOD endpoint` lines.
  List<String> get lines => [for (final c in calls) c.line];
}

/// The parsed `release.yml` plus a temporary directory to run its scripts in.
///
/// Scripts run under `bash` with a fake `gh` first on `PATH` that answers from
/// per-test replies and records every call. `sha256sum` and `jq` are the real
/// ones, so the scripts run as they do on the `ubuntu-latest` runner.
class ReleaseScriptHarness {
  ReleaseScriptHarness._(this.workflow, this.root, this._bash);

  /// Loads [releaseWorkflowPath] and prepares an empty sandbox.
  ///
  /// Fails with a clear message when `bash`, `jq` or `sha256sum` is missing.
  factory ReleaseScriptHarness.create() {
    final file = File(releaseWorkflowPath);
    if (!file.existsSync()) {
      throw StateError('$releaseWorkflowPath must exist');
    }
    final bash = _findBash();
    for (final tool in ['jq', 'sha256sum']) {
      final probe = Process.runSync(bash, ['-c', 'command -v $tool']);
      if (probe.exitCode != 0) {
        throw StateError(
          '$tool is not available to bash ($bash); the release scripts '
          'need bash, jq and sha256sum',
        );
      }
    }
    final workflow = (toPlain(loadYaml(file.readAsStringSync())) as Map)
        .cast<String, dynamic>();
    final root = Directory.systemTemp.createTempSync('release_scripts_');
    return ReleaseScriptHarness._(workflow, root, bash)
      .._install(Directory('${root.path}/bin')..createSync());
  }

  /// The parsed workflow.
  final Map<String, dynamic> workflow;

  /// The sandbox root; deleted by [dispose].
  final Directory root;

  final String _bash;
  final _replies = <String, List<GhReply>>{};

  /// The directory the steps run in, with `dist/` as the publish job sees it.
  Directory get work => Directory('${root.path}/work')..createSync();

  /// Deletes the sandbox.
  void dispose() => root.deleteSync(recursive: true);

  /// Answers the n-th call of `METHOD endpoint` with the n-th of [replies]; the
  /// last reply answers every later call.
  void route(String method, String endpoint, List<GhReply> replies) {
    _replies['$method $endpoint'] = replies;
  }

  /// The `run:` script of the step named [step] in job [job].
  String script(String job, String step) => '${_step(job, step)['run']}';

  Map<String, dynamic> _step(String job, String name) {
    final jobs = (workflow['jobs'] as Map).cast<String, dynamic>();
    final steps = ((jobs[job] as Map)['steps'] as List).cast<Map>();
    return steps.singleWhere((s) => s['name'] == name).cast<String, dynamic>();
  }

  /// Runs the named steps of [job] in order inside [work], stopping at the
  /// first failure.
  ///
  /// Each `${{ expr }}` in a step's `env:` is replaced by `expressions[expr]`;
  /// an expression without a value fails the test run.
  ScriptRun run(
    String job,
    List<String> steps, {
    required Map<String, String> expressions,
  }) {
    final state = Directory('${root.path}/state');
    if (state.existsSync()) state.deleteSync(recursive: true);
    state.createSync();
    final resp = Directory('${state.path}/resp')..createSync();
    for (final MapEntry(:key, :value) in _replies.entries) {
      for (final (i, reply) in value.indexed) {
        File('${resp.path}/${_key(key)}.${i + 1}')
            .writeAsStringSync(reply.body);
        File('${resp.path}/${_key(key)}.${i + 1}.exit')
            .writeAsStringSync('${reply.exitCode}');
      }
    }
    final outputFile = File('${state.path}/github_output')
      ..writeAsStringSync('');
    final log = StringBuffer();
    var exitCode = 0;
    for (final name in steps) {
      final step = _step(job, name);
      final scriptFile = File('${state.path}/step.sh')
        ..writeAsStringSync('${step['run']}\n');
      final env = _environment(
        step,
        expressions,
        state: state,
        outputFile: outputFile,
      );
      final result = Process.runSync(
        _bash,
        [scriptFile.path],
        workingDirectory: work.path,
        environment: env,
        includeParentEnvironment: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      log
        ..writeln('--- $name (exit ${result.exitCode})')
        ..write(result.stdout)
        ..write(result.stderr);
      exitCode = result.exitCode;
      if (exitCode != 0) break;
    }
    return ScriptRun(
      exitCode: exitCode,
      log: log.toString(),
      calls: _readCalls(state),
      outputs: _readOutputs(outputFile),
    );
  }

  Map<String, String> _environment(
    Map<String, dynamic> step,
    Map<String, String> expressions, {
    required Directory state,
    required File outputFile,
  }) {
    final env = <String, String>{
      for (final MapEntry(:key, :value) in Platform.environment.entries)
        // The sandbox never inherits the CI confirmation variables.
        if (!key.toUpperCase().startsWith('BLACKGRID_')) key: value,
    };
    final pathKey = env.keys.firstWhere(
      (k) => k.toUpperCase() == 'PATH',
      orElse: () => 'PATH',
    );
    final separator = Platform.isWindows ? ';' : ':';
    env[pathKey] = '${root.path}/bin$separator${env[pathKey] ?? ''}';
    env['FAKE_GH_DIR'] = state.path.replaceAll(r'\', '/');
    env['GITHUB_REPOSITORY'] = testRepository;
    env['GITHUB_OUTPUT'] = outputFile.path.replaceAll(r'\', '/');
    final declared = ((step['env'] ?? <String, dynamic>{}) as Map)
        .cast<String, dynamic>();
    final expression = RegExp(r'\$\{\{\s*(.*?)\s*\}\}');
    for (final MapEntry(:key, :value) in declared.entries) {
      env[key] = '$value'.replaceAllMapped(expression, (m) {
        final text = m.group(1)!;
        final replacement = expressions[text];
        if (replacement == null) {
          throw StateError('no test value for the expression: $text');
        }
        return replacement;
      });
    }
    return env;
  }

  List<GhCall> _readCalls(Directory state) {
    final log = File('${state.path}/calls.log');
    if (!log.existsSync()) return const [];
    return [
      for (final line in log.readAsLinesSync().where((l) => l.isNotEmpty))
        _call(state, line),
    ];
  }

  GhCall _call(Directory state, String line) {
    final [index, method, endpoint] = line.split(' ');
    final payload = File('${state.path}/payload.$index');
    return GhCall(
      int.parse(index),
      method,
      endpoint,
      payload.existsSync() ? payload.readAsBytesSync() : null,
    );
  }

  Map<String, String> _readOutputs(File file) => {
    for (final line in file.readAsLinesSync())
      if (line.contains('='))
        line.substring(0, line.indexOf('=')): line.substring(
          line.indexOf('=') + 1,
        ),
  };

  void _install(Directory bin) {
    File('${bin.path}/gh').writeAsStringSync(_fakeGh);
  }
}

String _key(String routeKey) =>
    routeKey.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

String _findBash() {
  if (!Platform.isWindows) return 'bash';
  // `bash` on a Windows PATH can be the WSL launcher; use Git for Windows.
  final found = Process.runSync('where', ['bash']);
  final candidates = '${found.stdout}'
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .where((l) => !l.toLowerCase().contains(r'\windowsapps\'))
      .where((l) => !l.toLowerCase().contains(r'\system32\'));
  if (candidates.isEmpty) {
    throw StateError(
      'bash (Git for Windows) is not on PATH; the release scripts need '
      'bash, jq and sha256sum',
    );
  }
  return candidates.first;
}

/// A `gh api` stand-in that answers from `$FAKE_GH_DIR/resp` and records calls.
///
/// It supports only what the release scripts use: `api [-X M] [-H h]
/// [--paginate] [--input file|-] endpoint`. Like the real `gh api --paginate`
/// without `--jq`, a reply body is printed as is, so a multi-page listing is
/// several JSON arrays back to back.
const _fakeGh = r'''#!/usr/bin/env bash
dir="$FAKE_GH_DIR"
if [ "${1:-}" != api ]; then echo "fake gh: unsupported: $*" >&2; exit 97; fi
shift
method=GET
endpoint=
input=
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    -H) shift 2 ;;
    --paginate) shift ;;
    -*) echo "fake gh: unsupported flag: $1" >&2; exit 97 ;;
    *) endpoint="$1"; shift ;;
  esac
done
n=$(( $(cat "$dir/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$dir/count"
echo "$n $method $endpoint" >> "$dir/calls.log"
if [ -n "$input" ]; then
  if [ "$input" = - ]; then cat > "$dir/payload.$n"; else cp "$input" "$dir/payload.$n"; fi
fi
key=$(printf '%s_%s' "$method" "$endpoint" | tr -c 'A-Za-z0-9' '_')
echo "$key" >> "$dir/keys.log"
hits=$(grep -c -x -F "$key" "$dir/keys.log")
while [ "$hits" -gt 0 ] && [ ! -f "$dir/resp/$key.$hits" ]; do hits=$((hits - 1)); done
if [ "$hits" -eq 0 ]; then echo "fake gh: no route for $method $endpoint" >&2; exit 98; fi
cat "$dir/resp/$key.$hits"
code=$(cat "$dir/resp/$key.$hits.exit")
if [ "$code" != 0 ]; then echo "gh: HTTP error" >&2; fi
exit "$code"
''';

/// A release package as the publish job finds it after the download.
class PackageFixture {
  /// Writes a package into `<work>/dist` and keeps what the tests compare.
  PackageFixture.write(
    Directory work, {
    this.version = '0.6.0',
    this.prerelease = false,
    this.latest = true,
    String? tag,
  }) : tag = tag ?? 'v$version' {
    final dist = Directory('${work.path}/dist')..createSync(recursive: true);
    final release = Directory('${dist.path}/release')..createSync();
    final meta = Directory('${dist.path}/release-meta')..createSync();
    File('${release.path}/$zipName').writeAsStringSync('zip bytes');
    File('${release.path}/$setupName').writeAsStringSync('setup bytes');
    File('${release.path}/SHA256SUMS.txt').writeAsStringSync(
      '${_sha(File('${release.path}/$zipName'))}  $zipName\n'
      '${_sha(File('${release.path}/$setupName'))}  $setupName\n',
    );
    File('${meta.path}/notes.md').writeAsStringSync('## Notes\n\n- a change\n');
    File('${meta.path}/release.json').writeAsStringSync(
      jsonEncode({
        'tag': this.tag,
        'version': version,
        'prerelease': prerelease,
        'latest': latest,
      }),
    );
    this.dist = dist;
  }

  /// The package version.
  final String version;

  /// The tag the package is for.
  final String tag;

  /// The `prerelease` value of `release.json`.
  final bool prerelease;

  /// The `latest` value of `release.json`.
  final bool latest;

  /// The download directory.
  late final Directory dist;

  /// The zip asset name.
  String get zipName => 'Blackgrid-$version-windows-x64.zip';

  /// The installer asset name.
  String get setupName => 'Blackgrid-$version-windows-x64-setup.exe';

  /// A file below `dist/`.
  File file(String relative) => File('${dist.path}/$relative');

  /// Lowercase hex SHA-256 of the checksum file, the gates' `sums_sha256`.
  String get sumsDigest => _sha(file('release/SHA256SUMS.txt'));

  static String _sha(File file) =>
      sha256.convert(file.readAsBytesSync()).toString();
}
