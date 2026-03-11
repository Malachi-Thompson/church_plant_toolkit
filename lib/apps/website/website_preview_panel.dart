// lib/apps/website/website_preview_panel.dart
//
// In-app live preview of the generated website.
//
// Platform strategy:
//   Windows  → webview_windows (WebView2/Chromium), loads HTML via loadStringContent()
//   Android/iOS/macOS/Linux → webview_flutter,      loads HTML via loadHtmlString()
//
// The generated CSS is inlined so no disk writes or network calls are needed.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'website_models.dart';
import 'website_exporter.dart';

// ─── Public entry-point ───────────────────────────────────────────────────────

class WebsitePreviewPanel extends StatefulWidget {
  final ChurchWebsite site;
  final WebPage       initialPage;
  final Color         primary;

  const WebsitePreviewPanel({
    super.key,
    required this.site,
    required this.initialPage,
    required this.primary,
  });

  @override
  State<WebsitePreviewPanel> createState() => _WebsitePreviewPanelState();
}

// ─── Device frame sizes ───────────────────────────────────────────────────────

enum _Device { desktop, tablet, phone }

const _deviceLabel = {
  _Device.desktop: 'Desktop',
  _Device.tablet:  'Tablet',
  _Device.phone:   'Phone',
};

const _deviceIcon = {
  _Device.desktop: Icons.desktop_mac_outlined,
  _Device.tablet:  Icons.tablet_mac_outlined,
  _Device.phone:   Icons.smartphone_outlined,
};

const _deviceMaxWidth = {
  _Device.desktop: 0.0,    // 0 = fill all available space
  _Device.tablet:  768.0,
  _Device.phone:   375.0,
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

bool get _isWindows => !kIsWeb && Platform.isWindows;

/// Replaces the external style.css <link> with an inlined <style> block so
/// the webview never needs to resolve a file:// URL.
String _inlineCSS(String html, String css) {
  const link = '<link rel="stylesheet" href="style.css">';
  final style = '<style>\n$css\n</style>';
  if (html.contains(link)) return html.replaceFirst(link, style);
  return html.replaceFirst('</head>', '$style\n</head>');
}

// ─── State ────────────────────────────────────────────────────────────────────

class _WebsitePreviewPanelState extends State<WebsitePreviewPanel> {
  // Windows path (webview_windows)
  WebviewController? _winController;
  bool               _winReady = false;

  // Cross-platform path (webview_flutter)
  wf.WebViewController? _wfController;

  late WebPage _currentPage;
  _Device      _device  = _Device.desktop;
  bool         _loading = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    if (_isWindows) {
      _initWindows();
    } else {
      _initWebviewFlutter();
    }
  }

  @override
  void didUpdateWidget(WebsitePreviewPanel old) {
    super.didUpdateWidget(old);
    if (old.site != widget.site || old.initialPage != widget.initialPage) {
      _currentPage = widget.initialPage;
      _loadPage(_currentPage);
    }
  }

  @override
  void dispose() {
    _winController?.dispose();
    super.dispose();
  }

  // ── Windows init ────────────────────────────────────────────────────────────

  Future<void> _initWindows() async {
    final c = WebviewController();
    await c.initialize();
    if (!mounted) return;
    setState(() {
      _winController = c;
      _winReady      = true;
    });
    _loadPage(_currentPage);
  }

  // ── webview_flutter init (non-Windows) ──────────────────────────────────────

  void _initWebviewFlutter() {
    _wfController = wf.WebViewController()
      ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(wf.NavigationDelegate(
        onPageStarted:  (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (req) {
          _handleCrossPageLink(req.url);
          return wf.NavigationDecision.prevent;
        },
      ));
    _loadPage(_currentPage);
  }

  // ── Load a page ─────────────────────────────────────────────────────────────

  void _loadPage(WebPage page) {
    final css  = generateCSS(widget.site.settings);
    final html = _inlineCSS(generatePageHtml(widget.site, page), css);

    if (_isWindows) {
      if (_winReady && _winController != null) {
        setState(() => _loading = true);
        _winController!.loadStringContent(html).then((_) {
          if (mounted) setState(() => _loading = false);
        });
      }
      // If not yet initialised, _initWindows() will call _loadPage once done.
    } else {
      setState(() => _loading = true);
      _wfController?.loadHtmlString(html).then((_) {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  // ── Inter-page link handling (webview_flutter only) ─────────────────────────

  void _handleCrossPageLink(String url) {
    if (url.startsWith('data:') || url.startsWith('#')) return;
    final slug = url.split('/').last.replaceAll('.html', '');
    final target = widget.site.pages.firstWhere(
      (p) => p.slug == slug || (slug == 'index' && p.isHomePage),
      orElse: () => _currentPage,
    );
    if (target.id != _currentPage.id) {
      setState(() => _currentPage = target);
      _loadPage(target);
    }
  }

  // ── Device switcher button ──────────────────────────────────────────────────

  Widget _deviceBtn(_Device d) {
    final active = _device == d;
    return Tooltip(
      message: _deviceLabel[d]!,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _device = d),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? widget.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? widget.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Icon(_deviceIcon[d], size: 18,
              color: active ? widget.primary : Colors.grey.shade500),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Spinner while the Windows WebView2 controller is initialising
    if (_isWindows && !_winReady) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: widget.primary, strokeWidth: 2),
          const SizedBox(height: 12),
          Text('Initialising WebView2…',
              style: TextStyle(
                  color: widget.primary.withValues(alpha: 0.6), fontSize: 12)),
        ]),
      );
    }

    final maxW = _deviceMaxWidth[_device]!;

    return Column(children: [
      // ── Toolbar ───────────────────────────────────────────────────────────
      _PreviewToolbar(
        site:        widget.site,
        currentPage: _currentPage,
        primary:     widget.primary,
        deviceButtons: Row(
          mainAxisSize: MainAxisSize.min,
          children: _Device.values.map(_deviceBtn).toList(),
        ),
        onSelectPage: (p) {
          setState(() => _currentPage = p);
          _loadPage(p);
        },
        onRefresh: () => _loadPage(_currentPage),
      ),

      // ── Frame ─────────────────────────────────────────────────────────────
      Expanded(
        child: Container(
          color: const Color(0xFFE8EAF0),
          alignment: Alignment.topCenter,
          padding: EdgeInsets.symmetric(
            horizontal: _device == _Device.desktop ? 0 : 24,
            vertical:   _device == _Device.desktop ? 0 : 20,
          ),
          child: _DeviceFrame(
            device:   _device,
            maxWidth: maxW,
            primary:  widget.primary,
            child: Stack(children: [
              // Webview
              if (_isWindows && _winController != null)
                Webview(_winController!)
              else if (_wfController != null)
                wf.WebViewWidget(controller: _wfController!)
              else
                const SizedBox.shrink(),

              // Loading overlay
              if (_loading)
                Container(
                  color: Colors.white,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(
                          color: widget.primary, strokeWidth: 2),
                      const SizedBox(height: 12),
                      Text('Rendering preview…',
                          style: TextStyle(
                              color: widget.primary.withValues(alpha: 0.6),
                              fontSize: 12)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ─── Toolbar ─────────────────────────────────────────────────────────────────

class _PreviewToolbar extends StatelessWidget {
  final ChurchWebsite         site;
  final WebPage               currentPage;
  final Color                 primary;
  final Widget                deviceButtons;
  final ValueChanged<WebPage> onSelectPage;
  final VoidCallback          onRefresh;

  const _PreviewToolbar({
    required this.site,         required this.currentPage,
    required this.primary,      required this.deviceButtons,
    required this.onSelectPage, required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: site.pages.map((p) {
                final active = p.id == currentPage.id;
                return GestureDetector(
                  onTap: () => onSelectPage(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: active ? primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(p.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w600 : FontWeight.normal,
                          color: active ? primary : Colors.grey.shade600,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Container(width: 1, height: 20, color: Colors.grey.shade200,
            margin: const EdgeInsets.symmetric(horizontal: 8)),
        deviceButtons,
        const SizedBox(width: 8),
        Tooltip(
          message: 'Refresh preview',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onRefresh,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.refresh, size: 18,
                  color: Colors.grey.shade500),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Device frame chrome ──────────────────────────────────────────────────────

class _DeviceFrame extends StatelessWidget {
  final _Device device;
  final double  maxWidth;
  final Color   primary;
  final Widget  child;

  const _DeviceFrame({
    required this.device,  required this.maxWidth,
    required this.primary, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (device == _Device.desktop) return child;
    final isPhone = device == _Device.phone;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(isPhone ? 40 : 20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(children: [
            SizedBox(
              height: isPhone ? 36 : 24,
              child: Center(
                child: Container(
                  width: isPhone ? 120 : 80,
                  height: isPhone ? 14 : 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isPhone ? 8 : 4),
                child: child,
              ),
            ),
            SizedBox(
              height: isPhone ? 28 : 20,
              child: Center(
                child: Container(
                  width: isPhone ? 120 : 80,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}