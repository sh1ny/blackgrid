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
  });
}
