import 'dart:async';

// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../data/database.dart' show NewerDatabaseException;
import 'app_logo.dart';
import 'shell.dart';
import 'theme.dart';

class BlackgridApp extends StatelessWidget {
  const BlackgridApp({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Blackgrid',
    debugShowCheckedModeBanner: false,
    theme: blackgridTheme(),
    home: BlackgridShell(services: services),
  );
}

/// Whether [error] is, or wraps, a [NewerDatabaseException].
///
/// A second query on a database opened in a background isolate delivers the
/// exception wrapped twice in [DriftRemoteException]: once by the isolate
/// response and once by Drift's cached migration error. Unwrapping follows
/// only that form.
bool isNewerDatabaseError(Object? error) {
  var current = error;
  while (current is DriftRemoteException) {
    current = current.remoteCause;
  }
  return current is NewerDatabaseException;
}

class BlackgridBootstrap extends StatefulWidget {
  const BlackgridBootstrap({super.key, this.open = AppServices.open});

  /// Opens local storage; replaced in tests.
  final Future<AppServices> Function() open;

  @override
  State<BlackgridBootstrap> createState() => _BlackgridBootstrapState();
}

class _BlackgridBootstrapState extends State<BlackgridBootstrap> {
  late Future<AppServices> _opening = widget.open();
  AppServices? _services;
  @override
  void dispose() {
    final services = _services;
    if (services != null) unawaited(services.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppServices>(
    future: _opening,
    builder: (context, snapshot) {
      final services = snapshot.data;
      if (services != null) {
        _services = services;
        return BlackgridApp(services: services);
      }
      return MaterialApp(
        title: 'Blackgrid',
        debugShowCheckedModeBanner: false,
        theme: blackgridTheme(),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppLogo(size: 54),
                      const SizedBox(height: 20),
                      const Text(
                        'BLACKGRID',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!snapshot.hasError)
                        const CircularProgressIndicator()
                      else ...[
                        Text(
                          isNewerDatabaseError(snapshot.error)
                              ? 'Your data was saved by a newer version of Blackgrid. Install that version or a later one to open it. Your data has not been changed.'
                              : 'Local storage or current-user protection could not be opened. Existing data is not reset, downgraded or deleted.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: () =>
                              setState(() => _opening = widget.open()),
                          child: const Text('Retry opening local storage'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
