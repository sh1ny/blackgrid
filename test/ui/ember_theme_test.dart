import 'dart:io';

import 'package:blackgrid/ui/ember/blackgrid_tokens.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the token copy is byte-identical to the brand kit file', () {
    final kit = File('brand/flutter/ember_tokens.dart').readAsBytesSync();
    final copy = File('lib/ui/ember/ember_tokens.dart').readAsBytesSync();
    expect(copy, kit, reason: 'recopy brand/flutter/ember_tokens.dart');
  });

  test('dark room carries the dark token values', () {
    final theme = blackgridTheme(Brightness.dark);
    final ember = theme.extension<EmberColors>()!;
    final blackgrid = theme.extension<BlackgridColors>()!;
    expect(theme.brightness, Brightness.dark);
    expect(ember, same(EmberColors.dark));
    expect(ember.canvas, const Color(0xFF0C0C0E));
    expect(ember.panel, const Color(0xFF121215));
    expect(ember.ink, const Color(0xFFE8E6E1));
    expect(ember.raised, const Color(0xFF18181C));
    expect(ember.accent, const Color(0xFFE9A14B));
    expect(ember.hairline, const Color(0x12FFFFFF));
    expect(theme.colorScheme.surface, ember.canvas);
    expect(theme.colorScheme.onSurface, ember.ink);
    expect(theme.colorScheme.primary, ember.accent);
    expect(theme.scaffoldBackgroundColor, ember.canvas);
    expect(blackgrid, same(BlackgridColors.dark));
    expect(blackgrid.okFill, const Color(0xFF6FCF8E));
    expect(blackgrid.okOnFill, const Color(0xFF0C0C0E));
    expect(blackgrid.okBg, const Color(0x1A6FCF8E));
    expect(blackgrid.okLine, const Color(0x526FCF8E));
    expect(blackgrid.okInk, const Color(0xFFA6E3BA));
    expect(blackgrid.okStrong, const Color(0xFFCDEED8));
  });

  test('light room carries the light token values', () {
    final theme = blackgridTheme(Brightness.light);
    final ember = theme.extension<EmberColors>()!;
    final blackgrid = theme.extension<BlackgridColors>()!;
    expect(theme.brightness, Brightness.light);
    expect(ember, same(EmberColors.light));
    expect(ember.canvas, const Color(0xFFF7F6F3));
    expect(ember.panel, const Color(0xFFEFEDE9));
    expect(ember.ink, const Color(0xFF1D1B18));
    expect(ember.raised, const Color(0xFFFFFFFF));
    expect(ember.accent, const Color(0xFFD98A2B));
    expect(ember.hairline, const Color(0x171E1810));
    expect(ember.accentText, const Color(0xFF8A4C05));
    expect(theme.colorScheme.surface, ember.canvas);
    expect(theme.colorScheme.onSurface, ember.ink);
    expect(theme.colorScheme.primary, ember.accent);
    expect(theme.scaffoldBackgroundColor, ember.canvas);
    expect(blackgrid, same(BlackgridColors.light));
    expect(blackgrid.okFill, const Color(0xFF1F6B3B));
    expect(blackgrid.okOnFill, const Color(0xFFFFFFFF));
    expect(blackgrid.okBg, const Color(0xFFE8F5EC));
    expect(blackgrid.okLine, const Color(0xFFB5DCC2));
    expect(blackgrid.okInk, const Color(0xFF1F6B3B));
    expect(blackgrid.okStrong, const Color(0xFF154D2A));
  });

  test('map ground is the same in both rooms', () {
    const ground = Color(0xFF0C0C0E);
    expect(BlackgridColors.dark.mapGround, ground);
    expect(BlackgridColors.light.mapGround, ground);
    for (final brightness in Brightness.values) {
      final extension = blackgridTheme(brightness)
          .extension<BlackgridColors>()!;
      expect(extension.mapGround, ground);
    }
  });

  test('body text uses Geist and title roles use Literata', () {
    for (final brightness in Brightness.values) {
      final text = blackgridTheme(brightness).textTheme;
      expect(text.bodyMedium!.fontFamily, 'Geist');
      expect(text.titleSmall!.fontFamily, 'Geist');
      expect(text.labelLarge!.fontFamily, 'Geist');
      expect(text.labelSmall!.fontFamily, 'Geist');
      expect(text.displaySmall!.fontFamily, 'Literata');
      expect(text.headlineSmall!.fontFamily, 'Literata');
      expect(text.titleLarge!.fontFamily, 'Literata');
      expect(text.bodyLarge!.fontFamily, 'Literata');
    }
    expect(BlackgridType.verdict.fontFamily, 'Geist');
    expect(BlackgridType.verdict.fontWeight, FontWeight.w600);
    expect(BlackgridType.verdict.fontSize, 22);
    expect(BlackgridType.verdict.height, 1.2);
  });
}
