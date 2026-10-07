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
  });

  static const sectionRva = 0x2000;
  static const sectionFileOffset = 0x400;

  final List<String> imports;
  final List<String> delayImports;

  /// Four-part file version, or null for no version resource.
  final List<int>? version;
  final int machine;

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

    final v = version;
    if (v != null) {
      resRva = rva();
      final base = resRva;
      // Layout: type dir @0, name dir @24, language dir @48,
      // data entry @72, version blob @88.
      Uint8List dir(int entryId, int target) {
        final d = ByteData(24);
        d.setUint16(14, 1, Endian.little); // one id entry
        d.setUint32(16, entryId, Endian.little);
        d.setUint32(20, target, Endian.little);
        return d.buffer.asUint8List();
      }

      section.add(dir(16, 0x80000000 | 24));
      section.add(dir(1, 0x80000000 | 48));
      section.add(dir(0x409, 72));
      final blob = _versionBlob(v);
      section.add(u32s([base + 88, blob.length, 0, 0]));
      section.add(blob);
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
