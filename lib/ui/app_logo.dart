import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// The bundled compiled vector of the application icon.
const appLogoAsset = 'assets/app_icon/app_icon.vec';

/// Draws the Blackgrid application icon at a fixed square [size].
///
/// The logo is decorative: it adds no semantics node. While the asset loads,
/// and if it fails to load, it shows an empty box of the same size so the
/// surrounding layout never moves. A failed load is handled here and never
/// reaches the framework error handler.
class AppLogo extends StatefulWidget {
  /// Creates a logo of [size] logical pixels on each side.
  ///
  /// [load] replaces the default asset bundle read of [appLogoAsset]; tests
  /// use it to supply bytes or a failure.
  const AppLogo({super.key, this.size = 32, this.load});

  /// The width and height of the logo.
  final double size;

  /// Reads the compiled vector bytes, or `null` to read [appLogoAsset].
  final Future<ByteData> Function(BuildContext context)? load;

  @override
  State<AppLogo> createState() => _AppLogoState();
}

class _AppLogoState extends State<AppLogo> {
  bool _started = false;
  ByteData? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final load =
        widget.load ??
        (context) => DefaultAssetBundle.of(context).load(appLogoAsset);
    load(context).then<void>(
      (bytes) {
        if (mounted) setState(() => _bytes = bytes);
      },
      onError: (Object _) {
        // The box stays empty; see the class documentation.
      },
    );
  }

  @override
  Widget build(BuildContext context) => switch (_bytes) {
    final bytes? => VectorGraphic(
      loader: _LoadedBytes(bytes),
      width: widget.size,
      height: widget.size,
      excludeFromSemantics: true,
    ),
    null => SizedBox.square(dimension: widget.size),
  };
}

/// A [BytesLoader] over bytes already in memory, so it cannot fail.
class _LoadedBytes extends BytesLoader {
  const _LoadedBytes(this.bytes);

  final ByteData bytes;

  @override
  Future<ByteData> loadBytes(BuildContext? context) async => bytes;

  @override
  Object cacheKey(BuildContext? context) => appLogoAsset;
}
