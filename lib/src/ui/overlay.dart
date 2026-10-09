import 'package:flutter/material.dart';

import '../monitor.dart';
import 'panel.dart';

/// Floating bubble showing the current page's API call count. Tap it to open
/// the monitor panel; drag it out of the way.
///
/// Usually inserted via `MaterialApp(builder: ConsolyMonitor.builder)`.
class ConsolyOverlay extends StatefulWidget {
  const ConsolyOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<ConsolyOverlay> createState() => _ConsolyOverlayState();
}

class _ConsolyOverlayState extends State<ConsolyOverlay> {
  Offset? _position;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final padding = MediaQuery.maybeOf(context)?.padding ?? EdgeInsets.zero;
        final pos = _clamp(
          _position ?? Offset(size.width - 76, size.height - 160),
          size,
          padding,
        );
        return Stack(
          alignment: Alignment.topLeft,
          children: [
            Positioned.fill(child: widget.child),
            if (!_open)
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() => _position = pos + d.delta),
                  onTap: () => setState(() => _open = true),
                  child: const _Bubble(),
                ),
              ),
            if (_open)
              Positioned.fill(
                child: _PanelHost(
                  onClose: () => setState(() => _open = false),
                ),
              ),
          ],
        );
      }),
    );
  }

  static Offset _clamp(Offset o, Size size, EdgeInsets padding) {
    const w = 64.0, h = 64.0;
    return Offset(
      o.dx.clamp(0.0, (size.width - w).clamp(0.0, double.infinity)),
      o.dy.clamp(
          padding.top, (size.height - h).clamp(padding.top, double.infinity)),
    );
  }
}

class _PanelHost extends StatefulWidget {
  const _PanelHost({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  // The panel gets its own Overlay so text selection and tooltips work even
  // though it sits above the app's Navigator. A fresh entry per opening,
  // since an entry cannot move between Overlays.
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => ConsolyPanel(onClose: widget.onClose),
  );

  @override
  Widget build(BuildContext context) {
    // Provide Material localizations so the panel also works under
    // CupertinoApp / WidgetsApp.
    return Localizations(
      locale: const Locale('en'),
      delegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Theme(
        data: consolyTheme,
        child: Overlay(initialEntries: [_entry]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble();

  @override
  Widget build(BuildContext context) {
    final monitor = ConsolyMonitor.instance;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final visit = monitor.currentVisit;
        final count = visit?.calls.length ?? 0;
        final errors = visit?.errorCount ?? 0;
        final pending = visit?.calls.where((c) => c.isPending).length ?? 0;
        final color = errors > 0
            ? const Color(0xFFE5484D)
            : pending > 0
                ? const Color(0xFFF5A524)
                : const Color(0xFF3E63DD);
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xEE15171C),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), blurRadius: 8),
            ],
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontFamily: 'monospace',
              decoration: TextDecoration.none,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'API',
                  style: TextStyle(fontSize: 9, color: Color(0xFFAAAAAA)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
