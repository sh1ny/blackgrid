import 'dart:convert';
import 'dart:typed_data';

/// Builds a minimal, valid-enough x64 PE32+ image for parser tests.
///
/// One section (`.rdata`) is mapped at [sectionRva] and stored at
/// [sectionFileOffset], so RVA to file offset translation is exercised.
class PeBuilder {
  PeBuilder({
    this.imports = const [],
    this.delayImports = const [],
    this.version,
    this.machine = 0x8664,
    this.iconGroup,
    this.iconImages = const {},
    this.iconSizeOverrides = const {},
  });

  static const sectionRva = 0x2000;
  static const sectionFileOffset = 0x400;

  final List<String> imports;
  final List<String> delayImports;

  /// Four-part file version, or null for no version resource.
  final List<int>? version;
  final int machine;

  /// Raw RT_GROUP_ICON resource data (see [iconGroupDir]), or null for none.
  final Uint8List? iconGroup;

  /// RT_ICON resource data keyed by resource id.
  final Map<int, Uint8List> iconImages;

  /// Replaces the size recorded in an RT_ICON data entry, keyed by resource
  /// id, to build entries that run past the end of the file.
  final Map<int, int> iconSizeOverrides;

  /// Builds a GRPICONDIR. [declaredCount] overrides the entry count field.
  static Uint8List iconGroupDir(
    List<({int width, int height, int bitCount, int planes, int size, int id})>
    entries, {
    int? declaredCount,
  }) {
    final d = ByteData(6 + 14 * entries.length);
    d.setUint16(2, 1, Endian.little);
    d.setUint16(4, declaredCount ?? entries.length, Endian.little);
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final p = 6 + 14 * i;
      d.setUint8(p, e.width >= 256 ? 0 : e.width);
      d.setUint8(p + 1, e.height >= 256 ? 0 : e.height);
      d.setUint16(p + 4, e.planes, Endian.little);
      d.setUint16(p + 6, e.bitCount, Endian.little);
      d.setUint32(p + 8, e.size, Endian.little);
      d.setUint16(p + 12, e.id, Endian.little);
    }
    return d.buffer.asUint8List();
  }

  Uint8List build() {
    final section = BytesBuilder();
    int here() => section.length;
    int rva() => sectionRva + here();
    void align4() {
      while (here() % 4 != 0) {
        section.addByte(0);
      }
    }

    Uint8List u32s(List<int> v) {
      final d = ByteData(v.length * 4);
      for (var i = 0; i < v.length; i++) {
        d.setUint32(i * 4, v[i], Endian.little);
      }
      return d.buffer.asUint8List();
    }

    int importRva = 0, importSize = 0, delayRva = 0, delaySize = 0;
    int resRva = 0, resSize = 0;

    // Name strings first so descriptors can reference them.
    final nameRvas = <String, int>{};
    for (final n in [...imports, ...delayImports]) {
      nameRvas[n] = rva();
      section.add(ascii.encode(n));
      section.addByte(0);
    }
    align4();

    if (imports.isNotEmpty) {
      importRva = rva();
      for (final n in imports) {
        section.add(u32s([0, 0, 0, nameRvas[n]!, 0]));
      }
      section.add(Uint8List(20));
      importSize = rva() - importRva;
    }
    if (delayImports.isNotEmpty) {
      delayRva = rva();
      for (final n in delayImports) {
        section.add(u32s([1, nameRvas[n]!, 0, 0, 0, 0, 0, 0]));
      }
      section.add(Uint8List(32));
      delaySize = rva() - delayRva;
    }

    final tree = _resourceTree();
    if (tree != null) {
      resRva = rva();
      section.add(tree(resRva));
      resSize = rva() - resRva;
    }
    align4();

    final sectionBytes = section.toBytes();
    const headerSize = sectionFileOffset;
    final out = Uint8List(headerSize + sectionBytes.length);
    final d = ByteData.sublistView(out);
    out[0] = 0x4D;
    out[1] = 0x5A;
    const peOff = 0x80;
    d.setUint32(0x3C, peOff, Endian.little);
    out.setAll(peOff, [0x50, 0x45, 0, 0]);
    const coff = peOff + 4;
    d.setUint16(coff, machine, Endian.little);
    d.setUint16(coff + 2, 1, Endian.little); // sections
    const optSize = 112 + 16 * 8;
    d.setUint16(coff + 16, optSize, Endian.little);
    d.setUint16(coff + 18, 0x2022, Endian.little);
    const opt = coff + 20;
    d.setUint16(opt, 0x20B, Endian.little);
    d.setUint32(opt + 32, 0x1000, Endian.little); // SectionAlignment
    d.setUint32(opt + 36, 0x200, Endian.little); // FileAlignment
    d.setUint32(opt + 56, sectionRva + sectionBytes.length, Endian.little);
    d.setUint32(opt + 60, headerSize, Endian.little);
    d.setUint32(opt + 108, 16, Endian.little); // NumberOfRvaAndSizes
    const dd = opt + 112;
    void dataDir(int i, int r, int s) {
      d.setUint32(dd + i * 8, r, Endian.little);
      d.setUint32(dd + i * 8 + 4, s, Endian.little);
    }

    dataDir(1, importRva, importSize);
    dataDir(2, resRva, resSize);
    dataDir(13, delayRva, delaySize);
    const sh = opt + optSize;
    out.setAll(sh, ascii.encode('.rdata'));
    d.setUint32(sh + 8, sectionBytes.length, Endian.little);
    d.setUint32(sh + 12, sectionRva, Endian.little);
    d.setUint32(sh + 16, sectionBytes.length, Endian.little);
    d.setUint32(sh + 20, sectionFileOffset, Endian.little);
    d.setUint32(sh + 36, 0x40000040, Endian.little);
    out.setAll(sectionFileOffset, sectionBytes);
    return out;
  }

  /// Returns a function building the resource directory tree for a given
  /// base RVA, or null when there are no resources. Every leaf has one
  /// language (0x409).
  Uint8List Function(int base)? _resourceTree() {
    final types = <int, Map<int, Uint8List>>{};
    final v = version;
    if (v != null) types[16] = {1: _versionBlob(v)};
    final group = iconGroup;
    if (group != null) types[14] = {1: group};
    if (iconImages.isNotEmpty) types[3] = iconImages;
    if (types.isEmpty) return null;
    return (base) {
      final typeIds = types.keys.toList()..sort();
      final leaves = <({int type, int name, Uint8List data})>[
        for (final t in typeIds)
          for (final n in (types[t]!.keys.toList()..sort()))
            (type: t, name: n, data: types[t]![n]!),
      ];
      var pos = 16 + 8 * typeIds.length;
      final nameDirAt = <int, int>{};
      for (final t in typeIds) {
        nameDirAt[t] = pos;
        pos += 16 + 8 * types[t]!.length;
      }
      final langDirAt = <int>[];
      for (var i = 0; i < leaves.length; i++) {
        langDirAt.add(pos);
        pos += 24;
      }
      final entryAt = <int>[];
      for (var i = 0; i < leaves.length; i++) {
        entryAt.add(pos);
        pos += 16;
      }
      final blobAt = <int>[];
      for (final leaf in leaves) {
        pos = (pos + 3) & ~3;
        blobAt.add(pos);
        pos += leaf.data.length;
      }
      final out = Uint8List((pos + 3) & ~3);
      final d = ByteData.sublistView(out);
      void dir(int at, List<(int, int)> entries) {
        d.setUint16(at + 14, entries.length, Endian.little);
        for (var i = 0; i < entries.length; i++) {
          d.setUint32(at + 16 + i * 8, entries[i].$1, Endian.little);
          d.setUint32(at + 20 + i * 8, entries[i].$2, Endian.little);
        }
      }

      const subdir = 0x80000000;
      dir(0, [for (final t in typeIds) (t, subdir | nameDirAt[t]!)]);
      var leaf = 0;
      for (final t in typeIds) {
        final names = types[t]!.keys.toList()..sort();
        dir(nameDirAt[t]!, [
          for (var i = 0; i < names.length; i++)
            (names[i], subdir | langDirAt[leaf + i]),
        ]);
        leaf += names.length;
      }
      for (var i = 0; i < leaves.length; i++) {
        dir(langDirAt[i], [(0x409, entryAt[i])]);
        final l = leaves[i];
        final size = l.type == 3
            ? (iconSizeOverrides[l.name] ?? l.data.length)
            : l.data.length;
        d.setUint32(entryAt[i], base + blobAt[i], Endian.little);
        d.setUint32(entryAt[i] + 4, size, Endian.little);
        out.setAll(blobAt[i], l.data);
      }
      return out;
    };
  }

  static Uint8List _versionBlob(List<int> v) {
    final b = BytesBuilder();
    final head = ByteData(6)..setUint16(2, 52, Endian.little);
    b.add(head.buffer.asUint8List());
    for (final c in 'VS_VERSION_INFO'.codeUnits) {
      b.addByte(c);
      b.addByte(0);
    }
    b.add([0, 0]);
    while (b.length % 4 != 0) {
      b.addByte(0);
    }
    final f = ByteData(52);
    f.setUint32(0, 0xFEEF04BD, Endian.little);
    f.setUint32(4, 0x10000, Endian.little);
    f.setUint32(8, (v[0] << 16) | v[1], Endian.little);
    f.setUint32(12, (v[2] << 16) | v[3], Endian.little);
    b.add(f.buffer.asUint8List());
    final out = b.toBytes();
    ByteData.sublistView(out).setUint16(0, out.length, Endian.little);
    return out;
  }
}
