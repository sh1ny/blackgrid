/// Release notes carried by an OpenSpec proposal.
///
/// Ports specwright's `release.sh notes --proposal` section parser and its
/// `## Why` first-sentence extractor, so that this repository's release
/// tooling and specwright decide the same proposals the same way.
library;

import 'dart:io';

import 'git.dart';
import 'semver.dart';

/// Longest summary, in characters, after whitespace collapses.
const int maxSummary = 600;

/// Longest list item, in characters, after whitespace collapses.
const int maxItem = 500;

/// Longest `## Why` sentence; a longer one is cut to 299 characters plus `…`.
const int maxWhy = 300;

/// The headings a section may hold, in their lowercase form.
const List<String> noteHeadings = ['added', 'changed', 'fixed', 'removed'];

final RegExp _whyHead = RegExp(
  r'^#{2}[ \t]+Why[ \t]*$',
  caseSensitive: false,
  multiLine: true,
);
final RegExp _abbrev = RegExp(
  r'(?:^|[\s(])(?:e\.g|i\.e|vs|cf)$',
  caseSensitive: false,
);
final RegExp _listMarker = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+');
final RegExp _notesHead = RegExp(
  r'^##[ \t]+Release Notes[ \t]*$',
  caseSensitive: false,
);
final RegExp _subHead = RegExp(r'^###(?!#)[ \t]*(.*?)[ \t]*$');
final RegExp _itemStart = RegExp(r'^[-*+][ \t]+(.*)$');
final RegExp _codeSpan = RegExp(
  r'(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)',
  dotAll: true,
);
final RegExp _reference = RegExp(r'#\d+(?!\w)');
final RegExp _comment = RegExp(r'<!--.*?-->', dotAll: true);
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _endsSpace = RegExp(r'\s');

String _collapse(String text) => text.replaceAll(_whitespace, ' ').trim();

/// One list item of a release notes section.
class ReleaseNoteItem {
  /// Creates an item with its collapsed [text] from the 1-based file [line].
  const ReleaseNoteItem(this.text, this.line);

  /// The item text, continuation lines joined by one space.
  final String text;

  /// The 1-based line of the file where the item starts.
  final int line;

  @override
  String toString() => 'ReleaseNoteItem($line: $text)';
}

/// One problem found in a release notes section.
class ReleaseNotesError {
  /// Creates an error at the 1-based file [line].
  const ReleaseNotesError(this.line, this.message);

  /// The 1-based line of the file the problem is on.
  final int line;

  /// What is wrong, in a form fit to show a person.
  final String message;

  @override
  String toString() => 'line $line: $message';
}

/// The outcome of [parseReleaseNotes].
sealed class ReleaseNotesResult {
  const ReleaseNotesResult();
}

/// A valid `## Release Notes` section.
final class ReleaseNotes extends ReleaseNotesResult {
  /// Creates a valid section with its [summary] and [items] per heading.
  const ReleaseNotes(this.summary, this.items);

  /// The summary: the text before the first `###` heading, collapsed.
  final String summary;

  /// The items per lowercase heading (`added`, `changed`, `fixed`, `removed`),
  /// in file order. Only headings that hold items appear.
  final Map<String, List<ReleaseNoteItem>> items;

  @override
  String toString() => 'ReleaseNotes($summary, $items)';
}

/// A `## Release Notes` section that breaks the format.
final class ReleaseNotesInvalid extends ReleaseNotesResult {
  /// Creates an invalid outcome carrying every [errors] found.
  const ReleaseNotesInvalid(this.errors);

  /// The problems, sorted by line.
  final List<ReleaseNotesError> errors;

  @override
  String toString() => 'ReleaseNotesInvalid(${errors.join('; ')})';
}

/// A proposal without a `## Release Notes` heading.
final class NoReleaseNotes extends ReleaseNotesResult {
  /// Creates the outcome.
  const NoReleaseNotes();

  /// The refusal to show a person.
  String get message =>
      "the proposal has no release notes (no '## Release "
      "Notes' section)";

  @override
  String toString() => 'NoReleaseNotes()';
}

/// Parses the `## Release Notes` section of [proposal].
///
/// HTML comments go first, with their newlines kept so that reported lines
/// stay the file's. The section runs to the next `## ` heading or the end. The
/// summary is the text before the first `###`, at most [maxSummary]
/// characters. The headings are Added, Changed, Fixed and Removed (any case),
/// each at most once, followed only by items: a line starting `-`, `*` or `+`
/// and a space, joined with the indented lines after it, at most [maxItem]
/// characters. Every error is collected with its line.
ReleaseNotesResult parseReleaseNotes(String proposal) {
  final text = proposal.replaceAllMapped(
    _comment,
    (m) => '\n' * '\n'.allMatches(m[0]!).length,
  );
  final lines = [
    for (final l in text.split('\n'))
      l.endsWith('\r') ? l.substring(0, l.length - 1) : l,
  ];
  final start = lines.indexWhere(_notesHead.hasMatch);
  if (start < 0) return const NoReleaseNotes();
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].startsWith('##') && !lines[i].startsWith('###')) {
      end = i;
      break;
    }
  }

  final errors = <ReleaseNotesError>[];
  final items = <String, List<ReleaseNoteItem>>{};
  final summary = <String>[];
  final seen = <String>{};
  String? cur; // The heading being read; null under an invalid one.
  List<String>? itemParts; // The open item's lines.
  var itemLine = 0;

  void close() {
    final parts = itemParts;
    final heading = cur;
    itemParts = null;
    if (parts == null || heading == null) return;
    final t = _collapse(parts.join(' '));
    if (t.isEmpty) {
      errors.add(ReleaseNotesError(itemLine, 'empty list item'));
    } else if (t.length > maxItem) {
      errors.add(
        ReleaseNotesError(
          itemLine,
          'item is ${t.length} characters, over the $maxItem limit',
        ),
      );
    } else {
      items[heading]!.add(ReleaseNoteItem(t, itemLine));
    }
  }

  for (var i = start + 1; i < end; i++) {
    final line = lines[i];
    final n = i + 1;
    final h = _subHead.firstMatch(line);
    if (h != null) {
      close();
      final name = h[1]!;
      final key = name.toLowerCase();
      if (!noteHeadings.contains(key)) {
        errors.add(
          ReleaseNotesError(
            n,
            "unknown heading '$name' (use Added, Changed, Fixed or Removed)",
          ),
        );
        cur = null;
      } else if (seen.contains(key)) {
        errors.add(ReleaseNotesError(n, "heading '$name' appears twice"));
        cur = null;
      } else {
        cur = key;
        items[key] = [];
      }
      seen.add(key);
      continue;
    }
    if (line.trim().isEmpty) continue;
    if (seen.isEmpty) {
      summary.add(line.trim());
      continue;
    }
    if (cur == null) continue; // That heading's error covers its lines.
    final m = _itemStart.firstMatch(line);
    if (m != null) {
      close();
      itemParts = [m[1]!];
      itemLine = n;
    } else if ((line.startsWith(' ') || line.startsWith('\t')) &&
        itemParts != null) {
      itemParts!.add(line.trim());
    } else {
      close();
      final shown = line.trim();
      errors.add(
        ReleaseNotesError(
          n,
          'line is neither a list item nor an indented continuation: '
          '${shown.length > 60 ? shown.substring(0, 60) : shown}',
        ),
      );
    }
  }
  close();

  final bodyErrors = errors.length;
  final summaryText = _collapse(summary.join(' '));
  if (summaryText.isEmpty) {
    errors.add(
      ReleaseNotesError(
        start + 1,
        'the summary is missing (text before the first ### heading)',
      ),
    );
  } else if (summaryText.length > maxSummary) {
    errors.add(
      ReleaseNotesError(
        start + 1,
        'summary is ${summaryText.length} characters, '
        'over the $maxSummary limit',
      ),
    );
  }
  if (items.values.every((v) => v.isEmpty) && bodyErrors == 0) {
    errors.add(
      ReleaseNotesError(
        start + 1,
        'no list item under Added, Changed, Fixed or Removed',
      ),
    );
  }
  if (errors.isNotEmpty) {
    // A stable sort by line: equal lines keep the order they were found in.
    final order = List.generate(errors.length, (i) => i)
      ..sort((a, b) {
        final c = errors[a].line.compareTo(errors[b].line);
        return c != 0 ? c : a.compareTo(b);
      });
    return ReleaseNotesInvalid([for (final i in order) errors[i]]);
  }
  return ReleaseNotes(summaryText, {
    for (final e in items.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  });
}

/// The first sentence of the first paragraph under `## Why`, or `null`.
///
/// The paragraph runs from the first non-blank line after the heading to a
/// blank line, a heading, or (after a list item's first line) the next list
/// marker. A leading list marker (`-`, `*`, `+`, `1.`) is dropped and
/// whitespace collapses to single spaces. The sentence ends at the first `.`,
/// `!` or `?` that is followed by whitespace or the end, is outside a backtick
/// code span, and does not close `e.g`, `i.e`, `vs` or `cf`; with no end the
/// whole paragraph is the sentence. Over [maxWhy] characters it is cut to 299
/// plus an ellipsis.
String? firstWhySentence(String proposal) {
  final head = _whyHead.firstMatch(proposal);
  if (head == null) return null;
  final para = <String>[];
  for (var line in proposal.substring(head.end).split(RegExp(r'\r\n|\r|\n'))) {
    if (line.trim().isEmpty) {
      if (para.isNotEmpty) break;
      continue;
    }
    if (line.trimLeft().startsWith('#')) break;
    if (para.isEmpty) {
      line = line.replaceFirst(_listMarker, '');
    } else if (_listMarker.hasMatch(line)) {
      break;
    }
    para.add(line.trim());
  }
  final text = _collapse(para.join(' '));
  if (text.isEmpty) return null;

  var end = text.length;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (ch == '`') {
      var j = i;
      while (j < text.length && text[j] == '`') {
        j++;
      }
      final close = text.indexOf(text.substring(i, j), j);
      i = close >= 0 ? close + (j - i) : j;
      continue;
    }
    if ((ch == '.' || ch == '!' || ch == '?') &&
        (i + 1 == text.length || _endsSpace.hasMatch(text[i + 1])) &&
        !(ch == '.' && _abbrev.hasMatch(text.substring(0, i)))) {
      end = i + 1;
      break;
    }
    i++;
  }
  final sentence = text.substring(0, end);
  return sentence.length <= maxWhy
      ? sentence
      : '${sentence.substring(0, maxWhy - 1)}…';
}

/// Whether [item] names an issue or PR (`#<n>`) outside a backtick code span.
///
/// An item that does gets no `(#<pr>)` appended when notes are rendered.
bool namesReference(String item) =>
    _reference.hasMatch(item.replaceAll(_codeSpan, ' '));

/// Longest proposal, in bytes, that is read; a larger one is listed by name.
const int maxProposalBytes = 64 * 1024;

/// Most changes one release range may hold before the release is refused.
const int maxRangeChanges = 1000;

/// Most items listed in the grouped blocks of the notes.
const int maxListedItems = 150;

/// Most changes listed with their detail in the `Changes:` block.
const int maxListedChanges = 100;

/// One change archived in a release range.
class RangeChange {
  /// Creates a change.
  ///
  /// [notes] is `null` when the proposal was over [maxProposalBytes] or,
  /// with [missing], no longer exists at `HEAD`, and so was not read; [why]
  /// is then `null` too.
  const RangeChange({
    required this.name,
    required this.pr,
    required this.sha,
    required this.notes,
    required this.why,
    this.missing = false,
  });

  /// The change name: its archive directory minus the date prefix.
  final String name;

  /// The PR number read from the subject of the adding commit, or `null`.
  final int? pr;

  /// The commit on main's first-parent line that added the archived proposal.
  final String sha;

  /// What [parseReleaseNotes] made of the proposal; `null` when oversized.
  final ReleaseNotesResult? notes;

  /// The first sentence of the proposal's `## Why`, or `null`.
  final String? why;

  /// Whether the archived proposal no longer exists at `HEAD`: its change was
  /// reverted, or its archive directory was moved, after it was added.
  final bool missing;

  /// Why the change has no valid section, or `null` when it has one.
  String? get problem => switch (notes) {
    ReleaseNotes() => null,
    ReleaseNotesInvalid(:final errors) => errors.first.toString(),
    NoReleaseNotes() => 'no release notes',
    null when missing =>
      'the archived proposal is no longer at HEAD (reverted or moved)',
    null => 'proposal is over the ${maxProposalBytes ~/ 1024} KB limit',
  };
}

/// The changes archived since the last final release tag.
class ReleaseRange {
  /// Creates the range.
  const ReleaseRange(this.lastFinalTag, this.changes);

  /// The latest final release tag reachable from `HEAD`, or `null`.
  final String? lastFinalTag;

  /// The changes, oldest first on the first-parent line.
  final List<RangeChange> changes;

  /// The commits that added at least one archived proposal.
  Set<String> get proposalShas => {for (final c in changes) c.sha};
}

/// The rendered body of a release section and the warnings found on the way.
typedef RenderedNotes = ({String body, List<String> warnings});

final RegExp _trailingPr = RegExp(r'\(#(\d+)\)\s*$');
final RegExp _mergePr = RegExp(r'^Merge pull request #(\d+)');
final RegExp _datePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}-');
const String _field = '\x01';

int? _prOf(String subject) {
  final m = _trailingPr.firstMatch(subject) ?? _mergePr.firstMatch(subject);
  return m == null ? null : int.parse(m[1]!);
}

/// Reads the changes archived on main's first-parent line since the last final
/// tag reachable from `HEAD` (all of history when there is none), oldest first.
///
/// A change is an archived `proposal.md` added by a first-parent commit; its PR
/// is the trailing `(#<n>)` of that commit's subject or the number of a
/// `Merge pull request #<n>` subject. A proposal over [maxProposalBytes] is
/// not read, and neither is one that no longer exists at `HEAD`; both stay
/// listed, without a section, so one bad archive never blocks a release. A
/// path added more than once (reverted, then archived again) is one change
/// with its last PR, and a missing proposal is dropped when a change of the
/// same name is still at `HEAD` (a renamed archive directory). Throws
/// [ReleaseException] above [maxRangeChanges] changes, naming the count.
Future<ReleaseRange> readReleaseRange(Git git) async {
  final tags = await git.output(['tag', '--merged', 'HEAD']);
  SemVer? latest;
  String? lastFinal;
  for (final raw in tags.split('\n')) {
    final name = raw.trim();
    if (!releaseTagPattern.hasMatch(name)) continue;
    final v = SemVer.tryParse(name.substring(1));
    if (v == null || v.preRelease.isNotEmpty) continue;
    if (latest == null || v.compareTo(latest) > 0) {
      latest = v;
      lastFinal = name;
    }
  }

  final log = await git.output([
    '-c',
    'core.quotepath=false',
    'log',
    '--first-parent',
    '--diff-merges=first-parent',
    '--no-renames',
    '--diff-filter=A',
    '--name-only',
    '--reverse',
    '--format=$_field%H$_field%s',
    ?(lastFinal == null ? null : '$lastFinal..HEAD'),
    '--',
    ':(glob)openspec/changes/archive/*/proposal.md',
  ]);
  final found = <(String sha, int? pr, String path)>[];
  String? sha;
  int? pr;
  for (final line in log.split('\n')) {
    if (line.startsWith(_field)) {
      final parts = line.split(_field);
      sha = parts[1];
      pr = _prOf(parts.sublist(2).join(_field).trim());
    } else if (line.trim().isNotEmpty && sha != null) {
      found.add((sha, pr, line.trim()));
    }
  }
  if (found.length > maxRangeChanges) {
    throw ReleaseException(
      '${found.length} changes were archived since '
      '${lastFinal ?? 'the first commit'}; at most $maxRangeChanges are '
      'supported.',
    );
  }

  // A path added again after a revert is one change: keep its last add, the
  // introduction that survives at HEAD, so its items are listed once.
  final lastAdd = {for (final (i, (_, _, path)) in found.indexed) path: i};
  final changes = <RangeChange>[];
  for (final (i, (sha, pr, path)) in found.indexed) {
    if (lastAdd[path] != i) continue;
    final name = path.split('/')[3].replaceFirst(_datePrefix, '');
    final exists = await git.run(['cat-file', '-e', 'HEAD:$path']);
    if (exists.exitCode != 0) {
      changes.add(
        RangeChange(
          name: name,
          pr: pr,
          sha: sha,
          notes: null,
          why: null,
          missing: true,
        ),
      );
      continue;
    }
    final size = int.tryParse(
      await git.output(['cat-file', '-s', 'HEAD:$path']),
    );
    if (size == null || size > maxProposalBytes) {
      changes.add(
        RangeChange(name: name, pr: pr, sha: sha, notes: null, why: null),
      );
      continue;
    }
    final text = await git.output(['show', 'HEAD:$path']);
    changes.add(
      RangeChange(
        name: name,
        pr: pr,
        sha: sha,
        notes: parseReleaseNotes(text),
        why: firstWhySentence(text),
      ),
    );
  }
  // An archive directory renamed in the range leaves its old path missing at
  // HEAD while the new path lists the same change; drop the missing copy.
  final present = {
    for (final c in changes)
      if (!c.missing) c.name,
  };
  return ReleaseRange(lastFinal, [
    for (final c in changes)
      if (!c.missing || !present.contains(c.name)) c,
  ]);
}

String _itemLine(String text, int? pr) =>
    pr != null && !namesReference(text) ? '- $text (#$pr)' : '- $text';

List<String> _changeLines(List<RangeChange> changes) {
  final detailed = changes.length <= maxListedChanges;
  return [
    for (final c in changes.take(maxListedChanges))
      if (detailed)
        '- ${c.name}${c.pr == null ? '' : ' (#${c.pr})'}'
            '${(c.why ?? '').isEmpty ? '' : ': ${c.why}'}'
      else
        '- ${c.name}',
    if (!detailed) '…and ${changes.length - maxListedChanges} more',
  ];
}

/// Renders the notes body for [changes] under [summary].
///
/// The blocks are joined by one blank line: the summary; `Added:`, `Changed:`,
/// `Fixed:` and `Removed:` (empty groups omitted) with the items of every
/// valid section in change order, at most [maxListedItems] items and then
/// `…and <n> more items`; then `Changes:` for the changes without a valid
/// section. With no valid section at all the body is the summary and
/// `Changes:`. An item that names no `#<n>` gets ` (#<pr>)` of its change.
/// Each change without a valid section adds a warning naming it and its first
/// problem. The `## v<version> - <date>` heading is not part of the body.
///
/// Throws [ArgumentError] when [changes] is empty.
RenderedNotes renderReleaseNotes(String summary, List<RangeChange> changes) {
  if (changes.isEmpty) {
    throw ArgumentError.value(changes, 'changes', 'must not be empty');
  }
  final warnings = <String>[];
  final plain = <RangeChange>[];
  final byHeading = {for (final h in noteHeadings) h: <String>[]};
  for (final c in changes) {
    if (c.notes case ReleaseNotes(:final items)) {
      for (final h in noteHeadings) {
        for (final item in items[h] ?? const <ReleaseNoteItem>[]) {
          byHeading[h]!.add(_itemLine(item.text, c.pr));
        }
      }
    } else {
      plain.add(c);
      warnings.add('${c.name}: ${c.problem}');
    }
  }

  final blocks = [summary];
  var remaining = maxListedItems;
  var total = 0;
  for (final h in noteHeadings) {
    final lines = byHeading[h]!;
    total += lines.length;
    final shown = lines.take(remaining).toList();
    remaining -= shown.length;
    if (shown.isNotEmpty) {
      blocks.add(
        ['${h[0].toUpperCase()}${h.substring(1)}:', ...shown].join('\n'),
      );
    }
  }
  if (total > maxListedItems) {
    blocks[blocks.length - 1] += '\n…and ${total - maxListedItems} more items';
  }
  if (plain.isNotEmpty) {
    blocks.add(['Changes:', ..._changeLines(plain)].join('\n'));
  }
  return (body: blocks.join('\n\n'), warnings: warnings);
}

/// Checks every in-flight proposal under [changesDir] offline.
///
/// An in-flight proposal is `<changesDir>/<name>/proposal.md` for each
/// directory except `archive`. Returns one `(path, problem)` per proposal
/// without a valid `## Release Notes` section; the problem is its first error
/// as `line <n>: <message>`, or the missing-section message. An empty list
/// means every in-flight proposal is valid.
List<(String path, String problem)> checkInFlightProposals(
  Directory changesDir,
) {
  final problems = <(String, String)>[];
  final dirs = changesDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final dir in dirs) {
    final name = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name == 'archive') continue;
    final file = File('${dir.path}${Platform.pathSeparator}proposal.md');
    if (!file.existsSync()) continue;
    switch (parseReleaseNotes(file.readAsStringSync())) {
      case ReleaseNotes():
        break;
      case ReleaseNotesInvalid(:final errors):
        problems.add((file.path, errors.first.toString()));
      case final NoReleaseNotes none:
        problems.add((file.path, none.message));
    }
  }
  return problems;
}
