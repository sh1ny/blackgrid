import 'dart:io';

import 'package:yaml/yaml.dart';

import 'git.dart';

/// Arguments that make Git take credentials only from `gh`, which in turn
/// reads the fenced GH_TOKEN. The empty value clears inherited helpers.
const credentialHelperArguments = [
  '-c',
  'credential.helper=',
  '-c',
  'credential.helper=!gh auth git-credential',
];

/// The confirmed GitHub account and the fenced environment holding its token.
///
/// The token exists only inside [environment]; it is handed to child
/// processes through the environment and never appears in arguments, output
/// or messages.
/// Git arguments that make the fenced token the only credential for [urls].
///
/// Besides [credentialHelperArguments], inherited `http.extraHeader` values
/// (an `Authorization` header set by automation, say) would authenticate
/// independently of the credential helper. An empty value resets them only
/// at the most specific matching URL, so the reset names each exact URL.
List<String> fencedGitArguments(Iterable<String> urls) => [
  ...credentialHelperArguments,
  for (final url in urls) ...['-c', 'http.$url.extraHeader='],
];

class PushIdentity {
  PushIdentity._(this.login, this.environment);

  final String login;
  final Map<String, String> environment;

  /// Runs a network Git command against `origin` under the fenced credential
  /// environment, with [fencedGitArguments] for origin's fetch and push URLs.
  Future<CommandResult> git(Git git, List<String> arguments) async {
    final urls = {
      for (final push in [false, true])
        await git.output([
          'remote',
          'get-url',
          if (push) '--push',
          'origin',
        ], failure: 'Could not read the URL of origin'),
    };
    for (final url in urls) {
      if (!_fencedUrl(url)) {
        throw ReleaseException(
          'origin URL "${_redactUserinfo(url)}" would not authenticate with '
          'the confirmed GitHub token (only HTTPS without embedded '
          'credentials does). Point origin at an HTTPS URL, for example '
          'https://github.com/<owner>/<repo>.git.',
        );
      }
    }
    return git.run([
      ...fencedGitArguments(urls),
      ...arguments,
    ], environment: environment);
  }

  /// Like [git] but throws [ReleaseException] with [failure] on failure.
  Future<String> gitOutput(
    Git git,
    List<String> arguments, {
    required String failure,
  }) async {
    final r = await this.git(git, arguments);
    if (r.exitCode != 0) {
      throw ReleaseException('$failure: ${r.stderr.trim()}');
    }
    return r.stdout.trim();
  }

  /// Reads `github.login` from `openspec/specwright.yaml`, obtains that
  /// account's token from `gh` and confirms `gh` authenticates as it.
  static Future<PushIdentity> confirm({
    required Directory repoDir,
    required CommandRunner runner,
  }) async {
    final login = _configuredLogin(repoDir);

    // A (non-null) per-call environment makes the runner strip inherited
    // GH_TOKEN / GITHUB_TOKEN; the map below is the only place the token is
    // ever kept.
    final authToken = await runner.run(
      'gh',
      ['auth', 'token', '--hostname', 'github.com', '--user', login],
      workingDirectory: repoDir.path,
      environment: const {},
    );
    final token = authToken.stdout.trim();
    if (authToken.exitCode != 0 || token.isEmpty) {
      throw ReleaseException(
        'No GitHub credential for the configured account "$login": '
        '${_scrub(authToken.stderr, token).trim()}',
      );
    }

    final environment = {'GH_TOKEN': token};
    final api = await runner.run(
      'gh',
      ['api', '--hostname', 'github.com', 'user', '--jq', '.login'],
      workingDirectory: repoDir.path,
      environment: environment,
    );
    final actual = api.stdout.trim();
    if (api.exitCode != 0) {
      throw ReleaseException(
        'Could not confirm the GitHub identity of "$login": '
        '${_scrub(api.stderr, token).trim()}',
      );
    }
    if (actual != login) {
      throw ReleaseException(
        'The authenticated GitHub account is "${_scrub(actual, token)}", '
        'but the configured account is "$login". Refusing to push.',
      );
    }
    return PushIdentity._(login, environment);
  }
}

/// Whether Git authenticates to [url] only through the fenced credential
/// helper: HTTPS without userinfo (`gh auth git-credential` answers for
/// HTTPS only). Local paths involve no authentication. HTTP, SSH, scp-like,
/// `git://` and `<transport>::` remote-helper URLs are refused.
bool _fencedUrl(String url) {
  final withScheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://([^/]*)')
      .firstMatch(url);
  if (withScheme != null) {
    final scheme = withScheme[1]!.toLowerCase();
    if (scheme == 'file') return true;
    return scheme == 'https' && !withScheme[2]!.contains('@');
  }
  if (url.contains('::')) return false;
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url)) return true;
  // scp-like `[user@]host:path`: a colon before the first slash.
  final colon = url.indexOf(':');
  final slash = url.indexOf('/');
  return colon < 0 || (slash >= 0 && slash < colon);
}

String _redactUserinfo(String url) =>
    url.replaceFirst(RegExp(r'://[^/@]*@'), '://***@');

String _scrub(String text, String token) =>
    token.isEmpty ? text : text.replaceAll(token, '***');

String _configuredLogin(Directory repoDir) {
  final file = File('${repoDir.path}/openspec/specwright.yaml');
  if (!file.existsSync()) {
    throw const ReleaseException(
      'openspec/specwright.yaml not found; cannot determine the GitHub '
      'account to push as.',
    );
  }
  final Object? doc;
  try {
    doc = loadYaml(file.readAsStringSync());
  } on YamlException catch (e) {
    throw ReleaseException('openspec/specwright.yaml is not valid YAML: $e');
  }
  final github = doc is YamlMap ? doc['github'] : null;
  final login = github is YamlMap ? github['login'] : null;
  if (login is! String || login.trim().isEmpty) {
    throw const ReleaseException(
      'github.login is not set in openspec/specwright.yaml; cannot determine '
      'the GitHub account to push as.',
    );
  }
  return login.trim();
}
