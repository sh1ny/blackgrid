/// Release notes carried by an OpenSpec proposal.
///
/// Ports specwright's `release.sh notes --proposal` section parser and its
/// `## Why` first-sentence extractor, so that this repository's release
/// tooling and specwright decide the same proposals the same way.
library;

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
