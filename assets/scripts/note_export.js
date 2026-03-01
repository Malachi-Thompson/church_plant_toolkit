// assets/scripts/note_export.js
// Usage: node note_export.js <input_json_path> <output_docx_path>
// Input JSON: { title, date, type, folder, subfolder, bookOfBible, seriesName, content }

const fs   = require('fs');
const path = require('path');

const {
  Document, Packer, Paragraph, TextRun, HeadingLevel,
  AlignmentType, BorderStyle, ShadingType, WidthType,
  Header, Footer, PageNumber, NumberFormat,
} = require('docx');

const inputPath  = process.argv[2];
const outputPath = process.argv[3];

if (!inputPath || !outputPath) {
  console.error('Usage: node note_export.js <input.json> <output.docx>');
  process.exit(1);
}

const note = JSON.parse(fs.readFileSync(inputPath, 'utf8'));

// ── HELPERS ───────────────────────────────────────────────────────────────────

function safeText(s) { return (s || '').toString().trim(); }

function metaRow(label, value) {
  if (!value) return null;
  return new Paragraph({
    spacing: { before: 60, after: 60 },
    children: [
      new TextRun({ text: label + ': ', bold: true, font: 'Arial', size: 20 }),
      new TextRun({ text: safeText(value), font: 'Arial', size: 20 }),
    ],
  });
}

function divider() {
  return new Paragraph({
    border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: '1A3A5C', space: 1 } },
    spacing: { before: 120, after: 120 },
    children: [],
  });
}

function bodyParagraphs(content) {
  const lines = safeText(content).split('\n');
  return lines.map(line => {
    const trimmed = line.trim();
    // Detect scripture quote lines: starts with " or —
    const isQuote = trimmed.startsWith('"') || trimmed.startsWith('\u201c') || trimmed.startsWith('\u2014');
    return new Paragraph({
      spacing: { before: 80, after: 80 },
      indent: isQuote ? { left: 720 } : undefined,
      children: [
        new TextRun({
          text:   line || ' ',
          font:   'Arial',
          size:   22,
          italics: isQuote,
          color:  isQuote ? '555555' : '1C1C2E',
        }),
      ],
    });
  });
}

// ── DOCUMENT ──────────────────────────────────────────────────────────────────

const children = [];

// Title
children.push(new Paragraph({
  heading: HeadingLevel.HEADING_1,
  spacing: { before: 0, after: 200 },
  children: [new TextRun({
    text: safeText(note.title) || 'Untitled Note',
    font: 'Arial', size: 40, bold: true, color: '1A3A5C',
  })],
}));

// Metadata block
const meta = [
  metaRow('Date',       note.date),
  metaRow('Type',       note.messageType),
  metaRow('Folder',     note.folder),
  metaRow('Topic',      note.subfolder),
  metaRow('Book',       note.bookOfBible),
  metaRow('Series',     note.seriesName),
  metaRow('Translation',note.translation),
].filter(Boolean);

if (meta.length > 0) {
  children.push(...meta);
  children.push(divider());
}

// Body
children.push(...bodyParagraphs(note.content));

// ── BUILD ─────────────────────────────────────────────────────────────────────

const doc = new Document({
  styles: {
    default: {
      document: { run: { font: 'Arial', size: 22 } },
    },
    paragraphStyles: [
      {
        id: 'Heading1', name: 'Heading 1', basedOn: 'Normal',
        next: 'Normal', quickFormat: true,
        run:       { size: 40, bold: true, font: 'Arial', color: '1A3A5C' },
        paragraph: { spacing: { before: 0, after: 200 }, outlineLevel: 0 },
      },
    ],
  },
  sections: [{
    properties: {
      page: {
        size:   { width: 12240, height: 15840 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
      },
    },
    headers: {
      default: new Header({
        children: [new Paragraph({
          alignment: AlignmentType.RIGHT,
          children: [new TextRun({
            text: safeText(note.title), font: 'Arial', size: 16, color: '888888',
          })],
        })],
      }),
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [
            new TextRun({ text: 'Page ', font: 'Arial', size: 16, color: '888888' }),
            new TextRun({ children: [PageNumber.CURRENT], font: 'Arial', size: 16, color: '888888' }),
            new TextRun({ text: ' of ', font: 'Arial', size: 16, color: '888888' }),
            new TextRun({ children: [PageNumber.TOTAL_PAGES], font: 'Arial', size: 16, color: '888888' }),
          ],
        })],
      }),
    },
    children,
  }],
});

Packer.toBuffer(doc).then(buffer => {
  fs.writeFileSync(outputPath, buffer);
  console.log('OK:' + outputPath);
}).catch(err => {
  console.error('ERROR:' + err.message);
  process.exit(1);
});