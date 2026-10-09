// consoly_monitor is a dev_dependency, so only this dev entrypoint imports it.
// Run with: flutter run -t lib/main_dev.dart
// ignore_for_file: depend_on_referenced_packages
import 'package:consoly_monitor/consoly_monitor.dart';
import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  ConsolyMonitor.init(logLevel: ConsolyLogLevel.verbose);
  runApp(
    ExampleApp(
      navigatorObservers: [ConsolyNavigatorObserver()],
      builder: ConsolyMonitor.builder,
    ),
  );
}
