import 'package:flutter/material.dart';

import '../application/app_services.dart';
import 'ember/theme_access.dart';
import 'map_workspace.dart';

/// The Map screen: the map takes the whole main column.
///
/// The map's controls are drawn over the map by [MapWorkspace], and the
/// shell's inspector holds the working lists. The only text below the map is a
/// settings save failure or load notice the player has to act on; debug
/// status lives in Settings under Diagnostics.
class MapScreen extends StatelessWidget {
  /// Creates the screen for [services].
  const MapScreen({super.key, required this.services});

  /// The services whose map and settings the screen shows.
  final AppServices services;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        // One semantic region: the controls, marker targets and popup are
        // updated together. Without the boundary, closing the marker popup
        // with Escape tripped a Flutter semantics assertion once the rail no
        // longer sat beside the map (map_viewport_test).
        child: Semantics(
          container: true,
          child: MapWorkspace(services: services),
        ),
      ),
      ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) {
          final style = TextStyle(color: context.ember.errInk);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (services.settings.error != null)
                Text(services.settings.error!, style: style),
              if (services.settings.loadNotice != null)
                Text(services.settings.loadNotice!, style: style),
            ],
          );
        },
      ),
    ],
  );
}
