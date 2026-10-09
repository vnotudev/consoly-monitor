/// Monitor every API call your Flutter app makes, grouped by page.
///
/// ```dart
/// void main() {
///   ConsolyMonitor.init();
///   runApp(MaterialApp(
///     navigatorObservers: [ConsolyNavigatorObserver()],
///     builder: ConsolyMonitor.builder,
///     home: const HomePage(),
///   ));
/// }
/// ```
library;

export 'src/models.dart' show ApiCall, PageVisit, PageSummary;
export 'src/monitor.dart' show ConsolyMonitor, ConsolyLogLevel;
export 'src/navigator_observer.dart' show ConsolyNavigatorObserver;
export 'src/ui/overlay.dart' show ConsolyOverlay;
