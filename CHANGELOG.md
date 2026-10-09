## 0.1.0

* Initial release.
* Automatic capture of every `dart:io` HTTP request (`http`, `dio`, `chopper`, GraphQL clients, ...).
* Attribution of each call to the page on screen via `ConsolyNavigatorObserver`, with name inference for unnamed routes.
* Floating in-app bubble and panel: per-visit call list, per-page summary, request/response details, cURL export.
* Console summary of a page's calls when you leave it; optional per-call logging.
* `ConsolyMonitor.instance.logCall` for web and custom transports.
