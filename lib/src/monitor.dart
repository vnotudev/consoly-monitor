import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'http/install.dart';
import 'models.dart';
import 'ui/overlay.dart';

/// How much Consoly Monitor prints to the console.
enum ConsolyLogLevel {
  /// Print nothing.
  none,

  /// Print a summary of a page's API calls when the user leaves it.
  summary,

  /// [summary] plus one line per finished call.
  verbose,
}

/// Central registry of page visits and the API calls made during each.
///
/// Call [ConsolyMonitor.init] once before `runApp`, then add
/// [ConsolyNavigatorObserver] to your navigator and [ConsolyMonitor.builder]
/// to your app's `builder`.
class ConsolyMonitor extends ChangeNotifier {
  ConsolyMonitor._();

  static final ConsolyMonitor instance = ConsolyMonitor._();

  static const String launchPageName = '(launch)';

  bool _enabled = false;
  bool _initialized = false;

  /// Whether monitoring is active. Always `false` until [init] is called.
  bool get enabled => _enabled;

  ConsolyLogLevel logLevel = ConsolyLogLevel.summary;

  /// Show the floating bubble and panel from [builder].
  bool showOverlay = true;

  /// Keep responses with an `image/*` content type (e.g. `Image.network`).
  bool trackImages = false;

  /// Maximum number of page visits kept in memory; oldest are dropped.
  int maxVisits = 200;

  /// Maximum number of request/response body bytes kept per call.
  int maxBodyBytes = 64 * 1024;

  /// Return `true` to skip a request entirely.
  bool Function(Uri uri)? ignoreRequest;

  /// Override how a route is named. Return `null` to use the default.
  String? Function(Route<dynamic> route)? routeNameResolver;

  final List<PageVisit> _visits = [];
  int _nextVisitId = 0;
  int _nextCallId = 0;
  Object? _currentRouteKey;

  /// Initializes monitoring. Safe to call more than once.
  ///
  /// [enabled] defaults to `!kReleaseMode`, so the monitor is inert in
  /// release builds even if you forget to remove it.
  ///
  /// With [interceptHttp] (the default) every `dart:io` [HttpClient] created
  /// after this call is observed. That covers `package:http`, `dio`,
  /// `chopper`, `retrofit`, GraphQL clients and anything else built on
  /// `dart:io`. On web, report calls yourself with [logCall].
  static void init({
    bool? enabled,
    bool interceptHttp = true,
    ConsolyLogLevel logLevel = ConsolyLogLevel.summary,
    bool showOverlay = true,
    bool trackImages = false,
    int maxVisits = 200,
    int maxBodyBytes = 64 * 1024,
    bool Function(Uri uri)? ignoreRequest,
    String? Function(Route<dynamic> route)? routeNameResolver,
  }) {
    final m = instance;
    m._enabled = enabled ?? !kReleaseMode;
    m.logLevel = logLevel;
    m.showOverlay = showOverlay;
    m.trackImages = trackImages;
    m.maxVisits = maxVisits;
    m.maxBodyBytes = maxBodyBytes;
    m.ignoreRequest = ignoreRequest;
    m.routeNameResolver = routeNameResolver;
    if (!m._enabled) return;
    if (!m._initialized) {
      m._initialized = true;
      m._visits.add(PageVisit(
        id: m._nextVisitId++,
        name: launchPageName,
        enteredAt: DateTime.now(),
      ));
    }
    if (interceptHttp) installHttpInterceptor();
  }

  /// Pass to `MaterialApp.builder` (or `CupertinoApp`/`WidgetsApp`) to show
  /// the floating monitor. Returns [child] untouched when disabled.
  ///
  /// To combine with another builder:
  /// `builder: (c, child) => ConsolyMonitor.builder(c, other(c, child))`.
  static Widget builder(BuildContext context, Widget? child) {
    final content = child ?? const SizedBox.shrink();
    if (!instance._enabled || !instance.showOverlay) return content;
    return ConsolyOverlay(child: content);
  }

  /// All retained page visits, oldest first.
  List<PageVisit> get visits => List.unmodifiable(_visits);

  /// The visit currently on screen.
  PageVisit? get currentVisit => _visits.isEmpty ? null : _visits.last;

  /// Every retained call, oldest first.
  List<ApiCall> get calls => [for (final v in _visits) ...v.calls];

  /// Marks [name] as the page now on screen.
  ///
  /// [routeKey] identifies the route; re-entering with the same key (e.g.
  /// when a non-top route is removed) does not start a new visit.
  void enterPage(String name, {Object? routeKey}) {
    if (!_enabled) return;
    if (routeKey != null && identical(routeKey, _currentRouteKey)) return;
    _currentRouteKey = routeKey;

    final now = DateTime.now();
    final previous = currentVisit;
    if (previous != null) {
      previous.leftAt = now;
      _logSummary(previous);
    }
    _visits.add(PageVisit(id: _nextVisitId++, name: name, enteredAt: now));
    while (_visits.length > maxVisits) {
      _visits.removeAt(0);
    }
    _notify();
  }

  /// Renames the current visit, e.g. once a nicer route name is known.
  void renameCurrentPage(String name, {Object? routeKey}) {
    final visit = currentVisit;
    if (visit == null) return;
    if (routeKey != null && !identical(routeKey, _currentRouteKey)) return;
    visit.name = name;
    _notify();
  }

  /// Starts tracking a request. Returns `null` when it should be ignored.
  ApiCall? startCall(String method, Uri uri) {
    if (!_enabled) return null;
    if (ignoreRequest?.call(uri) ?? false) return null;
    final visit = currentVisit;
    if (visit == null) return null;
    final call = ApiCall(
      id: _nextCallId++,
      method: method.toUpperCase(),
      uri: uri,
      visit: visit,
      startedAt: DateTime.now(),
    );
    visit.calls.add(call);
    _notify();
    return call;
  }

  /// Records what was sent once the request is closed.
  void onRequestSent(
    ApiCall call, {
    required Map<String, String> headers,
    required List<int> body,
    required int bodySize,
  }) {
    call.requestHeaders = headers;
    call.requestSize = bodySize;
    call.requestBody = decodeBody(
      body,
      totalSize: bodySize,
      contentType: _find(headers, 'content-type'),
    );
    _notify();
  }

  /// Records the status line and headers.
  void onResponse(
    ApiCall call, {
    required int statusCode,
    required Map<String, String> headers,
  }) {
    call.statusCode = statusCode;
    call.responseHeaders = headers;
    call.endedAt = DateTime.now();
    final type = call.responseContentType ?? '';
    if (!trackImages && type.toLowerCase().startsWith('image/')) {
      call.visit.calls.remove(call);
    }
    _notify();
  }

  /// Records the response body once it has been fully read.
  void onResponseBody(ApiCall call, List<int> body, int totalSize) {
    call.endedAt = DateTime.now();
    call.responseSize = totalSize;
    call.responseBody = decodeBody(
      body,
      totalSize: totalSize,
      contentType: call.responseContentType,
    );
    _logCall(call);
    _notify();
  }

  /// Records a failure (DNS, timeout, socket closed, ...).
  void onError(ApiCall call, Object error) {
    if (call.error != null) return;
    call.error = error.toString();
    call.endedAt = DateTime.now();
    _logCall(call);
    _notify();
  }

  /// Manually records a finished call. Useful on web or for transports that
  /// do not go through `dart:io` (gRPC, WebSockets, platform channels, ...).
  ApiCall? logCall({
    required String method,
    required Uri uri,
    int? statusCode,
    Duration? duration,
    Map<String, String> requestHeaders = const {},
    String? requestBody,
    Map<String, String> responseHeaders = const {},
    String? responseBody,
    Object? error,
  }) {
    final call = startCall(method, uri);
    if (call == null) return null;
    call.requestHeaders = requestHeaders;
    call.requestBody = requestBody;
    call.requestSize = requestBody?.length ?? 0;
    call.statusCode = statusCode;
    call.responseHeaders = responseHeaders;
    call.responseBody = responseBody;
    call.responseSize = responseBody?.length;
    call.endedAt =
        duration == null ? DateTime.now() : call.startedAt.add(duration);
    if (error != null) call.error = error.toString();
    _logCall(call);
    _notify();
    return call;
  }

  /// Aggregated stats per page name, in first-seen order.
  Map<String, PageSummary> summarizeByPage() {
    final result = <String, PageSummary>{};
    for (final v in _visits) {
      final s = result.putIfAbsent(v.name, () => PageSummary(v.name));
      s.visits++;
      v.calls.forEach(s.add);
    }
    return result;
  }

  /// A plain-text report of API calls per page.
  String buildReport() {
    final b = StringBuffer('Consoly Monitor — API calls per page\n');
    for (final s in summarizeByPage().values) {
      if (s.calls == 0) continue;
      final avg = s.averageDuration;
      b.writeln(
        '\n■ ${s.page}  (${s.visits} visit${s.visits == 1 ? '' : 's'}, '
        '${s.calls} call${s.calls == 1 ? '' : 's'}, ${s.errors} error'
        '${s.errors == 1 ? '' : 's'}'
        '${avg == null ? '' : ', avg ${avg.inMilliseconds}ms'})',
      );
      final sorted = s.endpoints.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        b.writeln('    ${e.value}× ${e.key}');
      }
    }
    return b.toString();
  }

  /// Prints [buildReport] to the console.
  void printReport() => _print(buildReport());

  /// Drops every recorded visit except the current one, which is emptied.
  void clear() {
    final current = currentVisit;
    _visits.clear();
    if (current != null) {
      current.calls.clear();
      _visits.add(current);
    }
    _notify();
  }

  /// Resets all state. Intended for tests.
  @visibleForTesting
  void reset() {
    _visits.clear();
    _initialized = false;
    _enabled = false;
    _currentRouteKey = null;
    _nextVisitId = 0;
    _nextCallId = 0;
  }

  // Navigator callbacks can fire during a build, and HTTP callbacks can fire
  // at any time, so listeners are notified in a microtask, coalesced.
  bool _notifyScheduled = false;
  void _notify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void _logCall(ApiCall call) {
    if (logLevel != ConsolyLogLevel.verbose) return;
    if (!call.visit.calls.contains(call)) return; // filtered out
    _print('[${call.page}] ${call.toLogLine()}');
  }

  void _logSummary(PageVisit visit) {
    if (logLevel == ConsolyLogLevel.none || visit.calls.isEmpty) return;
    final secs = DateTime.now().difference(visit.enteredAt).inSeconds;
    final b = StringBuffer(
      '📄 ${visit.name} — ${visit.calls.length} API call'
      '${visit.calls.length == 1 ? '' : 's'} in ${secs}s'
      '${visit.errorCount > 0 ? ', ${visit.errorCount} failed' : ''}',
    );
    for (final c in visit.calls) {
      b.write('\n   ${c.toLogLine()}');
    }
    _print(b.toString());
  }

  void _print(String message) {
    for (final line in message.split('\n')) {
      debugPrint('[Consoly] $line');
    }
  }

  static String? _find(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }
}
