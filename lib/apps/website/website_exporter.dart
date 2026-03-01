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

Future<ExportResult> exportWebsite(ChurchWebsite site) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/church_website_export');
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await outDir.create(recursive: true);

    final files = <String>[];

    // ── Shared CSS ──────────────────────────────────────────────────────────
    final cssFile = File('${outDir.path}/style.css');
    await cssFile.writeAsString(_generateCSS(site.settings));
    files.add('style.css');

    // ── Pages ───────────────────────────────────────────────────────────────
    for (final page in site.pages) {
      final filename = page.isHomePage ? 'index.html' : '${page.slug}.html';
      final html     = _generatePage(site, page);
      await File('${outDir.path}/$filename').writeAsString(html);
      files.add(filename);
    }

    // ── GitHub Actions workflow ─────────────────────────────────────────────
    if (site.settings.deploy.githubPagesEnabled) {
      final ghDir = Directory('${outDir.path}/.github/workflows');
      await ghDir.create(recursive: true);
      await File('${ghDir.path}/deploy.yml')
          .writeAsString(_githubActionsYml(site.settings.deploy));
      files.add('.github/workflows/deploy.yml');
    }

    // ── Cloudflare Pages config ─────────────────────────────────────────────
    if (site.settings.deploy.cloudflareEnabled) {
      await File('${outDir.path}/wrangler.toml')
          .writeAsString(_cloudflareToml(site.settings.deploy));
      files.add('wrangler.toml');
    }

    // ── Custom domain CNAME ─────────────────────────────────────────────────
    if (site.settings.deploy.customDomain.isNotEmpty) {
      await File('${outDir.path}/CNAME')
          .writeAsString(site.settings.deploy.customDomain.trim());
      files.add('CNAME');
    }

    // ── README ──────────────────────────────────────────────────────────────
    await File('${outDir.path}/README.md')
        .writeAsString(_readme(site));
    files.add('README.md');

    return ExportResult(outputDir: outDir.path, files: files);
  } catch (e) {
    return ExportResult(outputDir: '', files: [], error: e.toString());
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
}

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
.btn { display: inline-block; padding: 14px 32px; border-radius: var(--radius); font-weight: 600; font-size: 1rem; cursor: pointer; transition: transform .15s, opacity .15s; }
.btn:hover { opacity: 0.9; transform: translateY(-1px); }
.btn-primary { background: var(--secondary); color: #fff; }
.btn-outline { border: 2px solid #fff; color: #fff; }

/* SERVICE TIMES */
.service-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
.service-card { background: #fff; border: 1px solid var(--border); border-radius: var(--radius); padding: 28px; text-align: center; box-shadow: 0 1px 4px rgba(0,0,0,.05); }
.service-card .day { font-weight: 700; color: var(--primary); font-size: 1.1rem; margin-bottom: 8px; }
.service-card .time { font-size: 1.4rem; font-weight: 700; color: var(--text); }
.service-card .location { font-size: 0.85rem; color: var(--text-muted); margin-top: 6px; }

/* ABOUT */
.about-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 60px; align-items: center; }
.about-grid img { border-radius: var(--radius); object-fit: cover; width: 100%; height: 340px; }
.about-text h2 { font-family: var(--font-head); font-size: 2rem; color: var(--primary); margin-bottom: 16px; }
.about-text p { color: var(--text-muted); line-height: 1.8; }
@media(max-width: 700px){ .about-grid { grid-template-columns: 1fr; } }

/* EVENTS */
.events-list { display: grid; gap: 16px; }
.event-card { background: #fff; border: 1px solid var(--border); border-radius: var(--radius); padding: 20px 24px; display: flex; gap: 20px; align-items: flex-start; }
.event-date { background: var(--primary); color: #fff; border-radius: 8px; padding: 10px 16px; text-align: center; min-width: 64px; flex-shrink: 0; }
.event-date .month { font-size: 0.7rem; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; }
.event-date .day-num { font-size: 1.6rem; font-weight: 900; line-height: 1; }
.event-info h3 { font-weight: 700; font-size: 1.05rem; }
.event-info p { color: var(--text-muted); font-size: 0.9rem; margin-top: 4px; }

/* TEAM */
.team-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 24px; }
.team-card { text-align: center; }
.team-avatar { width: 100px; height: 100px; border-radius: 50%; background: var(--primary); display: flex; align-items: center; justify-content: center; margin: 0 auto 14px; font-size: 2rem; color: #fff; font-weight: 700; overflow: hidden; }
.team-avatar img { width: 100%; height: 100%; object-fit: cover; }
.team-card h3 { font-weight: 700; }
.team-card .role { color: var(--secondary); font-size: 0.85rem; font-weight: 600; margin-top: 4px; }
.team-card p { color: var(--text-muted); font-size: 0.85rem; margin-top: 8px; }

/* MAP */
.map-container { border-radius: var(--radius); overflow: hidden; height: 400px; border: 1px solid var(--border); }
.map-container iframe { width: 100%; height: 100%; border: none; }

/* CONTACT */
.contact-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 48px; }
@media(max-width:700px){ .contact-grid { grid-template-columns: 1fr; } }
.contact-form input, .contact-form textarea {
  width: 100%; padding: 12px 16px; border: 1px solid var(--border); border-radius: 8px;
  font-family: var(--font-body); font-size: 0.95rem; margin-bottom: 14px;
  outline: none; transition: border .2s;
}
.contact-form input:focus, .contact-form textarea:focus { border-color: var(--primary); }
.contact-form textarea { min-height: 120px; resize: vertical; }
.contact-info p { display: flex; align-items: flex-start; gap: 10px; margin-bottom: 16px; color: var(--text-muted); }
.contact-info .icon { font-size: 1.1rem; flex-shrink: 0; margin-top: 2px; }

/* CTA */
.cta-band { background: var(--secondary); padding: 64px 0; text-align: center; }
.cta-band h2 { font-family: var(--font-head); font-size: 2rem; color: #fff; margin-bottom: 12px; }
.cta-band p { color: rgba(255,255,255,0.85); margin-bottom: 28px; font-size: 1.05rem; }

/* ANNOUNCEMENT */
.announcement-box { border-radius: var(--radius); padding: 24px 28px; display: flex; align-items: flex-start; gap: 16px; }
.announcement-box h3 { font-weight: 700; font-size: 1.1rem; margin-bottom: 6px; }

/* GALLERY */
.gallery-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; }
.gallery-grid img { border-radius: 8px; object-fit: cover; width: 100%; height: 180px; }

/* DIVIDER */
.divider-line { border: none; border-top: 2px solid var(--border); margin: 8px 0; }
.divider-cross { text-align: center; color: var(--primary); font-size: 2rem; padding: 8px 0; }
.divider-wave { text-align: center; color: var(--border); font-size: 2rem; padding: 8px 0; }

/* FOOTER */
footer { background: color-mix(in srgb, var(--primary) 90%, #000); color: rgba(255,255,255,0.7); padding: 40px 24px; text-align: center; }
footer .footer-social { display: flex; justify-content: center; gap: 20px; margin-bottom: 16px; }
footer .footer-social a { color: rgba(255,255,255,0.7); font-size: 1.3rem; transition: color .2s; }
footer .footer-social a:hover { color: #fff; }
footer p { font-size: 0.85rem; }

/* RICH TEXT */
.rich-text-content { max-width: 720px; margin: 0 auto; }
.rich-text-content h2 { font-family: var(--font-head); color: var(--primary); margin-bottom: 16px; }
.rich-text-content p { color: var(--text-muted); line-height: 1.8; }

/* SERMON */
.sermon-block { background: #F0F4FF; border-left: 4px solid var(--primary); border-radius: 0 var(--radius) var(--radius) 0; padding: 24px 28px; }
.sermon-block h2 { color: var(--primary); font-family: var(--font-head); margin-bottom: 12px; }
.sermon-block p { color: var(--text-muted); white-space: pre-line; }

/* RESPONSIVE */
@media(max-width: 600px) {
  section { padding: 48px 0; }
  .hero { min-height: 60vh; }
  .hero h1 { font-size: 2rem; }
  nav .nav-links { display: none; }
}
''';

// ── PAGE GENERATOR ────────────────────────────────────────────────────────────

String _generatePage(ChurchWebsite site, WebPage page) {
  final s   = site.settings;
  final nav = _nav(site, page);
  final blocks = page.blocks
      .where((b) => b.isVisible)
      .map((b) => _block(b, s))
      .join('\n');
  final footer = _footer(s);

  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_esc(page.title)} – ${_esc(s.siteTitle)}</title>
  <link rel="stylesheet" href="style.css">
  <meta name="description" content="${_esc(s.tagline)}">
</head>
<body>
$nav
<main>
$blocks
</main>
$footer
</body>
</html>''';
}

String _nav(ChurchWebsite site, WebPage current) {
  final s     = site.settings;
  final links = site.pages
      .where((p) => p.showInNav)
      .map((p) {
        final href    = p.isHomePage ? 'index.html' : '${p.slug}.html';
        final active  = p.id == current.id ? ' class="active"' : '';
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
      ${st.location.isNotEmpty ? '<div class="location">${_esc(st.location)}</div>' : ''}
    </div>''').join('\n');

  return '''<section class="alt" id="services">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2>${b.subheading.isNotEmpty ? '<p>${_esc(b.subheading)}</p>' : ''}</div>
    <div class="service-grid">$cards</div>
  </div>
</section>''';
}

String _aboutBlock(WebBlock b) => '''
<section id="about">
  <div class="container">
    <div class="about-grid">
      ${b.imageUrl.isNotEmpty ? '<img src="${_esc(b.imageUrl)}" alt="Church image">' : ''}
      <div class="about-text">
        <h2>${_esc(b.heading)}</h2>
        ${b.subheading.isNotEmpty ? '<p style="font-weight:600;margin-bottom:8px">${_esc(b.subheading)}</p>' : ''}
        <p>${_esc(b.body)}</p>
        ${b.buttonText.isNotEmpty ? '<a href="${_esc(b.buttonUrl)}" class="btn btn-primary" style="margin-top:20px">${_esc(b.buttonText)}</a>' : ''}
      </div>
    </div>
  </div>
</section>''';

String _eventsBlock(WebBlock b) {
  final items = b.events.isEmpty
      ? '<p style="text-align:center;color:#6B7280">No upcoming events. Check back soon!</p>'
      : b.events.map((e) {
          final dateParts = e.date.split(' ');
          final month = dateParts.length > 1 ? dateParts[0].substring(0, 3) : '';
          final day   = dateParts.length > 1 ? dateParts[1].replaceAll(',','') : e.date;
          return '''<div class="event-card">
        <div class="event-date"><div class="month">${_esc(month)}</div><div class="day-num">${_esc(day)}</div></div>
        <div class="event-info">
          <h3>${_esc(e.title)}</h3>
          ${e.time.isNotEmpty ? '<p>🕐 ${_esc(e.time)}</p>' : ''}
          ${e.description.isNotEmpty ? '<p>${_esc(e.description)}</p>' : ''}
        </div>
      </div>''';
        }).join('\n');

  return '''<section id="events">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2>${b.subheading.isNotEmpty ? '<p>${_esc(b.subheading)}</p>' : ''}</div>
    <div class="events-list">$items</div>
  </div>
</section>''';
}

String _teamBlock(WebBlock b) {
  final cards = b.team.isEmpty
      ? '<p style="text-align:center;color:#6B7280">Team members coming soon.</p>'
      : b.team.map((m) {
          final initials = m.name.split(' ')
              .take(2).map((w) => w.isNotEmpty ? w[0] : '').join();
          final avatar = m.photoUrl.isNotEmpty
              ? '<img src="${_esc(m.photoUrl)}" alt="${_esc(m.name)}">'
              : initials;
          return '''<div class="team-card">
        <div class="team-avatar">$avatar</div>
        <h3>${_esc(m.name)}</h3>
        ${m.role.isNotEmpty ? '<p class="role">${_esc(m.role)}</p>' : ''}
        ${m.bio.isNotEmpty  ? '<p>${_esc(m.bio)}</p>' : ''}
      </div>''';
        }).join('\n');

  return '''<section class="alt" id="team">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2></div>
    <div class="team-grid">$cards</div>
  </div>
</section>''';
}

String _sermonBlock(WebBlock b) => '''
<section id="sermon">
  <div class="container">
    <div class="sermon-block">
      <h2>${_esc(b.heading)}</h2>
      ${b.subheading.isNotEmpty ? '<p style="font-weight:600;margin-bottom:8px">${_esc(b.subheading)}</p>' : ''}
      <p>${_esc(b.body)}</p>
    </div>
  </div>
</section>''';

String _mapBlock(WebBlock b, WebsiteSettings s) {
  String mapEmbed;
  final addr = Uri.encodeComponent(b.mapAddress.isNotEmpty
      ? b.mapAddress : s.siteTitle);

  switch (b.mapProvider) {
    case MapProvider.google:
      mapEmbed = '<iframe src="https://maps.google.com/maps?q=${addr}&output=embed&z=${b.mapZoom}" allowfullscreen loading="lazy"></iframe>';
      break;
    case MapProvider.apple:
      // Apple Maps uses maps.apple.com — works in Safari; falls back to OSM in other browsers
      mapEmbed = '''<iframe src="https://maps.apple.com/?q=${addr}&z=${b.mapZoom}&output=embed"
          allowfullscreen loading="lazy"
          onerror="this.src='https://www.openstreetmap.org/export/embed.html?bbox=-0.5,51.3,0.3,51.6&layer=mapnik'">
      </iframe>''';
      break;
    case MapProvider.openStreetMap:
    default:
      // OpenStreetMap — free, no API key needed
      final lat  = b.mapLat  != 0 ? b.mapLat  : 40.7128;
      final lng  = b.mapLng  != 0 ? b.mapLng  : -74.0060;
      final zoom = int.tryParse(b.mapZoom) ?? 15;
      final bbox = _osmBbox(lat, lng, zoom);
      mapEmbed = '<iframe src="https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${lat}%2C${lng}" allowfullscreen loading="lazy"></iframe>';
  }

  return '''<section id="map">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2>${b.subheading.isNotEmpty ? '<p>${_esc(b.subheading)}</p>' : ''}</div>
    ${b.mapAddress.isNotEmpty ? '<p style="text-align:center;margin-bottom:16px">📍 ${_esc(b.mapAddress)}</p>' : ''}
    <div class="map-container">$mapEmbed</div>
  </div>
</section>''';
}

String _osmBbox(double lat, double lng, int zoom) {
  // Approximate bbox from center + zoom
  final delta = 0.02 * (20 - zoom.clamp(1, 19));
  final minLng = (lng - delta).toStringAsFixed(4);
  final minLat = (lat - delta).toStringAsFixed(4);
  final maxLng = (lng + delta).toStringAsFixed(4);
  final maxLat = (lat + delta).toStringAsFixed(4);
  return '$minLng%2C$minLat%2C$maxLng%2C$maxLat';
}

String _contactBlock(WebBlock b) => '''
<section id="contact" class="alt">
  <div class="container">
    <div class="section-heading"><h2>${_esc(b.heading)}</h2>${b.subheading.isNotEmpty ? '<p>${_esc(b.subheading)}</p>' : ''}</div>
    <div class="contact-grid">
      <form class="contact-form" onsubmit="alert('Message sent! (Connect this form to Formspree or EmailJS for real delivery.)'); return false;">
        <input type="text"  name="name"    placeholder="Your Name"    required>
        <input type="email" name="email"   placeholder="Email Address" required>
        <input type="text"  name="subject" placeholder="Subject">
        <textarea           name="message" placeholder="Your message..."></textarea>
        <button type="submit" class="btn btn-primary" style="width:100%">Send Message</button>
      </form>
      <div class="contact-info">
        ${b.body.isNotEmpty ? b.body.split('\n').map((l) => '<p><span class="icon">📌</span>${_esc(l)}</p>').join('') : ''}
      </div>
    </div>
  </div>
</section>''';

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
    case 'cross':
      return '<div class="divider-cross">✝</div>';
    case 'wave':
      return '<div class="divider-wave">〰〰〰</div>';
    default:
      return '<hr class="divider-line" style="margin:0">';
  }
}

String _richTextBlock(WebBlock b) => '''
<section id="text-${b.id.substring(0,6)}">
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

// ── DEPLOY CONFIG GENERATORS ──────────────────────────────────────────────────

String _githubActionsYml(DeploySettings d) => '''
# GitHub Actions – Deploy to GitHub Pages
# Push this repo to GitHub, then enable Pages in Settings > Pages > Source: gh-pages branch
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
3. Go to **Settings → Pages → Source** and set branch to `${d.githubBranch}`
4. Your site will be live at **https://USERNAME.github.io/REPO**
${d.githubRepo.isNotEmpty ? '\n   Configured repo: `${d.githubRepo}`' : ''}

### Option 2 – Cloudflare Pages (free)
1. Sign up at **pages.cloudflare.com**
2. Create a new project and upload these files
3. Your site will be live at **PROJECT.pages.dev**

### Option 3 – Any Static Host
Upload all files to Netlify, Vercel, Firebase Hosting, or any web server.

## Custom Domain
Set your CNAME record to point to your GitHub Pages or Cloudflare Pages URL.
${d.customDomain.isNotEmpty ? '\nConfigured domain: `${d.customDomain}`' : ''}

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