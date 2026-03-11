// lib/apps/notes/widgets/rich_editor_asset.dart
//
// Self-contained HTML page bundled as a Dart string.
// Loaded into the WebView in note_editor.dart via a temp file:// URL.
//
// JS → Flutter bridge
// ───────────────────
// webview_windows uses the WebView2 native postMessage API:
//   window.chrome.webview.postMessage(jsonString)
// Flutter receives these via WebviewController.webMessage stream.
//
// Flutter → JS bridge
// ───────────────────
// Flutter calls WebviewController.executeScript(jsString).
//
// Message protocol (JSON):
//   { "type": "ready" }               — editor JS initialised
//   { "type": "change", "html": "…" } — content changed
//   { "type": "wordCount", "count": N }
//
// Functions callable from Flutter via executeScript:
//   setContent(html)   — replace editor content
//   getContent()       — posts a "change" message with current HTML
//   setReadOnly(bool)  — lock/unlock editing
//   focusEditor()      — focus the Quill editor

const kRichEditorHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<link rel="stylesheet"
  href="https://cdnjs.cloudflare.com/ajax/libs/quill/2.0.2/quill.snow.min.css">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100%; overflow: hidden; background: #ffffff; }

  /* ── Toolbar ─────────────────────────────────────────────────── */
  #toolbar {
    position: sticky;
    top: 0;
    z-index: 10;
    background: #ffffff;
    border-bottom: 1px solid #e5e7eb;
    padding: 4px 8px;
    display: flex;
    flex-wrap: wrap;
    gap: 2px;
    align-items: center;
  }
  /* Tighter Quill toolbar overrides */
  .ql-toolbar.ql-snow {
    border: none !important;
    padding: 0 !important;
    font-family: inherit;
  }
  .ql-toolbar.ql-snow .ql-formats { margin-right: 6px; }
  .ql-toolbar button { width: 26px; height: 26px; padding: 2px; }
  .ql-toolbar .ql-picker { height: 26px; }

  /* ── Editor area ─────────────────────────────────────────────── */
  #editor-container {
    height: calc(100vh - 46px);
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
  }
  .ql-container.ql-snow {
    border: none !important;
    font-family: 'Segoe UI', Calibri, Arial, sans-serif;
    font-size: 15px;
  }
  .ql-editor {
    min-height: 100%;
    padding: 16px 20px 40px;
    line-height: 1.75;
    color: #1C1C2E;
  }
  .ql-editor h1 { font-size: 22px; color: #1A3A5C; margin: 12px 0 6px; }
  .ql-editor h2 { font-size: 18px; color: #1A3A5C; margin: 10px 0 4px; }
  .ql-editor h3 { font-size: 15px; color: #1A3A5C; margin: 8px 0 4px; }
  .ql-editor blockquote {
    border-left: 3px solid #1A3A5C;
    background: #F0F4FF;
    padding: 8px 14px;
    margin: 10px 0;
    font-style: italic;
    color: #374151;
  }
  .ql-editor p { margin: 2px 0; }
  /* Placeholder */
  .ql-editor.ql-blank::before {
    color: #9CA3AF;
    font-style: normal;
    left: 20px;
  }
  /* Loading overlay */
  #loading {
    position: fixed; inset: 0;
    background: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: sans-serif;
    font-size: 13px;
    color: #9CA3AF;
    z-index: 100;
  }
</style>
</head>
<body>

<div id="loading">Loading editor…</div>

<div id="editor-container">
  <div id="editor"></div>
</div>

<script
  src="https://cdnjs.cloudflare.com/ajax/libs/quill/2.0.2/quill.min.js"></script>
<script>
// ── Flutter bridge helper ──────────────────────────────────────────────────
// webview_windows uses the WebView2 native postMessage API.
// window.chrome.webview is injected by the WebView2 runtime.
function postToFlutter(obj) {
  const msg = JSON.stringify(obj);
  try {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(msg);
      return;
    }
  } catch(_) {}
  // Fallback for dev/testing in a browser
  console.log('[EditorBridge]', msg);
}

// ── Initialise Quill ──────────────────────────────────────────────────────
let quill;
let _changeTimer;
let _lastHtml = '';
let Delta;    // assigned once Quill loads

function initQuill() {
  const toolbarOptions = [
    [{ header: [1, 2, 3, false] }],
    ['bold', 'italic', 'underline', 'strike'],
    ['blockquote'],
    [{ list: 'ordered' }, { list: 'bullet' }],
    [{ indent: '-1' }, { indent: '+1' }],
    [{ align: [] }],
    ['clean'],
  ];

  quill = new Quill('#editor', {
    theme: 'snow',
    modules: { toolbar: toolbarOptions },
    placeholder: 'Start writing… use the toolbar for bold, headings, lists and more.',
  });

  // Quill 2.x exposes Delta on the constructor
  Delta = Quill.import('delta');

  // Move the generated toolbar into #toolbar slot (cosmetic)
  // Quill injects toolbar before #editor inside the container, but since we
  // use editor-container as the scroll area we need toolbar *outside* it.
  // Quill puts the toolbar before the ql-container inside the parent — the
  // simple CSS approach above handles sticky positioning correctly.

  // ── Change listener — debounced ──────────────────────────────────────────
  quill.on('text-change', function() {
    clearTimeout(_changeTimer);
    _changeTimer = setTimeout(function() {
      const html = quill.getSemanticHTML();
      if (html === _lastHtml) return;
      _lastHtml = html;
      postToFlutter({ type: 'change', html: html });

      // Word count
      const text = quill.getText().trim();
      const words = text ? text.split(/\s+/).filter(Boolean).length : 0;
      postToFlutter({ type: 'wordCount', count: words });
    }, 300);
  });

  // Hide loading overlay
  document.getElementById('loading').style.display = 'none';

  postToFlutter({ type: 'ready' });
}

// ── Public API (called by Flutter via evaluateJavascript) ─────────────────

window.setContent = function(html) {
  if (!quill) return;
  const delta = quill.clipboard.convert({ html: html || '<p></p>' });
  quill.setContents(delta, 'silent');
  _lastHtml = quill.getSemanticHTML();
};

window.getContent = function() {
  if (!quill) return;
  const html = quill.getSemanticHTML();
  postToFlutter({ type: 'change', html: html });
};

window.setReadOnly = function(readonly) {
  if (!quill) return;
  quill.enable(!readonly);
};

window.focusEditor = function() {
  if (!quill) return;
  quill.focus();
};

/// Insert an HTML snippet at the current cursor position (or end).
/// Used by Flutter when a verse is imported via the verse picker.
window.insertVerseHtml = function(html) {
  if (!quill) return;
  const range = quill.getSelection(true);
  const index = range ? range.index + range.length : quill.getLength() - 1;
  const delta = quill.clipboard.convert({ html: html });
  quill.updateContents(
    new Delta().retain(index).concat(delta),
    'user'
  );
  quill.setSelection(index + delta.length(), 'silent');
};

// ── Boot ──────────────────────────────────────────────────────────────────
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initQuill);
} else {
  initQuill();
}
</script>
</body>
</html>''';