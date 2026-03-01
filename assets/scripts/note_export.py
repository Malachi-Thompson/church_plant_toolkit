#!/usr/bin/env python3
# assets/scripts/note_export.py
# Usage: python note_export.py <input_json_path> <output_pdf_path>
# Requires: pip install reportlab --break-system-packages

import sys
import json
import os
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer,
                                 HRFlowable, KeepTogether)
from reportlab.platypus.flowables import HRFlowable

def safe(s):
    return str(s or '').strip()

def esc(s):
    """Escape for ReportLab XML paragraphs."""
    return safe(s).replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')

def main():
    if len(sys.argv) < 3:
        print('Usage: note_export.py <input.json> <output.pdf>')
        sys.exit(1)

    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        note = json.load(f)

    out_path = sys.argv[2]

    # ── STYLES ────────────────────────────────────────────────────────────────
    navy   = colors.HexColor('#1A3A5C')
    gold   = colors.HexColor('#D4A843')
    dark   = colors.HexColor('#1C1C2E')
    muted  = colors.HexColor('#6B7280')
    quote_bg = colors.HexColor('#F0F4FF')

    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        'NoteTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=24,
        textColor=navy,
        spaceAfter=12,
        leading=28,
    )
    meta_label_style = ParagraphStyle(
        'MetaLabel',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=10,
        textColor=navy,
        spaceBefore=4,
        spaceAfter=0,
    )
    meta_value_style = ParagraphStyle(
        'MetaValue',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=10,
        textColor=dark,
        spaceBefore=0,
        spaceAfter=4,
    )
    body_style = ParagraphStyle(
        'NoteBody',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=11,
        textColor=dark,
        leading=17,
        spaceBefore=4,
        spaceAfter=4,
    )
    quote_style = ParagraphStyle(
        'NoteQuote',
        parent=styles['Normal'],
        fontName='Helvetica-Oblique',
        fontSize=11,
        textColor=colors.HexColor('#374151'),
        leading=17,
        spaceBefore=8,
        spaceAfter=8,
        leftIndent=24,
        rightIndent=24,
        backColor=quote_bg,
        borderPadding=(6, 8, 6, 8),
    )

    # ── DOCUMENT ──────────────────────────────────────────────────────────────
    doc = SimpleDocTemplate(
        out_path,
        pagesize=letter,
        leftMargin=inch,
        rightMargin=inch,
        topMargin=inch,
        bottomMargin=inch,
        title=safe(note.get('title','Note')),
        author='Church Plant Toolkit',
    )

    story = []

    # Title
    story.append(Paragraph(esc(note.get('title','Untitled Note')), title_style))

    # Metadata
    meta_fields = [
        ('Date',        note.get('date')),
        ('Type',        note.get('messageType')),
        ('Folder',      note.get('folder')),
        ('Topic',       note.get('subfolder')),
        ('Book',        note.get('bookOfBible')),
        ('Series',      note.get('seriesName')),
        ('Translation', note.get('translation')),
    ]
    has_meta = any(v for _, v in meta_fields)
    if has_meta:
        meta_block = []
        for label, value in meta_fields:
            if value:
                row = Paragraph(
                    f'<b>{esc(label)}:</b>  {esc(value)}',
                    meta_value_style,
                )
                meta_block.append(row)
        story.append(KeepTogether(meta_block))
        story.append(HRFlowable(
            width='100%', thickness=2, color=navy,
            spaceAfter=12, spaceBefore=8,
        ))

    # Body
    content = safe(note.get('content', ''))
    for line in content.split('\n'):
        stripped = line.strip()
        if not stripped:
            story.append(Spacer(1, 6))
            continue
        is_quote = (stripped.startswith('"') or
                    stripped.startswith('\u201c') or
                    stripped.startswith('\u2014') or
                    stripped.startswith('—'))
        style = quote_style if is_quote else body_style
        story.append(Paragraph(esc(line), style))

    # ── HEADER / FOOTER via template ─────────────────────────────────────────
    def on_page(canvas, doc):
        canvas.saveState()
        title = safe(note.get('title', ''))
        # Header
        canvas.setFont('Helvetica', 9)
        canvas.setFillColor(muted)
        canvas.drawRightString(
            letter[0] - inch, letter[1] - 0.6*inch, title)
        # Footer
        page_num = f'Page {doc.page}'
        canvas.drawCentredString(letter[0]/2, 0.5*inch, page_num)
        canvas.restoreState()

    doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
    print(f'OK:{out_path}')

if __name__ == '__main__':
    main()