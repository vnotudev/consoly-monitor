import 'package:consoly_monitor/consoly_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('detail'));
}

void main() {
  final monitor = ConsolyMonitor.instance;
  final navKey = GlobalKey<NavigatorState>();

  setUp(() {
    monitor.reset();
    ConsolyMonitor.init(
      enabled: true,
      interceptHttp: false,
      logLevel: ConsolyLogLevel.none,
    );
  });

  Widget app() => MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [ConsolyNavigatorObserver()],
        builder: ConsolyMonitor.builder,
        routes: {
          '/': (_) => const Scaffold(body: Text('home')),
          '/settings': (_) => const Scaffold(body: Text('settings')),
        },
      );

  List<String> names() => monitor.visits.map((v) => v.name).toList();

  testWidgets('tracks named routes, pops and dialogs', (tester) async {
    await tester.pumpWidget(app());
    expect(monitor.currentVisit!.name, '/');

    monitor.startCall('GET', Uri.parse('https://api.test/home'));

    navKey.currentState!.pushNamed('/settings');
    await tester.pumpAndSettle();
    monitor.startCall('GET', Uri.parse('https://api.test/settings'));

    // A dialog is not a page: calls go to the page underneath.
    showDialog<void>(
      context: navKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('hi')),
    );
    await tester.pumpAndSettle();
    monitor.startCall('GET', Uri.parse('https://api.test/dialog'));
    navKey.currentState!.pop();
    await tester.pumpAndSettle();

    navKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(names(), ['(launch)', '/', '/settings', '/']);
    final settings = monitor.summarizeByPage()['/settings']!;
    expect(settings.calls, 2);
    expect(monitor.summarizeByPage()['/']!.calls, 1);
  });

  testWidgets('infers the page widget name for unnamed routes', (tester) async {
    await tester.pumpWidget(app());
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const DetailPage()),
    );
    await tester.pumpAndSettle();
    expect(monitor.currentVisit!.name, 'DetailPage');
  });

  testWidgets('overlay bubble opens the panel', (tester) async {
    await tester.pumpWidget(app());
    monitor.logCall(
      method: 'GET',
      uri: Uri.parse('https://api.test/users'),
      statusCode: 200,
      duration: const Duration(milliseconds: 120),
    );
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('API'));
    await tester.pumpAndSettle();
    expect(find.text('Consoly Monitor'), findsOneWidget);
    expect(find.text('/users'), findsOneWidget);

    await tester.tap(find.text('/users'));
    await tester.pumpAndSettle();
    expect(find.text('Copy cURL'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.text('1×'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Consoly Monitor'), findsNothing);
  });

  testWidgets('builder is a pass-through when disabled', (tester) async {
    monitor.reset();
    ConsolyMonitor.init(enabled: false);
    await tester.pumpWidget(app());
    expect(find.byType(ConsolyOverlay), findsNothing);
    expect(monitor.visits, isEmpty);
  });
}
