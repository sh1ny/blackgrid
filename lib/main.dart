import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'application/launch_mode.dart';
import 'application/vision_self_check.dart';
import 'ui/app.dart';

Future<void> main(List<String> args) => dispatchLaunch(
  args,
  runUi: () {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const BlackgridBootstrap());
  },
  selfCheck: runVisionSelfCheck,
  exitProcess: exit,
);
