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
    required this.jobFactory,
    required this.templates,
  });

  final SendPort replyTo;
  final String runtimeDirectory;
  final VisionNativeOpener opener;
  final CapturePlatformFactory platformFactory;

  // Covariant on purpose: the service only sends parameters of its own `P`.
  final VisionJob<Object?, Object?> Function() jobFactory;
  final List<_TemplateInit> templates;
}

final class _Run {
  const _Run(this.seq, this.image, this.params);

  final int seq;
  final _OwnedImageInit image;
  final Object? params;
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

final class _Reply {
  const _Reply(this.seq, this.result, this.startedQpc, this.finishedQpc);

  final int seq;
  final Object? result;
  final int startedQpc;
  final int finishedQpc;
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
  final commands = RawReceivePort();
  commands.handler = (Object? message) {
    switch (message) {
      case _Run():
        final started = qpcNow();
        final result = job.run(
          context,
          VisionJobInput.image(message.image.materialize()),
          message.params,
        );
        final finished = qpcNow();
        init.replyTo.send(_Reply(message.seq, result, started, finished));
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
