/// Strict SemVer 2.0.0 parsing and precedence (spec section 11).
///
/// Owned here instead of using pub_semver so release rules (no build
/// metadata, strict v-prefixed tags) stay explicit.
library;

const _numeric = r'(?:0|[1-9][0-9]*)';
const _preId = r'(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)';
const _buildId = r'[0-9A-Za-z-]+';
const _core = '($_numeric)\\.($_numeric)\\.($_numeric)';
const _pre = '(?:-($_preId(?:\\.$_preId)*))?';
const _build = '(?:\\+($_buildId(?:\\.$_buildId)*))?';

final RegExp _semver = RegExp('^$_core$_pre$_build\$');

/// Matches a strict v-prefixed SemVer release tag (`v1.2.3`, `v1.2.3-beta.1`).
final RegExp releaseTagPattern = RegExp('^v$_core$_pre$_build\$');

class SemVer implements Comparable<SemVer> {
  const SemVer._(
    this.major,
    this.minor,
    this.patch,
    this.preRelease,
    this.build,
  );

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;
  final List<String> build;

  static SemVer? tryParse(String text) {
    final m = _semver.firstMatch(text);
    return m == null ? null : _fromMatch(m);
  }

  /// Parses a release version: strict SemVer without build metadata and
  /// without a `v` prefix. Throws [FormatException] naming [text].
  static SemVer parseRelease(String text) {
    final v = tryParse(text);
    if (v == null || v.build.isNotEmpty) {
      throw FormatException(
        '"$text" is not a strict SemVer release version '
        '(expected MAJOR.MINOR.PATCH[-prerelease], no "v" prefix, '
        'no build metadata)',
      );
    }
    return v;
  }

  static SemVer _fromMatch(RegExpMatch m) => SemVer._(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    m[4]?.split('.') ?? const [],
    m[5]?.split('.') ?? const [],
  );

  @override
  int compareTo(SemVer other) {
    for (final c in [
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ]) {
      if (c != 0) return c;
    }
    if (preRelease.isEmpty || other.preRelease.isEmpty) {
      if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
      return preRelease.isEmpty ? 1 : -1;
    }
    final shared = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < shared; i++) {
      final c = _compareIdentifier(preRelease[i], other.preRelease[i]);
      if (c != 0) return c;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  static int _compareIdentifier(String a, String b) {
    final an = int.tryParse(a);
    final bn = int.tryParse(b);
    if (an != null && bn != null) return an.compareTo(bn);
    if (an != null) return -1;
    if (bn != null) return 1;
    return a.compareTo(b);
  }

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() =>
      '$major.$minor.$patch'
      '${preRelease.isEmpty ? '' : '-${preRelease.join('.')}'}'
      '${build.isEmpty ? '' : '+${build.join('.')}'}';
}

/// Highest tag by SemVer precedence among tags matching [releaseTagPattern];
/// other tags are ignored. Null when there is none.
SemVer? latestReleaseTag(Iterable<String> tags) {
  SemVer? latest;
  for (final tag in tags) {
    if (!releaseTagPattern.hasMatch(tag)) continue;
    final v = SemVer.tryParse(tag.substring(1))!;
    if (latest == null || v.compareTo(latest) > 0) latest = v;
  }
  return latest;
}

/// Null when [requested] has higher precedence than [latest] (or there is no
/// latest tag); otherwise a message naming both.
String? increaseRefusal(SemVer requested, SemVer? latest) {
  if (latest == null || requested.compareTo(latest) > 0) return null;
  return 'Version $requested must have higher SemVer precedence than the '
      'latest release tag v$latest.';
}
