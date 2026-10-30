import 'package:flutter_test/flutter_test.dart';

import 'support/no_games_scan.dart';

/// Proves the no-games setter scanner on synthetic inputs, so the repository
/// scan in `workflow_test.dart` cannot pass because the scanner is blind.
void main() {
  group('the no-games scanner', () {
    const v = noGamesVariable;
    // Built so this file holds no process call of its own.
    const p = 'Process';
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

    test('ignores dart comments', () {
      ignores('lib/a.dart', '// needs $v=1\n');
      ignores('lib/a.dart', '/// Reads [noGamesRunningVariable].\n');
      ignores('tool/a.dart', '  // $v\nvoid f() {}\n');
      ignores('test/qualification/x_test.dart', '/// Needs `$v=1`.\n');
      detects('lib/test/b.dart', "final env = {'$v': '1'};\n");
      ignores('other.json', '{"name": "x", "note": "$v"}\n');
      ignores('lib/a.dart', 'const y = notNoGamesRunningVariableAtAll;\n');
    });

    test(
      'flags dart under test unless a named exemption starts no process',
      () {
        detects(
          'test/qualification/x_test.dart',
          "$p.run('a.exe', [], environment: {'$v': '1'});\n",
        );
        detects('test/data/capture/support/g.dart', 'const n = "$v";\n');
        detects(
          'test/a_test.dart',
          'final env = {noGamesRunningVariable: "1"};\n',
        );
        ignores(
          'test/data/capture/native_guard_test.dart',
          "const confirmed = {noGamesRunningVariable: '1'};\n",
        );
        ignores(
          'test/data/capture/support/native_guard.dart',
          "const noGamesRunningVariable = '$v';\n",
        );
        expect(
          findNoGamesSetters(
            'test/data/capture/native_guard_test.dart',
            "const c = {noGamesRunningVariable: '1'};\n"
                "$p.runSync('a.exe', [], environment: c);\n",
          ),
          [contains('starts a process')],
        );
      },
    );

    test('flags shell setters in yaml run and script blocks', () {
      detects('other.yml', 'steps:\n  - run: export $v=1\n');
      detects('other.yml', 'steps:\n  - run: |\n      \$env:$v = "1"\n');
      detects('ci.yaml', 'job:\n  script:\n    - set $v=1\n');
      ignores(
        'other.yml',
        'steps:\n  - run: if (\$env:$v -ne "1") { exit 1 }\n',
      );
      ignores('other.yml', 'steps:\n  - run: echo "needs $v"\n');
      expect(
        findNoGamesSetters('other.yml', 'a:\n  - run: export $v=1\n').single,
        startsWith('other.yml: `run` at root.a[0].run'),
      );
    });

    test('flags native, cmake, powershell module and python setters', () {
      detects('windows/a.cpp', '  _putenv("$v=1");\n');
      detects('windows/a.h', 'SetEnvironmentVariableW(L"$v", L"1");\n');
      detects('windows/CMakeLists.txt', 'set(ENV{$v} 1)\n');
      detects(
        'windows/a.cmake',
        'execute_process(COMMAND \${CMAKE_COMMAND} -E env $v=1 x)\n',
      );
      detects('tool/a.psm1', '\$env:$v = "1"\n');
      detects('tool/a.py', 'os.environ["$v"] = "1"\n');
      detects('tool/a.py', "run(cmd, env={'$v': '1'})\n");
      ignores('windows/a.cpp', 'GetEnvironmentVariableW(L"$v", buf, 8);\n');
      ignores('windows/a.cpp', '// _putenv("$v=1");\n');
      ignores('windows/CMakeLists.txt', '# set(ENV{$v} 1)\n');
      ignores('tool/a.py', '# os.environ["$v"] = "1"\n');
      ignores('tool/a.py', 'print(os.environ.get("$v"))\n');
    });

    test('scans every file kind that can set the variable', () {
      for (final path in [
        'a/b.json',
        'lib/a.dart',
        'windows/a.cpp',
        'windows/a.cc',
        'windows/a.c',
        'windows/a.h',
        'windows/a.hpp',
        'windows/CMakeLists.txt',
        'windows/a.cmake',
        'tool/a.psm1',
        'tool/a.psd1',
        'tool/a.py',
      ]) {
        expect(isScannableKind(path), isTrue, reason: path);
      }
      expect(isScannableKind('README.md'), isFalse);
    });
  });
}
