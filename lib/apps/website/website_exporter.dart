// lib/apps/website/website_exporter.dart
//
// Generates a complete static HTML/CSS/JS website from a ChurchWebsite.
// Also writes GitHub Actions and Cloudflare Pages config files.
// The generated site can be deployed to any static host.

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'website_models.dart';

// ── PUBLIC API ────────────────────────────────────────────────────────────────

class ExportResult {
  final String outputDir;
  final List<String> files;
  final String? error;

  const ExportResult({
    required this.outputDir,
    required this.files,
    this.error,
  });
}

/// Exports website to a folder on disk and returns the path + file list.
/// Used by the manual "Export & Deploy" button.
Future<ExportResult> exportWebsite(ChurchWebsite site) async {
  try {
    final dir    = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/church_website_export');
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await outDir.create(recursive: true);

    final files = <String>[];

    // ── Shared CSS ──────────────────────────────────────────────────────────
    await File('${outDir.path}/style.css').writeAsString(_generateCSS(site.settings));
    files.add('style.css');

    // ── Pages ───────────────────────────────────────────────────────────────
    for (final page in site.pages) {
      final filename = page.isHomePage ? 'index.html' : '${page.slug}.html';
      await File('${outDir.path}/$filename').writeAsString(_generatePage(site, page));
      files.add(filename);
    }

    // ── GitHub Actions workflow ─────────────────────────────────────────────
    if (site.settings.deploy.githubPagesEnabled ||
        site.settings.deploy.hostingPlatform == HostingPlatform.githubPages) {
      final ghDir = Directory('${outDir.path}/.github/workflows');
      await ghDir.create(recursive: true);
      await File('${ghDir.path}/deploy.yml')
          .writeAsString(_githubActionsYml(site.settings.deploy));
      files.add('.github/workflows/deploy.yml');
    }

    // ── Cloudflare Pages config ─────────────────────────────────────────────
    if (site.settings.deploy.cloudflareEnabled ||
        site.settings.deploy.hostingPlatform == HostingPlatform.cloudflarePages) {
      await File('${outDir.path}/wrangler.toml')
          .writeAsString(_cloudflareToml(site.settings.deploy));
      files.add('wrangler.toml');
    }

    // ── Custom domain CNAME (GitHub Pages requires this file in the repo) ───
    if (site.settings.deploy.customDomain.isNotEmpty &&
        site.settings.deploy.hostingPlatform == HostingPlatform.githubPages) {
      await File('${outDir.path}/CNAME')
          .writeAsString(site.settings.deploy.customDomain.trim());
      files.add('CNAME');
    }

    // ── README ──────────────────────────────────────────────────────────────
    await File('${outDir.path}/README.md').writeAsString(_readme(site));
    files.add('README.md');

    return ExportResult(outputDir: outDir.path, files: files);
  } catch (e) {
    return ExportResult(outputDir: '', files: [], error: e.toString());
  }
}

// ── IN-MEMORY EXPORT (used by deploy service — no disk writes) ────────────────

class MemoryExportResult {
  /// All file contents keyed by their relative path, e.g. 'index.html' -> '<html>...'
  final Map<String, String> fileContents;
  final List<String> files;
  final String? error;

  const MemoryExportResult({
    required this.fileContents,
    required this.files,
    this.error,
  });
}

/// Builds the full website in memory and returns a map of path → content.
/// Used by GitHubDeployService and CloudflareDeployService.
Future<MemoryExportResult> exportWebsiteToMemory(ChurchWebsite site) async {
  try {
    final contents = <String, String>{};
    final files    = <String>[];

    // CSS
    contents['style.css'] = _generateCSS(site.settings);
    files.add('style.css');

    // Pages
    for (final page in site.pages) {
      final filename = page.isHomePage ? 'index.html' : '${page.slug}.html';
      contents[filename] = _generatePage(site, page);
      files.add(filename);
    }

    // GitHub Actions workflow
    if (site.settings.deploy.hostingPlatform == HostingPlatform.githubPages) {
      contents['.github/workflows/deploy.yml'] =
          _githubActionsYml(site.settings.deploy);
      files.add('.github/workflows/deploy.yml');
    }

    // Cloudflare wrangler.toml
    if (site.settings.deploy.hostingPlatform == HostingPlatform.cloudflarePages) {
      contents['wrangler.toml'] = _cloudflareToml(site.settings.deploy);
      files.add('wrangler.toml');
    }

    // CNAME file for GitHub Pages custom domain
    if (site.settings.deploy.customDomain.isNotEmpty &&
        site.settings.deploy.hostingPlatform == HostingPlatform.githubPages) {
      contents['CNAME'] = site.settings.deploy.customDomain.trim();
      files.add('CNAME');
    }

    // README
    contents['README.md'] = _readme(site);
    files.add('README.md');

    return MemoryExportResult(fileContents: contents, files: files);
  } catch (e) {
    return MemoryExportResult(fileContents: {}, files: [], error: e.toString());
  }
}

/// Generates HTML for a single page as a string (used for in-app preview too)
String generatePageHtml(ChurchWebsite site, WebPage page) =>
    _generatePage(site, page);

// ── CSS GENERATOR ─────────────────────────────────────────────────────────────

/// Public alias — used by the builder screen to write preview CSS
String generateCSS(WebsiteSettings s) => _generateCSS(s);

String _generateCSS(WebsiteSettings s) => '''
/* ─── Church Plant Toolkit Generated Site ─── */
@import url('https://fonts.googleapis.com/css2?family=${Uri.encodeComponent(s.fontFamily)}:wght@300;400;500;600;700;900&family=Inter:wght@400;500;600&display=swap');

*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --primary:    ${s.primaryHex};
  --secondary:  ${s.secondaryHex};
  --bg:         ${s.backgroundHex};
  --text:       ${s.textHex};
  --text-muted: #6B7280;
  --border:     #E5E7EB;
  --radius:     12px;
  --font-head:  '${s.fontFamily}', serif;
  --font-body:  'Inter', sans-serif;
  --max-w:      1100px;
  --footer-bg:  ${s.footerBgHex};
  --footer-text: ${s.footerTextHex};
}

/* DARK MODE */
html.dark-preview {
  --bg:         #111827;
  --text:       #F3F4F6;
  --text-muted: #9CA3AF;
  --border:     #374151;
}
html.dark-preview section.alt { background: #1F2937; }
html.dark-preview .service-card,
html.dark-preview .event-card { background: #1F2937; border-color: #374151; }
html.dark-preview .about-img { filter: brightness(0.85); }

body { font-family: var(--font-body); background: var(--bg); color: var(--text); line-height: 1.65; }
a { color: var(--primary); text-decoration: none; }
img { max-width: 100%; height: auto; display: block; }
.container { max-width: var(--max-w); margin: 0 auto; padding: 0 24px; }

/* NAV */
nav { background: var(--primary); padding: 0 24px; position: sticky; top: 0; z-index: 100; }
nav .nav-inner { max-width: var(--max-w); margin: 0 auto; display: flex; align-items: center; height: 64px; gap: 32px; }
nav .nav-brand { color: #fff; font-family: var(--font-head); font-size: 1.2rem; font-weight: 700; }
nav .nav-links { display: flex; gap: 24px; margin-left: auto; }
nav .nav-links a { color: rgba(255,255,255,0.85); font-size: 0.9rem; font-weight: 500; transition: color .2s; padding: 4px 0; border-bottom: 2px solid transparent; }
nav .nav-links a:hover, nav .nav-links a.active { color: #fff; border-bottom-color: var(--secondary); }

/* SECTIONS */
section { padding: 72px 0; }
section.alt { background: #F9FAFB; }
section.dark { background: var(--primary); color: #fff; }
section.dark h2, section.dark p { color: #fff; }
.section-heading { text-align: center; margin-bottom: 48px; }
.section-heading h2 { font-family: var(--font-head); font-size: clamp(1.6rem, 3vw, 2.4rem); font-weight: 700; color: var(--primary); }
.section-heading.light h2 { color: #fff; }
.section-heading p { color: var(--text-muted); margin-top: 10px; font-size: 1.05rem; }

/* HERO */
.hero { min-height: 80vh; display: flex; align-items: center; background: linear-gradient(135deg, var(--primary) 0%, color-mix(in srgb, var(--primary) 60%, #000) 100%); color: #fff; padding: 80px 0; }
.hero-content { max-width: var(--max-w); margin: 0 auto; padding: 0 24px; }
.hero h1 { font-family: var(--font-head); font-size: clamp(2.2rem, 5vw, 4rem); font-weight: 900; line-height: 1.15; margin-bottom: 20px; }
.hero p { font-size: clamp(1rem, 2vw, 1.3rem); opacity: 0.85; max-width: 600px; margin-bottom: 36px; }

/* BUTTONS */
.btn { display: inline-block; padding: 14px 32px; border-radius: var(--radius); font-weight: 600; font-size: 1rem; transition: all .2s; cursor: pointer; }
.btn-primary { background: var(--secondary); color: #1C1C2E; }
.btn-primary:hover { opacity: 0.9; transform: translateY(-1px); }
.btn-outline { border: 2px solid #fff; color: #fff; }
.btn-outline:hover { background: rgba(255,255,255,0.1); }

/* ABOUT */
.about-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 48px; align-items: center; }
@media (max-width: 768px) { .about-grid { grid-template-columns: 1fr; } }
.about-grid h2 { font-family: var(--font-head); font-size: clamp(1.5rem, 3vw, 2.2rem); font-weight: 700; color: var(--primary); margin-bottom: 16px; }
.about-grid p { color: var(--text-muted); line-height: 1.8; }
.about-img { border-radius: var(--radius); width: 100%; height: 360px; object-fit: cover; }

/* SERVICE TIMES */
.service-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
.service-card { background: #fff; border: 1px solid var(--border); border-radius: var(--radius); padding: 24px; text-align: center; }
.service-card .day { font-family: var(--font-head); font-size: 1.3rem; font-weight: 700; color: var(--primary); }
.service-card .time { font-size: 1rem; color: var(--text-muted); margin-top: 6px; }
.service-card .loc { font-size: 0.85rem; color: var(--text-muted); margin-top: 4px; }

/* EVENTS */
.events-list { display: flex; flex-direction: column; gap: 16px; }
.event-card { display: flex; gap: 20px; align-items: flex-start; background: #fff; border: 1px solid var(--border); border-radius: var(--radius); padding: 20px; }
.event-date { background: var(--primary); color: #fff; border-radius: 8px; padding: 10px 14px; text-align: center; min-width: 60px; }
.event-date .month { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 1px; }
.event-date .day { font-size: 1.6rem; font-weight: 700; line-height: 1; }

/* TEAM */
.team-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 24px; }
.team-card { text-align: center; }
.team-avatar { width: 100px; height: 100px; border-radius: 50%; object-fit: cover; margin: 0 auto 12px; background: var(--border); display: flex; align-items: center; justify-content: center; font-size: 2.5rem; }
.team-card h3 { font-size: 1rem; font-weight: 600; }
.team-card .role { color: var(--primary); font-size: 0.85rem; font-weight: 500; }
.team-card p { color: var(--text-muted); font-size: 0.85rem; margin-top: 6px; }

/* CONTACT */
.contact-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 48px; }
@media (max-width: 768px) { .contact-grid { grid-template-columns: 1fr; } }
.contact-info p { color: var(--text-muted); margin-bottom: 12px; }
.contact-info .icon { margin-right: 8px; }

/* MAP */
.map-embed { border-radius: var(--radius); overflow: hidden; height: 400px; background: #eee; }
.map-embed iframe { width: 100%; height: 100%; border: 0; }
.map-address { text-align: center; color: var(--text-muted); margin-top: 16px; }

/* GALLERY */
.gallery-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px; }
.gallery-grid img { border-radius: 8px; height: 200px; object-fit: cover; width: 100%; }

/* ANNOUNCEMENT */
.announcement-box { border-radius: var(--radius); padding: 24px; display: flex; gap: 16px; align-items: flex-start; }
.announcement-box h3 { font-size: 1.1rem; font-weight: 700; margin-bottom: 6px; }
.announcement-box p { color: var(--text-muted); font-size: 0.95rem; }

/* DIVIDER */
.divider-line { border: none; border-top: 1px solid var(--border); margin: 0; }
.divider-cross { text-align: center; font-size: 1.5rem; padding: 12px 0; color: var(--primary); }
.divider-wave { text-align: center; font-size: 1.2rem; padding: 12px 0; color: var(--border); letter-spacing: 4px; }

/* RICH TEXT */
.rich-text-content { max-width: 720px; margin: 0 auto; }
.rich-text-content h2 { font-family: var(--font-head); font-size: 1.8rem; color: var(--primary); margin-bottom: 16px; }
.rich-text-content p { color: var(--text-muted); line-height: 1.8; }

/* CTA BAND */
.cta-band { background: var(--primary); color: #fff; text-align: center; padding: 64px 24px; }
.cta-band h2 { font-family: var(--font-head); font-size: clamp(1.6rem, 3vw, 2.4rem); margin-bottom: 12px; }
.cta-band p { opacity: 0.85; margin-bottom: 28px; }

/* SERMON */
.sermon-block { background: var(--primary); color: #fff; border-radius: var(--radius); padding: 32px; }
.sermon-block h2 { font-family: var(--font-head); font-size: 1.6rem; margin-bottom: 8px; }
.sermon-block .ref { color: var(--secondary); font-weight: 600; font-size: 0.9rem; margin-bottom: 16px; }
.sermon-block p { opacity: 0.85; line-height: 1.8; }
.sermon-points p { display: flex; gap: 10px; margin-bottom: 8px; }

/* FOOTER */
footer { background: var(--footer-bg); color: var(--footer-text); text-align: center; padding: 32px 24px; font-size: 0.9rem; opacity: 1; }
footer a { color: var(--footer-text); }
.footer-social { display: flex; justify-content: center; gap: 16px; margin-bottom: 16px; font-size: 1.4rem; }
.footer-social a { text-decoration: none; }

@media (max-width: 640px) {
  nav .nav-links { gap: 14px; }
  nav .nav-links a { font-size: 0.8rem; }
  section { padding: 48px 0; }
  .hero { min-height: 60vh; }
}
''';

// ── PAGE GENERATOR ────────────────────────────────────────────────────────────

String _generatePage(ChurchWebsite site, WebPage page) {
  final s       = site.settings;
  final blocks  = page.blocks
      .where((b) => b.isVisible)
      .map((b) => _block(b, s))
      .join('\n\n');

  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_esc(page.isHomePage ? s.siteTitle : '${page.title} — ${s.siteTitle}')}</title>
  <meta name="description" content="${_esc(s.tagline)}">
  <link rel="stylesheet" href="style.css">
</head>
<body>
${_nav(s, site.pages, page)}

$blocks

${_footer(s)}
</body>
</html>''';
}

String _nav(WebsiteSettings s, List<WebPage> pages, WebPage current) {
  final links = pages
      .where((p) => p.showInNav)
      .map((p) {
        final href   = p.isHomePage ? 'index.html' : '${p.slug}.html';
        final active = p.id == current.id ? ' class="active"' : '';
        return '<a href="$href"$active>${_esc(p.title)}</a>';
      })
      .join('\n          ');

  return '''<nav>
  <div class="nav-inner">
    <span class="nav-brand">${_esc(s.siteTitle)}</span>
    <div class="nav-links">
      $links
    </div>
  </div>
</nav>''';
}

String _footer(WebsiteSettings s) {
  final social = s.footerShowSocial ? '''
    <div class="footer-social">
      ${s.facebookUrl.isNotEmpty  ? '<a href="${_esc(s.facebookUrl)}"  target="_blank" title="Facebook">📘</a>'  : ''}
      ${s.instagramUrl.isNotEmpty ? '<a href="${_esc(s.instagramUrl)}" target="_blank" title="Instagram">📸</a>' : ''}
      ${s.youtubeUrl.isNotEmpty   ? '<a href="${_esc(s.youtubeUrl)}"   target="_blank" title="YouTube">▶️</a>'   : ''}
      ${s.twitterUrl.isNotEmpty   ? '<a href="${_esc(s.twitterUrl)}"   target="_blank" title="Twitter/X">🐦</a>' : ''}
    </div>''' : '';

  final text = s.footerText.isNotEmpty
      ? s.footerText
      : '© ${DateTime.now().year} ${s.siteTitle}. All rights reserved.';

  return '''<footer>
  $social
  <p>${_esc(text)}</p>
</footer>''';
}

// ── BLOCK RENDERERS ───────────────────────────────────────────────────────────

String _block(WebBlock b, WebsiteSettings s) {
  switch (b.type) {
    case BlockType.hero:         return _heroBlock(b, s);
    case BlockType.about:        return _aboutBlock(b);
    case BlockType.services:     return _servicesBlock(b);
    case BlockType.events:       return _eventsBlock(b);
    case BlockType.team:         return _teamBlock(b);
    case BlockType.sermon:       return _sermonBlock(b);
    case BlockType.contact:      return _contactBlock(b);
    case BlockType.map:          return _mapBlock(b, s);
    case BlockType.gallery:      return _galleryBlock(b);
    case BlockType.announcement: return _announcementBlock(b);
    case BlockType.divider:      return _dividerBlock(b);
    case BlockType.richText:     return _richTextBlock(b);
    case BlockType.cta:          return _ctaBlock(b);
  }
}

String _heroBlock(WebBlock b, WebsiteSettings s) => '''
<section class="hero" id="hero">
  <div class="hero-content">
    <h1>${_esc(b.heading)}</h1>
    ${b.subheading.isNotEmpty ? '<p>${_esc(b.subheading)}</p>' : ''}
    ${b.buttonText.isNotEmpty ? '<a href="${_esc(b.buttonUrl)}" class="btn btn-primary">${_esc(b.buttonText)}</a>' : ''}
  </div>
</section>''';

String _servicesBlock(WebBlock b) {
  if (b.serviceTimes.isEmpty) {
    return '<section class="alt" id="services"><div class="container"><div class="section-heading"><h2>${_esc(b.heading)}</h2></div><p style="text-align:center;color:#6B7280">Service times coming soon.</p></div></section>';
  }
  final cards = b.serviceTimes.map((st) => '''
    <div class="service-card">
      <div class="day">${_esc(st.day)}</div>
      <div class="time">${_esc(st.time)}</div>
      ${st.location.isNotEmpty ? '<div class="loc">${_esc(st.location)}</div>' : ''}
    </div>''').join('\n');

  return '''<section class="alt" id="services">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2></div>
    <div class="service-grid">$cards
    </div>
  </div>
</section>''';
}

String _aboutBlock(WebBlock b) => '''
<section id="about">
  <div class="container">
    <div class="about-grid">
      <div>
        <h2>${_esc(b.heading)}</h2>
        <p>${_esc(b.body)}</p>
        ${b.buttonText.isNotEmpty ? '<a href="${_esc(b.buttonUrl)}" class="btn btn-primary" style="margin-top:24px">${_esc(b.buttonText)}</a>' : ''}
      </div>
      ${b.imageUrl.isNotEmpty ? '<img class="about-img" src="${_esc(b.imageUrl)}" alt="${_esc(b.heading)}">' : '<div class="about-img" style="display:flex;align-items:center;justify-content:center;font-size:4rem;background:#F3F4F6">✝</div>'}
    </div>
  </div>
</section>''';

String _eventsBlock(WebBlock b) {
  if (b.events.isEmpty) {
    return '<section id="events"><div class="container"><div class="section-heading"><h2>${_esc(b.heading)}</h2></div><p style="text-align:center;color:#6B7280">No upcoming events.</p></div></section>';
  }
  final cards = b.events.map((e) {
    final parts = e.date.split(' ');
    final month = parts.length >= 2 ? parts[0].substring(0, 3) : '';
    final day   = parts.length >= 2 ? parts[1] : e.date;
    return '''
    <div class="event-card">
      <div class="event-date">
        <div class="month">${_esc(month)}</div>
        <div class="day">${_esc(day)}</div>
      </div>
      <div>
        <h3>${_esc(e.title)}</h3>
        ${e.time.isNotEmpty ? '<p style="color:#6B7280;font-size:.9rem">⏰ ${_esc(e.time)}</p>' : ''}
        ${e.description.isNotEmpty ? '<p>${_esc(e.description)}</p>' : ''}
      </div>
    </div>''';
  }).join('\n');

  return '''<section id="events">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2></div>
    <div class="events-list">$cards
    </div>
  </div>
</section>''';
}

String _teamBlock(WebBlock b) {
  if (b.team.isEmpty) {
    return '<section class="alt" id="team"><div class="container"><div class="section-heading"><h2>${_esc(b.heading)}</h2></div><p style="text-align:center;color:#6B7280">Team members coming soon.</p></div></section>';
  }
  final cards = b.team.map((m) => '''
    <div class="team-card">
      ${m.photoUrl.isNotEmpty ? '<img class="team-avatar" src="${_esc(m.photoUrl)}" alt="${_esc(m.name)}">' : '<div class="team-avatar">👤</div>'}
      <h3>${_esc(m.name)}</h3>
      ${m.role.isNotEmpty ? '<div class="role">${_esc(m.role)}</div>' : ''}
      ${m.bio.isNotEmpty  ? '<p>${_esc(m.bio)}</p>'                   : ''}
    </div>''').join('\n');

  return '''<section class="alt" id="team">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2></div>
    <div class="team-grid">$cards
    </div>
  </div>
</section>''';
}

String _sermonBlock(WebBlock b) => '''
<section id="sermon">
  <div class="container">
    <div class="sermon-block">
      <div class="ref">${_esc(b.subheading)}</div>
      <h2>${_esc(b.heading)}</h2>
      ${b.body.isNotEmpty ? '<div class="sermon-points">${b.body.split('\n').map((l) => '<p><span class="icon">📌</span>${_esc(l)}</p>').join('')}</div>' : ''}
    </div>
  </div>
</section>''';

String _contactBlock(WebBlock b) => '''
<section id="contact">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2></div>
    <div class="contact-grid">
      <div class="contact-info">
        ${b.subheading.isNotEmpty ? '<p>${_esc(b.subheading)}</p>' : ''}
        ${b.body.isNotEmpty ? b.body.split('\n').map((l) => '<p><span class="icon">📍</span>${_esc(l)}</p>').join('') : ''}
      </div>
      <div>
        ${b.buttonText.isNotEmpty ? '<a href="${_esc(b.buttonUrl)}" class="btn btn-primary">${_esc(b.buttonText)}</a>' : ''}
      </div>
    </div>
  </div>
</section>''';

String _mapBlock(WebBlock b, WebsiteSettings s) {
  String embed;
  if (b.mapProvider == MapProvider.google) {
    final q = Uri.encodeComponent(b.mapAddress);
    embed = '<iframe src="https://maps.google.com/maps?q=$q&output=embed" allowfullscreen></iframe>';
  } else {
    // OpenStreetMap
    embed = '<iframe src="https://www.openstreetmap.org/export/embed.html?bbox=${b.mapLng - 0.01},${b.mapLat - 0.01},${b.mapLng + 0.01},${b.mapLat + 0.01}&layer=mapnik" allowfullscreen></iframe>';
  }
  return '''<section id="map">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2></div>
    <div class="map-embed">$embed</div>
    ${b.mapAddress.isNotEmpty ? '<p class="map-address">📍 ${_esc(b.mapAddress)}</p>' : ''}
  </div>
</section>''';
}

String _galleryBlock(WebBlock b) {
  final imgs = b.galleryImages.isEmpty
      ? '<p style="text-align:center;color:#6B7280">No photos yet.</p>'
      : b.galleryImages.map((img) =>
          '<img src="${_esc(img)}" alt="Church photo" loading="lazy">').join('\n');
  return '''<section class="alt" id="gallery">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2></div>
    <div class="gallery-grid">$imgs</div>
  </div>
</section>''';
}

String _announcementBlock(WebBlock b) => '''
<section>
  <div class="container">
    <div class="announcement-box" style="background:${b.announcementColor}1A;border-left:4px solid ${b.announcementColor}">
      <div>
        <h3 style="color:${b.announcementColor}">${_esc(b.heading)}</h3>
        ${b.body.isNotEmpty ? '<p>${_esc(b.body)}</p>' : ''}
        ${b.buttonText.isNotEmpty ? '<a href="${_esc(b.buttonUrl)}" class="btn btn-primary" style="margin-top:12px;background:${b.announcementColor}">${_esc(b.buttonText)}</a>' : ''}
      </div>
    </div>
  </div>
</section>''';

String _dividerBlock(WebBlock b) {
  switch (b.dividerStyle) {
    case 'cross': return '<div class="divider-cross">✝</div>';
    case 'wave':  return '<div class="divider-wave">〰〰〰</div>';
    default:      return '<hr class="divider-line" style="margin:0">';
  }
}

String _richTextBlock(WebBlock b) => '''
<section id="text-${b.id.substring(0, 6)}">
  <div class="container">
    <div class="rich-text-content">
      ${b.heading.isNotEmpty ? '<h2>${_esc(b.heading)}</h2>' : ''}
      <p>${_esc(b.body)}</p>
    </div>
  </div>
</section>''';

String _ctaBlock(WebBlock b) => '''
<section class="cta-band">
  <div class="container">
    <h2>${_esc(b.heading)}</h2>
    ${b.subheading.isNotEmpty ? '<p>${_esc(b.subheading)}</p>' : ''}
    ${b.buttonText.isNotEmpty ? '<a href="${_esc(b.buttonUrl)}" class="btn btn-outline">${_esc(b.buttonText)}</a>' : ''}
  </div>
</section>''';

// ── DEPLOY CONFIG GENERATORS ──────────────────────────────────────────────────

String _githubActionsYml(DeploySettings d) => '''
# GitHub Actions – auto-deploy to GitHub Pages on every push to main
name: Deploy to GitHub Pages

on:
  push:
    branches: [ main ]

permissions:
  contents: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: \${{ secrets.GITHUB_TOKEN }}
          publish_dir: .
          publish_branch: ${d.githubBranch}
${d.customDomain.isNotEmpty ? '          cname: ${d.customDomain}' : ''}
''';

String _cloudflareToml(DeploySettings d) => '''
# Cloudflare Pages – wrangler.toml
# Install wrangler: npm install -g wrangler
# Deploy: wrangler pages deploy . --project-name=${d.cloudflareProject}
name = "${d.cloudflareProject}"
compatibility_date = "${DateTime.now().toIso8601String().substring(0, 10)}"

[site]
bucket = "."
''';

String _readme(ChurchWebsite site) {
  final d = site.settings.deploy;
  return '''# ${site.settings.siteTitle} Website

Generated by **Church Plant Toolkit**.

## Files
${site.pages.map((p) => '- `${p.isHomePage ? "index" : p.slug}.html` — ${p.title}').join('\n')}
- `style.css` — site stylesheet

## Deploy Options

### Option 1 – GitHub Pages (free)
1. Create a GitHub repo at **github.com/new**
2. Upload these files to the repo
3. Go to **Settings → Pages → Source** and set branch to `main`
4. Your site will be live at **https://USERNAME.github.io/REPO**
${d.githubRepo.isNotEmpty ? '\n   Configured repo: `${d.githubRepo}`' : ''}
${d.githubPagesUrl.isNotEmpty ? '\n   Live URL: ${d.githubPagesUrl}' : ''}

### Option 2 – Cloudflare Pages (free)
1. Sign up at **pages.cloudflare.com**
2. Create a new project and upload these files
3. Your site will be live at **PROJECT.pages.dev**
${d.cloudflareProject.isNotEmpty ? '\n   Configured project: `${d.cloudflareProject}`' : ''}
${d.cloudflarePagesUrl.isNotEmpty ? '\n   Live URL: ${d.cloudflarePagesUrl}' : ''}

### Option 3 – Any Static Host
Upload all files to Netlify, Vercel, Firebase Hosting, or any web server.

## Custom Domain
${d.customDomain.isNotEmpty ? 'Configured domain: `${d.customDomain}`\n\nAdd a CNAME record pointing to: `${d.cnameTarget}`' : 'Set your CNAME record to point to your GitHub Pages or Cloudflare Pages URL.'}

---
*Built with Church Plant Toolkit*
''';
}

// ── UTIL ──────────────────────────────────────────────────────────────────────

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');