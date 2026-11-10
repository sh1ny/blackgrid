import 'package:flutter/material.dart';

import 'app_logo.dart';

/// The Blackgrid brand lockup: the hex logo, the `BLACKGRID` wordmark and the
/// `TRACK. PLAN. SURVIVE.` tagline.
///
/// This is the only place where Ember's no-capitals rule is lifted (DESIGN.md
/// X9). The logo stays decorative and adds no semantics node.
class BrandLockup extends StatelessWidget {
  /// Creates the top bar lockup: a 32 px logo beside the wordmark with the
  /// tagline under it.
  ///
  /// With [compact] the lockup keeps only the logo.
  const BrandLockup.topBar({super.key, this.compact = false})
    : _startup = false;

  /// Creates the startup lockup: a 54 px logo above the wordmark, with the
  /// tagline below it.
  const BrandLockup.startup({super.key}) : compact = false, _startup = true;

  /// Whether the top bar lockup drops the wordmark and tagline.
  final bool compact;

  final bool _startup;

  static const _wordmark = 'BLACKGRID';
  static const _tagline = 'TRACK. PLAN. SURVIVE.';

  @override
  Widget build(BuildContext context) {
    if (_startup) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLogo(size: 54),
          SizedBox(height: 20),
          Text(
            _wordmark,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(_tagline, style: TextStyle(fontSize: 8)),
        ],
      );
    }
    if (compact) return const AppLogo();
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(),
        SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_wordmark),
            Text(_tagline, style: TextStyle(fontSize: 8)),
          ],
        ),
      ],
    );
  }
}
