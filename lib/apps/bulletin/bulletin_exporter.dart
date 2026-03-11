// lib/apps/bulletin/bulletin_exporter.dart
//
// Generates print-ready HTML for each layout, then opens it in the browser
// so the user can File → Print → Save as PDF (or send to printer).
//
// All layouts are pure HTML/CSS — no external dependencies.

import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'bulletin_model.dart';

Future<void> exportBulletinHtml(BulletinModel b) async {
  final html = _buildHtml(b);
  final tmp  = await getTemporaryDirectory();
  final safe = b.title
      .replaceAll(RegExp(r'[^\w\s\-]'), '')
      .trim()
      .replaceAll(' ', '_');
  final file = File('${tmp.path}/${safe}_bulletin.html');
  await file.writeAsString(html);
  final uri = Uri.file(file.path);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ROUTING — pick the right template
// ══════════════════════════════════════════════════════════════════════════════

String _buildHtml(BulletinModel b) {
  switch (b.layout) {
    case BulletinLayout.singlePage: return _singlePageHtml(b);
    case BulletinLayout.bifold:     return _bifoldHtml(b);
    case BulletinLayout.halfSheet:  return _halfSheetHtml(b);
    case BulletinLayout.trifold:    return _trifoldHtml(b);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ══════════════════════════════════════════════════════════════════════════════

String _h(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _fmtDate(DateTime? d) => d == null
    ? '' : DateFormat('MMMM d, yyyy').format(d);

String _orderHtml(List<ServiceItem> items) {
  if (items.isEmpty) return '';
  final rows = items.map((i) {
    final time   = i.time.isNotEmpty   ? '<span class="oos-time">${_h(i.time)}</span>'   : '';
    final detail = i.detail.isNotEmpty ? '<span class="oos-detail">${_h(i.detail)}</span>' : '';
    return '<tr><td class="oos-time-col">$time</td>'
        '<td class="oos-label">${_h(i.label)}$detail</td></tr>';
  }).join('\n');
  return '<table class="oos">$rows</table>';
}

String _announcementsHtml(List<Announcement> items) {
  if (items.isEmpty) return '<p><em>No announcements this week.</em></p>';
  return items.map((a) =>
    '<div class="announcement">'
    '<div class="ann-title">${_h(a.title)}</div>'
    '${a.body.isNotEmpty ? '<div class="ann-body">${_h(a.body)}</div>' : ''}'
    '</div>'
  ).join('\n');
}

String _prayerHtml(String text) {
  if (text.trim().isEmpty) return '<p><em>See prayer card insert.</em></p>';
  return text.split('\n').where((l) => l.trim().isNotEmpty)
      .map((l) => '<p class="prayer-item">🙏 ${_h(l.trim())}</p>')
      .join('\n');
}

String _sermonNotesHtml(String prompt) => '''
<div class="notes-area">
  <div class="notes-heading">${_h(prompt)}</div>
  <div class="notes-lines">
    ${'<div class="note-line"></div>\n    ' * 12}
  </div>
</div>''';

String _contactCardHtml(BulletinModel b) => '''
<div class="contact-card">
  <div class="contact-heading">${_h(b.contactCardHeading)}</div>
  <table class="contact-fields">
    <tr>
      <td><div class="field-label">Name</div><div class="field-line"></div></td>
      <td><div class="field-label">Phone</div><div class="field-line"></div></td>
    </tr>
    <tr>
      <td colspan="2"><div class="field-label">Email</div><div class="field-line"></div></td>
    </tr>
    <tr>
      <td colspan="2"><div class="field-label">Address</div><div class="field-line"></div><div class="field-line"></div></td>
    </tr>
  </table>
  <div class="contact-checkboxes">
    <label><input type="checkbox"> First-time visitor</label>
    <label><input type="checkbox"> Regular attender</label>
    <label><input type="checkbox"> Prayer request</label>
    <label><input type="checkbox"> I'd like more information</label>
  </div>
</div>''';

String _churchInfoHtml(BulletinModel b) {
  final parts = <String>[];
  if (b.churchAddress.isNotEmpty) parts.add(_h(b.churchAddress));
  if (b.churchPhone.isNotEmpty)   parts.add(_h(b.churchPhone));
  if (b.churchWebsite.isNotEmpty) parts.add(_h(b.churchWebsite));
  if (b.churchEmail.isNotEmpty)   parts.add(_h(b.churchEmail));
  if (parts.isEmpty) return '';
  return '<div class="church-info">${parts.join(' &nbsp;·&nbsp; ')}</div>';
}

// Common CSS variables injected into every layout
String _cssVars(BulletinModel b) => '''
  :root {
    --accent: ${b.accentColor};
    --accent-light: ${b.accentColor}22;
    --text: #1C1C2E;
    --muted: #6B7280;
    --line: #D1D5DB;
  }''';

// Shared component styles used across layouts
const String _componentCss = '''
  /* Order of service */
  .oos { width: 100%; border-collapse: collapse; margin: 4px 0 8px; }
  .oos-time-col { width: 44px; vertical-align: top; padding: 3px 6px 3px 0; }
  .oos-time { font-size: 8pt; color: var(--muted); white-space: nowrap; }
  .oos-label { font-size: 9.5pt; padding: 3px 0; color: var(--text); }
  .oos-detail { display: block; font-size: 8pt; color: var(--muted); font-style: italic; }

  /* Announcements */
  .announcement { margin-bottom: 8px; }
  .ann-title { font-weight: 700; font-size: 9pt; color: var(--accent); }
  .ann-body  { font-size: 8.5pt; color: var(--text); margin-top: 1px; }

  /* Prayer */
  .prayer-item { font-size: 8.5pt; margin: 3px 0; color: var(--text); }

  /* Sermon notes */
  .notes-area { margin-top: 4px; }
  .notes-heading { font-weight: 700; font-size: 10pt; color: var(--accent); margin-bottom: 6px; }
  .note-line { border-bottom: 1px solid var(--line); height: 22px; margin: 0; }

  /* Contact card */
  .contact-card { border: 1.5px dashed var(--line); border-radius: 6px; padding: 10px 12px; margin-top: 6px; }
  .contact-heading { font-weight: 700; font-size: 9pt; color: var(--accent); margin-bottom: 8px; }
  .contact-fields { width: 100%; border-collapse: collapse; }
  .contact-fields td { padding: 4px 8px 4px 0; vertical-align: top; }
  .field-label { font-size: 7.5pt; color: var(--muted); margin-bottom: 2px; }
  .field-line { border-bottom: 1px solid var(--text); height: 16px; }
  .contact-checkboxes { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; font-size: 8pt; }
  .contact-checkboxes label { display: flex; align-items: center; gap: 4px; }

  /* Church info footer */
  .church-info { font-size: 8pt; color: var(--muted); text-align: center; margin-top: 6px; }

  /* Section heading */
  .section-heading {
    font-size: 9pt; font-weight: 800; letter-spacing: .08em;
    text-transform: uppercase; color: var(--accent);
    border-bottom: 1.5px solid var(--accent); padding-bottom: 3px;
    margin: 12px 0 6px;
  }
  .section-heading:first-child { margin-top: 0; }

  /* Print button */
  .print-btn {
    position: fixed; top: 16px; right: 16px;
    background: var(--accent); color: white; border: none;
    padding: 8px 18px; font-size: 12px; border-radius: 6px; cursor: pointer;
    box-shadow: 0 2px 8px rgba(0,0,0,.2);
  }
  @media print { .print-btn { display: none; } }
''';

// ══════════════════════════════════════════════════════════════════════════════
// SINGLE PAGE
// ══════════════════════════════════════════════════════════════════════════════

String _singlePageHtml(BulletinModel b) {
  final date = _fmtDate(b.serviceDate);
  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${_h(b.title)}</title>
<style>
  ${_cssVars(b)}
  @media print { @page { size: letter portrait; margin: .5in; } }
  body {
    font-family: 'Calibri', 'Segoe UI', Arial, sans-serif;
    font-size: 10pt; color: var(--text);
    max-width: 720px; margin: 0 auto; padding: 24px;
  }
  .header {
    text-align: center;
    border-bottom: 3px solid var(--accent);
    padding-bottom: 14px; margin-bottom: 16px;
  }
  .church-name { font-size: 22pt; font-weight: 800; color: var(--accent); margin: 0; }
  .date        { font-size: 11pt; color: var(--muted); margin: 4px 0 0; }
  .sermon-block {
    background: var(--accent-light); border-left: 4px solid var(--accent);
    border-radius: 4px; padding: 10px 14px; margin: 0 0 16px;
  }
  .sermon-title    { font-size: 14pt; font-weight: 700; color: var(--accent); }
  .sermon-speaker  { font-size: 9pt; color: var(--muted); margin-top: 3px; }
  .sermon-scripture{ font-size: 9pt; color: var(--text);  margin-top: 2px; font-style: italic; }
  .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
  $_componentCss
</style>
</head>
<body>
<button class="print-btn" onclick="window.print()">🖨 Print / Save as PDF</button>

<div class="header">
  <div class="church-name">${_h(b.churchName.isNotEmpty ? b.churchName : 'Church')}</div>
  ${date.isNotEmpty ? '<div class="date">$date</div>' : ''}
  ${_churchInfoHtml(b)}
</div>

${(b.sermonTitle.isNotEmpty || b.speakerName.isNotEmpty) ? '''
<div class="sermon-block">
  ${b.sermonTitle.isNotEmpty ? '<div class="sermon-title">${_h(b.sermonTitle)}</div>' : ''}
  ${b.speakerName.isNotEmpty ? '<div class="sermon-speaker">${_h(b.speakerName)}</div>' : ''}
  ${b.sermonScripture.isNotEmpty ? '<div class="sermon-scripture">${_h(b.sermonScripture)}</div>' : ''}
</div>''' : ''}

<div class="two-col">
  <div>
    <div class="section-heading">Order of Service</div>
    ${_orderHtml(b.orderOfService)}

    ${b.prayerRequests.trim().isNotEmpty ? '<div class="section-heading">Prayer Requests</div>${_prayerHtml(b.prayerRequests)}' : ''}
  </div>
  <div>
    <div class="section-heading">Announcements</div>
    ${_announcementsHtml(b.announcements)}
  </div>
</div>

${b.includeSermonNotes ? '<div class="section-heading">${_h(b.sermonNotesPrompt)}</div>${_sermonNotesHtml(b.sermonNotesPrompt)}' : ''}
${b.includeContactCard ? _contactCardHtml(b) : ''}

</body></html>''';
}

// ══════════════════════════════════════════════════════════════════════════════
// BI-FOLD  (letter folded in half → 4 panels)
// Print landscape on letter → fold down the middle.
// Panels: [back-outside | front-outside] on page 1
//         [inside-left  | inside-right ] on page 2
// ══════════════════════════════════════════════════════════════════════════════

String _bifoldHtml(BulletinModel b) {
  final date = _fmtDate(b.serviceDate);
  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${_h(b.title)}</title>
<style>
  ${_cssVars(b)}
  @media print {
    @page { size: letter landscape; margin: 0; }
    .page-break { page-break-after: always; }
  }
  * { box-sizing: border-box; }
  body { font-family: 'Calibri', 'Segoe UI', Arial, sans-serif; margin: 0; padding: 0; }

  /* Each "sheet" = two panels side by side */
  .sheet { display: flex; width: 11in; height: 8.5in; }
  .panel { width: 5.5in; height: 8.5in; padding: .45in .4in; overflow: hidden; }
  .panel-divider { width: 0; border-left: 1px dashed #ccc; }

  /* Front cover (panel right of sheet 1) */
  .cover {
    background: var(--accent);
    color: white;
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    text-align: center;
  }
  .cover-church { font-size: 22pt; font-weight: 800; letter-spacing: .02em; margin-bottom: 12px; }
  .cover-date   { font-size: 13pt; opacity: .85; margin-bottom: 6px; }
  .cover-sermon-label { font-size: 8pt; text-transform: uppercase; letter-spacing: .12em; opacity: .65; margin: 20px 0 6px; }
  .cover-sermon-title  { font-size: 15pt; font-weight: 700; line-height: 1.25; }
  .cover-speaker       { font-size: 10pt; opacity: .8; margin-top: 6px; }
  .cover-scripture     { font-size: 9pt;  opacity: .7; margin-top: 4px; font-style: italic; }
  .cover-divider { width: 60px; height: 3px; background: rgba(255,255,255,.4); margin: 16px auto; }

  /* Back cover (panel left of sheet 1) */
  .back-cover {
    display: flex; flex-direction: column; justify-content: space-between;
  }

  /* Inside panels (sheet 2) */
  .inside { background: #fff; }

  .section-heading {
    font-size: 8.5pt; font-weight: 800; letter-spacing: .08em;
    text-transform: uppercase; color: var(--accent);
    border-bottom: 1.5px solid var(--accent); padding-bottom: 3px;
    margin: 10px 0 5px;
  }
  .section-heading:first-child { margin-top: 0; }

  ${''}
  /* Sermon block (inside left) */
  .sermon-block {
    background: var(--accent-light); border-left: 4px solid var(--accent);
    border-radius: 4px; padding: 8px 12px; margin-bottom: 12px;
  }
  .sermon-title    { font-size: 13pt; font-weight: 700; color: var(--accent); line-height: 1.2; }
  .sermon-speaker  { font-size: 8.5pt; color: var(--muted); margin-top: 3px; }
  .sermon-scripture{ font-size: 8.5pt; font-style: italic; color: var(--text); margin-top: 2px; }

  $_componentCss
</style>
</head>
<body>
<button class="print-btn" onclick="window.print()">🖨 Print / Save as PDF</button>

<!-- ═══ SHEET 1: Back (left) + Front/Cover (right) ═══ -->
<div class="sheet">

  <!-- Panel 1L: Back cover — church info + prayer + contact card -->
  <div class="panel back-cover">
    <div>
      <div class="section-heading">Prayer Requests</div>
      ${_prayerHtml(b.prayerRequests)}
    </div>
    <div>
      ${b.includeContactCard ? _contactCardHtml(b) : ''}
      ${_churchInfoHtml(b)}
    </div>
  </div>

  <div class="panel-divider"></div>

  <!-- Panel 1R: Front cover -->
  <div class="panel cover">
    <div class="cover-church">${_h(b.churchName.isNotEmpty ? b.churchName : 'Church')}</div>
    ${date.isNotEmpty ? '<div class="cover-date">$date</div>' : ''}
    ${(b.sermonTitle.isNotEmpty) ? '''
    <div class="cover-divider"></div>
    <div class="cover-sermon-label">Today\'s Message</div>
    <div class="cover-sermon-title">${_h(b.sermonTitle)}</div>
    ${b.speakerName.isNotEmpty   ? '<div class="cover-speaker">${_h(b.speakerName)}</div>'     : ''}
    ${b.sermonScripture.isNotEmpty ? '<div class="cover-scripture">${_h(b.sermonScripture)}</div>' : ''}
    ''' : ''}
  </div>

</div>

<div class="page-break"></div>

<!-- ═══ SHEET 2: Inside left + Inside right ═══ -->
<div class="sheet">

  <!-- Panel 2L: Order of service + sermon info -->
  <div class="panel inside">
    ${(b.sermonTitle.isNotEmpty || b.speakerName.isNotEmpty) ? '''
    <div class="sermon-block">
      ${b.sermonTitle.isNotEmpty ? '<div class="sermon-title">${_h(b.sermonTitle)}</div>' : ''}
      ${b.speakerName.isNotEmpty ? '<div class="sermon-speaker">${_h(b.speakerName)}</div>' : ''}
      ${b.sermonScripture.isNotEmpty ? '<div class="sermon-scripture">${_h(b.sermonScripture)}</div>' : ''}
    </div>''' : ''}

    <div class="section-heading">Order of Service</div>
    ${_orderHtml(b.orderOfService)}
  </div>

  <div class="panel-divider"></div>

  <!-- Panel 2R: Announcements + sermon notes -->
  <div class="panel inside">
    <div class="section-heading">Announcements</div>
    ${_announcementsHtml(b.announcements)}

    ${b.includeSermonNotes ? '''
    <div class="section-heading">${_h(b.sermonNotesPrompt)}</div>
    ${_sermonNotesHtml(b.sermonNotesPrompt)}''' : ''}
  </div>

</div>

</body></html>''';
}

// ══════════════════════════════════════════════════════════════════════════════
// HALF-SHEET  (two identical half-pages on one letter sheet, cut apart)
// Portrait letter, two stacked half-pages separated by a cut line.
// ══════════════════════════════════════════════════════════════════════════════

String _halfSheetHtml(BulletinModel b) {
  final date = _fmtDate(b.serviceDate);
  // Build single half-page content and duplicate it
  final half = '''
<div class="half">
  <div class="half-header">
    <div class="hs-church">${_h(b.churchName.isNotEmpty ? b.churchName : 'Church')}</div>
    ${date.isNotEmpty ? '<div class="hs-date">$date</div>' : ''}
  </div>
  <div class="half-body">
    <div class="col">
      ${(b.sermonTitle.isNotEmpty || b.speakerName.isNotEmpty) ? '''
      <div class="sermon-mini">
        ${b.sermonTitle.isNotEmpty ? '<div class="sm-title">${_h(b.sermonTitle)}</div>' : ''}
        ${b.speakerName.isNotEmpty ? '<div class="sm-speaker">${_h(b.speakerName)}</div>' : ''}
        ${b.sermonScripture.isNotEmpty ? '<div class="sm-scripture">${_h(b.sermonScripture)}</div>' : ''}
      </div>''' : ''}
      <div class="section-heading">Order of Service</div>
      ${_orderHtml(b.orderOfService)}
      ${b.prayerRequests.trim().isNotEmpty ? '<div class="section-heading">Prayer</div>${_prayerHtml(b.prayerRequests)}' : ''}
    </div>
    <div class="col">
      <div class="section-heading">Announcements</div>
      ${_announcementsHtml(b.announcements)}
      ${b.includeSermonNotes ? '<div class="section-heading">${_h(b.sermonNotesPrompt)}</div>${_sermonNotesHtml(b.sermonNotesPrompt)}' : ''}
    </div>
  </div>
  ${_churchInfoHtml(b)}
</div>''';

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${_h(b.title)}</title>
<style>
  ${_cssVars(b)}
  @media print { @page { size: letter portrait; margin: 0; } }
  * { box-sizing: border-box; }
  body { font-family: 'Calibri', 'Segoe UI', Arial, sans-serif; margin: 0; padding: 0; }

  .half { width: 8.5in; height: 5.49in; padding: .35in .45in; overflow: hidden; }
  .cut-line {
    border-top: 1px dashed #bbb; text-align: center;
    font-size: 7pt; color: #bbb; line-height: 0; margin: 0;
    height: .02in;
  }
  .cut-line span { background: white; padding: 0 8px; }

  .half-header {
    text-align: center; border-bottom: 3px solid var(--accent);
    padding-bottom: 8px; margin-bottom: 10px;
  }
  .hs-church { font-size: 16pt; font-weight: 800; color: var(--accent); }
  .hs-date   { font-size: 9.5pt; color: var(--muted); }

  .half-body { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .col { /* single column */ }

  .sermon-mini { background: var(--accent-light); border-left: 3px solid var(--accent);
    padding: 6px 10px; border-radius: 3px; margin-bottom: 8px; }
  .sm-title   { font-size: 10.5pt; font-weight: 700; color: var(--accent); }
  .sm-speaker { font-size: 8pt; color: var(--muted); }
  .sm-scripture { font-size: 8pt; font-style: italic; color: var(--text); }

  $_componentCss
</style>
</head>
<body>
<button class="print-btn" onclick="window.print()">🖨 Print / Save as PDF</button>
$half
<div class="cut-line"><span>✂ cut here</span></div>
$half
</body></html>''';
}

// ══════════════════════════════════════════════════════════════════════════════
// TRI-FOLD  (letter landscape, folded in thirds → 6 panels)
// Sheet 1 (outside): [back | spine/address | cover]
// Sheet 2 (inside):  [left | center | right]
// ══════════════════════════════════════════════════════════════════════════════

String _trifoldHtml(BulletinModel b) {
  final date = _fmtDate(b.serviceDate);
  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${_h(b.title)}</title>
<style>
  ${_cssVars(b)}
  @media print {
    @page { size: letter landscape; margin: 0; }
    .page-break { page-break-after: always; }
  }
  * { box-sizing: border-box; }
  body { font-family: 'Calibri', 'Segoe UI', Arial, sans-serif; margin: 0; padding: 0; font-size: 9pt; }

  .sheet { display: flex; width: 11in; height: 8.5in; }
  .panel { width: 3.667in; height: 8.5in; padding: .38in .3in; overflow: hidden; }
  .panel-divider { width: 0; border-left: 1px dashed #ccc; }

  /* Cover panel (rightmost on outside sheet) */
  .cover {
    background: var(--accent); color: white;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    text-align: center; gap: 4px;
  }
  .cv-church  { font-size: 16pt; font-weight: 800; }
  .cv-date    { font-size: 10pt; opacity: .8; }
  .cv-divider { width: 40px; height: 2px; background: rgba(255,255,255,.4); margin: 10px auto; }
  .cv-label   { font-size: 7pt; text-transform: uppercase; letter-spacing: .1em; opacity: .6; }
  .cv-sermon  { font-size: 12pt; font-weight: 700; line-height: 1.25; }
  .cv-speaker { font-size: 8.5pt; opacity: .75; }
  .cv-scripture { font-size: 8pt; opacity: .65; font-style: italic; }

  /* Spine/address panel (center on outside) */
  .spine {
    background: #F8F9FA;
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    text-align: center;
  }
  .spine-name { font-size: 11pt; font-weight: 700; color: var(--accent); }
  .spine-info { font-size: 7.5pt; color: var(--muted); margin-top: 6px; line-height: 1.6; }

  /* Inside panels */
  .inside { background: #fff; }

  .section-heading {
    font-size: 8pt; font-weight: 800; letter-spacing: .08em;
    text-transform: uppercase; color: var(--accent);
    border-bottom: 1.5px solid var(--accent); padding-bottom: 2px;
    margin: 10px 0 5px;
  }
  .section-heading:first-child { margin-top: 0; }

  .sermon-block {
    background: var(--accent-light); border-left: 3px solid var(--accent);
    border-radius: 3px; padding: 7px 10px; margin-bottom: 10px;
  }
  .sermon-title    { font-size: 11pt; font-weight: 700; color: var(--accent); line-height: 1.2; }
  .sermon-speaker  { font-size: 8pt; color: var(--muted); margin-top: 2px; }
  .sermon-scripture{ font-size: 8pt; font-style: italic; color: var(--text); margin-top: 2px; }

  $_componentCss
</style>
</head>
<body>
<button class="print-btn" onclick="window.print()">🖨 Print / Save as PDF</button>

<!-- ═══ SHEET 1 OUTSIDE: [Back | Spine | Cover] ═══ -->
<div class="sheet">

  <!-- Panel L: Back — prayer + contact card -->
  <div class="panel inside">
    <div class="section-heading">Prayer Requests</div>
    ${_prayerHtml(b.prayerRequests)}
    ${b.includeContactCard ? _contactCardHtml(b) : ''}
  </div>
  <div class="panel-divider"></div>

  <!-- Panel C: Spine / address label -->
  <div class="panel spine">
    <div class="spine-name">${_h(b.churchName.isNotEmpty ? b.churchName : 'Church')}</div>
    <div class="spine-info">
      ${b.churchAddress.isNotEmpty ? _h(b.churchAddress) + '<br>' : ''}
      ${b.churchPhone.isNotEmpty   ? _h(b.churchPhone)   + '<br>' : ''}
      ${b.churchWebsite.isNotEmpty ? _h(b.churchWebsite)          : ''}
    </div>
  </div>
  <div class="panel-divider"></div>

  <!-- Panel R: Cover -->
  <div class="panel cover">
    <div class="cv-church">${_h(b.churchName.isNotEmpty ? b.churchName : 'Church')}</div>
    ${date.isNotEmpty ? '<div class="cv-date">$date</div>' : ''}
    ${b.sermonTitle.isNotEmpty ? '''
    <div class="cv-divider"></div>
    <div class="cv-label">Today\'s Message</div>
    <div class="cv-sermon">${_h(b.sermonTitle)}</div>
    ${b.speakerName.isNotEmpty    ? '<div class="cv-speaker">${_h(b.speakerName)}</div>'       : ''}
    ${b.sermonScripture.isNotEmpty ? '<div class="cv-scripture">${_h(b.sermonScripture)}</div>' : ''}
    ''' : ''}
  </div>
</div>

<div class="page-break"></div>

<!-- ═══ SHEET 2 INSIDE: [Left | Center | Right] ═══ -->
<div class="sheet">

  <!-- Panel L: Order of service -->
  <div class="panel inside">
    ${(b.sermonTitle.isNotEmpty || b.speakerName.isNotEmpty) ? '''
    <div class="sermon-block">
      ${b.sermonTitle.isNotEmpty ? '<div class="sermon-title">${_h(b.sermonTitle)}</div>' : ''}
      ${b.speakerName.isNotEmpty ? '<div class="sermon-speaker">${_h(b.speakerName)}</div>' : ''}
      ${b.sermonScripture.isNotEmpty ? '<div class="sermon-scripture">${_h(b.sermonScripture)}</div>' : ''}
    </div>''' : ''}
    <div class="section-heading">Order of Service</div>
    ${_orderHtml(b.orderOfService)}
  </div>
  <div class="panel-divider"></div>

  <!-- Panel C: Announcements -->
  <div class="panel inside">
    <div class="section-heading">Announcements</div>
    ${_announcementsHtml(b.announcements)}
  </div>
  <div class="panel-divider"></div>

  <!-- Panel R: Sermon notes -->
  <div class="panel inside">
    ${b.includeSermonNotes ? '''
    <div class="section-heading">${_h(b.sermonNotesPrompt)}</div>
    ${_sermonNotesHtml(b.sermonNotesPrompt)}''' : '<div class="section-heading">Notes</div>'}
  </div>

</div>

</body></html>''';
}