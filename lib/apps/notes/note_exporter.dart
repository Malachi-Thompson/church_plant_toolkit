// lib/apps/notes/note_exporter.dart
//
// Pure Dart/Flutter export for sermon notes.
// Content is stored as Quill HTML — all three export paths convert it
// to properly formatted output with NO raw HTML visible to the user.
//
// • DOCX  — builds a real .docx ZIP (OpenXML). Bold, italic, underline,
//           strikethrough, h1/h2/h3, bullet lists, numbered lists, and
//           blockquotes are all mapped to native Word styles/runs.
// • ODT   — builds a real .odt ZIP (ODF). Same formatting mapped to
//           named automatic styles so LibreOffice renders them correctly.
// • PDF   — generates a styled HTML file and opens it in the browser
//           for File → Print → Save as PDF.  The HTML already has proper
//           CSS so every formatting element renders visually.
// • DOCX import — extracts rich HTML from an uploaded .docx.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

Future<void> exportDocx(Map<String, dynamic> noteData, String outputPath) async {
  await File(outputPath).writeAsBytes(_buildDocxBytes(noteData));
}

Future<void> exportOdt(Map<String, dynamic> noteData, String outputPath) async {
  await File(outputPath).writeAsBytes(_buildOdtBytes(noteData));
}

Future<void> exportHtmlForPdf(Map<String, dynamic> noteData) async {
  final tmp  = await getTemporaryDirectory();
  final safe = (noteData['title'] as String? ?? 'note')
      .replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');
  final file = File('${tmp.path}/${safe}_print.html');
  await file.writeAsString(_buildPrintHtml(noteData));
  final uri = Uri.file(file.path);
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String? extractTextFromDocx(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    return extractTextFromDocxBytes(bytes);
  } catch (_) { return null; }
}

String? extractTextFromDocxBytes(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final f = archive.files.where((f) => f.name == 'word/document.xml' && f.isFile).firstOrNull;
    if (f == null) return null;
    return _xmlToPlainText(utf8.decode(f.content as List<int>));
  } catch (_) { return null; }
}

String? extractHtmlFromDocx(String path) {
  try { return extractHtmlFromDocxBytes(File(path).readAsBytesSync()); }
  catch (_) { return null; }
}

String? extractHtmlFromDocxBytes(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final f = archive.files.where((f) => f.name == 'word/document.xml' && f.isFile).firstOrNull;
    if (f == null) return null;
    return _xmlToHtml(utf8.decode(f.content as List<int>));
  } catch (_) { return null; }
}

// ─────────────────────────────────────────────────────────────────────────────
// HTML PARSER  (shared by DOCX and ODT builders)
// ─────────────────────────────────────────────────────────────────────────────
//
// Quill outputs HTML like:
//   <h1>Title</h1>
//   <p><strong>Bold</strong> and <em>italic</em></p>
//   <blockquote>A quote</blockquote>
//   <ul><li>Item</li></ul>
//   <ol><li>Item</li></ol>
//
// _parseBlocks() splits this into a flat list of _Block objects.

enum _BlockType { h1, h2, h3, body, blockquote, bulletItem, numberedItem }

class _Block {
  final _BlockType type;
  final List<_Run> runs;
  _Block(this.type, this.runs);
}

class _Run {
  final String text;
  final bool bold, italic, underline, strike;
  _Run(this.text, {this.bold=false, this.italic=false,
      this.underline=false, this.strike=false});
}

/// Parse HTML content into a flat list of [_Block] objects.
List<_Block> _parseBlocks(String html) {
  if (html.trim().isEmpty) return [];

  // Plain-text fallback
  if (!html.trimLeft().startsWith('<')) {
    return html.split('\n').map((l) => _Block(_BlockType.body, [_Run(l)])).toList();
  }

  // Normalise self-closing <br>
  final norm = html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  final blocks = <_Block>[];
  int pos = 0;

  while (pos < norm.length) {
    // Skip whitespace between blocks
    while (pos < norm.length && norm[pos].trim().isEmpty) pos++;
    if (pos >= norm.length) break;

    if (norm[pos] != '<') {
      // Bare text between block tags
      final end = norm.indexOf('<', pos);
      final text = norm.substring(pos, end < 0 ? norm.length : end).trim();
      if (text.isNotEmpty) blocks.add(_Block(_BlockType.body, _parseInline(text)));
      pos = end < 0 ? norm.length : end;
      continue;
    }

    // Identify opening tag
    final tagEnd = norm.indexOf('>', pos);
    if (tagEnd < 0) break;
    final tagStr = norm.substring(pos + 1, tagEnd).trim().toLowerCase().split(RegExp(r'\s'))[0];

    if (tagStr == 'ul' || tagStr == 'ol') {
      // Find closing tag
      final closeTag = '</$tagStr>';
      final closeIdx = norm.toLowerCase().indexOf(closeTag, tagEnd);
      final body = closeIdx >= 0 ? norm.substring(tagEnd + 1, closeIdx) : '';
      final isOl  = tagStr == 'ol';
      final liRe  = RegExp(r'<li(?:\s[^>]*)?>([\s\S]*?)</li>', caseSensitive: false);
      for (final m in liRe.allMatches(body)) {
        blocks.add(_Block(
          isOl ? _BlockType.numberedItem : _BlockType.bulletItem,
          _parseInline(m.group(1)!),
        ));
      }
      pos = closeIdx >= 0 ? closeIdx + closeTag.length : norm.length;
      continue;
    }

    // Block-level tags: h1, h2, h3, p, blockquote
    final closeTag = '</$tagStr>';
    final closeIdx = norm.toLowerCase().indexOf(closeTag, tagEnd);
    if (closeIdx < 0) { pos = tagEnd + 1; continue; }

    final inner = norm.substring(tagEnd + 1, closeIdx);
    _BlockType type;
    switch (tagStr) {
      case 'h1': type = _BlockType.h1; break;
      case 'h2': type = _BlockType.h2; break;
      case 'h3': type = _BlockType.h3; break;
      case 'blockquote': type = _BlockType.blockquote; break;
      default: type = _BlockType.body;
    }
    blocks.add(_Block(type, _parseInline(inner)));
    pos = closeIdx + closeTag.length;
  }

  return blocks;
}

/// Parse inline HTML (bold/italic/underline/strike/br) into a list of [_Run]s.
List<_Run> _parseInline(String html) {
  if (html.trim().isEmpty) return [];
  final runs = <_Run>[];
  bool b = false, i = false, u = false, s = false;

  final re = RegExp(r'<(/?)(\w+)(?:\s[^>]*)?>|([^<]+)', dotAll: true);
  for (final m in re.allMatches(html)) {
    if (m.group(3) != null) {
      // Text node — split on literal \n from <br> substitution
      for (final part in m.group(3)!.split('\n')) {
        final t = _unescapeHtml(part);
        if (t.isNotEmpty) runs.add(_Run(t, bold: b, italic: i, underline: u, strike: s));
        // emit an empty run as line-break marker if there was a \n
      }
    } else {
      final closing = m.group(1) == '/';
      switch (m.group(2)!.toLowerCase()) {
        case 'strong': case 'b': b = !closing; break;
        case 'em':     case 'i': i = !closing; break;
        case 'u':                u = !closing; break;
        case 's': case 'del':    s = !closing; break;
      }
    }
  }
  return runs;
}

String _unescapeHtml(String s) => s
    .replaceAll('&amp;',  '&')
    .replaceAll('&lt;',   '<')
    .replaceAll('&gt;',   '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;',  "'")
    .replaceAll('&apos;', "'");

// ─────────────────────────────────────────────────────────────────────────────
// DOCX BUILDER
// ─────────────────────────────────────────────────────────────────────────────

Uint8List _buildDocxBytes(Map<String, dynamic> n) {
  final title       = _e(n['title']       as String? ?? 'Untitled Note');
  final content     = n['content']        as String? ?? '';
  final date        = n['date']           as String? ?? '';
  final msgType     = n['messageType']    as String? ?? '';
  final folder      = n['folder']         as String? ?? '';
  final subfolder   = n['subfolder']      as String? ?? '';
  final series      = n['seriesName']     as String? ?? '';
  final translation = n['translation']    as String? ?? '';

  // ── [Content_Types].xml ──────────────────────────────────────────────────
  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
</Types>''';

  // ── _rels/.rels ──────────────────────────────────────────────────────────
  const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Target="word/document.xml"/>
</Relationships>''';

  // ── word/_rels/document.xml.rels ────────────────────────────────────────
  const docRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"
    Target="styles.xml"/>
  <Relationship Id="rId2"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"
    Target="numbering.xml"/>
</Relationships>''';

  // ── word/styles.xml ──────────────────────────────────────────────────────
  const styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault><w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
      <w:sz w:val="24"/>
    </w:rPr></w:rPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:outlineLvl w:val="0"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="40"/><w:color w:val="1A3A5C"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:outlineLvl w:val="1"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="1A3A5C"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:outlineLvl w:val="2"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="2D5A8C"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="BlockQuote">
    <w:name w:val="Block Quote"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:ind w:left="720" w:right="720"/>
      <w:shd w:val="clear" w:color="auto" w:fill="F0F4FF"/>
    </w:pPr>
    <w:rPr><w:i/><w:color w:val="374151"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="ListParagraph">
    <w:name w:val="List Paragraph"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:ind w:left="720"/></w:pPr>
  </w:style>
</w:styles>''';

  // ── word/numbering.xml (bullet numId=1, decimal numId=2) ─────────────────
  const numbering = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="bullet"/>
      <w:lvlText w:val="•"/>
      <w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:abstractNum w:abstractNumId="1">
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="decimal"/>
      <w:lvlText w:val="%1."/>
      <w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
  <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>''';

  // ── Metadata rows ────────────────────────────────────────────────────────
  final metaRows = <String>[];
  void addMeta(String label, String val) {
    if (val.isEmpty) return;
    metaRows.add('''<w:p>
      <w:pPr><w:spacing w:before="60" w:after="60"/></w:pPr>
      <w:r><w:rPr><w:b/><w:color w:val="1A3A5C"/><w:sz w:val="20"/></w:rPr>
        <w:t xml:space="preserve">${_e(label)}: </w:t></w:r>
      <w:r><w:rPr><w:sz w:val="20"/></w:rPr>
        <w:t>${_e(val)}</w:t></w:r>
    </w:p>''');
  }
  addMeta('Date', date); addMeta('Type', msgType);
  addMeta('Folder', folder); addMeta('Topic', subfolder);
  addMeta('Series', series); addMeta('Translation', translation);

  // ── Body paragraphs from HTML ────────────────────────────────────────────
  final blocks = _parseBlocks(content);
  final bodyParas = StringBuffer();
  for (final block in blocks) {
    bodyParas.writeln(_blockToDocxPara(block));
  }

  // ── word/document.xml ────────────────────────────────────────────────────
  final document = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/>
        <w:spacing w:before="0" w:after="200"/></w:pPr>
      <w:r><w:t>$title</w:t></w:r>
    </w:p>
    ${metaRows.join('\n    ')}
    ${metaRows.isNotEmpty ? '''<w:p><w:pPr><w:spacing w:before="120" w:after="120"/>
      <w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="1A3A5C"/></w:pBdr>
    </w:pPr></w:p>''' : ''}
    ${bodyParas.toString()}
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''';

  // ── Assemble ZIP ─────────────────────────────────────────────────────────
  final archive = Archive();
  void addXml(String name, String xml) {
    final b = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, b.length, b));
  }
  addXml('[Content_Types].xml',          contentTypes);
  addXml('_rels/.rels',                  rels);
  addXml('word/_rels/document.xml.rels', docRels);
  addXml('word/styles.xml',             styles);
  addXml('word/numbering.xml',          numbering);
  addXml('word/document.xml',           document);
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

String _blockToDocxPara(_Block block) {
  final runs = block.runs.map(_runToDocxRun).join();
  switch (block.type) {
    case _BlockType.h1:
      return '<w:p><w:pPr><w:pStyle w:val="Heading1"/>'
          '<w:spacing w:before="200" w:after="80"/></w:pPr>$runs</w:p>';
    case _BlockType.h2:
      return '<w:p><w:pPr><w:pStyle w:val="Heading2"/>'
          '<w:spacing w:before="160" w:after="60"/></w:pPr>$runs</w:p>';
    case _BlockType.h3:
      return '<w:p><w:pPr><w:pStyle w:val="Heading3"/>'
          '<w:spacing w:before="120" w:after="40"/></w:pPr>$runs</w:p>';
    case _BlockType.blockquote:
      return '<w:p><w:pPr><w:pStyle w:val="BlockQuote"/>'
          '<w:spacing w:before="100" w:after="100"/></w:pPr>$runs</w:p>';
    case _BlockType.bulletItem:
      return '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/>'
          '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>'
          '<w:spacing w:before="40" w:after="40"/></w:pPr>$runs</w:p>';
    case _BlockType.numberedItem:
      return '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/>'
          '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr>'
          '<w:spacing w:before="40" w:after="40"/></w:pPr>$runs</w:p>';
    case _BlockType.body:
      if (block.runs.isEmpty || block.runs.every((r) => r.text.trim().isEmpty)) {
        return '<w:p><w:pPr><w:spacing w:after="0"/></w:pPr></w:p>';
      }
      return '<w:p><w:pPr><w:spacing w:before="80" w:after="80"/></w:pPr>$runs</w:p>';
  }
}

String _runToDocxRun(_Run r) {
  if (r.text.isEmpty) return '';
  final rPr = StringBuffer('<w:rPr><w:sz w:val="24"/>');
  if (r.bold)      rPr.write('<w:b/>');
  if (r.italic)    rPr.write('<w:i/>');
  if (r.underline) rPr.write('<w:u w:val="single"/>');
  if (r.strike)    rPr.write('<w:strike/>');
  rPr.write('</w:rPr>');
  return '<w:r>$rPr<w:t xml:space="preserve">${_e(r.text)}</w:t></w:r>';
}

// ─────────────────────────────────────────────────────────────────────────────
// ODT BUILDER
// ─────────────────────────────────────────────────────────────────────────────

Uint8List _buildOdtBytes(Map<String, dynamic> n) {
  final title       = n['title']       as String? ?? 'Untitled Note';
  final content     = n['content']     as String? ?? '';
  final date        = n['date']        as String? ?? '';
  final msgType     = n['messageType'] as String? ?? '';
  final folder      = n['folder']      as String? ?? '';
  final subfolder   = n['subfolder']   as String? ?? '';
  final series      = n['seriesName']  as String? ?? '';
  final translation = n['translation'] as String? ?? '';

  const mimeType = 'application/vnd.oasis.opendocument.text';

  const manifest = '''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
    manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml"  manifest:media-type="text/xml"/>
</manifest:manifest>''';

  // Named paragraph/character styles used in content.xml.
  // ODF requires all formatting to reference named styles —
  // inline style attributes are NOT supported on text:span.
  const stylesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
    xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
    office:version="1.2">
  <office:styles>
    <!-- Paragraph styles -->
    <style:style style:name="Default" style:family="paragraph">
      <style:text-properties fo:font-size="12pt" fo:font-family="Calibri"/>
    </style:style>
    <style:style style:name="Heading1" style:family="paragraph" style:parent-style-name="Default">
      <style:paragraph-properties fo:margin-top="0.15in" fo:margin-bottom="0.08in"/>
      <style:text-properties fo:font-size="20pt" fo:font-weight="bold" fo:color="#1A3A5C"/>
    </style:style>
    <style:style style:name="Heading2" style:family="paragraph" style:parent-style-name="Default">
      <style:paragraph-properties fo:margin-top="0.12in" fo:margin-bottom="0.05in"/>
      <style:text-properties fo:font-size="15pt" fo:font-weight="bold" fo:color="#1A3A5C"/>
    </style:style>
    <style:style style:name="Heading3" style:family="paragraph" style:parent-style-name="Default">
      <style:paragraph-properties fo:margin-top="0.10in" fo:margin-bottom="0.04in"/>
      <style:text-properties fo:font-size="12pt" fo:font-weight="bold" fo:color="#2D5A8C"/>
    </style:style>
    <style:style style:name="BlockQuote" style:family="paragraph" style:parent-style-name="Default">
      <style:paragraph-properties fo:margin-left="0.5in" fo:margin-right="0.5in"
          fo:background-color="#F0F4FF" fo:padding="0.05in"
          fo:margin-top="0.08in" fo:margin-bottom="0.08in"/>
      <style:text-properties fo:font-style="italic" fo:color="#374151"/>
    </style:style>
    <style:style style:name="ListItem" style:family="paragraph" style:parent-style-name="Default">
      <style:paragraph-properties fo:margin-left="0.4in" fo:text-indent="-0.2in"
          fo:margin-top="0.02in" fo:margin-bottom="0.02in"/>
    </style:style>
    <style:style style:name="MetaLabel" style:family="text">
      <style:text-properties fo:font-weight="bold" fo:color="#1A3A5C" fo:font-size="10pt"/>
    </style:style>
    <style:style style:name="MetaValue" style:family="text">
      <style:text-properties fo:font-size="10pt"/>
    </style:style>
    <!-- Inline character styles for run-level formatting -->
    <style:style style:name="Bold" style:family="text">
      <style:text-properties fo:font-weight="bold"/>
    </style:style>
    <style:style style:name="Italic" style:family="text">
      <style:text-properties fo:font-style="italic"/>
    </style:style>
    <style:style style:name="BoldItalic" style:family="text">
      <style:text-properties fo:font-weight="bold" fo:font-style="italic"/>
    </style:style>
    <style:style style:name="Underline" style:family="text">
      <style:text-properties style:text-underline-style="solid" style:text-underline-width="auto" style:text-underline-color="font-color"/>
    </style:style>
    <style:style style:name="Strike" style:family="text">
      <style:text-properties style:text-line-through-style="solid"/>
    </style:style>
    <style:style style:name="BoldUnderline" style:family="text">
      <style:text-properties fo:font-weight="bold" style:text-underline-style="solid" style:text-underline-width="auto" style:text-underline-color="font-color"/>
    </style:style>
    <style:style style:name="ItalicUnderline" style:family="text">
      <style:text-properties fo:font-style="italic" style:text-underline-style="solid" style:text-underline-width="auto" style:text-underline-color="font-color"/>
    </style:style>
    <style:style style:name="BoldItalicUnderline" style:family="text">
      <style:text-properties fo:font-weight="bold" fo:font-style="italic" style:text-underline-style="solid" style:text-underline-width="auto" style:text-underline-color="font-color"/>
    </style:style>
  </office:styles>
  <office:automatic-styles>
    <style:page-layout style:name="pm1">
      <style:page-layout-properties fo:page-width="8.5in" fo:page-height="11in" fo:margin="1in"/>
    </style:page-layout>
  </office:automatic-styles>
  <office:master-styles>
    <style:master-page style:name="Standard" style:page-layout-name="pm1"/>
  </office:master-styles>
</office:document-styles>''';

  // ── Build body XML ───────────────────────────────────────────────────────
  final body = StringBuffer();

  // Title
  body.writeln('<text:h text:style-name="Heading1" text:outline-level="1">'
      '${_e(title)}</text:h>');

  // Metadata
  void addMeta(String label, String val) {
    if (val.isEmpty) return;
    body.writeln('<text:p text:style-name="Default">'
        '<text:span text:style-name="MetaLabel">${_e(label)}: </text:span>'
        '<text:span text:style-name="MetaValue">${_e(val)}</text:span>'
        '</text:p>');
  }
  addMeta('Date', date); addMeta('Type', msgType);
  addMeta('Folder', folder); addMeta('Topic', subfolder);
  addMeta('Series', series); addMeta('Translation', translation);

  if ([date, msgType, folder, subfolder, series, translation].any((v) => v.isNotEmpty)) {
    body.writeln('<text:p text:style-name="Default"/>');
  }

  // Body blocks from HTML
  for (final block in _parseBlocks(content)) {
    body.writeln(_blockToOdtPara(block));
  }

  final contentXml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
    xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
    xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
    office:version="1.2">
  <office:body><office:text>
${body.toString()}
  </office:text></office:body>
</office:document-content>''';

  // ── Assemble ZIP ─────────────────────────────────────────────────────────
  final archive = Archive();
  final mimeBytes = utf8.encode(mimeType);
  final mimeFile  = ArchiveFile('mimetype', mimeBytes.length, mimeBytes);
  mimeFile.compress = false;
  archive.addFile(mimeFile);

  void addXml(String name, String xml) {
    final b = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, b.length, b));
  }
  addXml('META-INF/manifest.xml', manifest);
  addXml('styles.xml',            stylesXml);
  addXml('content.xml',           contentXml);
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

String _blockToOdtPara(_Block block) {
  final spans = _runsToOdtSpans(block.runs);
  switch (block.type) {
    case _BlockType.h1:
      return '<text:h text:style-name="Heading1" text:outline-level="1">$spans</text:h>';
    case _BlockType.h2:
      return '<text:h text:style-name="Heading2" text:outline-level="2">$spans</text:h>';
    case _BlockType.h3:
      return '<text:h text:style-name="Heading3" text:outline-level="3">$spans</text:h>';
    case _BlockType.blockquote:
      return '<text:p text:style-name="BlockQuote">$spans</text:p>';
    case _BlockType.bulletItem:
      return '<text:p text:style-name="ListItem">• $spans</text:p>';
    case _BlockType.numberedItem:
      return '<text:p text:style-name="ListItem">$spans</text:p>';
    case _BlockType.body:
      if (block.runs.isEmpty || block.runs.every((r) => r.text.trim().isEmpty)) {
        return '<text:p text:style-name="Default"/>';
      }
      return '<text:p text:style-name="Default">$spans</text:p>';
  }
}

/// Converts a list of [_Run]s to ODF XML using the named character styles
/// defined in styles.xml.  Plain (unformatted) runs are emitted as raw text.
String _runsToOdtSpans(List<_Run> runs) {
  final sb = StringBuffer();
  for (final r in runs) {
    if (r.text.isEmpty) continue;
    final esc = _e(r.text);
    final styleName = _odtCharStyle(r.bold, r.italic, r.underline, r.strike);
    if (styleName == null) {
      sb.write(esc);
    } else {
      sb.write('<text:span text:style-name="$styleName">$esc</text:span>');
    }
  }
  return sb.toString();
}

/// Returns the name of a pre-defined character style for the given combination,
/// or null if the run has no formatting (plain text).
String? _odtCharStyle(bool bold, bool italic, bool underline, bool strike) {
  if (strike)    return 'Strike';
  if (underline) {
    if (bold && italic) return 'BoldItalicUnderline';
    if (bold)           return 'BoldUnderline';
    if (italic)         return 'ItalicUnderline';
    return 'Underline';
  }
  if (bold && italic) return 'BoldItalic';
  if (bold)           return 'Bold';
  if (italic)         return 'Italic';
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// HTML / PRINT-TO-PDF BUILDER
// ─────────────────────────────────────────────────────────────────────────────

String _buildPrintHtml(Map<String, dynamic> n) {
  final title       = n['title']       as String? ?? 'Untitled Note';
  final content     = n['content']     as String? ?? '';
  final date        = n['date']        as String? ?? '';
  final msgType     = n['messageType'] as String? ?? '';
  final folder      = n['folder']      as String? ?? '';
  final subfolder   = n['subfolder']   as String? ?? '';
  final series      = n['seriesName']  as String? ?? '';
  final translation = n['translation'] as String? ?? '';

  final metaRows = <String>[];
  void addMeta(String label, String val) {
    if (val.isEmpty) return;
    metaRows.add('<tr><td><b>${_h(label)}</b></td><td>${_h(val)}</td></tr>');
  }
  addMeta('Date', date); addMeta('Type', msgType);
  addMeta('Folder', folder); addMeta('Topic', subfolder);
  addMeta('Series', series); addMeta('Translation', translation);

  // Content is Quill HTML — pass it through directly (it's already valid HTML).
  // For plain-text notes (legacy), wrap lines in <p> tags.
  final String bodyHtml;
  if (content.trimLeft().startsWith('<')) {
    bodyHtml = content;
  } else {
    bodyHtml = content.split('\n').map((l) {
      final t = l.trim();
      return t.isEmpty ? '<br>' : '<p>${_h(l)}</p>';
    }).join('\n');
  }

  final now = DateFormat('MMMM d, yyyy').format(DateTime.now());

  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${_h(title)}</title>
  <style>
    @media print { @page { margin: 1in; } .no-print { display: none; } }
    body {
      font-family: 'Calibri', 'Segoe UI', Arial, sans-serif;
      font-size: 12pt; line-height: 1.7; color: #1C1C2E;
      max-width: 720px; margin: 40px auto; padding: 0 24px;
    }
    h1 { font-size: 24pt; color: #1A3A5C; margin: 20px 0 8px; line-height: 1.2; }
    h2 { font-size: 18pt; color: #1A3A5C; margin: 16px 0 6px; }
    h3 { font-size: 13pt; color: #2D5A8C; margin: 12px 0 4px; }
    p  { margin: 4px 0; }
    ul, ol { margin: 6px 0 6px 28px; padding: 0; }
    li { margin: 2px 0; }
    blockquote {
      margin: 12px 0 12px 0; padding: 10px 16px;
      border-left: 3px solid #1A3A5C; background: #F0F4FF;
      font-style: italic; color: #374151;
    }
    table.meta { border-collapse: collapse; margin-bottom: 20px; font-size: 10pt; }
    table.meta td { padding: 3px 16px 3px 0; color: #444; }
    table.meta td:first-child { color: #1A3A5C; font-weight: 600; white-space: nowrap; }
    hr { border: none; border-top: 2px solid #1A3A5C; margin: 20px 0; }
    .footer { margin-top: 48px; font-size: 9pt; color: #9CA3AF; text-align: center; }
    .print-btn {
      position: fixed; top: 20px; right: 20px;
      background: #1A3A5C; color: white; border: none;
      padding: 10px 20px; font-size: 13px; border-radius: 8px; cursor: pointer;
    }
    .print-btn:hover { background: #2a5a8c; }
  </style>
</head>
<body>
  <button class="print-btn no-print" onclick="window.print()">🖨 Print / Save as PDF</button>
  <h1>${_h(title)}</h1>
  ${metaRows.isNotEmpty ? '<table class="meta">${metaRows.join()}</table><hr>' : ''}
  $bodyHtml
  <div class="footer">Generated by Church Plant Toolkit · $now</div>
</body>
</html>''';
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCX TEXT / HTML EXTRACTOR  (import from .docx)
// ─────────────────────────────────────────────────────────────────────────────

String _xmlToPlainText(String xml) {
  var s = xml.replaceAll(RegExp(r'</w:p>'), '\n');
  final buf = StringBuffer();
  for (final m in RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true).allMatches(s)) {
    buf.write(m.group(1));
  }
  return buf.toString()
      .replaceAll('&amp;', '&').replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>').replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _xmlToHtml(String xml) {
  final buf        = StringBuffer();
  final paraRe     = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
  final runRe      = RegExp(r'<w:r[ >].*?</w:r>', dotAll: true);
  final rPrRe      = RegExp(r'<w:rPr>(.*?)</w:rPr>', dotAll: true);
  final tRe        = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
  final pPrRe      = RegExp(r'<w:pPr>(.*?)</w:pPr>', dotAll: true);
  final styleRe    = RegExp(r'<w:pStyle w:val="([^"]+)"');
  final alignRe    = RegExp(r'<w:jc w:val="([^"]+)"');

  for (final pM in paraRe.allMatches(xml)) {
    final para  = pM.group(0)!;
    String tag  = 'p';
    String? align;

    final pPrM = pPrRe.firstMatch(para);
    if (pPrM != null) {
      final pPr = pPrM.group(1)!;
      final sM  = styleRe.firstMatch(pPr);
      if (sM != null) {
        final v = sM.group(1)!.toLowerCase();
        if (v.contains('heading1') || v == '1') tag = 'h1';
        else if (v.contains('heading2') || v == '2') tag = 'h2';
        else if (v.contains('heading3') || v == '3') tag = 'h3';
      }
      final aM = alignRe.firstMatch(pPr);
      if (aM != null) {
        switch (aM.group(1)) {
          case 'center': align = 'center'; break;
          case 'right':  align = 'right';  break;
          case 'both':   align = 'justify'; break;
        }
      }
    }

    final runsBuf = StringBuffer();
    for (final rM in runRe.allMatches(para)) {
      final run = rM.group(0)!;
      final texts = tRe.allMatches(run)
          .map((m) => _unescapeHtml(m.group(1) ?? '')).join();
      if (texts.isEmpty) continue;

      bool bold = false, italic = false, under = false, strike = false;
      final rPrM = rPrRe.firstMatch(run);
      if (rPrM != null) {
        final r = rPrM.group(1)!;
        bold   = r.contains('<w:b/>') || r.contains('<w:b ');
        italic = r.contains('<w:i/>') || r.contains('<w:i ');
        under  = r.contains('<w:u ') && !r.contains('w:val="none"');
        strike = r.contains('<w:strike/>') || r.contains('<w:strike ');
      }
      String span = _h(texts);
      if (strike) span = '<s>$span</s>';
      if (under)  span = '<u>$span</u>';
      if (italic) span = '<em>$span</em>';
      if (bold)   span = '<strong>$span</strong>';
      runsBuf.write(span);
    }

    final inner = runsBuf.toString();
    final sAttr = align != null ? ' style="text-align:$align"' : '';
    buf.writeln(inner.isEmpty ? '<p><br></p>' : '<$tag$sAttr>$inner</$tag>');
  }
  return buf.toString().trim();
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// XML/HTML encode for embedding in XML attribute values and element content.
String _e(String s) => s
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// HTML encode for the print-to-PDF builder (no attribute quoting needed).
String _h(String s) => s
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _unescapeXml(String s) => s
    .replaceAll('&amp;', '&').replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>').replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");