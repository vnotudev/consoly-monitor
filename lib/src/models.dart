import 'dart:convert';

/// A single HTTP request observed by Consoly Monitor.
class ApiCall {
  ApiCall({
    required this.id,
    required this.method,
    required this.uri,
    required this.visit,
    required this.startedAt,
  });

  /// Monotonic id, unique for the lifetime of the app.
  final int id;

  /// Upper-case HTTP method, e.g. `GET`.
  final String method;

  final Uri uri;

  /// The page visit that was on screen when the request started.
  final PageVisit visit;

  final DateTime startedAt;

  Map<String, String> requestHeaders = const {};
  String? requestBody;
  int requestSize = 0;

  int? statusCode;
  Map<String, String> responseHeaders = const {};
  String? responseBody;
  int? responseSize;

  /// When the response finished (or failed). `null` while pending.
  DateTime? endedAt;

  /// Set when the request failed before a response was received.
  String? error;

  /// The page name, as shown in the UI and console.
  String get page => visit.name;

  bool get isPending => endedAt == null && error == null;

  bool get isError =>
      error != null || (statusCode != null && statusCode! >= 400);

  Duration? get duration => endedAt?.difference(startedAt);

  /// `METHOD host/path` without query, used to group identical endpoints.
  String get endpoint => '$method ${uri.host}${uri.path}';

  String? get responseContentType => _header(responseHeaders, 'content-type');

  /// Renders the request as a `curl` command that can be pasted in a shell.
  String toCurl() {
    final b = StringBuffer("curl -X $method '${uri.toString()}'");
    requestHeaders.forEach((k, v) {
      if (k.toLowerCase() == 'content-length') return;
      b.write(" \\\n  -H '${_shellEscape('$k: $v')}'");
    });
    final body = requestBody;
    if (body != null && body.isNotEmpty) {
      b.write(" \\\n  --data '${_shellEscape(body)}'");
    }
    return b.toString();
  }

  /// One-line summary used in console logs.
  String toLogLine() {
    final status = error != null ? 'ERR' : (statusCode?.toString() ?? '...');
    final ms = duration == null ? '' : ' ${duration!.inMilliseconds}ms';
    final size = responseSize == null ? '' : ' ${formatBytes(responseSize!)}';
    return '$method $status $uri$ms$size${error != null ? ' ($error)' : ''}';
  }

  static String _shellEscape(String s) => s.replaceAll("'", r"'\''");
}

/// One visit to a page: from the moment it became the top route until
/// another page replaced it.
class PageVisit {
  PageVisit({required this.id, required this.name, required this.enteredAt});

  final int id;
  String name;
  final DateTime enteredAt;
  DateTime? leftAt;
  final List<ApiCall> calls = [];

  bool get isActive => leftAt == null;
  int get errorCount => calls.where((c) => c.isError).length;
}

/// Aggregated numbers for a page across all of its visits.
class PageSummary {
  PageSummary(this.page);

  final String page;
  int visits = 0;
  int calls = 0;
  int errors = 0;
  Duration totalDuration = Duration.zero;
  int _timedCalls = 0;

  /// Number of calls per endpoint (`METHOD host/path`).
  final Map<String, int> endpoints = {};

  Duration? get averageDuration => _timedCalls == 0
      ? null
      : Duration(microseconds: totalDuration.inMicroseconds ~/ _timedCalls);

  void add(ApiCall call) {
    calls++;
    if (call.isError) errors++;
    final d = call.duration;
    if (d != null) {
      totalDuration += d;
      _timedCalls++;
    }
    endpoints[call.endpoint] = (endpoints[call.endpoint] ?? 0) + 1;
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

String? _header(Map<String, String> headers, String name) {
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == name) return e.value;
  }
  return null;
}

/// Turns captured bytes into something readable for the UI and console.
String decodeBody(
  List<int> bytes, {
  required int totalSize,
  String? contentType,
}) {
  if (totalSize == 0) return '';
  final type = (contentType ?? '').toLowerCase();
  final looksBinary = type.startsWith('image/') ||
      type.startsWith('video/') ||
      type.startsWith('audio/') ||
      type.contains('octet-stream') ||
      type.contains('protobuf') ||
      type.contains('pdf');
  if (looksBinary) return '<binary ${formatBytes(totalSize)}>';

  var text = utf8.decode(bytes, allowMalformed: true);
  if (type.contains('json') || text.startsWith('{') || text.startsWith('[')) {
    try {
      text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } catch (_) {
      // Truncated or not JSON after all; show as-is.
    }
  }
  if (bytes.length < totalSize) {
    text += '\n… truncated (${formatBytes(totalSize)} total)';
  }
  return text;
}
