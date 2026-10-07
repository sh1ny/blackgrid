/// Typed reasons the native vision runtime or one of its operations cannot
/// deliver a result. Operations return these instead of throwing.
sealed class VisionFailure {
  const VisionFailure();

  /// Human-readable description naming the offending file, component or step.
  String get message;

  @override
  String toString() => message;
}

/// The runtime directory is not an absolute path (or a manifest entry escapes
/// it). No file was opened.
final class VisionInvalidPath extends VisionFailure {
  const VisionInvalidPath([this.detail = '']);

  final String detail;

  @override
  String get message => detail.isEmpty
      ? 'Vision runtime directory must be an absolute path.'
      : 'Vision runtime path is invalid: $detail';
}

/// A required file (binding manifest, library or model) is absent or the
/// binding is unusable.
final class VisionMissingFile extends VisionFailure {
  const VisionMissingFile(this.path);

  final String path;

  @override
  String get message => 'Vision runtime file is missing: $path';
}

/// A file's bytes differ from its build binding. Nothing was loaded.
final class VisionHashMismatch extends VisionFailure {
  const VisionHashMismatch(this.path, this.expected, this.actual);

  final String path;
  final String expected;
  final String actual;

  @override
  String get message =>
      'Vision runtime file $path hash mismatch: expected $expected, '
      'actual $actual.';
}

/// A loaded component reports a version other than the pinned one.
final class VisionAbiMismatch extends VisionFailure {
  const VisionAbiMismatch(this.component, this.expected, this.actual);

  final String component;
  final String expected;
  final String actual;

  @override
  String get message =>
      'Vision component $component version mismatch: expected $expected, '
      'actual $actual.';
}

/// The OS refused to load a library.
final class VisionLoadFailed extends VisionFailure {
  const VisionLoadFailed(this.path, this.osError);

  final String path;
  final String osError;

  @override
  String get message => 'Cannot load vision library $path: $osError';
}

/// The OCR engine could not initialise from its model directory.
final class VisionEngineInitFailed extends VisionFailure {
  const VisionEngineInitFailed(this.datapath);

  final String datapath;

  @override
  String get message => 'OCR engine failed to initialise from $datapath.';
}

/// A caller-supplied image violates the buffer contract; no native call ran.
final class VisionInvalidImage extends VisionFailure {
  const VisionInvalidImage(this.reason);

  final String reason;

  @override
  String get message => 'Invalid image: $reason';
}

/// The runtime was disposed; no native call ran.
final class VisionDisposedFailure extends VisionFailure {
  const VisionDisposedFailure();

  @override
  String get message => 'Vision runtime is disposed.';
}

/// A native operation ran and reported a non-success status (OpenCV error,
/// out of memory, an input the native side rejected, or no OCR text).
final class VisionNativeFailure extends VisionFailure {
  const VisionNativeFailure(this.status, this.detail);

  /// The native `bgv_*` status, or -5 (internal) for a thrown error.
  final int status;
  final String detail;

  @override
  String get message => 'Native vision call failed (status $status): $detail';
}

/// A bounded step did not finish in time.
final class VisionTimeout extends VisionFailure {
  const VisionTimeout(this.step);

  final String step;

  @override
  String get message => 'Vision step timed out: $step';
}

/// Value or typed failure; the return type of every runtime operation.
sealed class VisionResult<T> {
  const VisionResult();
}

final class VisionOk<T> extends VisionResult<T> {
  const VisionOk(this.value);

  final T value;
}

final class VisionFailed<T> extends VisionResult<T> {
  const VisionFailed(this.failure);

  final VisionFailure failure;
}
