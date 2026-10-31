// Minimal PE32+ (x64) reader used by the release bundle checks: imported DLL
// names (import and delay-import directories) and the VS_FIXEDFILEINFO file
// version. Every read is bounds-checked; malformed input yields an
// "unreadable" result and never an exception or an out-of-range read.
// [readIconGroup] reads the application icon group on its own, so a malformed
// icon resource never makes the imports or the version unreadable.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _machineAmd64 = 0x8664;
const _magicPe32Plus = 0x20B;
const _fixedFileInfoSignature = 0xFEEF04BD;
const _rtIcon = 3;
const _rtGroupIcon = 14;
const _rtVersion = 16;
const _maxIconEntries = 32;
const _maxIconBytes = 0x100000;
const _maxImports = 4096;
const _maxNameLength = 260;

class _Malformed implements Exception {
  _Malformed(this.message);
  final String message;
}

class _Section {
  _Section(this.rva, this.virtualSize, this.rawOffset, this.rawSize);
  final int rva;
  final int virtualSize;
  final int rawOffset;
  final int rawSize;
}

/// Parsed view of a PE32+ image, or the reason it could not be read.
class PeReadResult {
  PeReadResult._ok({
    required List<String> imports,
    required List<String> delayImports,
    required this.version,
  }) : imports = List.unmodifiable(imports),
       delayImports = List.unmodifiable(delayImports),
       error = null;

  const PeReadResult._bad(this.error)
    : imports = const [],
      delayImports = const [],
      version = null;

  final String? error;

  /// DLL names from the import directory (data directory 1).
  final List<String> imports;

  /// DLL names from the delay-import directory (data directory 13).
  final List<String> delayImports;

  /// Four-part file version, or null when there is no readable version
  /// resource.
  final List<int>? version;

  bool get readable => error == null;

  List<String> get allImports => [...imports, ...delayImports];

  String? get versionString => version?.join('.');
}

/// One image of an executable's icon group.
class PeIconImage {
  const PeIconImage._({
    required this.width,
    required this.height,
    required this.planes,
    required this.bitCount,
    required this.id,
    required this.bytes,
  });

  /// Width in pixels from the group entry (a stored 0 reads as 256).
  final int width;

  /// Height in pixels from the group entry (a stored 0 reads as 256).
  final int height;

  /// Colour planes from the group entry.
  final int planes;

  /// Bits per pixel from the group entry.
  final int bitCount;

  /// The RT_ICON resource id the group entry names.
  final int id;

  /// The RT_ICON resource data: the bytes `rc.exe` copied from the `.ico`.
  final Uint8List bytes;
}

/// Outcome of [readIconGroup].
sealed class IconGroupResult {
  const IconGroupResult();
}

/// An icon group whose every image was read.
final class IconGroupReadable extends IconGroupResult {
  /// Wraps [images].
  IconGroupReadable(List<PeIconImage> images)
    : images = List.unmodifiable(images);

  /// The images, in group order.
  final List<PeIconImage> images;
}

/// Input without a readable icon group.
final class IconGroupUnreadable extends IconGroupResult {
  /// Creates a failure carrying [reason].
  const IconGroupUnreadable(this.reason);

  /// Why the icon group could not be read.
  final String reason;
}

/// Reads the first RT_GROUP_ICON of the PE image in [bytes] with the RT_ICON
/// data of every entry.
///
/// This is separate from [readPe]: a malformed icon resource gives
/// [IconGroupUnreadable] and leaves the imports and version readable. Every
/// read is bounds-checked; this never throws.
IconGroupResult readIconGroup(Uint8List bytes) {
  try {
    final reader = _PeReader(bytes)..readHeaders();
    return IconGroupReadable(reader.iconGroup());
  } on _Malformed catch (e) {
    return IconGroupUnreadable(e.message);
  } on RangeError catch (e) {
    return IconGroupUnreadable('out of range read: ${e.message}');
  }
}

PeReadResult readPe(Uint8List bytes) {
  try {
    return _PeReader(bytes).read();
  } on _Malformed catch (e) {
    return PeReadResult._bad(e.message);
  } on RangeError catch (e) {
    return PeReadResult._bad('out of range read: ${e.message}');
  }
}

class _PeReader {
  _PeReader(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  final sections = <_Section>[];
  late List<(int, int)> dirs;

  int u16(int o) {
    if (o < 0 || o + 2 > bytes.length) throw _Malformed('truncated at $o');
    return data.getUint16(o, Endian.little);
  }

  int u32(int o) {
    if (o < 0 || o + 4 > bytes.length) throw _Malformed('truncated at $o');
    return data.getUint32(o, Endian.little);
  }

  /// Validates the headers and fills [sections] and [dirs].
  void readHeaders() {
    if (bytes.length < 0x40 || bytes[0] != 0x4D || bytes[1] != 0x5A) {
      throw _Malformed('missing MZ header');
    }
    final peOff = u32(0x3C);
    if (u32(peOff) != 0x00004550) throw _Malformed('missing PE signature');
    final coff = peOff + 4;
    if (u16(coff) != _machineAmd64) throw _Malformed('not an x64 image');
    final sectionCount = u16(coff + 2);
    final optSize = u16(coff + 16);
    final opt = coff + 20;
    if (u16(opt) != _magicPe32Plus) throw _Malformed('not PE32+');
    if (optSize < 112) throw _Malformed('optional header too small');
    final dirCount = u32(opt + 108);
    if (dirCount > 16 || 112 + dirCount * 8 > optSize) {
      throw _Malformed('bad data directory count');
    }
    dirs = [
      for (var i = 0; i < 16; i++)
        i < dirCount
            ? (u32(opt + 112 + i * 8), u32(opt + 112 + i * 8 + 4))
            : (0, 0),
    ];
    if (sectionCount > 96) throw _Malformed('too many sections');
    final table = opt + optSize;
    for (var i = 0; i < sectionCount; i++) {
      final s = table + i * 40;
      sections.add(_Section(u32(s + 12), u32(s + 8), u32(s + 20), u32(s + 16)));
    }
  }

  PeReadResult read() {
    readHeaders();
    return PeReadResult._ok(
      imports: _importNames(dirs[1].$1, 20, 12),
      delayImports: _importNames(dirs[13].$1, 32, 4),
      version: _version(),
    );
  }

  /// RVA to file offset, validating that [length] bytes lie in the file.
  int offsetOf(int rva, [int length = 1]) {
    for (final s in sections) {
      final span = s.rawSize > s.virtualSize ? s.rawSize : s.virtualSize;
      if (rva >= s.rva && rva - s.rva < span) {
        final delta = rva - s.rva;
        final off = s.rawOffset + delta;
        if (delta + length > s.rawSize || off + length > bytes.length) {
          throw _Malformed('RVA $rva outside section data');
        }
        return off;
      }
    }
    throw _Malformed('RVA $rva not in any section');
  }

  String cString(int rva) {
    final start = offsetOf(rva);
    final out = <int>[];
    for (var i = start; i < bytes.length; i++) {
      if (bytes[i] == 0) return ascii.decode(out, allowInvalid: true);
      out.add(bytes[i]);
      if (out.length > _maxNameLength) throw _Malformed('name too long');
    }
    throw _Malformed('unterminated name');
  }

  List<String> _importNames(int dirRva, int stride, int nameField) {
    if (dirRva == 0) return const [];
    final names = <String>[];
    for (var i = 0; i < _maxImports; i++) {
      final off = offsetOf(dirRva + i * stride, stride);
      var allZero = true;
      for (var b = 0; b < stride; b++) {
        if (bytes[off + b] != 0) {
          allZero = false;
          break;
        }
      }
      if (allZero) return names;
      final nameRva = u32(off + nameField);
      if (nameRva == 0) throw _Malformed('descriptor without a name');
      names.add(cString(nameRva));
    }
    throw _Malformed('unterminated import directory');
  }

  List<int>? _version() {
    final root = dirs[2].$1;
    if (root == 0) return null;
    final rootOff = offsetOf(root, 16);
    final entry = _findEntry(root, rootOff, id: _rtVersion);
    if (entry == null || !entry.isDir) return null;
    final nameDir = root + entry.offset;
    final first = _firstEntry(nameDir);
    if (first == null || !first.isDir) return null;
    final langDir = root + first.offset;
    final lang = _firstEntry(langDir);
    if (lang == null || lang.isDir) return null;
    final dataOff = offsetOf(root + lang.offset, 16);
    final dataRva = u32(dataOff);
    final size = u32(dataOff + 4);
    if (size < 52 || size > 0x100000) return null;
    final start = offsetOf(dataRva, size);
    for (var o = start; o + 52 <= start + size; o += 4) {
      if (u32(o) == _fixedFileInfoSignature) {
        final ms = u32(o + 8);
        final ls = u32(o + 12);
        return [ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF];
      }
    }
    return null;
  }

  /// The RT_GROUP_ICON data with the RT_ICON image of every entry, or throws
  /// [_Malformed] naming what is missing or out of bounds.
  List<PeIconImage> iconGroup() {
    final root = dirs[2].$1;
    if (root == 0) throw _Malformed('no resource directory');
    final rootOff = offsetOf(root, 16);
    final groupType = _findEntry(root, rootOff, id: _rtGroupIcon);
    if (groupType == null || !groupType.isDir) {
      throw _Malformed('no RT_GROUP_ICON resource');
    }
    final groupNames = root + groupType.offset;
    final groupName = _firstEntry(groupNames);
    if (groupName == null) throw _Malformed('RT_GROUP_ICON has no entry');
    final group = _leaf(root, groupName.isDir, groupName.offset);
    if (group.size < 6) throw _Malformed('icon group is shorter than 6 bytes');
    final head = group.start;
    if (u16(head) != 0 || u16(head + 2) != 1) {
      throw _Malformed('icon group header is not reserved 0, type 1');
    }
    final count = u16(head + 4);
    if (count == 0 || count > _maxIconEntries) {
      throw _Malformed('icon group declares $count images (1 to 32 allowed)');
    }
    if (6 + 14 * count > group.size) {
      throw _Malformed('icon group of $count entries runs past its data');
    }
    final iconType = _findEntry(root, rootOff, id: _rtIcon);
    if (iconType == null || !iconType.isDir) {
      throw _Malformed('no RT_ICON resources');
    }
    final iconNames = root + iconType.offset;
    final iconNamesOff = offsetOf(iconNames, 16);
    final images = <PeIconImage>[];
    for (var i = 0; i < count; i++) {
      final p = head + 6 + 14 * i;
      final id = u16(p + 12);
      final name = _findEntry(iconNames, iconNamesOff, id: id);
      if (name == null) throw _Malformed('entry $i names RT_ICON $id: missing');
      final image = _leaf(root, name.isDir, name.offset);
      images.add(
        PeIconImage._(
          width: bytes[p] == 0 ? 256 : bytes[p],
          height: bytes[p + 1] == 0 ? 256 : bytes[p + 1],
          planes: u16(p + 4),
          bitCount: u16(p + 6),
          id: id,
          bytes: Uint8List.sublistView(
            bytes,
            image.start,
            image.start + image.size,
          ),
        ),
      );
    }
    return images;
  }

  /// The first-language data of a name entry whose subdirectory is at
  /// [nameOffset] from [root]; [isDir] is the entry's subdirectory flag.
  ({int start, int size}) _leaf(int root, bool isDir, int nameOffset) {
    if (!isDir) throw _Malformed('resource name entry is not a directory');
    final lang = _firstEntry(root + nameOffset);
    if (lang == null || lang.isDir) {
      throw _Malformed('resource has no language data');
    }
    final dataOff = offsetOf(root + lang.offset, 16);
    final dataRva = u32(dataOff);
    final size = u32(dataOff + 4);
    if (size > _maxIconBytes) throw _Malformed('resource data too large');
    return (start: offsetOf(dataRva, size), size: size);
  }

  ({bool isDir, int offset, int id})? _firstEntry(int dirRva) {
    final off = offsetOf(dirRva, 16);
    final count = u16(off + 12) + u16(off + 14);
    if (count == 0) return null;
    return _entryAt(dirRva, 0);
  }

  ({bool isDir, int offset, int id}) _entryAt(int dirRva, int index) {
    final off = offsetOf(dirRva + 16 + index * 8, 8);
    final target = u32(off + 4);
    return (
      isDir: target & 0x80000000 != 0,
      offset: target & 0x7FFFFFFF,
      id: u32(off),
    );
  }

  ({bool isDir, int offset})? _findEntry(
    int dirRva,
    int dirOff, {
    required int id,
  }) {
    final named = u16(dirOff + 12);
    final ids = u16(dirOff + 14);
    for (var i = named; i < named + ids; i++) {
      final e = _entryAt(dirRva, i);
      if (e.id == id) return (isDir: e.isDir, offset: e.offset);
    }
    return null;
  }
}

/// Committed list of Windows system DLLs a bundle may import without
/// shipping. Visual C++ runtime names are never allowed, whatever the list
/// says.
class SystemAllowList {
  SystemAllowList({
    required Iterable<String> dlls,
    required Iterable<String> prefixes,
  }) : _dlls = {for (final d in dlls) d.toLowerCase()},
       _prefixes = [for (final p in prefixes) p.toLowerCase()];

  factory SystemAllowList.fromJson(String source) {
    final json = jsonDecode(source);
    if (json is! Map || json['format'] != 1) {
      throw const FormatException('unsupported allow-list format');
    }
    return SystemAllowList(
      dlls: (json['dlls'] as List).cast<String>(),
      prefixes: (json['prefixes'] as List).cast<String>(),
    );
  }

  factory SystemAllowList.load([
    String path = 'tool/vision/system_allowlist.json',
  ]) => SystemAllowList.fromJson(File(path).readAsStringSync());

  final Set<String> _dlls;
  final List<String> _prefixes;

  static final _forbidden = RegExp(
    r'^(msvcp|vcruntime|vcomp|concrt|ucrtbase|msvcr|msvcrt)',
  );

  static bool isVisualCppRuntime(String name) =>
      _forbidden.hasMatch(name.toLowerCase());

  bool allows(String dll) {
    final n = dll.toLowerCase();
    if (isVisualCppRuntime(n)) return false;
    return _dlls.contains(n) || _prefixes.any(n.startsWith);
  }
}

enum ImportFailureKind { unresolved, unreadable }

class ImportFailure {
  const ImportFailure.unresolved(this.file, String this.dll, this.detail)
    : kind = ImportFailureKind.unresolved;
  const ImportFailure.unreadable(this.file, this.detail)
    : kind = ImportFailureKind.unreadable,
      dll = null;

  final ImportFailureKind kind;

  /// Bundle-relative path of the file that was checked.
  final String file;

  /// The imported DLL that could not be resolved (unresolved only).
  final String? dll;
  final String detail;

  @override
  String toString() => kind == ImportFailureKind.unresolved
      ? '$file imports $dll, which is neither in the bundle nor an allowed '
            'system library'
      : '$file is unreadable: $detail';
}

class ImportCheckResult {
  const ImportCheckResult(this.failures);
  final List<ImportFailure> failures;
  bool get passed => failures.isEmpty;
}

/// Checks that every DLL imported (including delay-load) by each file is in
/// [bundleDllNames] or on [allow]. [files] maps bundle-relative path to the
/// file bytes.
ImportCheckResult checkImports({
  required Map<String, Uint8List> files,
  required Set<String> bundleDllNames,
  required SystemAllowList allow,
}) {
  final bundle = {for (final n in bundleDllNames) n.toLowerCase()};
  final failures = <ImportFailure>[];
  for (final entry in files.entries) {
    final pe = readPe(entry.value);
    if (!pe.readable) {
      failures.add(ImportFailure.unreadable(entry.key, pe.error!));
      continue;
    }
    for (final dll in pe.allImports) {
      final n = dll.toLowerCase();
      if (SystemAllowList.isVisualCppRuntime(n) && !bundle.contains(n)) {
        failures.add(ImportFailure.unresolved(entry.key, dll, 'not bundled'));
      } else if (!bundle.contains(n) && !allow.allows(dll)) {
        failures.add(ImportFailure.unresolved(entry.key, dll, 'not allowed'));
      }
    }
  }
  return ImportCheckResult(failures);
}

enum VersionFailureKind { belowMinimum, unreadable }

class VersionFailure {
  const VersionFailure.belowMinimum(
    this.file,
    String this.actual,
    String this.minimum,
  ) : kind = VersionFailureKind.belowMinimum;
  const VersionFailure.unreadable(this.file)
    : kind = VersionFailureKind.unreadable,
      actual = null,
      minimum = null;

  final VersionFailureKind kind;
  final String file;
  final String? actual;
  final String? minimum;

  @override
  String toString() => kind == VersionFailureKind.belowMinimum
      ? '$file version $actual is below the minimum $minimum'
      : '$file has an unreadable version';
}

class RuntimeVersionResult {
  const RuntimeVersionResult(this.versions, this.failures);

  /// Version of every file whose version could be read.
  final Map<String, String> versions;
  final List<VersionFailure> failures;
  bool get passed => failures.isEmpty;
}

/// Parses a dotted version of up to four numeric parts; missing parts are 0.
List<int> parseVersion(String text) {
  final parts = text.split('.');
  if (parts.length > 4) throw FormatException('bad version', text);
  final out = [for (final p in parts) int.parse(p)];
  while (out.length < 4) {
    out.add(0);
  }
  return out;
}

/// Numeric per-part comparison.
int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 4; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

RuntimeVersionResult checkRuntimeVersions({
  required Map<String, Uint8List> files,
  required Map<String, String> minimumVersions,
}) {
  final minimums = {
    for (final e in minimumVersions.entries) e.key.toLowerCase(): e.value,
  };
  final versions = <String, String>{};
  final failures = <VersionFailure>[];
  for (final entry in files.entries) {
    final version = readPe(entry.value).version;
    if (version == null) {
      failures.add(VersionFailure.unreadable(entry.key));
      continue;
    }
    final actual = version.join('.');
    versions[entry.key] = actual;
    final base = entry.key.split(RegExp(r'[\\/]')).last.toLowerCase();
    final minimum = minimums[entry.key.toLowerCase()] ?? minimums[base];
    if (minimum != null &&
        compareVersions(version, parseVersion(minimum)) < 0) {
      failures.add(
        VersionFailure.belowMinimum(
          entry.key,
          actual,
          parseVersion(minimum).join('.'),
        ),
      );
    }
  }
  return RuntimeVersionResult(versions, failures);
}
