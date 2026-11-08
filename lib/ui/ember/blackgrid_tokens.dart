import 'package:flutter/material.dart';

import 'ember_tokens.dart';

/// Blackgrid's own colour roles, kept out of the shared Ember kit.
///
/// The values are the `ok-*` and `map-ground` entries in the DESIGN.md
/// frontmatter. Read them with
/// `Theme.of(context).extension<BlackgridColors>()!`.
@immutable
class BlackgridColors extends ThemeExtension<BlackgridColors> {
  /// Creates a set of Blackgrid colour roles.
  const BlackgridColors({
    required this.okFill,
    required this.okOnFill,
    required this.okBg,
    required this.okLine,
    required this.okInk,
    required this.okStrong,
    required this.mapGround,
  });

  /// The solid green behind the Keep verdict.
  final Color okFill;

  /// Text on [okFill].
  final Color okOnFill;

  /// The soft green fill behind the Keep for later verdict.
  final Color okBg;

  /// The border of the Keep for later plate.
  final Color okLine;

  /// Green used as text or an icon on the room's surfaces.
  final Color okInk;

  /// The strong green text on [okBg].
  final Color okStrong;

  /// The ground the map is drawn on, the same dark colour in both rooms.
  final Color mapGround;

  /// The dark room's values.
  static const BlackgridColors dark = BlackgridColors(
    okFill: Color(0xFF6FCF8E),
    okOnFill: Color(0xFF0C0C0E),
    okBg: Color(0x1A6FCF8E),
    okLine: Color(0x526FCF8E),
    okInk: Color(0xFFA6E3BA),
    okStrong: Color(0xFFCDEED8),
    mapGround: Color(0xFF0C0C0E),
  );

  /// The light room's values.
  static const BlackgridColors light = BlackgridColors(
    okFill: Color(0xFF1F6B3B),
    okOnFill: Color(0xFFFFFFFF),
    okBg: Color(0xFFE8F5EC),
    okLine: Color(0xFFB5DCC2),
    okInk: Color(0xFF1F6B3B),
    okStrong: Color(0xFF154D2A),
    mapGround: Color(0xFF0C0C0E),
  );

  @override
  BlackgridColors copyWith({
    Color? okFill,
    Color? okOnFill,
    Color? okBg,
    Color? okLine,
    Color? okInk,
    Color? okStrong,
    Color? mapGround,
  }) => BlackgridColors(
    okFill: okFill ?? this.okFill,
    okOnFill: okOnFill ?? this.okOnFill,
    okBg: okBg ?? this.okBg,
    okLine: okLine ?? this.okLine,
    okInk: okInk ?? this.okInk,
    okStrong: okStrong ?? this.okStrong,
    mapGround: mapGround ?? this.mapGround,
  );

  @override
  BlackgridColors lerp(ThemeExtension<BlackgridColors>? other, double t) {
    if (other is! BlackgridColors) return this;
    return BlackgridColors(
      okFill: Color.lerp(okFill, other.okFill, t)!,
      okOnFill: Color.lerp(okOnFill, other.okOnFill, t)!,
      okBg: Color.lerp(okBg, other.okBg, t)!,
      okLine: Color.lerp(okLine, other.okLine, t)!,
      okInk: Color.lerp(okInk, other.okInk, t)!,
      okStrong: Color.lerp(okStrong, other.okStrong, t)!,
      mapGround: Color.lerp(mapGround, other.mapGround, t)!,
    );
  }
}

/// Blackgrid's own type roles, kept out of the shared Ember kit.
abstract final class BlackgridType {
  /// The verdict word on a plate: Geist 600, 22px, line height 1.2.
  static const TextStyle verdict = TextStyle(
    fontFamily: EmberType.sans,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}
