import 'dart:io';

/// Why writing [output] (and its `<output>.tmp` sibling) would be unsafe, or
/// null when it is safe.
///
/// Unsafe when the output, its temp sibling, or any existing ancestor is a
/// symbolic link or junction, or when the output canonically equals one of
/// [protectedFiles] or lies inside one of [protectedDirectories]. Paths are
/// compared after resolving links, case-insensitively on Windows.
String? unsafeOutputReason(
  String output, {
  Iterable<String> protectedFiles = const [],
  Iterable<String> protectedDirectories = const [],
}) {
  final absolute = File(output).absolute.path;
  for (final candidate in [absolute, '$absolute.tmp']) {
    if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
        FileSystemEntityType.link) {
      return '$candidate is a symbolic link or junction';
    }
  }
  var ancestor = File(absolute).parent;
  while (true) {
    if (FileSystemEntity.typeSync(ancestor.path, followLinks: false) ==
        FileSystemEntityType.link) {
      return 'ancestor ${ancestor.path} is a symbolic link or junction';
    }
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) break;
    ancestor = parent;
  }
  final canonical = _canonical(absolute);
  for (final file in protectedFiles) {
    final protected = _canonical(file);
    if (canonical == protected || '$canonical.tmp' == protected) {
      return '$output would overwrite input $file';
    }
  }
  for (final directory in protectedDirectories) {
    final protected = _canonical(directory);
    if (canonical == protected ||
        canonical.startsWith('$protected${Platform.pathSeparator}')) {
      return '$output is inside $directory, which must not be modified';
    }
  }
  return null;
}

/// Absolute path with the deepest existing ancestor's links resolved.
String _canonical(String path) {
  var head = File(path).absolute.path;
  final tail = <String>[];
  while (FileSystemEntity.typeSync(head) == FileSystemEntityType.notFound) {
    final parent = File(head).parent.path;
    if (parent == head) break;
    tail.insert(
      0,
      head.substring(parent.length).replaceAll(RegExp(r'^[\\/]'), ''),
    );
    head = parent;
  }
  var resolved = head;
  try {
    resolved = File(head).resolveSymbolicLinksSync();
  } on FileSystemException {
    // Keep the lexical path; the link checks above already ran.
  }
  resolved = resolved.replaceAll(RegExp(r'[\\/]+$'), '');
  final sep = Platform.pathSeparator;
  var result = [resolved, ...tail].join(sep).replaceAll('/', sep);
  while (result.length > 3 && result.endsWith(sep)) {
    result = result.substring(0, result.length - 1);
  }
  return Platform.isWindows ? result.toLowerCase() : result;
}

/// Writes [contents] to `<path>.tmp`, then renames it over [path].
///
/// A leftover `<path>.tmp` is removed first and the temp file is created
/// exclusively, so a planted hard link at the temp path is unlinked rather
/// than written through to the file it shares.
void writeViaTemp(String path, String contents) {
  final temp = File('$path.tmp');
  if (FileSystemEntity.typeSync(temp.path, followLinks: false) ==
      FileSystemEntityType.file) {
    temp.deleteSync();
  }
  temp.createSync(exclusive: true);
  temp.writeAsStringSync(contents, flush: true);
  temp.renameSync(path);
}
