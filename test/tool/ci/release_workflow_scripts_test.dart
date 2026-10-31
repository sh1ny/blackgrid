@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'support/no_games_scan.dart' show toPlain;
import 'support/release_script_harness.dart';

/// Runs the `run:` scripts of `.github/workflows/release.yml` under `bash`
/// with a fake `gh` (answers from the test, records every call) and the real
/// `jq` and `sha256sum`. Nothing here reaches the GitHub API.
void main() {
  const repo = testRepository;
  const tag = 'v0.6.0';
  const tagObject = 'a1b2c3';
  const preflightJob = 'preflight';
  const preflightStep = 'Check the tag and the release';
  const verifyStep = 'Verify the release package';
  const createStep = 'Create and publish the release';
  const refEndpoint = 'repos/$repo/git/ref/tags/$tag';
  const listEndpoint = 'repos/$repo/releases';
  const uploads = 'https://uploads.github.com/repos/$repo/releases/42/assets';

  late ReleaseScriptHarness h;

  var ready = false;
  setUp(() {
    h = ReleaseScriptHarness.create();
    ready = true;
  });
  tearDown(() {
    if (ready) h.dispose();
    ready = false;
  });

  String ref(String type, [String sha = tagObject]) => jsonEncode({
    'ref': 'refs/tags/$tag',
    'object': {'type': type, 'sha': sha},
  });

  String page(List<Map<String, Object?>> releases) => jsonEncode(releases);

  Map<String, Object?> release(
    int id, {
    String forTag = tag,
    bool draft = false,
  }) => {'id': id, 'tag_name': forTag, 'draft': draft};

  Map<String, String> pushed() => {
    'github.event_name': 'push',
    'github.ref': 'refs/tags/$tag',
    'github.ref_name': tag,
    'inputs.tag': '',
    'github.token': 'test-token',
  };

  Map<String, String> dispatched({String ref = 'refs/heads/main'}) => {
    'github.event_name': 'workflow_dispatch',
    'github.ref': ref,
    'github.ref_name': ref.split('/').last,
    'inputs.tag': tag,
    'github.token': 'test-token',
  };

  void routePreflight({
    String type = 'tag',
    List<String> releases = const ['[]'],
  }) {
    h.route('GET', refEndpoint, [GhReply(ref(type))]);
    h.route('GET', listEndpoint, [for (final r in releases) GhReply(r)]);
  }

  ScriptRun preflight(Map<String, String> expressions) =>
      h.run(preflightJob, [preflightStep], expressions: expressions);

  group('preflight', () {
    test('resolves the dispatch tag input like a pushed tag', () {
      routePreflight();
      final push = preflight(pushed());
      routePreflight();
      final manual = preflight(dispatched());
      expect(push.exitCode, 0, reason: push.log);
      expect(manual.exitCode, 0, reason: manual.log);
      expect(manual.outputs, push.outputs);
      expect(push.outputs, {'tag': tag, 'tag_object': tagObject});
      expect(manual.lines, push.lines);
      expect(push.lines, ['GET $refEndpoint', 'GET $listEndpoint']);
    });

    test('refuses a tag missing on origin, naming it', () {
      h.route('GET', refEndpoint, [const GhReply.fail()]);
      final result = preflight(pushed());
      expect(result.exitCode, isNot(0));
      expect(result.log, contains(tag));
      expect(result.log, contains('does not exist on origin'));
      expect(result.lines, ['GET $refEndpoint']);
    });

    test('refuses a manual run whose ref is not main', () {
      routePreflight();
      final result = preflight(dispatched(ref: 'refs/heads/feature'));
      expect(result.exitCode, isNot(0));
      expect(result.log, contains('a manual run must start from main'));
      expect(result.calls, isEmpty, reason: 'refused before any API call');
    });

    test('refuses a name that is not a version tag before any API call', () {
      final result = preflight({...pushed(), 'github.ref_name': 'nightly'});
      expect(result.exitCode, isNot(0));
      expect(result.log, contains('nightly'));
      expect(result.calls, isEmpty);
    });

    test('refuses a lightweight tag', () {
      routePreflight(type: 'commit');
      final result = preflight(pushed());
      expect(result.exitCode, isNot(0));
      expect(result.log, contains('$tag is not annotated'));
      expect(result.outputs, isEmpty);
    });

    test('refuses a published release for the tag', () {
      routePreflight(
        releases: [
          page([release(7)]),
        ],
      );
      final result = preflight(pushed());
      expect(result.exitCode, isNot(0));
      expect(result.log, contains('published release 7 for $tag'));
      expect(result.outputs, isEmpty);
    });

    test('refuses a draft for the tag, naming it', () {
      // The match is on the second of two pages that gh prints back to back.
      routePreflight(
        releases: [
          '${page([release(5, forTag: 'v0.5.0')])}\n'
              '${page([release(8, draft: true)])}',
        ],
      );
      final result = preflight(pushed());
      expect(result.exitCode, isNot(0));
      expect(result.log, contains('draft release 8 for $tag'));
      expect(result.log, isNot(contains('release 5')));
    });

    test('lets a tag that only other releases mention through', () {
      routePreflight(
        releases: [
          page([release(5, forTag: 'v0.5.0'), release(6, forTag: 'v0.60.0')]),
        ],
      );
      final result = preflight(pushed());
      expect(result.exitCode, 0, reason: result.log);
    });
  });

  group('the tooling guard', () {
    Map<String, dynamic> guard() {
      final gates = (toPlain(
        loadYaml(File('.github/workflows/gates.yml').readAsStringSync()),
      ) as Map).cast<String, dynamic>();
      final steps = ((gates['jobs'] as Map)['gates'] as Map)['steps'] as List;
      return (steps.singleWhere(
        (s) =>
            (s as Map)['name'] == 'Refuse a tag from before release publishing',
      ) as Map).cast<String, dynamic>();
    }

    ProcessResult runGuard(String miseToml) {
      final probe = Process.runSync('pwsh', ['-NoProfile', '-Command', '1']);
      expect(probe.exitCode, 0, reason: 'the guard step needs pwsh on PATH');
      final dir = Directory('${h.root.path}/tree')..createSync();
      File('${dir.path}/mise.toml').writeAsStringSync(miseToml);
      final script = File('${h.root.path}/guard.ps1')
        ..writeAsStringSync('${guard()['run']}');
      return Process.runSync(
        'pwsh',
        ['-NoProfile', '-File', script.path],
        workingDirectory: dir.path,
        environment: {'RELEASE_TAG': 'v0.5.0'},
      );
    }

    test('the tooling guard refuses a tree without release:verify-tag', () {
      final result = runGuard(
        '[tasks."package:release"]\nrun = "x"\n[tasks.analyze]\nrun = "y"\n',
      );
      expect(result.exitCode, isNot(0));
      expect('${result.stderr}${result.stdout}', contains('v0.5.0 predates'));
    });

    test('the tooling guard lets a tree with both tasks through', () {
      final result = runGuard(
        '[tasks."release:verify-tag"]\nrun = "x"\n'
        '[tasks."package:release"]\nrun = "y"\n',
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });
  });

  group('publish', () {
    late PackageFixture pkg;

    Map<String, String> expressions({String? sums, String? object}) => {
      'needs.preflight.outputs.tag': tag,
      'needs.preflight.outputs.tag_object': object ?? tagObject,
      'needs.gates.outputs.sums_sha256': sums ?? pkg.sumsDigest,
      'github.token': 'test-token',
    };

    /// Routes a healthy publish; each override breaks one call.
    void routePublish({
      List<String>? listings,
      String? tagRef,
      GhReply? create,
      Map<String, GhReply> uploadReplies = const {},
      String? current,
    }) {
      h.route('GET', listEndpoint, [GhReply(listings?.first ?? '[]')]);
      h.route('GET', refEndpoint, [GhReply(tagRef ?? ref('tag'))]);
      h.route('POST', listEndpoint, [
        create ??
            GhReply(
              jsonEncode({'id': 42, 'upload_url': '$uploads{?name,label}'}),
            ),
      ]);
      for (final name in [pkg.zipName, pkg.setupName, 'SHA256SUMS.txt']) {
        h.route('POST', '$uploads?name=$name', [
          uploadReplies[name] ?? const GhReply('{}'),
        ]);
      }
      h.route('GET', 'repos/$repo/releases/42', [
        GhReply(
          current ??
              jsonEncode({
                'id': 42,
                'assets': [
                  for (final n in [
                    pkg.zipName,
                    pkg.setupName,
                    'SHA256SUMS.txt',
                  ])
                    {'name': n, 'state': 'uploaded'},
                ],
              }),
        ),
      ]);
      h.route('PATCH', 'repos/$repo/releases/42', [const GhReply('{}')]);
    }

    ScriptRun publish({String? sums, String? object}) => h.run('publish', [
      verifyStep,
      createStep,
    ], expressions: expressions(sums: sums, object: object));

    List<GhCall> posts(ScriptRun r) => [
      for (final c in r.calls)
        if (c.method == 'POST') c,
    ];

    setUp(() => pkg = PackageFixture.write(h.work));

    test(
      'publish uploads exactly the zip, setup and sums to the created id',
      () {
        routePublish();
        final result = publish();
        expect(result.exitCode, 0, reason: result.log);
        expect(result.lines, [
          'GET $listEndpoint',
          'GET $refEndpoint',
          'POST $listEndpoint',
          'POST $uploads?name=${pkg.zipName}',
          'POST $uploads?name=${pkg.setupName}',
          'POST $uploads?name=SHA256SUMS.txt',
          'GET repos/$repo/releases/42',
          'PATCH repos/$repo/releases/42',
        ]);
        final created = result.calls[2].json!;
        expect(created, {
          'tag_name': tag,
          'name': tag,
          'body': '## Notes\n\n- a change\n',
          'draft': true,
          'prerelease': false,
        });
        for (final call in result.calls.sublist(3, 6)) {
          final name = call.endpoint.split('name=').last;
          expect(
            call.payload,
            pkg.file('release/$name').readAsBytesSync(),
            reason: name,
          );
        }
        expect(result.calls.last.json, {'draft': false, 'make_latest': 'true'});
      },
    );

    test('release.json prerelease and latest pass through to the POST and the '
        'PATCH', () {
      for (final (prerelease, latest) in [(true, false), (false, false)]) {
        h.dispose();
        h = ReleaseScriptHarness.create();
        pkg = PackageFixture.write(
          h.work,
          prerelease: prerelease,
          latest: latest,
        );
        routePublish();
        final result = publish();
        expect(result.exitCode, 0, reason: result.log);
        expect(result.calls[2].json!['prerelease'], prerelease);
        expect(result.calls.last.json, {
          'draft': false,
          'make_latest': 'false',
        });
      }
    });

    test('publish refuses a file that fails sha256sum before any POST', () {
      routePublish();
      pkg.file('release/${pkg.zipName}').writeAsStringSync('tampered');
      final result = publish();
      expect(result.exitCode, isNot(0));
      expect(result.log, contains(pkg.zipName));
      expect(result.calls, isEmpty);
    });

    test('publish refuses sums that differ from the gates digest output', () {
      routePublish();
      // The whole set is replaced consistently, so only the digest gives it
      // away.
      pkg.file('release/${pkg.zipName}').writeAsStringSync('other zip');
      pkg
          .file('release/SHA256SUMS.txt')
          .writeAsStringSync(
            '${_sha('other zip')}  ${pkg.zipName}\n'
            '${_sha('setup bytes')}  ${pkg.setupName}\n',
          );
      final result = publish(sums: _sha('the checksum file of the gates'));
      expect(result.exitCode, isNot(0));
      expect(result.log, contains('SHA256SUMS.txt'));
      expect(result.calls, isEmpty);
    });

    test('publish refuses a missing or extra file before any POST', () {
      routePublish();
      pkg.file('release/${pkg.setupName}').deleteSync();
      final missing = publish();
      expect(missing.exitCode, isNot(0));
      expect(missing.log, contains('missing file release/${pkg.setupName}'));
      expect(missing.calls, isEmpty);

      h.dispose();
      h = ReleaseScriptHarness.create();
      pkg = PackageFixture.write(h.work);
      routePublish();
      pkg.file('release/extra.txt').writeAsStringSync('x');
      final extra = publish();
      expect(extra.exitCode, isNot(0));
      expect(extra.log, contains('unexpected file release/extra.txt'));
      expect(extra.calls, isEmpty);
    });

    test(
      'publish refuses a draft listed just before the POST and makes none',
      () {
        routePublish(
          listings: [
            page([release(9, draft: true)]),
          ],
        );
        final result = publish();
        expect(result.exitCode, isNot(0));
        expect(result.log, contains('draft release 9 for $tag'));
        expect(posts(result), isEmpty);
        expect(result.lines, ['GET $listEndpoint']);
      },
    );

    test('publish refuses a published release listed just before the POST', () {
      routePublish(
        listings: [
          page([release(9)]),
        ],
      );
      final result = publish();
      expect(result.exitCode, isNot(0));
      expect(result.log, contains('published release 9 for $tag'));
      expect(posts(result), isEmpty);
    });

    test(
      'publish refuses a tag that moved or vanished since the preflight',
      () {
        routePublish(tagRef: ref('tag', 'ffffff'));
        final moved = publish();
        expect(moved.exitCode, isNot(0));
        expect(moved.log, contains('$tag moved'));
        expect(posts(moved), isEmpty);

        h.dispose();
        h = ReleaseScriptHarness.create();
        pkg = PackageFixture.write(h.work);
        routePublish();
        h.route('GET', refEndpoint, [const GhReply.fail()]);
        final gone = publish();
        expect(gone.exitCode, isNot(0));
        expect(gone.log, contains('$tag no longer exists'));
        expect(posts(gone), isEmpty);
      },
    );

    test('a failed upload exits non-zero and never sends draft false', () {
      routePublish(
        uploadReplies: {
          pkg.setupName: const GhReply.fail('{"message":"boom"}'),
        },
      );
      final result = publish();
      expect(result.exitCode, isNot(0));
      expect(result.log, contains('draft release 42 is left in place'));
      expect(
        result.calls.where((c) => c.method == 'PATCH'),
        isEmpty,
        reason: 'the draft must stay a draft',
      );
      expect(
        result.lines,
        isNot(contains('POST $uploads?name=SHA256SUMS.txt')),
        reason: 'no upload after the failed one',
      );
    });

    test(
      'publish patches draft false by id only after three uploaded assets',
      () {
        routePublish(
          current: jsonEncode({
            'id': 42,
            'assets': [
              {'name': pkg.zipName, 'state': 'uploaded'},
              {'name': pkg.setupName, 'state': 'starter'},
              {'name': 'SHA256SUMS.txt', 'state': 'uploaded'},
            ],
          }),
        );
        final partial = publish();
        expect(partial.exitCode, isNot(0));
        expect(partial.log, contains(pkg.setupName));
        expect(partial.calls.where((c) => c.method == 'PATCH'), isEmpty);

        h.dispose();
        h = ReleaseScriptHarness.create();
        pkg = PackageFixture.write(h.work);
        routePublish(
          current: jsonEncode({
            'id': 42,
            'assets': [
              {'name': pkg.zipName, 'state': 'uploaded'},
              {'name': pkg.setupName, 'state': 'uploaded'},
              {'name': 'SHA256SUMS.txt', 'state': 'uploaded'},
              {'name': 'stray.bin', 'state': 'uploaded'},
            ],
          }),
        );
        final extra = publish();
        expect(extra.exitCode, isNot(0), reason: 'exactly three assets');
        expect(extra.calls.where((c) => c.method == 'PATCH'), isEmpty);

        h.dispose();
        h = ReleaseScriptHarness.create();
        pkg = PackageFixture.write(h.work);
        routePublish();
        final whole = publish();
        expect(whole.exitCode, 0, reason: whole.log);
        final names = whole.lines;
        expect(
          names.indexOf('PATCH repos/$repo/releases/42'),
          greaterThan(names.indexOf('GET repos/$repo/releases/42')),
        );
        // Every call after the create addresses the release by id.
        for (final call in whole.calls.skip(3)) {
          expect(
            call.endpoint,
            anyOf(contains('/releases/42'), contains(uploads)),
          );
        }
      },
    );
  });
}

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();
