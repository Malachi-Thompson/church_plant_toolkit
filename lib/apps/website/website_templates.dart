// lib/apps/website/website_templates.dart
import 'package:uuid/uuid.dart';
import 'website_models.dart';

const _uuid = Uuid();

String _id() => _uuid.v4();

// ── TEMPLATE FACTORY ──────────────────────────────────────────────────────────

ChurchWebsite buildTemplate(
  String templateId,
  String churchName,
  String tagline,
  String primaryHex,
  String secondaryHex,
) {
  final settings = WebsiteSettings(
    siteTitle:    churchName,
    tagline:      tagline,
    primaryHex:   primaryHex,
    secondaryHex: secondaryHex,
    fontFamily:   'Inter',
  );

  switch (templateId) {
    case 'modern_multi':
      return _modernMulti(settings, churchName, tagline);
    case 'bold_landing':
      return _boldLanding(settings, churchName, tagline);
    case 'minimal_clean':
      return _minimalClean(settings, churchName, tagline);
    case 'community_hub':
      return _communityHub(settings, churchName, tagline);
    case 'classic_single':
    default:
      return _classicSingle(settings, churchName, tagline);
  }
}

// ── CLASSIC SINGLE PAGE ───────────────────────────────────────────────────────
ChurchWebsite _classicSingle(WebsiteSettings s, String name, String tag) =>
    ChurchWebsite(
      settings: s,
      pages: [
        WebPage(
          id: _id(), title: 'Home', slug: 'index', isHomePage: true,
          blocks: [
            WebBlock(id: _id(), type: BlockType.hero,
                heading: 'Welcome to $name',
                subheading: tag.isNotEmpty ? tag : 'Come as you are.',
                buttonText: 'Plan Your Visit', buttonUrl: '#contact'),
            WebBlock(id: _id(), type: BlockType.services,
                heading: 'Join Us',
                serviceTimes: [
                  ServiceTime(day: 'Sunday', time: '10:00 AM'),
                ]),
            WebBlock(id: _id(), type: BlockType.about,
                heading: 'About Us',
                body: 'We are a community of believers passionate about loving God and loving people.'),
            WebBlock(id: _id(), type: BlockType.events,
                heading: 'Upcoming Events'),
            WebBlock(id: _id(), type: BlockType.map,
                heading: 'Find Us',
                mapProvider: MapProvider.openStreetMap),
            WebBlock(id: _id(), type: BlockType.contact,
                heading: 'Get In Touch'),
          ],
        ),
      ],
    );

// ── MODERN MULTI PAGE ─────────────────────────────────────────────────────────
ChurchWebsite _modernMulti(WebsiteSettings s, String name, String tag) =>
    ChurchWebsite(
      settings: s,
      pages: [
        WebPage(
          id: _id(), title: 'Home', slug: 'index', isHomePage: true,
          blocks: [
            WebBlock(id: _id(), type: BlockType.hero,
                heading: 'Welcome to $name',
                subheading: tag.isNotEmpty ? tag : 'Rooted in faith. Growing together.',
                buttonText: 'Learn More', buttonUrl: 'about.html'),
            WebBlock(id: _id(), type: BlockType.services,
                heading: 'Worship With Us',
                serviceTimes: [ServiceTime(day: 'Sunday', time: '10:00 AM')]),
            WebBlock(id: _id(), type: BlockType.cta,
                heading: 'New Here?',
                subheading: 'We\'d love to meet you. Plan your first visit today.',
                buttonText: 'Plan a Visit', buttonUrl: 'contact.html'),
          ],
        ),
        WebPage(
          id: _id(), title: 'About', slug: 'about',
          blocks: [
            WebBlock(id: _id(), type: BlockType.about,
                heading: 'Who We Are',
                body: 'We are a community of believers passionate about loving God and loving people.'),
            WebBlock(id: _id(), type: BlockType.team,
                heading: 'Meet Our Team'),
          ],
        ),
        WebPage(
          id: _id(), title: 'Events', slug: 'events',
          blocks: [
            WebBlock(id: _id(), type: BlockType.events,
                heading: 'What\'s Coming Up',
                subheading: 'Join us for these upcoming gatherings.'),
          ],
        ),
        WebPage(
          id: _id(), title: 'Sermons', slug: 'sermons',
          blocks: [
            WebBlock(id: _id(), type: BlockType.sermon,
                heading: 'Messages',
                body: 'Watch or listen to our latest sermons.'),
          ],
        ),
        WebPage(
          id: _id(), title: 'Contact', slug: 'contact',
          blocks: [
            WebBlock(id: _id(), type: BlockType.map,
                heading: 'Find Us',
                mapProvider: MapProvider.openStreetMap),
            WebBlock(id: _id(), type: BlockType.contact,
                heading: 'Reach Out'),
          ],
        ),
      ],
    );

// ── BOLD LANDING ──────────────────────────────────────────────────────────────
ChurchWebsite _boldLanding(WebsiteSettings s, String name, String tag) =>
    ChurchWebsite(
      settings: s,
      pages: [
        WebPage(
          id: _id(), title: 'Home', slug: 'index', isHomePage: true,
          blocks: [
            WebBlock(id: _id(), type: BlockType.hero,
                heading: name.toUpperCase(),
                subheading: tag.isNotEmpty ? tag : 'God. Community. Purpose.',
                buttonText: 'Join Us This Sunday', buttonUrl: '#services'),
            WebBlock(id: _id(), type: BlockType.announcement,
                heading: '🎉 New Series Starting Soon',
                body: 'Join us this Sunday as we kick off our new sermon series.',
                announcementColor: '#D4A843'),
            WebBlock(id: _id(), type: BlockType.services,
                heading: 'Service Times',
                serviceTimes: [
                  ServiceTime(day: 'Sunday', time: '9:00 AM'),
                  ServiceTime(day: 'Sunday', time: '11:00 AM'),
                  ServiceTime(day: 'Wednesday', time: '7:00 PM'),
                ]),
            WebBlock(id: _id(), type: BlockType.about,
                heading: 'Our Mission',
                body: 'We exist to glorify God by making disciples who love God, love people, and serve the world.'),
            WebBlock(id: _id(), type: BlockType.cta,
                heading: 'Ready to Take Your Next Step?',
                subheading: 'We\'d love to walk alongside you.',
                buttonText: 'Connect With Us', buttonUrl: '#contact'),
            WebBlock(id: _id(), type: BlockType.contact,
                heading: 'Contact'),
          ],
        ),
      ],
    );

// ── MINIMAL CLEAN ─────────────────────────────────────────────────────────────
ChurchWebsite _minimalClean(WebsiteSettings s, String name, String tag) =>
    ChurchWebsite(
      settings: s..fontFamily = 'Playfair Display',
      pages: [
        WebPage(
          id: _id(), title: 'Home', slug: 'index', isHomePage: true,
          blocks: [
            WebBlock(id: _id(), type: BlockType.hero,
                heading: name,
                subheading: tag.isNotEmpty ? tag : 'A place to belong.',
                buttonText: 'Visit Us', buttonUrl: '#contact'),
            WebBlock(id: _id(), type: BlockType.divider,
                dividerStyle: 'cross'),
            WebBlock(id: _id(), type: BlockType.services,
                heading: 'Sunday Worship',
                serviceTimes: [ServiceTime(day: 'Sunday', time: '10:30 AM')]),
            WebBlock(id: _id(), type: BlockType.richText,
                heading: 'A Word from Our Pastor',
                body: 'We believe in a God who meets us right where we are. No matter your story, there\'s a seat for you at the table.'),
            WebBlock(id: _id(), type: BlockType.contact,
                heading: 'We\'d Love to Hear From You'),
          ],
        ),
      ],
    );

// ── COMMUNITY HUB ─────────────────────────────────────────────────────────────
ChurchWebsite _communityHub(WebsiteSettings s, String name, String tag) =>
    ChurchWebsite(
      settings: s,
      pages: [
        WebPage(
          id: _id(), title: 'Home', slug: 'index', isHomePage: true,
          blocks: [
            WebBlock(id: _id(), type: BlockType.hero,
                heading: 'Welcome to $name',
                subheading: tag.isNotEmpty ? tag : 'Building community. Changing lives.',
                buttonText: 'Get Involved', buttonUrl: 'connect.html'),
            WebBlock(id: _id(), type: BlockType.services,
                heading: 'Gather With Us',
                serviceTimes: [
                  ServiceTime(day: 'Sunday', time: '10:00 AM'),
                  ServiceTime(day: 'Wednesday', time: '6:30 PM'),
                ]),
            WebBlock(id: _id(), type: BlockType.events,
                heading: 'Coming Up'),
          ],
        ),
        WebPage(
          id: _id(), title: 'About', slug: 'about',
          blocks: [
            WebBlock(id: _id(), type: BlockType.about,
                heading: 'Our Story',
                body: 'We started as a small group of friends who wanted to create a church that felt like home.'),
            WebBlock(id: _id(), type: BlockType.team,
                heading: 'Leadership'),
          ],
        ),
        WebPage(
          id: _id(), title: 'Events', slug: 'events',
          blocks: [
            WebBlock(id: _id(), type: BlockType.events,
                heading: 'Events & Gatherings'),
          ],
        ),
        WebPage(
          id: _id(), title: 'Connect', slug: 'connect',
          blocks: [
            WebBlock(id: _id(), type: BlockType.map,
                heading: 'Find Us',
                mapProvider: MapProvider.openStreetMap),
            WebBlock(id: _id(), type: BlockType.contact,
                heading: 'Connect With Us'),
          ],
        ),
      ],
    );