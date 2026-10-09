import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import '../monitor.dart';

/// Wraps every [HttpClient] created from now on so its traffic is recorded.
///
/// Any [HttpOverrides] installed earlier keeps working: new clients are
/// created through it and then wrapped.
void installHttpInterceptor() {
  final previous = HttpOverrides.current;
  if (previous is _ConsolyHttpOverrides) return;
  HttpOverrides.global = _ConsolyHttpOverrides(previous);
}

class _ConsolyHttpOverrides extends HttpOverrides {
  _ConsolyHttpOverrides(this._previous);

  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner =
        _previous?.createHttpClient(context) ?? super.createHttpClient(context);
    return _ConsolyHttpClient(inner);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    return _previous?.findProxyFromEnvironment(url, environment) ??
        super.findProxyFromEnvironment(url, environment);
  }
}

/// Captures up to [limit] bytes while counting the total.
class _ByteCapture {
  _ByteCapture(this.limit);

  final int limit;
  final List<int> bytes = [];
  int total = 0;

  void add(List<int> data) {
    total += data.length;
    final room = limit - bytes.length;
    if (room <= 0) return;
    bytes.addAll(data.length <= room ? data : data.sublist(0, room));
  }
}

Map<String, String> _headersToMap(HttpHeaders headers) {
  final map = <String, String>{};
  headers.forEach((name, values) => map[name] = values.join(', '));
  return map;
}

class _ConsolyHttpClient implements HttpClient {
  _ConsolyHttpClient(this._inner);

  final HttpClient _inner;

  Future<HttpClientRequest> _track(
    String method,
    Uri uri,
    Future<HttpClientRequest> Function() open,
  ) async {
    final call = ConsolyMonitor.instance.startCall(method, uri);
    if (call == null) return open();
    try {
      return _ConsolyHttpClientRequest(await open(), call);
    } catch (e) {
      ConsolyMonitor.instance.onError(call, e);
      rethrow;
    }
  }

  static Uri _uriOf(String host, int port, String path) {
    final query = path.indexOf('?');
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: query < 0 ? path : path.substring(0, query),
      query: query < 0 ? null : path.substring(query + 1),
    );
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      _track(method, _uriOf(host, port, path),
          () => _inner.open(method, host, port, path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _track(method, url, () => _inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('get', host, port, path);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('get', url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('post', host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('post', url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('put', host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('put', url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('delete', host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('delete', url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('patch', host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('patch', url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('head', host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('head', url);

  // Everything below is plain delegation.

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(
      String host,
      int port,
      String scheme,
      String? realm,
    )? f,
  ) =>
      _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) =>
      _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )? f,
  ) =>
      _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

class _ConsolyHttpClientRequest implements HttpClientRequest {
  _ConsolyHttpClientRequest(this._inner, this._call)
      : _body = _ByteCapture(ConsolyMonitor.instance.maxBodyBytes);

  final HttpClientRequest _inner;
  final ApiCall _call;
  final _ByteCapture _body;
  Future<HttpClientResponse>? _response;

  Future<HttpClientResponse> _wrapOnce(Future<HttpClientResponse> future) {
    return _response ??= future.then(
      (response) => _ConsolyHttpClientResponse.wrap(response, _call),
      onError: (Object e, StackTrace st) {
        ConsolyMonitor.instance.onError(_call, e);
        Error.throwWithStackTrace(e, st);
      },
    );
  }

  @override
  Future<HttpClientResponse> close() {
    ConsolyMonitor.instance.onRequestSent(
      _call,
      headers: _headersToMap(_inner.headers),
      body: _body.bytes,
      bodySize: _body.total,
    );
    return _wrapOnce(_inner.close());
  }

  @override
  Future<HttpClientResponse> get done => _wrapOnce(_inner.done);

  @override
  void add(List<int> data) {
    _body.add(data);
    _inner.add(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return _inner.addStream(stream.map((data) {
      _body.add(data);
      return data;
    }));
  }

  @override
  void write(Object? object) {
    final string = '$object';
    if (string.isEmpty) return;
    _body.add(encoding.encode(string));
    _inner.write(string);
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    ConsolyMonitor.instance.onError(_call, exception ?? 'aborted');
    _inner.abort(exception, stackTrace);
  }

  @override
  Future<void> flush() => _inner.flush();

  // Plain delegation.

  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool value) => _inner.followRedirects = value;

  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;

  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;
}

class _ConsolyHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _ConsolyHttpClientResponse._(this._inner, Stream<List<int>> stream)
      : super(stream);

  static HttpClientResponse wrap(HttpClientResponse inner, ApiCall call) {
    final monitor = ConsolyMonitor.instance;
    monitor.onResponse(
      call,
      statusCode: inner.statusCode,
      headers: _headersToMap(inner.headers),
    );
    final body = _ByteCapture(monitor.maxBodyBytes);
    final stream = inner.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          body.add(data);
          sink.add(data);
        },
        handleError: (error, stackTrace, sink) {
          monitor.onError(call, error);
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          if (call.error == null) {
            monitor.onResponseBody(call, body.bytes, body.total);
          }
          sink.close();
        },
      ),
    );
    return _ConsolyHttpClientResponse._(inner, stream);
  }

  final HttpClientResponse _inner;

  @override
  X509Certificate? get certificate => _inner.certificate;

  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  int get contentLength => _inner.contentLength;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  Future<Socket> detachSocket() => _inner.detachSocket();

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  bool get isRedirect => _inner.isRedirect;

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  String get reasonPhrase => _inner.reasonPhrase;

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) =>
      _inner.redirect(method, url, followLoops);

  @override
  List<RedirectInfo> get redirects => _inner.redirects;

  @override
  int get statusCode => _inner.statusCode;
}
