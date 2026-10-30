import 'package:flutter_test/flutter_test.dart';

import 'support/no_games_scan.dart';

/// Proves the no-games setter scanner on synthetic inputs, so the repository
/// scan in `workflow_test.dart` cannot pass because the scanner is blind.
void main() {
  group('the no-games scanner', () {
    const v = noGamesVariable;
    void detects(String path, String content) => expect(
      findNoGamesSetters(path, content),
      isNotEmpty,
      reason: '$path should be flagged',
    );
    void ignores(String path, String content) => expect(
      findNoGamesSetters(path, content),
      isEmpty,
      reason: '$path should be ignored',
    );

    test('detects each setter kind and names the file', () {
      detects('mise.toml', '[env]\n$v = "1"\n');
      detects('mise.toml', '[tasks.x]\nenv = { $v = "1" }\n');
      detects('mise.toml', '[tasks.x.env]\n"$v" = "1"\n');
      detects('tool/a.ps1', '\$env:$v = "1"\n');
      detects('tool/a.ps1', 'Set-Item env:$v 1\n');
      detects('tool/a.cmd', 'set $v=1\n');
      detects('tool/a.bat', '  SET "$v=1"\n');
      detects('tool/a.sh', 'export $v=1\n');
      detects('tool/a.sh', '$v=1\n');
      detects('dart_test.yaml', 'env:\n  $v: "1"\n');
      detects('other.yml', 'a:\n  - env:\n      $v: "1"\n');
      expect(
        findNoGamesSetters('tool/a.sh', 'export $v=1\n').single,
        startsWith('tool/a.sh:1'),
      );
      expect(
        findNoGamesSetters('other.yml', 'env:\n  $v: "1"\n').single,
        startsWith('other.yml'),
      );
    });

    test('ignores comments, descriptions, reads and Markdown', () {
      ignores('mise.toml', '# $v = "1"\n');
      ignores('mise.toml', 'description = "needs $v=1; refuses"\n');
      ignores('tool/a.ps1', '# \$env:$v = "1"\n');
      ignores('tool/a.ps1', 'if (\$env:$v -ne "1") { exit 1 }\n');
      ignores('tool/a.cmd', 'rem set $v=1\n');
      ignores('tool/a.sh', '# export $v=1\n');
      ignores('tool/a.sh', 'echo "\$$v"\n');
      ignores('other.yml', '# env:\n#   $v: "1"\nname: x\n');
      ignores('other.yml', 'description: "set $v=1"\n');
      ignores('README.md', '\$env:$v = "1"\n');
    });

    test('flags a json key and a non-test dart mention with path:line', () {
      expect(findNoGamesSetters('.vscode/launch.json', '{\n  "$v": "1"\n}\n'), [
        '.vscode/launch.json:2: "$v": "1"',
      ]);
      expect(
        findNoGamesSetters(
          'tool/run.dart',
          "void f() {\n  run(environment: {'$v': '1'});\n}\n",
        ),
        ["tool/run.dart:2: run(environment: {'$v': '1'});"],
      );
      detects('lib/a.dart', 'const x = noGamesRunningVariable;\n');
      detects('integration_test/a.dart', 'final s = "$v";\n');
      detects('windows/runner/a.dart', "final s = '$v'; // set\n");
    });

    test('ignores dart comments outside test and dart under test', () {
      ignores('lib/a.dart', '// needs $v=1\n');
      ignores('lib/a.dart', '/// Reads [noGamesRunningVariable].\n');
      ignores('tool/a.dart', '  // $v\nvoid f() {}\n');
      ignores('test/a_test.dart', "final env = {'$v': '1'};\n");
      ignores('test/data/capture/support/g.dart', 'const n = "$v";\n');
      detects('lib/test/b.dart', "final env = {'$v': '1'};\n");
      ignores('other.json', '{"name": "x", "note": "$v"}\n');
      ignores('lib/a.dart', 'const y = notNoGamesRunningVariableAtAll;\n');
    });

    test('scans json and dart files', () {
      expect(isScannableKind('a/b.json'), isTrue);
      expect(isScannableKind('lib/a.dart'), isTrue);
      expect(isScannableKind('README.md'), isFalse);
    });
  });
}
