import 'dart:convert';
import 'dart:io';

import 'package:consoly_monitor/consoly_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

// Plain `test`s (no widget binding), so the real dart:io HttpClient is used.
void main() {
  late HttpServer server;
  late Uri base;
  final monitor = ConsolyMonitor.instance;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final res = req.response;
      if (req.uri.path == '/missing') {
        res.statusCode = 404;
      }
      if (req.uri.path == '/logo.png') {
        res.headers.contentType = ContentType('image', 'png');
        res.add([1, 2, 3]);
      } else {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'path': req.uri.path, 'echo': body}));
      }
      await res.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  setUp(() {
    monitor.reset();
    ConsolyMonitor.init(enabled: true, logLevel: ConsolyLogLevel.none);
  });

  Future<String> send(String method, String path, {String? body}) async {
    final client = HttpClient();
    final req = await client.openUrl(method, base.resolve(path));
    req.headers.contentType = ContentType.json;
    if (body != null) req.write(body);
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    client.close();
    return text;
  }

  test('records calls against the current page', () async {
    monitor.enterPage('Home');
    await send('GET', '/users?page=1');
    monitor.enterPage('Checkout');
    await send('POST', '/orders', body: '{"id":7}');
    await send('GET', '/missing');

    final summary = monitor.summarizeByPage();
    expect(summary['Home']!.calls, 1);
    expect(summary['Checkout']!.calls, 2);
    expect(summary['Checkout']!.errors, 1);

    final post = monitor.calls.firstWhere((c) => c.method == 'POST');
    expect(post.page, 'Checkout');
    expect(post.statusCode, 200);
    expect(post.requestBody, contains('"id": 7'));
    expect(post.responseBody, contains('/orders'));
    expect(post.duration, isNotNull);
    expect(
        post.toCurl(), contains("curl -X POST '${base.resolve('/orders')}'"));

    final get = monitor.calls.first;
    expect(get.uri.queryParameters['page'], '1');
  });

  test('response body still reaches the caller unchanged', () async {
    final text = await send('POST', '/echo', body: 'hello');
    expect(jsonDecode(text), {'path': '/echo', 'echo': 'hello'});
  });

  test('ignores images by default and honours ignoreRequest', () async {
    monitor.reset();
    ConsolyMonitor.init(
      enabled: true,
      logLevel: ConsolyLogLevel.none,
      ignoreRequest: (uri) => uri.path == '/health',
    );
    await send('GET', '/logo.png');
    await send('GET', '/health');
    await send('GET', '/data');
    expect(monitor.calls.map((c) => c.uri.path), ['/data']);
  });

  test('records connection failures', () async {
    final client = HttpClient();
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    await expectLater(
      client.getUrl(Uri.parse('http://127.0.0.1:$port/x')),
      throwsA(isA<SocketException>()),
    );
    final call = monitor.calls.single;
    expect(call.isError, isTrue);
    expect(call.error, contains('SocketException'));
  });

  test('build report lists endpoints per page', () async {
    monitor.enterPage('Feed');
    await send('GET', '/posts');
    await send('GET', '/posts');
    final report = monitor.buildReport();
    expect(report, contains('■ Feed'));
    expect(report, contains('2× GET 127.0.0.1/posts'));
  });

  test('disabled monitor records nothing', () async {
    monitor.reset();
    ConsolyMonitor.init(enabled: false);
    await send('GET', '/data');
    expect(monitor.calls, isEmpty);
  });
}
