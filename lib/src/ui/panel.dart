import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../monitor.dart';

// Palette
const _bg = Color(0xFF0E0F13);
const _surface = Color(0xFF17191F);
const _surfaceHi = Color(0xFF1F222A);
const _line = Color(0xFF2A2D37);
const _text = Color(0xFFECEEF2);
const _muted = Color(0xFF8B91A0);
const _accent = Color(0xFF5B7CFA);
const _ok = Color(0xFF3DD68C);
const _warn = Color(0xFFF5A524);
const _err = Color(0xFFFF5C5C);

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4);

final ThemeData consolyTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  colorSchemeSeed: _accent,
  scaffoldBackgroundColor: _bg,
  canvasColor: _bg,
  dividerColor: _line,
  splashFactory: InkRipple.splashFactory,
);

Color _statusColor(ApiCall c) {
  if (c.error != null) return _err;
  if (c.isPending) return _warn;
  final s = c.statusCode ?? 0;
  if (s >= 500) return _err;
  if (s >= 400) return _warn;
  if (s >= 300) return _accent;
  return _ok;
}

Color _methodColor(String m) {
  switch (m) {
    case 'GET':
      return const Color(0xFF4DA3FF);
    case 'POST':
      return _ok;
    case 'PUT':
    case 'PATCH':
      return _warn;
    case 'DELETE':
      return _err;
    default:
      return _muted;
  }
}

String _statusText(ApiCall c) =>
    c.error != null ? 'ERR' : (c.statusCode?.toString() ?? '···');

String _ms(Duration? d) {
  if (d == null) return '—';
  final ms = d.inMilliseconds;
  return ms >= 1000 ? '${(ms / 1000).toStringAsFixed(2)}s' : '${ms}ms';
}

String _time(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

enum _Filter { all, errors, pending, slow }

/// Full-screen panel listing API calls per page.
class ConsolyPanel extends StatefulWidget {
  const ConsolyPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<ConsolyPanel> createState() => _ConsolyPanelState();
}

class _ConsolyPanelState extends State<ConsolyPanel> {
  int _tab = 0;
  String _query = '';
  _Filter _filter = _Filter.all;
  ApiCall? _selected;
  String? _flash;

  ConsolyMonitor get _monitor => ConsolyMonitor.instance;

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _flash = '$what copied');
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  bool _matches(ApiCall c) {
    if (_query.isNotEmpty &&
        !c.page.toLowerCase().contains(_query) &&
        !c.uri.toString().toLowerCase().contains(_query)) {
      return false;
    }
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.errors:
        return c.isError;
      case _Filter.pending:
        return c.isPending;
      case _Filter.slow:
        return (c.duration?.inMilliseconds ?? 0) >= 1000;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _bg,
      child: SafeArea(
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: _monitor,
              builder: (context, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _selected != null
                    ? _DetailView(
                        key: ValueKey(_selected!.id),
                        call: _selected!,
                        onBack: () => setState(() => _selected = null),
                        onCopy: _copy,
                      )
                    : _buildMain(),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _flash == null ? 0 : 1,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _surfaceHi,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, color: _ok, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            _flash ?? '',
                            style: const TextStyle(color: _text, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMain() {
    final all = _monitor.calls;
    final errors = all.where((c) => c.isError).length;
    final timed = all.where((c) => c.duration != null).toList();
    final avg = timed.isEmpty
        ? null
        : Duration(
            microseconds: timed
                    .map((c) => c.duration!.inMicroseconds)
                    .reduce((a, b) => a + b) ~/
                timed.length,
          );
    final pages = _monitor.summarizeByPage().values.where((s) => s.calls > 0);

    return Column(
      key: const ValueKey('main'),
      children: [
        _TopBar(
          title: 'Consoly Monitor',
          leading: _IconBtn(Icons.close, 'Close', widget.onClose),
          actions: [
            _IconBtn(Icons.copy_all_outlined, 'Copy report',
                () => _copy(_monitor.buildReport(), 'Report')),
            _IconBtn(Icons.terminal, 'Print report to console',
                _monitor.printReport),
            _IconBtn(Icons.delete_outline, 'Clear', _monitor.clear),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              _Stat('${all.length}', 'Calls', _text),
              _Stat('${pages.length}', 'Pages', _text),
              _Stat('$errors', 'Errors', errors > 0 ? _err : _text),
              _Stat(_ms(avg), 'Avg', _text),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                  child: _SearchField(
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              )),
              const SizedBox(width: 10),
              _Segmented(
                labels: const ['Pages', 'Summary'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: switch (f) {
                      _Filter.all => 'All',
                      _Filter.errors => 'Errors',
                      _Filter.pending => 'Pending',
                      _Filter.slow => 'Slow ≥1s',
                    },
                    selected: _filter == f,
                    onTap: () => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _tab == 0 ? _buildVisits() : _buildSummary()),
      ],
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.radar, size: 40, color: _line),
            SizedBox(height: 12),
            Text('No API calls to show',
                style: TextStyle(color: _muted, fontSize: 14)),
          ],
        ),
      );

  Widget _buildVisits() {
    final filtering = _query.isNotEmpty || _filter != _Filter.all;
    final visits = _monitor.visits.reversed
        .where((v) => v.calls.any(_matches) || (!filtering && v.isActive))
        .toList();
    if (visits.isEmpty) return _empty();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: visits.length,
      itemBuilder: (context, i) {
        final v = visits[i];
        final calls = v.calls.where(_matches).toList();
        return _VisitCard(
          key: ValueKey(v.id),
          visit: v,
          calls: calls,
          initiallyExpanded: i == 0,
          onSelect: (c) => setState(() => _selected = c),
        );
      },
    );
  }

  Widget _buildSummary() {
    final pages = _monitor
        .summarizeByPage()
        .values
        .where((s) => s.calls > 0)
        .where((s) =>
            _query.isEmpty ||
            s.page.toLowerCase().contains(_query) ||
            s.endpoints.keys.any((e) => e.toLowerCase().contains(_query)))
        .toList()
      ..sort((a, b) => b.calls.compareTo(a.calls));
    if (pages.isEmpty) return _empty();
    final maxCalls = pages.first.calls;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: pages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = pages[i];
        final avg = s.averageDuration;
        final endpoints = s.endpoints.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return _Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.page,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    _Pill('${s.calls}', _accent),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.visits} visit${s.visits == 1 ? '' : 's'}'
                  '${avg == null ? '' : ' · avg ${_ms(avg)}'}'
                  '${s.errors > 0 ? ' · ${s.errors} failed' : ''}',
                  style: TextStyle(
                    color: s.errors > 0 ? _err : _muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: s.calls / maxCalls,
                    minHeight: 4,
                    backgroundColor: _line,
                    color: s.errors > 0 ? _err : _accent,
                  ),
                ),
                const SizedBox(height: 8),
                for (final e in endpoints)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text('${e.value}×',
                              style: _mono.copyWith(color: _muted)),
                        ),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: '${e.key.split(' ').first} ',
                                style: TextStyle(
                                  color: _methodColor(e.key.split(' ').first),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: e.key.substring(e.key.indexOf(' ') + 1),
                                style: const TextStyle(color: _text),
                              ),
                            ]),
                            style: _mono,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── Page visit card ─────────────────────────

class _VisitCard extends StatefulWidget {
  const _VisitCard({
    super.key,
    required this.visit,
    required this.calls,
    required this.initiallyExpanded,
    required this.onSelect,
  });

  final PageVisit visit;
  final List<ApiCall> calls;
  final bool initiallyExpanded;
  final ValueChanged<ApiCall> onSelect;

  @override
  State<_VisitCard> createState() => _VisitCardState();
}

class _VisitCardState extends State<_VisitCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final v = widget.visit;
    final calls = widget.calls;
    final maxMs = calls.fold<int>(
      1,
      (m, c) => (c.duration?.inMilliseconds ?? 0) > m
          ? c.duration!.inMilliseconds
          : m,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Card(
        accent: v.errorCount > 0 ? _err : (v.isActive ? _ok : null),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  v.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (v.isActive) ...[
                                const SizedBox(width: 8),
                                const _Pill('LIVE', _ok),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_time(v.enteredAt)}'
                            '${v.errorCount > 0 ? ' · ${v.errorCount} failed' : ''}',
                            style: TextStyle(
                              color: v.errorCount > 0 ? _err : _muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Pill('${calls.length}', _accent),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.expand_more, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              if (calls.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No API calls yet',
                        style: TextStyle(color: _muted, fontSize: 12)),
                  ),
                )
              else
                for (final c in calls)
                  _CallRow(
                    call: c,
                    maxMs: maxMs,
                    onTap: () => widget.onSelect(c),
                  ),
          ],
        ),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.call,
    required this.maxMs,
    required this.onTap,
  });

  final ApiCall call;
  final int maxMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(call);
    final ms = call.duration?.inMilliseconds;
    final path = call.uri.path.isEmpty ? '/' : call.uri.path;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _line)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MethodBadge(call.method),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mono.copyWith(color: _text, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                if (call.isPending)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: _warn),
                  )
                else
                  _Pill(_statusText(call), color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                call.uri.host,
                if (call.uri.hasQuery) '?${call.uri.query}',
              ].join(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ms == null ? null : (ms / maxMs).clamp(0.03, 1),
                      minHeight: 3,
                      backgroundColor: _line,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  [
                    _ms(call.duration),
                    if (call.responseSize != null)
                      formatBytes(call.responseSize!),
                  ].join(' · '),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Detail view ─────────────────────────

class _DetailView extends StatefulWidget {
  const _DetailView({
    super.key,
    required this.call,
    required this.onBack,
    required this.onCopy,
  });

  final ApiCall call;
  final VoidCallback onBack;
  final void Function(String text, String what) onCopy;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.call;
    final color = _statusColor(c);
    return Column(
      children: [
        _TopBar(
          title: 'Request',
          leading: _IconBtn(Icons.arrow_back, 'Back', widget.onBack),
          actions: [
            TextButton.icon(
              onPressed: () => widget.onCopy(c.toCurl(), 'cURL'),
              icon: const Icon(Icons.terminal, size: 16),
              label: const Text('Copy cURL'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _MethodBadge(c.method),
                  const SizedBox(width: 8),
                  _Pill(
                    c.error != null
                        ? 'ERROR'
                        : (c.statusCode?.toString() ?? 'PENDING'),
                    color,
                  ),
                  const SizedBox(width: 8),
                  Text(_ms(c.duration),
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  if (c.responseSize != null) ...[
                    const Text(' · ', style: TextStyle(color: _muted)),
                    Text(formatBytes(c.responseSize!),
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                c.uri.toString(),
                style: _mono.copyWith(color: _text, fontSize: 13),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _Segmented(
            labels: const ['Overview', 'Request', 'Response'],
            index: _tab,
            expand: true,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: switch (_tab) {
              0 => _overview(c),
              1 => [
                  _Block(
                      'Headers', _fmtHeaders(c.requestHeaders), widget.onCopy),
                  _Block('Body', c.requestBody ?? '', widget.onCopy,
                      json: true),
                ],
              _ => [
                  if (c.error != null)
                    _Block('Error', c.error!, widget.onCopy, color: _err),
                  _Block(
                      'Headers', _fmtHeaders(c.responseHeaders), widget.onCopy),
                  _Block('Body', c.responseBody ?? '', widget.onCopy,
                      json: true),
                ],
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _overview(ApiCall c) {
    Widget row(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(k,
                    style: const TextStyle(color: _muted, fontSize: 13)),
              ),
              Expanded(
                child: SelectableText(
                  v,
                  style: TextStyle(color: color ?? _text, fontSize: 13),
                ),
              ),
            ],
          ),
        );
    final q = c.uri.queryParameters;
    return [
      const SizedBox(height: 8),
      row('Page', c.page),
      row('Host', c.uri.host),
      row('Path', c.uri.path.isEmpty ? '/' : c.uri.path),
      row('Started', _time(c.startedAt)),
      row('Duration', _ms(c.duration)),
      row('Request size', formatBytes(c.requestSize)),
      row('Response size',
          c.responseSize == null ? '—' : formatBytes(c.responseSize!)),
      row('Content-Type', c.responseContentType ?? '—'),
      if (c.error != null) row('Error', c.error!, color: _err),
      if (q.isNotEmpty)
        _Block(
          'Query parameters',
          q.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
          widget.onCopy,
        ),
    ];
  }

  static String _fmtHeaders(Map<String, String> h) =>
      h.entries.map((e) => '${e.key}: ${e.value}').join('\n');
}

class _Block extends StatelessWidget {
  const _Block(this.title, this.body, this.onCopy,
      {this.json = false, this.color});

  final String title;
  final String body;
  final void Function(String, String) onCopy;
  final bool json;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (body.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onCopy(body, title),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.copy_rounded, size: 15, color: _muted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _line),
            ),
            child: body.isEmpty
                ? const Text('(empty)',
                    style: TextStyle(color: _muted, fontSize: 12))
                : SelectableText.rich(
                    json
                        ? _highlightJson(body)
                        : TextSpan(
                            text: body,
                            style: TextStyle(color: color ?? _text),
                          ),
                    style: _mono,
                  ),
          ),
        ],
      ),
    );
  }
}

final _jsonToken = RegExp(
  r'("(?:\\.|[^"\\])*")(\s*:)?|\b(true|false|null)\b|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)',
);

TextSpan _highlightJson(String text) {
  if (text.length > 20000) {
    return TextSpan(text: text, style: const TextStyle(color: _text));
  }
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in _jsonToken.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(
        text: text.substring(last, m.start),
        style: const TextStyle(color: _text),
      ));
    }
    if (m.group(1) != null) {
      final isKey = m.group(2) != null;
      spans.add(TextSpan(
        text: m.group(1),
        style: TextStyle(color: isKey ? const Color(0xFF7FB2FF) : _ok),
      ));
      if (isKey) {
        spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(color: _text),
        ));
      }
    } else if (m.group(3) != null) {
      spans.add(TextSpan(
        text: m.group(3),
        style: const TextStyle(color: Color(0xFFC792EA)),
      ));
    } else {
      spans.add(TextSpan(
        text: m.group(4),
        style: const TextStyle(color: _warn),
      ));
    }
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(
      text: text.substring(last),
      style: const TextStyle(color: _text),
    ));
  }
  return TextSpan(children: spans);
}

// ───────────────────────── Small widgets ─────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.leading, this.actions});

  final String title;
  final Widget leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...?actions,
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(this.icon, this.tooltip, this.onTap);

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon, size: 22),
        color: _text,
        tooltip: tooltip,
        onPressed: onTap,
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: accent == null
          ? child
          : Stack(
              children: [
                child,
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 3, color: accent),
                ),
              ],
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge(this.method);

  final String method;

  @override
  Widget build(BuildContext context) {
    final color = _methodColor(method);
    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        method.length > 6 ? method.substring(0, 6) : method,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(color: _text, fontSize: 13),
        cursorColor: _accent,
        decoration: InputDecoration(
          hintText: 'Search page or URL',
          hintStyle: const TextStyle(color: _muted, fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 18, color: _muted),
          filled: true,
          fillColor: _surface,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _accent),
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.labels,
    required this.index,
    required this.onChanged,
    this.expand = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (var i = 0; i < labels.length; i++)
        GestureDetector(
          onTap: () => onChanged(i),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: i == index ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                color: i == index ? Colors.white : _muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final item in items) expand ? Expanded(child: item) : item,
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _accent : _line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _accent : _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
