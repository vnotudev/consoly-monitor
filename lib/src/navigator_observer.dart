import 'package:flutter/widgets.dart';

import 'monitor.dart';

/// Tells [ConsolyMonitor] which page is on screen.
///
/// Add one to every navigator whose pages you want tracked:
///
/// ```dart
/// MaterialApp(navigatorObservers: [ConsolyNavigatorObserver()]);
/// GoRouter(observers: [ConsolyNavigatorObserver()], routes: [...]);
/// ```
///
/// Only [PageRoute]s count as pages; requests made while a dialog or bottom
/// sheet is open are attributed to the page underneath, unless
/// [trackPopups] is `true`.
///
/// Page names come from, in order: `ConsolyMonitor.routeNameResolver`,
/// `RouteSettings.name`, a `Page` key holding a string (go_router uses the
/// location), and finally the type of the page's root widget.
class ConsolyNavigatorObserver extends NavigatorObserver {
  ConsolyNavigatorObserver({this.trackPopups = false});

  final bool trackPopups;

  // Keyed by NavigatorState so a fresh observer instance (e.g. created inside
  // a `build` method) picks up where the previous one left off.
  static final Expando<List<Route<dynamic>>> _stacks = Expando();
  static final Expando<String> _inferredNames = Expando();

  List<Route<dynamic>> get _stack => _stacks[navigator ?? this] ??= [];

  bool _isPage(Route<dynamic> route) =>
      route is PageRoute || (trackPopups && route is PopupRoute);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isPage(route)) return;
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.remove(route)) _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.remove(route)) _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final stack = _stack;
    final index = oldRoute == null ? -1 : stack.indexOf(oldRoute);
    final replacement = newRoute != null && _isPage(newRoute);
    if (index >= 0) {
      if (replacement) {
        stack[index] = newRoute;
      } else {
        stack.removeAt(index);
      }
    } else if (replacement) {
      stack.add(newRoute);
    }
    _sync();
  }

  void _sync() {
    final monitor = ConsolyMonitor.instance;
    if (!monitor.enabled || _stack.isEmpty) return;
    final route = _stack.last;
    final name = nameOf(route);
    if (name != null) {
      monitor.enterPage(name, routeKey: route);
      return;
    }
    // The page widget is not built yet; use a placeholder and rename once
    // the first frame is out. Requests from initState still land on this
    // visit because they are attributed by visit, not by name.
    monitor.enterPage(route.runtimeType.toString(), routeKey: route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inferred = _inferName(route);
      if (inferred != null) {
        _inferredNames[route] = inferred;
        monitor.renameCurrentPage(inferred, routeKey: route);
      }
    });
  }

  /// The best known name for [route], or `null` if it has to be inferred
  /// from its widget tree.
  static String? nameOf(Route<dynamic> route) {
    final custom = ConsolyMonitor.instance.routeNameResolver?.call(route);
    if (custom != null) return custom;
    final settings = route.settings;
    final name = settings.name;
    if (name != null && name.isNotEmpty) return name;
    if (settings is Page) {
      final key = settings.key;
      if (key is ValueKey<String>) return key.value;
    }
    return _inferredNames[route];
  }

  // Wrapper widgets that routes put between the route and the page widget.
  static const _wrapperTypes = {
    'RepaintBoundary',
    'Builder',
    'Semantics',
    'KeyedSubtree',
    'Actions',
    'Focus',
    'PrimaryScrollController',
  };

  static String? _inferName(Route<dynamic> route) {
    if (route is! ModalRoute) return null;
    final root = route.subtreeContext;
    if (root == null) return null;

    String? found;
    var depth = 0;
    void visit(Element element) {
      if (found != null || depth > 12) return;
      final type = element.widget.runtimeType.toString();
      final base = type.split('<').first;
      if (!_wrapperTypes.contains(base) && !base.startsWith('_')) {
        found = type;
        return;
      }
      depth++;
      element.visitChildElements(visit);
    }

    (root as Element).visitChildElements(visit);
    return found;
  }
}
