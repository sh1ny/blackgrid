import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'vision_failure.dart';
import 'vision_image.dart';
import 'vision_native.dart';
import 'vision_primitives.dart';
import 'vision_scratch.dart';

export 'vision_failure.dart';
export 'vision_image.dart' show VisionImage;
export 'vision_native.dart'
    show OcrText, VisionLoadException, VisionNativeOpener;
export 'vision_primitives.dart' show TemplateMatch;

/// `bgv_abi()` value this build of the Dart binding expects.
const int visionExpectedAbi = 1;

/// Manifest location relative to the runtime directory.
const String visionManifestPath = 'data/vision/runtime.manifest.json';

/// Files that must be listed (and so hash-verified) in the manifest, in the
/// order they are checked. Library open order is the first three.
const List<String> visionCoreFiles = [
  'leptonica-1.82.0.dll',
  'tesseract50.dll',
  'blackgrid_vision.dll',
  'data/vision/tessdata/eng.traineddata',
];

const String _tessdataRelative = 'data/vision/tessdata';
const int _oemLstmOnly = 1;
const int _psmRawLine = 13;

/// One verified file of the runtime.
final class VisionFileIdentity {
  const VisionFileIdentity(this.path, this.sha256);

  final String path;
  final String sha256;
}

/// What a ready runtime is: verified files, engine version and configuration.
final class VisionIdentity {
  const VisionIdentity({
    required this.files,
    required this.tesseractVersion,
    required this.visionAbi,
    required this.language,
    required this.oem,
    required this.psm,
  });

  final List<VisionFileIdentity> files;
  final String tesseractVersion;
  final int visionAbi;
  final String language;
  final int oem;
  final int psm;
}

sealed class VisionRuntimeStatus {
  const VisionRuntimeStatus();
}

final class VisionReady extends VisionRuntimeStatus {
  const VisionReady(this.identity);

  final VisionIdentity identity;
}

final class VisionUnavailable extends VisionRuntimeStatus {
  const VisionUnavailable(this.failure);

  final VisionFailure failure;
}

final class VisionDisposed extends VisionRuntimeStatus {
  const VisionDisposed();
}

/// Synchronous owner of the native Tesseract + vision stack. Opening never
/// throws; every operation returns a [VisionResult]. No UI-isolate caller is
/// added here (ADR-0004): callers decide which isolate runs it.
final class VisionRuntime {
  VisionRuntime._(this._status, this._native, this._engine);

  VisionRuntimeStatus _status;
  VisionNative? _native;
  VisionEngine? _engine;

  VisionRuntimeStatus get status => _status;

  /// Verifies the runtime directory against its manifest, then loads it.
  ///
  /// A malformed manifest is reported as [VisionMissingFile] naming the
  /// manifest: an unreadable binding is treated as an absent binding.
  static VisionRuntime open({
    required String runtimeDirectory,
    VisionNativeOpener opener = openVisionNative,
  }) {
    VisionNative? native;
    VisionEngine? engine;
    VisionRuntime unavailable(VisionFailure failure) {
      // Engine first, then libraries (reverse of acquisition).
      try {
        engine?.dispose();
      } catch (_) {}
      try {
        native?.close();
      } catch (_) {}
      return VisionRuntime._(VisionUnavailable(failure), null, null);
    }

    if (!File(runtimeDirectory).isAbsolute) {
      return unavailable(const VisionInvalidPath());
    }
    final root = _normalize(runtimeDirectory);
    String resolve(String relative) => '$root/$relative';

    final manifestFile = resolve(visionManifestPath);
    final manifest = _readManifest(manifestFile);
    if (manifest == null) {
      return unavailable(VisionMissingFile(manifestFile));
    }
    final listed = <String, String>{};
    for (final entry in manifest.files) {
      if (!_safeRelative(entry.path)) {
        return unavailable(VisionInvalidPath('manifest entry ${entry.path}'));
      }
      listed[entry.path] = entry.sha256;
    }
    for (final core in visionCoreFiles) {
      if (!listed.containsKey(core)) {
        return unavailable(VisionMissingFile(resolve(core)));
      }
    }
    for (final entry in manifest.files) {
      if (!File(resolve(entry.path)).existsSync()) {
        return unavailable(VisionMissingFile(resolve(entry.path)));
      }
    }
    // Every hash passes before any library is opened.
    for (final entry in manifest.files) {
      final String actual;
      try {
        actual = sha256
            .convert(File(resolve(entry.path)).readAsBytesSync())
            .toString();
      } on FileSystemException {
        return unavailable(VisionMissingFile(resolve(entry.path)));
      }
      if (actual != entry.sha256) {
        return unavailable(
          VisionHashMismatch(resolve(entry.path), entry.sha256, actual),
        );
      }
    }

    final leptonica = resolve(visionCoreFiles[0]);
    final tesseract = resolve(visionCoreFiles[1]);
    final vision = resolve(visionCoreFiles[2]);
    final VisionNative loaded;
    try {
      loaded = opener(leptonica, tesseract, vision);
      native = loaded;
    } on VisionLoadException catch (error) {
      return unavailable(VisionLoadFailed(error.path, error.osError));
    } catch (error) {
      return unavailable(VisionLoadFailed(vision, '$error'));
    }

    final datapath = resolve(_tessdataRelative);
    try {
      final abi = loaded.visionAbi;
      if (abi != visionExpectedAbi) {
        return unavailable(
          VisionAbiMismatch('blackgrid_vision', '$visionExpectedAbi', '$abi'),
        );
      }
      if (manifest.abi != visionExpectedAbi) {
        return unavailable(
          VisionAbiMismatch(
            'manifest',
            '$visionExpectedAbi',
            '${manifest.abi}',
          ),
        );
      }
      final version = loaded.tessVersion;
      if (version != manifest.engineVersion) {
        return unavailable(
          VisionAbiMismatch('tesseract', manifest.engineVersion, version),
        );
      }
      final created = loaded.createEngine();
      if (created == null) {
        return unavailable(VisionEngineInitFailed(datapath));
      }
      engine = created;
      if (created.init(datapath, 'eng', _oemLstmOnly) != 0) {
        return unavailable(VisionEngineInitFailed(datapath));
      }
      created.setPageSegMode(_psmRawLine);
      final identity = VisionIdentity(
        files: [
          for (final entry in manifest.files)
            VisionFileIdentity(entry.path, entry.sha256),
        ],
        tesseractVersion: version,
        visionAbi: abi,
        language: created.initLanguages,
        oem: created.oem,
        psm: created.pageSegMode,
      );
      return VisionRuntime._(VisionReady(identity), loaded, created);
    } catch (error) {
      return unavailable(VisionLoadFailed(vision, '$error'));
    }
  }

  /// Ends the engine once, then closes the libraries and frees the scratch
  /// pool. Idempotent.
  void dispose() {
    if (_status is VisionDisposed) return;
    final engine = _engine;
    final native = _native;
    _status = const VisionDisposed();
    _engine = null;
    _native = null;
    try {
      engine?.dispose();
    } finally {
      native?.close();
    }
  }

  /// Shrinks the native scratch buffers back to their 16 MiB retention cap.
  /// The vision worker calls it after each request so one oversized frame does
  /// not stay pinned. A no-op once disposed or when the native stack keeps no
  /// scratch.
  void trimScratch() {
    if (_native case final VisionScratchOwner owner) owner.trimScratch();
  }

  /// OCR over [image] with the pinned engine configuration.
  VisionResult<OcrText> recognise(VisionImage image) => _run((native, engine) {
    final invalid = image.validate();
    if (invalid != null) return VisionFailed(invalid);
    return VisionOk(engine.recognise(image));
  });

  VisionResult<VisionImage> toGray(
    VisionImage image, {
    bool rgbOrder = false,
  }) => _run((native, engine) {
    final invalid = image.validate();
    if (invalid != null) return VisionFailed(invalid);
    final bytes = native.primitives.toGray(image, rgbOrder: rgbOrder);
    return VisionOk(_tight(bytes, image.width, image.height, 1));
  });

  VisionResult<VisionImage> resize(
    VisionImage image,
    int width,
    int height, {
    int interp = visionInterCubic,
  }) => _run((native, engine) {
    final invalid = image.validate();
    if (invalid != null) return VisionFailed(invalid);
    if (width < 1 ||
        width > visionMaxSide ||
        height < 1 ||
        height > visionMaxSide ||
        width * height > visionMaxPixels) {
      return VisionFailed(
        VisionInvalidImage('target ${width}x$height is outside the caps'),
      );
    }
    if (interp != visionInterCubic && interp != visionInterArea) {
      return VisionFailed(VisionInvalidImage('unknown interpolation $interp'));
    }
    final bytes = native.primitives.resize(image, width, height, interp);
    return VisionOk(_tight(bytes, width, height, image.channels));
  });

  VisionResult<VisionImage> thresholdBinaryInv(
    VisionImage image,
    int thresh,
    int maxval,
  ) => _run((native, engine) {
    final invalid = _grayOnly(image);
    if (invalid != null) return VisionFailed(invalid);
    if (thresh < 0 || thresh > 255 || maxval < 0 || maxval > 255) {
      return const VisionFailed(
        VisionInvalidImage('threshold and maxval must be 0..255'),
      );
    }
    final bytes = native.primitives.thresholdBinaryInv(image, thresh, maxval);
    return VisionOk(_tight(bytes, image.width, image.height, 1));
  });

  VisionResult<TemplateMatch> matchTemplate(
    VisionImage image,
    VisionImage template,
  ) => _run((native, engine) {
    final invalid =
        _grayOnly(image) ?? VisionImage.validateTemplate(image, template);
    if (invalid != null) return VisionFailed(invalid);
    if (template.channels != 1) {
      return const VisionFailed(
        VisionInvalidImage('template must be 1 channel'),
      );
    }
    return VisionOk(native.primitives.matchTemplateBest(image, template));
  });

  /// Null [VisionOk.value] when no pixel of the row is in range.
  VisionResult<int?> findInRangeRow(
    VisionImage image,
    int row,
    int startX,
    List<int> lo,
    List<int> hi,
  ) => _run((native, engine) {
    final invalid = image.validate();
    if (invalid != null) return VisionFailed(invalid);
    if (image.channels == 1) {
      return const VisionFailed(
        VisionInvalidImage('image must be 3 or 4 channels'),
      );
    }
    if (row < 0 ||
        row >= image.height ||
        startX < 0 ||
        startX >= image.width ||
        lo.length != 3 ||
        hi.length != 3 ||
        [...lo, ...hi].any((v) => v < 0 || v > 255)) {
      return const VisionFailed(
        VisionInvalidImage('row, start or range is invalid'),
      );
    }
    return VisionOk(
      native.primitives.findInRangeRow(image, row, startX, lo, hi),
    );
  });

  VisionResult<T> _run<T>(
    VisionResult<T> Function(VisionNative native, VisionEngine engine) body,
  ) {
    final native = _native;
    final engine = _engine;
    switch (_status) {
      case VisionDisposed():
        return VisionFailed(const VisionDisposedFailure());
      case VisionUnavailable(:final failure):
        return VisionFailed(failure);
      case VisionReady():
        break;
    }
    if (native == null || engine == null) {
      return VisionFailed(const VisionDisposedFailure());
    }
    try {
      return body(native, engine);
    } on VisionNativeError catch (error) {
      return VisionFailed(VisionNativeFailure(error.status, error.detail));
    } catch (error) {
      return VisionFailed(VisionNativeFailure(-5, '$error'));
    }
  }

  static VisionInvalidImage? _grayOnly(VisionImage image) {
    final invalid = image.validate();
    if (invalid != null) return invalid;
    if (image.channels != 1) {
      return const VisionInvalidImage('image must be 1 channel');
    }
    return null;
  }

  static VisionImage _tight(
    Uint8List bytes,
    int width,
    int height,
    int channels,
  ) => VisionImage(
    bytes,
    width: width,
    height: height,
    stride: width * channels,
    channels: channels,
  );
}

String _normalize(String directory) {
  var value = directory.replaceAll('\\', '/');
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

bool _safeRelative(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.contains(':')) {
    return false;
  }
  return !path
      .split('/')
      .any((part) => part.isEmpty || part == '..' || part == '.');
}

final class _ManifestEntry {
  const _ManifestEntry(this.path, this.sha256);

  final String path;
  final String sha256;
}

final class _Manifest {
  const _Manifest(this.abi, this.engineVersion, this.files);

  final int abi;
  final String engineVersion;
  final List<_ManifestEntry> files;
}

_Manifest? _readManifest(String path) {
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map<String, dynamic>) return null;
    final abi = decoded['abi'];
    final engineVersion = decoded['engineVersion'];
    final files = decoded['files'];
    if (abi is! int || engineVersion is! String || files is! List) return null;
    final entries = <_ManifestEntry>[];
    for (final file in files) {
      if (file is! Map<String, dynamic>) return null;
      final entryPath = file['path'];
      final digest = file['sha256'];
      if (entryPath is! String || digest is! String) return null;
      entries.add(_ManifestEntry(entryPath, digest.toLowerCase()));
    }
    return _Manifest(abi, engineVersion, entries);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}
