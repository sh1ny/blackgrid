part of 'vision_service.dart';

// --- Messages (all sendable plain data) ---

/// A template as it crosses the isolate boundary: the bytes are copied into a
/// [TransferableTypedData] when the service is constructed.
final class _TemplateInit {
  _TemplateInit.copy(VisionTemplate template)
    : name = template.name,
      bytes = TransferableTypedData.fromList([template.image.bytes]),
      width = template.image.width,
      height = template.image.height,
      stride = template.image.stride,
      channels = template.image.channels;

  final String name;
  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int stride;
  final int channels;

  VisionTemplate materialize() => VisionTemplate(
    name,
    VisionImage(
      bytes.materialize().asUint8List(),
      width: width,
      height: height,
      stride: stride,
      channels: channels,
    ),
  );
}

/// An owned image as it crosses the isolate boundary.
final class _OwnedImageInit {
  _OwnedImageInit.copy(VisionImage image)
    : bytes = TransferableTypedData.fromList([image.bytes]),
      width = image.width,
      height = image.height,
      stride = image.stride,
      channels = image.channels;

  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int stride;
  final int channels;

  VisionImage materialize() => VisionImage(
    bytes.materialize().asUint8List(),
    width: width,
    height: height,
    stride: stride,
    channels: channels,
  );
}

final class _WorkerInit {
  const _WorkerInit({
    required this.replyTo,
    required this.runtimeDirectory,
    required this.opener,
    required this.platformFactory,
    required this.registryFactory,
    required this.jobFactory,
    required this.templates,
  });

  final SendPort replyTo;
  final String runtimeDirectory;
  final VisionNativeOpener opener;
  final CapturePlatformFactory platformFactory;
  final FrameRegistryFactory registryFactory;

  // Covariant on purpose: the service only sends parameters of its own `P`.
  final VisionJob<Object?, Object?> Function() jobFactory;
  final List<_TemplateInit> templates;
}

final class _Run {
  const _Run(this.seq, this.params, this.image, this.ticket);

  final int seq;
  final Object? params;

  /// Exactly one of [image] and [ticket] is set. A ticket's frame belongs to
  /// the worker from the moment it is sent.
  final _OwnedImageInit? image;
  final CaptureFrameTicket? ticket;
}

final class _Close {
  const _Close();
}

final class _Ready {
  const _Ready(this.commands);

  final SendPort commands;
}

/// The worker could not become ready; exactly one of [failure] and
/// [templateName] is set unless the cause was neither (then only [reason]).
final class _OpenFailed {
  const _OpenFailed(this.reason, {this.failure, this.templateName});

  final String reason;
  final VisionFailure? failure;
  final String? templateName;

  VisionStartFailure toFailure() {
    final failure = this.failure;
    final templateName = this.templateName;
    if (failure != null) return VisionRuntimeStartFailure(failure);
    if (templateName != null) {
      return VisionInvalidTemplateStart(templateName, reason);
    }
    return VisionWorkerStartFailure(reason);
  }
}

/// The worker's answer to one [_Run]. The input was released before it was
/// sent, and [startedQpc] and [finishedQpc] bracket the job on the worker's
/// clock.
sealed class _Reply {
  const _Reply(this.seq, this.startedQpc, this.finishedQpc);

  final int seq;
  final int startedQpc;
  final int finishedQpc;
}

/// The job returned [result].
final class _ResultReply extends _Reply {
  const _ResultReply(super.seq, this.result, super.started, super.finished);

  final Object? result;
}

/// The job threw; [description] is the error text, never the object.
final class _JobFailedReply extends _Reply {
  const _JobFailedReply(
    super.seq,
    this.description,
    super.started,
    super.finished,
  );

  final String description;
}

/// The job threw [VisionJobAbort] with a typed [failure].
final class _FailureReply extends _Reply {
  const _FailureReply(super.seq, this.failure, super.started, super.finished);

  final VisionFailure failure;
}

// --- Worker isolate ---

void _visionWorkerMain(_WorkerInit init) {
  final int Function() qpcNow;
  try {
    qpcNow = init.platformFactory().qpcNow;
  } on Object catch (error) {
    init.replyTo.send(_OpenFailed('Capture platform cannot open: $error'));
    return;
  }

  final runtime = VisionRuntime.open(
    runtimeDirectory: init.runtimeDirectory,
    opener: init.opener,
  );
  if (runtime.status case VisionUnavailable(:final failure)) {
    init.replyTo.send(_OpenFailed(failure.message, failure: failure));
    return;
  }

  final templates = <String, VisionTemplate>{};
  for (final item in init.templates) {
    final template = item.materialize();
    final problem = _templateProblem(template.image);
    if (problem != null) {
      runtime.dispose();
      init.replyTo.send(_OpenFailed(problem, templateName: item.name));
      return;
    }
    templates[item.name] = template;
  }

  final job = init.jobFactory();
  final context = VisionJobContext(
    runtime,
    templates: templates,
    qpcNow: qpcNow,
  );
  FrameRegistry? registry;
  final commands = RawReceivePort();
  commands.handler = (Object? message) {
    switch (message) {
      case _Run():
        final ticket = message.ticket;
        // Adopted before anything can throw, so the frame is always released.
        final frame = ticket == null
            ? null
            : CaptureFrame.adopt(ticket, registry ??= init.registryFactory());
        final started = qpcNow();
        final seq = message.seq;
        _Reply reply;
        try {
          final result = job.run(
            context,
            frame != null
                ? VisionJobInput.frame(frame)
                : VisionJobInput.image(message.image!.materialize()),
            message.params,
          );
          reply = _ResultReply(seq, result, started, qpcNow());
        } on VisionJobAbort catch (abort) {
          reply = _FailureReply(seq, abort.failure, started, qpcNow());
        } on Object catch (error) {
          reply = _JobFailedReply(seq, '$error', started, qpcNow());
        } finally {
          // Released before the reply on every path.
          frame?.release();
        }
        try {
          init.replyTo.send(reply);
        } on Object {
          // The result cannot cross the isolate boundary (a port, a closure
          // over one, a native handle). The worker stays ready.
          init.replyTo.send(
            _JobFailedReply(
              seq,
              'result is not sendable',
              reply.startedQpc,
              reply.finishedQpc,
            ),
          );
        }
        // After the reply, so the answer does not wait; the next request is
        // not received until this returns.
        runtime.trimScratch();
      case _Close():
        runtime.dispose();
        commands.close();
      default:
        break;
    }
  };
  init.replyTo.send(_Ready(commands.sendPort));
}

/// Null when [image] is a usable template: valid layout, exactly 1 channel and
/// not all one value. (`VisionImage.validateTemplate` needs a target image, so
/// the size check stays per match.)
String? _templateProblem(VisionImage image) {
  final invalid = image.validate();
  if (invalid != null) return invalid.reason;
  if (image.channels != 1) {
    return 'expected 1 channel, got ${image.channels}';
  }
  final first = image.bytes[0];
  for (var y = 0; y < image.height; y++) {
    final row = y * image.stride;
    for (var x = 0; x < image.width; x++) {
      if (image.bytes[row + x] != first) return null;
    }
  }
  return 'zero variance: every pixel is $first';
}
