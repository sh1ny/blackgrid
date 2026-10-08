import '../capture/capture_frame.dart';
import 'vision_primitives.dart';
import 'vision_runtime.dart';

/// Builds the job inside the worker isolate. It must be a top-level or static
/// function so it can be sent to the worker at spawn.
typedef VisionJobFactory<P, R> = VisionJob<P, R> Function();

/// One unit of work that runs synchronously inside the vision worker.
///
/// The returned `R` must be sendable plain data: it must hold no native
/// resource, frame, [VisionJobInput] view or runtime handle. A job that throws is
/// answered [VisionJobFailed]; a job that throws [VisionJobAbort] is answered
/// [VisionFailureAnswer].
abstract interface class VisionJob<P, R> {
  /// Runs the job over [input] with [params]. Must be synchronous.
  R run(VisionJobContext context, VisionJobInput input, P params);
}

/// Thrown by a job to report a typed [VisionFailure] (for example a
/// [VisionFailed] result it cannot continue past).
final class VisionJobAbort implements Exception {
  const VisionJobAbort(this.failure);

  final VisionFailure failure;

  @override
  String toString() => 'VisionJobAbort(${failure.message})';
}

/// A named 1-channel template image. Sendable plain data.
final class VisionTemplate {
  const VisionTemplate(this.name, this.image);

  final String name;

  /// Expected to have exactly one channel; the service answers
  /// [VisionInvalidTemplate] otherwise.
  final VisionImage image;
}

/// What a job may use: the runtime operations, the templates and the clock.
/// Lives in the worker isolate only; a job must not keep it past `run`.
final class VisionJobContext {
  VisionJobContext(
    this._runtime, {
    required Map<String, VisionTemplate> templates,
    required this.qpcNow,
  }) : templates = Map.unmodifiable(templates);

  final VisionRuntime _runtime;

  /// Templates by name.
  final Map<String, VisionTemplate> templates;

  /// The capture DLL's monotonic QPC tick counter (`CapturePlatform.qpcNow`).
  final int Function() qpcNow;

  /// See [VisionRuntime.recognise].
  VisionResult<OcrText> recognise(VisionImage image) =>
      _runtime.recognise(image);

  /// See [VisionRuntime.toGray].
  VisionResult<VisionImage> toGray(
    VisionImage image, {
    bool rgbOrder = false,
  }) => _runtime.toGray(image, rgbOrder: rgbOrder);

  /// See [VisionRuntime.resize].
  VisionResult<VisionImage> resize(
    VisionImage image,
    int width,
    int height, {
    int interp = visionInterCubic,
  }) => _runtime.resize(image, width, height, interp: interp);

  /// See [VisionRuntime.thresholdBinaryInv].
  VisionResult<VisionImage> thresholdBinaryInv(
    VisionImage image,
    int thresh,
    int maxval,
  ) => _runtime.thresholdBinaryInv(image, thresh, maxval);

  /// See [VisionRuntime.matchTemplate].
  VisionResult<TemplateMatch> matchTemplate(
    VisionImage image,
    VisionImage template,
  ) => _runtime.matchTemplate(image, template);

  /// See [VisionRuntime.findInRangeRow].
  VisionResult<int?> findInRangeRow(
    VisionImage image,
    int row,
    int startX,
    List<int> lo,
    List<int> hi,
  ) => _runtime.findInRangeRow(image, row, startX, lo, hi);
}

/// The image a job works on. Pixels are only reachable inside [withImage], so
/// a lent frame's memory cannot outlive its lending scope.
final class VisionJobInput {
  /// A lent capture frame; its pixels are viewed as BGRX, 4 channels.
  VisionJobInput.frame(CaptureFrame frame) : _frame = frame, _image = null;

  /// An image the worker owns outright.
  VisionJobInput.image(VisionImage image) : _frame = null, _image = image;

  final CaptureFrame? _frame;
  final VisionImage? _image;

  /// Provenance of the frame, or null for an owned image.
  CaptureFrameMetadata? get frameMetadata => _frame?.metadata;

  /// Runs [use] over the image. For a frame the [VisionImage] views the lent
  /// native pixels (BGRX, 4 channels, the frame's stride); it is valid only
  /// until [use] returns, and [use] must be synchronous and must not keep the
  /// image or its bytes. Copy anything that must survive.
  R withImage<R>(R Function(VisionImage image) use) {
    final frame = _frame;
    if (frame != null) {
      final metadata = frame.metadata;
      return frame.withPixels(
        (pixels) => use(
          VisionImage(
            pixels,
            width: metadata.width,
            height: metadata.height,
            stride: metadata.stride,
            channels: 4,
          ),
        ),
      );
    }
    return use(_image!);
  }
}

/// What a submitter receives for one request. Timestamps are monotonic QPC
/// ticks from the capture DLL's clock.
sealed class VisionAnswer<R> {
  const VisionAnswer(this.submittedQpc);

  /// When the request was submitted.
  final int submittedQpc;
}

/// The job ran and returned [result].
final class VisionDelivered<R> extends VisionAnswer<R> {
  const VisionDelivered(
    this.result, {
    required int submittedQpc,
    required this.startedQpc,
    required this.finishedQpc,
  }) : super(submittedQpc);

  final R result;

  /// When the worker started the job.
  final int startedQpc;

  /// When the job returned.
  final int finishedQpc;
}

/// A request that was answered without a result. Superseded, invalidated,
/// deadline, closed, unavailable and invalid-input answers carry only the
/// submission time: no job started or finished.
sealed class VisionNotDelivered<R> extends VisionAnswer<R> {
  const VisionNotDelivered(super.submittedQpc);
}

/// A newer request replaced this one before it started.
final class VisionSuperseded<R> extends VisionNotDelivered<R> {
  const VisionSuperseded(super.submittedQpc);
}

/// The generation advanced (for example the game window changed) before the
/// request started or while it ran, so its result was discarded.
final class VisionInvalidated<R> extends VisionNotDelivered<R> {
  const VisionInvalidated(super.submittedQpc);
}

/// The request outlived its deadline. This is the worker-level answer
/// `visionTimeout`, distinct from the step-level [VisionTimeout] failure.
final class VisionDeadlineExceeded<R> extends VisionNotDelivered<R> {
  const VisionDeadlineExceeded(super.submittedQpc);
}

/// The service was closed, or was closing, when the request was answered.
final class VisionClosed<R> extends VisionNotDelivered<R> {
  const VisionClosed(super.submittedQpc);
}

/// The worker cannot run jobs. [reason] is a human-readable description;
/// [failure] is the runtime's typed failure when the cause was a runtime open
/// failure, otherwise null.
final class VisionUnavailableAnswer<R> extends VisionNotDelivered<R> {
  const VisionUnavailableAnswer(
    super.submittedQpc,
    this.reason, {
    this.failure,
  });

  final String reason;
  final VisionFailure? failure;
}

/// The submitted owned image violated the buffer contract; nothing was
/// admitted.
final class VisionInvalidInput<R> extends VisionNotDelivered<R> {
  const VisionInvalidInput(super.submittedQpc, [this.detail = '']);

  final String detail;
}

/// A template given to the service is not a valid 1-channel image.
final class VisionInvalidTemplate<R> extends VisionNotDelivered<R> {
  const VisionInvalidTemplate(super.submittedQpc, this.name);

  /// The offending template's name.
  final String name;
}

/// The job ran and threw. The worker stays ready.
final class VisionJobFailed<R> extends VisionAnswer<R> {
  const VisionJobFailed(
    this.description, {
    required int submittedQpc,
    required this.startedQpc,
    required this.finishedQpc,
  }) : super(submittedQpc);

  /// The error description, never the exception object.
  final String description;
  final int startedQpc;
  final int finishedQpc;
}

/// The job ran and ended with a runtime [VisionFailure] (see
/// [VisionJobAbort]). The worker stays ready.
final class VisionFailureAnswer<R> extends VisionAnswer<R> {
  const VisionFailureAnswer(
    this.failure, {
    required int submittedQpc,
    required this.startedQpc,
    required this.finishedQpc,
  }) : super(submittedQpc);

  final VisionFailure failure;
  final int startedQpc;
  final int finishedQpc;
}
