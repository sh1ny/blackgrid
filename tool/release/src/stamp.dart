import 'dart:convert';
import 'dart:io';

import 'git.dart';

/// The build stamp, relative to the repository root, next to `Release/`.
const stampPath = 'build/windows/x64/runner/blackgrid-build.json';

/// What a passing `build:release` built: the record packaging trusts (D1).
class BuildStamp {
  const BuildStamp({
    required this.version,
    required this.buildNumber,
    required this.commit,
  });

  /// Parses a stamp file's [source], rejecting anything but format 1.
  ///
  /// Throws a [FormatException] for malformed JSON or a wrong shape.
  factory BuildStamp.parse(String source) {
    switch (jsonDecode(source)) {
      case {
            'format': 1,
            'version': final String version,
            'buildNumber': final int buildNumber,
            'commit': final String commit,
          }
          when _commitPattern.hasMatch(commit):
        return BuildStamp(
          version: version,
          buildNumber: buildNumber,
          commit: commit,
        );
      default:
        throw const FormatException('not a format 1 build stamp');
    }
  }

  static final _commitPattern = RegExp(r'^[0-9a-f]{40}$');

  /// The pubspec SemVer the bundle was built as.
  final String version;

  /// The commit-count build number (ADR-0009).
  final int buildNumber;

  /// The full hash of the built `HEAD`.
  final String commit;

  /// Encodes the stamp as one JSON object.
  String encode() => jsonEncode({
    'format': 1,
    'version': version,
    'buildNumber': buildNumber,
    'commit': commit,
  });
}

/// The stamp file of the repository at [repoDir].
File stampFile(Directory repoDir) => File('${repoDir.path}/$stampPath');

/// Writes [stamp] to [file] through a temporary file and a rename, so a
/// reader never sees a partial stamp.
void writeStamp(File file, BuildStamp stamp) {
  file.parent.createSync(recursive: true);
  final temp = File('${file.path}.tmp')..writeAsStringSync(stamp.encode());
  temp.renameSync(file.path);
}

/// Reads the stamp at [file], or returns `null` when there is none.
///
/// Throws a [ReleaseException] when the file exists but is not a valid stamp.
BuildStamp? readStamp(File file) {
  if (!file.existsSync()) return null;
  try {
    return BuildStamp.parse(file.readAsStringSync());
  } on FormatException catch (e) {
    throw ReleaseException(
      'The build stamp ${file.path} is malformed (${e.message}); '
      'run `mise run build:release` again.',
    );
  }
}
