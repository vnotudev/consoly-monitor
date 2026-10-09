# consoly_monitor

See which API calls each page of your Flutter app makes.

Consoly Monitor records every HTTP request your app sends and files it under
the page (route) that was on screen at the time. You can see the results in a
floating in-app panel or in the console.

- **No client changes needed.** It hooks `dart:io`'s `HttpClient`, so it
  catches `http`, `dio`, `chopper`, `retrofit`, GraphQL clients and anything
  else built on `dart:io`.
- **Tracks API calls per page.** Each page visit gets its own list of calls,
  and a summary shows endpoint counts, errors and average latency for each
  page.
- **Names pages automatically.** It uses route names, go_router locations,
  and for unnamed `MaterialPageRoute`s the page widget's class name (for
  example `ProductDetailPage`).
- **Console output.** When you leave a page it prints a summary of that
  page's calls. Verbose mode also prints one line per call.
- **Inspects requests.** You can view headers and bodies (JSON is
  pretty-printed), copy any request as cURL, and copy the full per-page
  report.
- **Does nothing in release builds.** Monitoring is off when `kReleaseMode`
  is true.

```
[Consoly] 📄 /products — 3 API calls in 12s, 1 failed
[Consoly]    GET 200 https://api.shop.dev/products?page=1 182ms 14.2KB
[Consoly]    GET 200 https://api.shop.dev/categories 95ms 1.1KB
[Consoly]    POST 500 https://api.shop.dev/analytics/view 240ms 52B
```

## Install

You can add it either way. Pick one.

### Option A: `dev_dependencies` (recommended)

```sh
flutter pub add --dev consoly_monitor
```

```yaml
dev_dependencies:
  consoly_monitor: ^0.1.0
```

### Option B: `dependencies`

```sh
flutter pub add consoly_monitor
```

```yaml
dependencies:
  consoly_monitor: ^0.1.0
```

With this option you can import the package from any file, including your
normal `main.dart`, with no lint ignore and no separate entrypoint:

```dart
void main() {
  ConsolyMonitor.init(); // inactive in release builds by default
  runApp(MaterialApp(
    navigatorObservers: [ConsolyNavigatorObserver()],
    builder: ConsolyMonitor.builder,
    home: const HomePage(),
  ));
}
```

The package code still ships in release builds, but it does nothing there:
no `HttpClient` wrapping, no overlay, no recording. To turn it on in a
release or profile build, pass `ConsolyMonitor.init(enabled: true)`. You can
also drive it from a flag, for example
`enabled: const bool.fromEnvironment('CONSOLY')`, then run
`flutter run --dart-define=CONSOLY=true`.

### Option A in detail: dev entrypoint

With a dev dependency, import it **only from a dev entrypoint**. Your
production `main.dart` then never contains any monitoring code.

```dart
// lib/main_dev.dart
// ignore_for_file: depend_on_referenced_packages
import 'package:consoly_monitor/consoly_monitor.dart';
import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  ConsolyMonitor.init();
  runApp(MyApp(
    navigatorObservers: [ConsolyNavigatorObserver()],
    builder: ConsolyMonitor.builder,
  ));
}
```

```dart
// lib/app.dart: your app accepts the hooks but doesn't depend on the package
class MyApp extends StatelessWidget {
  const MyApp({super.key, this.navigatorObservers = const [], this.builder});

  final List<NavigatorObserver> navigatorObservers;
  final TransitionBuilder? builder;

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorObservers: navigatorObservers,
        builder: builder,
        home: const HomePage(),
      );
}
```

```sh
flutter run -t lib/main_dev.dart     # with monitor
flutter build apk                    # lib/main.dart, no monitor
```

> The `ignore_for_file` comment is needed because the
> `depend_on_referenced_packages` lint expects packages imported from `lib/`
> to be regular dependencies.
>
> If you'd rather skip the separate entrypoint, use Option B above.

## Setup in 3 steps

1. **Call `ConsolyMonitor.init()` before `runApp`.** Clients created before
   this call are not monitored.
2. **Add `ConsolyNavigatorObserver()`** to every navigator you want to track.
3. **Set `builder: ConsolyMonitor.builder`** on your `MaterialApp`,
   `CupertinoApp` or `WidgetsApp` to get the floating bubble.

### go_router

```dart
GoRouter(
  observers: [ConsolyNavigatorObserver()],
  routes: [
    ShellRoute(
      observers: [ConsolyNavigatorObserver()], // nested navigators too
      builder: (context, state, child) => Shell(child: child),
      routes: [...],
    ),
  ],
);

MaterialApp.router(routerConfig: router, builder: ConsolyMonitor.builder);
```

### Already using `builder`?

```dart
builder: (context, child) =>
    ConsolyMonitor.builder(context, MyOtherBuilder(child: child)),
```

### auto_route / other routers

Pass `ConsolyNavigatorObserver()` wherever the router accepts
`NavigatorObserver`s. For example, with auto_route:
`_appRouter.config(navigatorObservers: () => [ConsolyNavigatorObserver()])`.

## Options

```dart
ConsolyMonitor.init(
  enabled: true,                          // default: !kReleaseMode
  logLevel: ConsolyLogLevel.verbose,      // none | summary (default) | verbose
  showOverlay: true,                      // floating bubble
  trackImages: false,                     // hide image/* responses (Image.network)
  maxVisits: 200,                         // page visits kept in memory
  maxBodyBytes: 64 * 1024,                // body bytes kept per request
  ignoreRequest: (uri) => uri.host.contains('sentry.io'),
  routeNameResolver: (route) => route.settings.arguments is Product
      ? 'ProductPage'
      : null,                             // null → default naming
);
```

## Reading the data from code

```dart
final monitor = ConsolyMonitor.instance;

monitor.printReport();                    // per-page report to the console
final report = monitor.buildReport();     // same, as a String
final byPage = monitor.summarizeByPage(); // Map<String, PageSummary>
final visits = monitor.visits;            // List<PageVisit>, each with .calls
monitor.addListener(() { ... });          // it's a ChangeNotifier
```

This is useful in integration tests to assert a page doesn't make too many
calls:

```dart
expect(ConsolyMonitor.instance.summarizeByPage()['/home']!.calls,
    lessThanOrEqualTo(3));
```

## Web and custom transports

Browsers don't use `dart:io`, so on Flutter web (and for gRPC, WebSockets or
platform channels) you need to report calls yourself, for example from a Dio
interceptor:

```dart
ConsolyMonitor.instance.logCall(
  method: 'GET',
  uri: uri,
  statusCode: 200,
  duration: elapsed,
  responseBody: body,
);
```

## How it works

- `ConsolyMonitor.init()` installs a global `HttpOverrides` that wraps every
  new `HttpClient`. Any `HttpOverrides` you installed earlier is kept and
  wrapped. Response bodies are copied as they stream through, so your code
  still receives the same bytes.
- `ConsolyNavigatorObserver` keeps a stack of `PageRoute`s. The top one is
  the current page. Dialogs and bottom sheets are not counted as pages unless
  you pass `trackPopups: true`.
- Each request is attached to the page **visit** that was current when it
  started, so a request fired in `initState` belongs to the page that
  triggered it.

## Limitations

- HTTP clients created in other isolates are not monitored.
- Requests made by native code (Firebase SDKs, platform WebViews,
  `cronet_http`/`cupertino_http`) bypass `dart:io`. Use `logCall` for those.
- Bodies larger than `maxBodyBytes` are truncated in the monitor only. Your
  app still receives the full response.
