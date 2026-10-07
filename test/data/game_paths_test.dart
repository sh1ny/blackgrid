import 'dart:io';

import 'package:blackgrid/data/game_paths.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('blackgrid-game-paths-');
  });
  tearDown(() => root.delete(recursive: true));

  String path(String relative) =>
      '${root.path}\\${relative.replaceAll('/', r'\')}';
  Future<void> folder(String relative) =>
      Directory(path(relative)).create(recursive: true);

  GamePathDiscovery discovery(
    Map<String, String> registry, {
    Map<String, String> environment = const {},
  }) => GamePathDiscovery(
    readRegistry: (key, value) async => registry['$key|$value'],
    environment: environment,
  );

  test('launcher uninstall location supplies Logs, then build/Logs', () async {
    await folder('EFT/Logs');
    const key =
        r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\EscapeFromTarkov|InstallLocation';
    expect(await discovery({key: path('EFT')}).logs(), path('EFT/Logs'));
    await Directory(path('EFT/Logs')).delete();
    await folder('EFT/build/Logs');
    expect(await discovery({key: path('EFT')}).logs(), path('EFT/build/Logs'));
  });

  test('Steam library manifests locate the install when the launcher is absent', () async {
    await folder('Steam/steamapps');
    await folder('Library/steamapps/common/EFT Steam/build/Logs');
    await File(path('Steam/steamapps/libraryfolders.vdf')).writeAsString(
      '"libraryfolders"\n{\n  "1"\n  {\n    "path"    "${path('Library').replaceAll(r'\', r'\\')}"\n  }\n}\n',
    );
    await File(path('Library/steamapps/appmanifest_3932890.acf'))
        .writeAsString('"AppState"\n{\n  "installdir"    "EFT Steam"\n}\n');
    expect(
      await discovery({
        r'HKCU\SOFTWARE\Valve\Steam|SteamPath': path('Steam')
            .replaceAll(r'\', '/'),
      }).logs(),
      path('Library/steamapps/common/EFT Steam/build/Logs'),
    );
  });

  for (final directory in [
    '../Unexpected',
    r'..\Unexpected',
    '.',
    '..',
    '. ',
    '.. ',
    'Unexpected/nested',
    r'Unexpected\nested',
    r'C:\Unexpected',
    r'C:Unexpected',
    r'\Unexpected',
  ]) {
    test(
      'Steam install name "$directory" cannot redirect log discovery',
      () async {
        await folder('Steam/steamapps/common/Logs');
        await folder('Steam/steamapps/Logs');
        await folder('Steam/steamapps/Unexpected/Logs');
        await folder('Steam/steamapps/common/Unexpected/nested/Logs');
        await File(path('Steam/steamapps/appmanifest_3932890.acf'))
            .writeAsString('"installdir" "$directory"');
        final paths = discovery({
          r'HKCU\SOFTWARE\Valve\Steam|SteamPath': path('Steam'),
        });
        expect(await paths.logs(), '');
        await folder('Steam/steamapps/common/Escape from Tarkov/Logs');
        expect(
          await paths.logs(),
          path('Steam/steamapps/common/Escape from Tarkov/Logs'),
        );
      },
    );
  }

  test('missing installs report no logs folder', () async {
    expect(await discovery({}).logs(), '');
    expect(
      await discovery({
        r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\EscapeFromTarkov|InstallLocation':
            path('absent'),
      }).logs(),
      '',
    );
  });

  test('screenshots follow the Documents shell folder, then the profile', () async {
    expect(
      await discovery({
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders|Personal':
            r'C:\Users\me\OneDrive\Documents',
      }).screenshots(),
      r'C:\Users\me\OneDrive\Documents\Escape from Tarkov\Screenshots',
    );
    expect(
      await discovery(
        {},
        environment: {'USERPROFILE': r'C:\Users\me'},
      ).screenshots(),
      r'C:\Users\me\Documents\Escape from Tarkov\Screenshots',
    );
    expect(await discovery({}).screenshots(), '');
  });
}
