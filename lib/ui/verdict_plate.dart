import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../domain/decision.dart';
import '../domain/roubles.dart';
import 'ember/blackgrid_tokens.dart';
import 'ember/theme_access.dart';
import 'labels.dart' show recommendationLabel;

/// Draws a 1px dashed border with soft corners around its box, in [color].
///
/// In Ember a dashed border means a missing or broken value. The colour is
/// exposed so a test can read it without comparing pixels.
class DashedBorderPainter extends CustomPainter {
  /// Creates a painter for a dashed border in [color].
  const DashedBorderPainter({
    required this.color,
    this.radius = 8,
    this.dash = 5,
    this.gap = 3,
  });

  /// The colour of the dashes.
  final Color color;

  /// The corner radius of the border.
  final double radius;

  /// The length of one dash.
  final double dash;

  /// The space between two dashes.
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    for (final PathMetric metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        canvas.drawPath(metric.extractPath(at, at + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}

/// The 44px plate that carries a verdict word.
///
/// Each verdict has its own style, taken from the room's theme (DESIGN.md X1).
/// Flea and Trader add the price that decided them, set in ink after the word.
/// No plate uses the accent.
class VerdictPlate extends StatelessWidget {
  /// Creates the plate for [decision].
  const VerdictPlate({super.key, required this.decision});

  /// The decision whose verdict is shown.
  final ItemDecision decision;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final green = context.blackgrid;
    final recommendation = decision.recommendation;
    final (fill, border, text) = switch (recommendation) {
      Recommendation.keep => (green.okFill, null, green.okOnFill),
      Recommendation.keepForLater => (green.okBg, green.okLine, green.okStrong),
      Recommendation.check => (ember.warnBg, ember.warnLine, ember.warnStrong),
      Recommendation.flea || Recommendation.trader => (
        ember.raised,
        ember.hairline,
        ember.inkSecondary,
      ),
      Recommendation.priceUnavailable => (null, null, ember.inkSecondary),
    };
    final price = switch (recommendation) {
      Recommendation.flea => decision.fleaGross,
      Recommendation.trader => decision.traderGross,
      _ => null,
    };
    final dashed = recommendation == Recommendation.priceUnavailable;
    final content = Align(
      // Hug the content's width; the plate's height is fixed at 44.
      widthFactor: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                recommendationLabel(recommendation),
                key: const Key('recommendation'),
                style: BlackgridType.verdict.copyWith(color: text),
              ),
            ),
            if (price != null) ...[
              const SizedBox(width: 10),
              Text(
                rub(price),
                key: const Key('verdict-price'),
                style: BlackgridType.verdict.copyWith(color: ember.ink),
              ),
            ],
          ],
        ),
      ),
    );
    return Container(
      key: const Key('verdict-plate'),
      height: 44,
      decoration: dashed
          ? null
          : BoxDecoration(
              color: fill,
              border: border == null ? null : Border.all(color: border),
              borderRadius: BorderRadius.circular(8),
            ),
      child: dashed
          ? CustomPaint(
              painter: DashedBorderPainter(color: ember.inkTertiary),
              child: content,
            )
          : content,
    );
  }
}
