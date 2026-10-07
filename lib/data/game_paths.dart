import 'dart:io';

/// Reads one string value, or null when the key or value is absent.
typedef RegistryReader = Future<String?> Function(String key, String value);

/// Locates the game's Logs and Screenshots folders the way the reference
/// tracker does: registry uninstall entries, then Steam libraries for logs;
/// Documents\Escape from Tarkov\Screenshots for screenshots. Only folder
/// metadata and Steam's own manifests are read; the game is never touched.
class GamePathDiscovery {
  GamePathDiscovery({
    RegistryReader? readRegistry,
    Map<String, String>? environment,
  }) : _read = readRegistry ?? _readWindowsRegistry,
       _environment = environment ?? Platform.environment;
  final RegistryReader _read;
  final Map<String, String> _environment;

  static const _steamAppId = '3932890';
  static const _uninstallKeys = [
    r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\EscapeFromTarkov',
    r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\EscapeFromTarkov',
    r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 3932890',
    r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 3932890',
  ];

  /// The first existing Logs folder, or '' when none is found.
  Future<String> logs() async {
    final installs = <String>{};
    for (final hive in const ['HKCU', 'HKLM']) {
      for (final key in _uninstallKeys) {
        final path = await _read('$hive\\$key', 'InstallLocation');
        if (path != null && path.isNotEmpty) installs.add(path);
      }
    }
    for (final install in installs) {
      final logs = await _logsIn(install);
      if (logs != null) return logs;
    }
    for (final library in await _steamLibraries()) {
      final install = await _steamInstall(library);
      final logs = install == null ? null : await _logsIn(install);
      if (logs != null) return logs;
    }
    return '';
  }

  /// The game's default screenshot folder, which may not exist yet.
  Future<String> screenshots() async {
    final documents =
        await _read(
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
          'Personal',
        ) ??
        (_environment['USERPROFILE'] == null
            ? null
            : _join(_environment['USERPROFILE']!, 'Documents'));
    return documents == null || documents.isEmpty
        ? ''
        : _join(_join(documents, 'Escape from Tarkov'), 'Screenshots');
  }

  Future<String?> _logsIn(String install) async {
    for (final candidate in [
      _join(install, 'Logs'),
      _join(_join(install, 'build'), 'Logs'),
    ]) {
      if (await Directory(candidate).exists()) return candidate;
    }
    return null;
  }

  Future<List<String>> _steamLibraries() async {
    final roots = <String>{};
    for (final (key, value) in const [
      (r'HKCU\SOFTWARE\Valve\Steam', 'SteamPath'),
      (r'HKLM\SOFTWARE\Valve\Steam', 'InstallPath'),
      (r'HKLM\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
    ]) {
      final path = await _read(key, value);
      if (path != null && path.isNotEmpty && await Directory(path).exists()) {
        roots.add(path.replaceAll('/', r'\'));
      }
    }
    final libraries = <String>{...roots};
    for (final root in roots) {
      final folders = File(
        _join(_join(root, 'steamapps'), 'libraryfolders.vdf'),
      );
      try {
        for (final match in RegExp(
          r'"path"\s+"([^"]+)"',
          caseSensitive: false,
        ).allMatches(await folders.readAsString())) {
          final path = match[1]!.replaceAll(r'\\', r'\');
          if (await Directory(path).exists()) libraries.add(path);
        }
      } on FileSystemException {
        // A missing or unreadable library list leaves the Steam root itself.
      }
    }
    return libraries.toList();
  }

  Future<String?> _steamInstall(String library) async {
    final apps = _join(library, 'steamapps');
    final candidates = <String>[];
    try {
      final manifest = await File(_join(apps, 'appmanifest_$_steamAppId.acf'))
          .readAsString();
      final directory = RegExp(
        r'"installdir"\s+"([^"]+)"',
        caseSensitive: false,
      ).firstMatch(manifest);
      if (directory != null) {
        candidates.add(_join(_join(apps, 'common'), directory[1]!));
      }
    } on FileSystemException {
      // Fall back to the default install folder name.
    }
    candidates.add(_join(_join(apps, 'common'), 'Escape from Tarkov'));
    for (final candidate in candidates) {
      if (await Directory(candidate).exists()) return candidate;
    }
    return null;
  }
}

String _join(String parent, String child) =>
    parent.endsWith(r'\') || parent.endsWith('/')
    ? '$parent$child'
    : '$parent\\$child';

Future<String?> _readWindowsRegistry(String key, String value) async {
  if (!Platform.isWindows) return null;
  for (final view in const ['/reg:64', '/reg:32']) {
    try {
      final result = await Process.run('reg', [
        'query',
        key,
        '/v',
        value,
        view,
      ]);
      if (result.exitCode != 0) continue;
      final match = RegExp(
        '^\\s+${RegExp.escape(value)}\\s+REG_(?:EXPAND_)?SZ\\s+(.+?)\\s*\$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(result.stdout as String);
      if (match != null) return match[1];
    } on ProcessException {
      return null;
    }
  }
  return null;
}
