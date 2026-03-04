// lib/apps/notes/note_exporter.dart
//
// Pure Dart/Flutter export for sermon notes.
// • DOCX  — builds a real .docx ZIP (OpenXML) using the archive package.
// • PDF   — generates a styled HTML file, saves it, then opens it in the
//            browser where the user can File → Print → Save as PDF.
// • DOCX import — extracts plain text from an uploaded .docx ZIP.
//
// No Python, Node.js, or external tools required.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ── PUBLIC API ────────────────────────────────────────────────────────────────

/// Writes a .docx file to [outputPath] from [noteData].
/// [noteData] must contain: title, content, and optionally date, messageType,
/// folder, subfolder, seriesName, bookOfBible, translation.
Future<void> exportDocx(Map<String, dynamic> noteData, String outputPath) async {
  final bytes = _buildDocxBytes(noteData);
  await File(outputPath).writeAsBytes(bytes);
}

/// Generates an HTML file from [noteData], saves it to a temp location,
/// then opens it in the default browser. The user can print/save as PDF.
Future<void> exportHtmlForPdf(Map<String, dynamic> noteData) async {
  final tmp  = await getTemporaryDirectory();
  final safe = (noteData['title'] as String? ?? 'note')
      .replaceAll(RegExp(r'[^\w\s\-]'), '')
      .trim()
      .replaceAll(' ', '_');
  final file = File('${tmp.path}/${safe}_print.html');
  await file.writeAsString(_buildPrintHtml(noteData));
  final uri = Uri.file(file.path);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Reads text from a .docx file at [path] using pure Dart ZIP extraction.
/// Returns the extracted plain text, or null on failure.
String? extractTextFromDocx(String path) {
  try {
    final bytes   = File(path).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    // word/document.xml contains the main body text
    final docXml = archive
        .files
        .where((f) => f.name == 'word/document.xml' && f.isFile)
        .firstOrNull;
    if (docXml == null) return null;

    final xml = utf8.decode(docXml.content as List<int>);
    return _xmlToPlainText(xml);
  } catch (e) {
    return null;
  }
}

/// Extracts plain text from raw .docx bytes (works on all platforms, no file path needed).
String? extractTextFromDocxBytes(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final docXml = archive.files
        .where((f) => f.name == 'word/document.xml' && f.isFile)
        .firstOrNull;
    if (docXml == null) return null;
    final xml = utf8.decode(docXml.content as List<int>);
    return _xmlToPlainText(xml);
  } catch (e) {
    return null;
  }
}

// ── DOCX BUILDER ─────────────────────────────────────────────────────────────

Uint8List _buildDocxBytes(Map<String, dynamic> n) {
  final title      = _e(n['title']      as String? ?? 'Untitled Note');
  final content    = n['content']        as String? ?? '';
  final date       = n['date']           as String? ?? '';
  final msgType    = n['messageType']    as String? ?? '';
  final folder     = n['folder']         as String? ?? '';
  final subfolder  = n['subfolder']      as String? ?? '';
  final series     = n['seriesName']     as String? ?? '';
  final translation= n['translation']    as String? ?? '';

  // ── [Content_Types].xml ───────────────────────────────────────────────────
  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

  // ── _rels/.rels ────────────────────────────────────────────────────────────
  const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Target="word/document.xml"/>
</Relationships>''';

  // ── word/_rels/document.xml.rels ──────────────────────────────────────────
  const docRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"
    Target="styles.xml"/>
</Relationships>''';

  // ── word/styles.xml ────────────────────────────────────────────────────────
  const styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
        <w:sz w:val="24"/>
      </w:rPr>
    </w:rPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:styleId="Normal">
    <w:name w:val="Normal"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:outlineLvl w:val="0"/></w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
      <w:b/>
      <w:sz w:val="40"/>
      <w:color w:val="1A3A5C"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:outlineLvl w:val="1"/></w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
      <w:b/>
      <w:sz w:val="28"/>
      <w:color w:val="1A3A5C"/>
    </w:rPr>
  </w:style>
</w:styles>''';

  // ── Build metadata rows ────────────────────────────────────────────────────
  final metaRows = <String>[];
  void addMeta(String label, String val) {
    if (val.isEmpty) return;
    metaRows.add(_metaPara(label, val));
  }
  addMeta('Date',        date);
  addMeta('Type',        msgType);
  addMeta('Folder',      folder);
  addMeta('Topic',       subfolder);
  addMeta('Series',      series);
  addMeta('Translation', translation);

  // ── Build body paragraphs ─────────────────────────────────────────────────
  final bodyParas = <String>[];
  for (final line in content.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) {
      bodyParas.add('<w:p><w:pPr><w:spacing w:after="0"/></w:pPr></w:p>');
      continue;
    }
    final isQuote = t.startsWith('"') || t.startsWith('\u201c') || t.startsWith('—') || t.startsWith('\u2014');
    if (isQuote) {
      bodyParas.add(_quotePara(line));
    } else {
      bodyParas.add(_bodyPara(line));
    }
  }

  // ── word/document.xml ─────────────────────────────────────────────────────
  final document = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <!-- Title -->
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Heading1"/>
        <w:spacing w:before="0" w:after="200"/>
      </w:pPr>
      <w:r><w:t>$title</w:t></w:r>
    </w:p>
    <!-- Meta -->
    ${metaRows.join('\n    ')}
    ${metaRows.isNotEmpty ? _dividerPara() : ''}
    <!-- Body -->
    ${bodyParas.join('\n    ')}
    <!-- Section end -->
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''';

  // ── Assemble ZIP ──────────────────────────────────────────────────────────
  final archive = Archive();
  void addFile(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addFile('[Content_Types].xml',              contentTypes);
  addFile('_rels/.rels',                      rels);
  addFile('word/_rels/document.xml.rels',     docRels);
  addFile('word/styles.xml',                  styles);
  addFile('word/document.xml',                document);

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

// ── XML HELPERS ───────────────────────────────────────────────────────────────

String _e(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _metaPara(String label, String value) => '''<w:p>
      <w:pPr><w:spacing w:before="60" w:after="60"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:color w:val="1A3A5C"/><w:sz w:val="20"/></w:rPr>
        <w:t xml:space="preserve">${_e(label)}: </w:t>
      </w:r>
      <w:r>
        <w:rPr><w:sz w:val="20"/></w:rPr>
        <w:t>${_e(value)}</w:t>
      </w:r>
    </w:p>''';

String _dividerPara() => '''<w:p>
      <w:pPr>
        <w:spacing w:before="120" w:after="120"/>
        <w:pBdr>
          <w:bottom w:val="single" w:sz="6" w:space="1" w:color="1A3A5C"/>
        </w:pBdr>
      </w:pPr>
    </w:p>''';

String _bodyPara(String line) => '''<w:p>
      <w:pPr><w:spacing w:before="80" w:after="80"/></w:pPr>
      <w:r>
        <w:rPr><w:sz w:val="24"/></w:rPr>
        <w:t xml:space="preserve">${_e(line)}</w:t>
      </w:r>
    </w:p>''';

String _quotePara(String line) => '''<w:p>
      <w:pPr>
        <w:spacing w:before="100" w:after="100"/>
        <w:ind w:left="720" w:right="720"/>
        <w:shd w:val="clear" w:color="auto" w:fill="F0F4FF"/>
      </w:pPr>
      <w:r>
        <w:rPr><w:i/><w:color w:val="374151"/><w:sz w:val="24"/></w:rPr>
        <w:t xml:space="preserve">${_e(line)}</w:t>
      </w:r>
    </w:p>''';

// ── DOCX TEXT EXTRACTOR ───────────────────────────────────────────────────────

String _xmlToPlainText(String xml) {
  // Extract all <w:t> element contents and join with spaces/newlines
  final tPattern = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
  final pEnd     = RegExp(r'</w:p>');

  // We want paragraph breaks — replace </w:p> with newlines first
  var s = xml.replaceAll(pEnd, '\n');
  // Extract text runs
  final buf = StringBuffer();
  for (final m in tPattern.allMatches(s)) {
    buf.write(m.group(1));
  }
  // Decode XML entities
  return buf.toString()
      .replaceAll('&amp;',  '&')
      .replaceAll('&lt;',   '<')
      .replaceAll('&gt;',   '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

// ── HTML / PRINT-TO-PDF BUILDER ───────────────────────────────────────────────

String _buildPrintHtml(Map<String, dynamic> n) {
  final title      = n['title']       as String? ?? 'Untitled Note';
  final content    = n['content']     as String? ?? '';
  final date       = n['date']        as String? ?? '';
  final msgType    = n['messageType'] as String? ?? '';
  final folder     = n['folder']      as String? ?? '';
  final subfolder  = n['subfolder']   as String? ?? '';
  final series     = n['seriesName']  as String? ?? '';
  final translation= n['translation'] as String? ?? '';

  String _h(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  final metaRows = <String>[];
  void addMeta(String label, String val) {
    if (val.isEmpty) return;
    metaRows.add('<tr><td><b>${_h(label)}</b></td><td>${_h(val)}</td></tr>');
  }
  addMeta('Date',        date);
  addMeta('Type',        msgType);
  addMeta('Folder',      folder);
  addMeta('Topic',       subfolder);
  addMeta('Series',      series);
  addMeta('Translation', translation);

  final bodyLines = content.split('\n').map((line) {
    final t = line.trim();
    if (t.isEmpty) return '<br>';
    final isQuote = t.startsWith('"') || t.startsWith('\u201c')
        || t.startsWith('—') || t.startsWith('\u2014');
    if (isQuote) {
      return '<blockquote>${_h(line)}</blockquote>';
    }
    return '<p>${_h(line)}</p>';
  }).join('\n');

  final now = DateFormat('MMMM d, yyyy').format(DateTime.now());

  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${_h(title)}</title>
  <style>
    @media print {
      @page { margin: 1in; }
      .no-print { display: none; }
    }
    body {
      font-family: 'Calibri', 'Segoe UI', Arial, sans-serif;
      font-size: 12pt;
      line-height: 1.7;
      color: #1C1C2E;
      max-width: 720px;
      margin: 40px auto;
      padding: 0 24px;
    }
    h1 {
      font-size: 26pt;
      color: #1A3A5C;
      margin: 0 0 16px;
      line-height: 1.2;
    }
    table.meta {
      border-collapse: collapse;
      margin-bottom: 20px;
      font-size: 10pt;
    }
    table.meta td { padding: 3px 16px 3px 0; color: #444; }
    table.meta td:first-child { color: #1A3A5C; font-weight: 600; white-space: nowrap; }
    hr { border: none; border-top: 2px solid #1A3A5C; margin: 20px 0; }
    p { margin: 6px 0; }
    blockquote {
      margin: 12px 0 12px 24px;
      padding: 10px 16px;
      border-left: 3px solid #1A3A5C;
      background: #F0F4FF;
      font-style: italic;
      color: #374151;
    }
    .footer {
      margin-top: 48px;
      font-size: 9pt;
      color: #9CA3AF;
      text-align: center;
    }
    .print-btn {
      position: fixed;
      top: 20px;
      right: 20px;
      background: #1A3A5C;
      color: white;
      border: none;
      padding: 10px 20px;
      font-size: 13px;
      border-radius: 8px;
      cursor: pointer;
    }
    .print-btn:hover { background: #2a5a8c; }
  </style>
</head>
<body>
  <button class="print-btn no-print" onclick="window.print()">🖨 Print / Save as PDF</button>
  <h1>${_h(title)}</h1>
  ${metaRows.isNotEmpty ? '<table class="meta">${metaRows.join()}</table><hr>' : ''}
  $bodyLines
  <div class="footer">Generated by Church Plant Toolkit · $now</div>
</body>
</html>''';
}