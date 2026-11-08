import 'package:flutter/material.dart';

import 'blackgrid_tokens.dart';
import 'ember_tokens.dart';

/// Short reads of the colour roles registered by `blackgridTheme`.
///
/// Under a plain [ThemeData] without the extensions (a widget shown on its own
/// in a test or a preview), the roles of the room that matches the theme's
/// brightness are used, so a screen never fails for a missing extension.
extension EmberThemeAccess on BuildContext {
  /// The Ember colour roles of the current room.
  EmberColors get ember {
    final theme = Theme.of(this);
    return theme.extension<EmberColors>() ??
        (theme.brightness == Brightness.dark
            ? EmberColors.dark
            : EmberColors.light);
  }

  /// The Blackgrid colour roles of the current room.
  BlackgridColors get blackgrid {
    final theme = Theme.of(this);
    return theme.extension<BlackgridColors>() ??
        (theme.brightness == Brightness.dark
            ? BlackgridColors.dark
            : BlackgridColors.light);
  }
}
