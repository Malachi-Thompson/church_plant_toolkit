// lib/apps/website/website_models.dart

// ── BLOCK TYPES ───────────────────────────────────────────────────────────────
// Each block is a section of a page with a specific layout and content.

enum BlockType {
  hero,           // Large banner with title, subtitle, CTA button
  about,          // Text + optional image
  services,       // Service time and location cards
  events,         // Upcoming events list
  team,           // Staff grid
  sermon,         // Embedded sermon notes / scripture
  contact,        // Contact form + info
  map,            // Embedded map (Google, Apple, OpenStreetMap)
  gallery,        // Image grid (paths)
  announcement,   // Highlighted callout box
  divider,        // Visual spacer/divider
  richText,       // Free-form HTML/text block
  cta,            // Call-to-action band
}

const blockTypeLabels = <BlockType, String>{
  BlockType.hero:         'Hero Banner',
  BlockType.about:        'About',
  BlockType.services:     'Service Times',
  BlockType.events:       'Upcoming Events',
  BlockType.team:         'Meet the Team',
  BlockType.sermon:       'Scripture / Sermon',
  BlockType.contact:      'Contact',
  BlockType.map:          'Map / Directions',
  BlockType.gallery:      'Photo Gallery',
  BlockType.announcement: 'Announcement',
  BlockType.divider:      'Divider',
  BlockType.richText:     'Text Block',
  BlockType.cta:          'Call to Action',
};

// ── MAP PROVIDER ──────────────────────────────────────────────────────────────
enum MapProvider { google, apple, openStreetMap }

const mapProviderLabels = <MapProvider, String>{
  MapProvider.google:       'Google Maps',
  MapProvider.apple:        'Apple Maps',
  MapProvider.openStreetMap:'OpenStreetMap (free, no API key)',
};

// ── BLOCK ─────────────────────────────────────────────────────────────────────
class WebBlock {
  String id;
  BlockType type;
  bool isVisible;

  // Common fields
  String heading;
  String subheading;
  String body;           // rich text / description
  String buttonText;
  String buttonUrl;
  String imageUrl;       // local path or web URL

  // Services block
  List<ServiceTime> serviceTimes;

  // Events block
  List<WebEvent> events;

  // Team block
  List<WebTeamMember> team;

  // Map block
  MapProvider mapProvider;
  String mapAddress;
  double mapLat;
  double mapLng;
  String mapZoom;        // e.g. "15"

  // Gallery
  List<String> galleryImages;

  // Divider style
  String dividerStyle;   // 'line', 'wave', 'cross'

  // Announcement
  String announcementColor; // hex

  WebBlock({
    required this.id,
    required this.type,
    this.isVisible       = true,
    this.heading         = '',
    this.subheading      = '',
    this.body            = '',
    this.buttonText      = '',
    this.buttonUrl       = '',
    this.imageUrl        = '',
    List<ServiceTime>?  serviceTimes,
    List<WebEvent>?     events,
    List<WebTeamMember>?team,
    this.mapProvider     = MapProvider.openStreetMap,
    this.mapAddress      = '',
    this.mapLat          = 0,
    this.mapLng          = 0,
    this.mapZoom         = '15',
    List<String>?       galleryImages,
    this.dividerStyle    = 'line',
    this.announcementColor = '#1A3A5C',
  })  : serviceTimes   = serviceTimes  ?? [],
        events         = events         ?? [],
        team           = team           ?? [],
        galleryImages  = galleryImages  ?? [];

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type.name, 'isVisible': isVisible,
    'heading': heading, 'subheading': subheading, 'body': body,
    'buttonText': buttonText, 'buttonUrl': buttonUrl, 'imageUrl': imageUrl,
    'serviceTimes': serviceTimes.map((s) => s.toJson()).toList(),
    'events':       events.map((e) => e.toJson()).toList(),
    'team':         team.map((t) => t.toJson()).toList(),
    'mapProvider': mapProvider.name, 'mapAddress': mapAddress,
    'mapLat': mapLat, 'mapLng': mapLng, 'mapZoom': mapZoom,
    'galleryImages': galleryImages,
    'dividerStyle': dividerStyle,
    'announcementColor': announcementColor,
  };

  factory WebBlock.fromJson(Map<String, dynamic> j) => WebBlock(
    id:        j['id'] ?? '',
    type:      BlockType.values.firstWhere(
        (t) => t.name == j['type'], orElse: () => BlockType.richText),
    isVisible:   j['isVisible'] ?? true,
    heading:     j['heading']   ?? '',
    subheading:  j['subheading']?? '',
    body:        j['body']      ?? '',
    buttonText:  j['buttonText']?? '',
    buttonUrl:   j['buttonUrl'] ?? '',
    imageUrl:    j['imageUrl']  ?? '',
    serviceTimes: (j['serviceTimes'] as List? ?? [])
        .map((e) => ServiceTime.fromJson(e)).toList(),
    events: (j['events'] as List? ?? [])
        .map((e) => WebEvent.fromJson(e)).toList(),
    team:   (j['team'] as List? ?? [])
        .map((e) => WebTeamMember.fromJson(e)).toList(),
    mapProvider: MapProvider.values.firstWhere(
        (p) => p.name == j['mapProvider'],
        orElse: () => MapProvider.openStreetMap),
    mapAddress: j['mapAddress'] ?? '',
    mapLat:     (j['mapLat']   ?? 0).toDouble(),
    mapLng:     (j['mapLng']   ?? 0).toDouble(),
    mapZoom:    j['mapZoom']   ?? '15',
    galleryImages: List<String>.from(j['galleryImages'] ?? []),
    dividerStyle:      j['dividerStyle']      ?? 'line',
    announcementColor: j['announcementColor'] ?? '#1A3A5C',
  );

  WebBlock copyWith({
    String? id, BlockType? type, bool? isVisible,
    String? heading, String? subheading, String? body,
    String? buttonText, String? buttonUrl, String? imageUrl,
    List<ServiceTime>? serviceTimes, List<WebEvent>? events,
    List<WebTeamMember>? team,
    MapProvider? mapProvider, String? mapAddress,
    double? mapLat, double? mapLng, String? mapZoom,
    List<String>? galleryImages, String? dividerStyle,
    String? announcementColor,
  }) => WebBlock(
    id:               id               ?? this.id,
    type:             type             ?? this.type,
    isVisible:        isVisible        ?? this.isVisible,
    heading:          heading          ?? this.heading,
    subheading:       subheading       ?? this.subheading,
    body:             body             ?? this.body,
    buttonText:       buttonText       ?? this.buttonText,
    buttonUrl:        buttonUrl        ?? this.buttonUrl,
    imageUrl:         imageUrl         ?? this.imageUrl,
    serviceTimes:     serviceTimes     ?? this.serviceTimes,
    events:           events           ?? this.events,
    team:             team             ?? this.team,
    mapProvider:      mapProvider      ?? this.mapProvider,
    mapAddress:       mapAddress       ?? this.mapAddress,
    mapLat:           mapLat           ?? this.mapLat,
    mapLng:           mapLng           ?? this.mapLng,
    mapZoom:          mapZoom          ?? this.mapZoom,
    galleryImages:    galleryImages    ?? this.galleryImages,
    dividerStyle:     dividerStyle     ?? this.dividerStyle,
    announcementColor:announcementColor?? this.announcementColor,
  );
}

// ── NESTED MODELS ─────────────────────────────────────────────────────────────

class ServiceTime {
  String day;
  String time;
  String location;
  ServiceTime({required this.day, required this.time, this.location = ''});
  Map<String, dynamic> toJson() =>
      {'day': day, 'time': time, 'location': location};
  factory ServiceTime.fromJson(Map<String, dynamic> j) =>
      ServiceTime(day: j['day']??'', time: j['time']??'', location: j['location']??'');
}

class WebEvent {
  String title;
  String date;
  String time;
  String description;
  WebEvent({required this.title, this.date='', this.time='', this.description=''});
  Map<String, dynamic> toJson() =>
      {'title': title, 'date': date, 'time': time, 'description': description};
  factory WebEvent.fromJson(Map<String, dynamic> j) => WebEvent(
      title: j['title']??'', date: j['date']??'',
      time: j['time']??'', description: j['description']??'');
}

class WebTeamMember {
  String name;
  String role;
  String bio;
  String photoUrl;
  WebTeamMember({required this.name, this.role='', this.bio='', this.photoUrl=''});
  Map<String, dynamic> toJson() =>
      {'name': name, 'role': role, 'bio': bio, 'photoUrl': photoUrl};
  factory WebTeamMember.fromJson(Map<String, dynamic> j) => WebTeamMember(
      name: j['name']??'', role: j['role']??'',
      bio: j['bio']??'', photoUrl: j['photoUrl']??'');
}

// ── PAGE ──────────────────────────────────────────────────────────────────────

class WebPage {
  String id;
  String title;
  String slug;       // URL-safe name, e.g. "about-us"
  bool isHomePage;
  bool showInNav;
  List<WebBlock> blocks;

  WebPage({
    required this.id,
    required this.title,
    required this.slug,
    this.isHomePage  = false,
    this.showInNav   = true,
    List<WebBlock>? blocks,
  }) : blocks = blocks ?? [];

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'slug': slug,
    'isHomePage': isHomePage, 'showInNav': showInNav,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };

  factory WebPage.fromJson(Map<String, dynamic> j) => WebPage(
    id:         j['id']         ?? '',
    title:      j['title']      ?? '',
    slug:       j['slug']       ?? '',
    isHomePage: j['isHomePage'] ?? false,
    showInNav:  j['showInNav']  ?? true,
    blocks: (j['blocks'] as List? ?? [])
        .map((b) => WebBlock.fromJson(b)).toList(),
  );
}

// ── SITE SETTINGS ─────────────────────────────────────────────────────────────

class NavStyle { static const topbar = 'topbar'; static const sidebar = 'sidebar'; }

class WebsiteSettings {
  String siteTitle;
  String tagline;
  String faviconPath;
  String fontFamily;        // e.g. 'Inter', 'Playfair Display'
  String primaryHex;
  String secondaryHex;
  String backgroundHex;
  String textHex;
  String navStyle;          // 'topbar' | 'sidebar'
  bool   footerShowSocial;
  String facebookUrl;
  String instagramUrl;
  String youtubeUrl;
  String twitterUrl;
  String footerText;
  // Deploy
  DeploySettings deploy;

  WebsiteSettings({
    this.siteTitle        = '',
    this.tagline          = '',
    this.faviconPath      = '',
    this.fontFamily       = 'Inter',
    this.primaryHex       = '#1A3A5C',
    this.secondaryHex     = '#D4A843',
    this.backgroundHex    = '#FFFFFF',
    this.textHex          = '#1C1C2E',
    this.navStyle         = NavStyle.topbar,
    this.footerShowSocial = true,
    this.facebookUrl      = '',
    this.instagramUrl     = '',
    this.youtubeUrl       = '',
    this.twitterUrl       = '',
    this.footerText       = '',
    DeploySettings? deploy,
  }) : deploy = deploy ?? DeploySettings();

  Map<String, dynamic> toJson() => {
    'siteTitle': siteTitle, 'tagline': tagline, 'faviconPath': faviconPath,
    'fontFamily': fontFamily,
    'primaryHex': primaryHex, 'secondaryHex': secondaryHex,
    'backgroundHex': backgroundHex, 'textHex': textHex,
    'navStyle': navStyle,
    'footerShowSocial': footerShowSocial,
    'facebookUrl': facebookUrl, 'instagramUrl': instagramUrl,
    'youtubeUrl': youtubeUrl, 'twitterUrl': twitterUrl,
    'footerText': footerText,
    'deploy': deploy.toJson(),
  };

  factory WebsiteSettings.fromJson(Map<String, dynamic> j) => WebsiteSettings(
    siteTitle:        j['siteTitle']       ?? '',
    tagline:          j['tagline']         ?? '',
    faviconPath:      j['faviconPath']     ?? '',
    fontFamily:       j['fontFamily']      ?? 'Inter',
    primaryHex:       j['primaryHex']      ?? '#1A3A5C',
    secondaryHex:     j['secondaryHex']    ?? '#D4A843',
    backgroundHex:    j['backgroundHex']   ?? '#FFFFFF',
    textHex:          j['textHex']         ?? '#1C1C2E',
    navStyle:         j['navStyle']        ?? NavStyle.topbar,
    footerShowSocial: j['footerShowSocial']?? true,
    facebookUrl:      j['facebookUrl']     ?? '',
    instagramUrl:     j['instagramUrl']    ?? '',
    youtubeUrl:       j['youtubeUrl']      ?? '',
    twitterUrl:       j['twitterUrl']      ?? '',
    footerText:       j['footerText']      ?? '',
    deploy: j['deploy'] != null
        ? DeploySettings.fromJson(j['deploy']) : DeploySettings(),
  );
}

// ── DEPLOY SETTINGS ───────────────────────────────────────────────────────────

class DeploySettings {
  // GitHub Pages
  bool   githubPagesEnabled;
  String githubRepo;        // e.g. 'myusername/mychurch'
  String githubBranch;      // typically 'gh-pages'
  // Cloudflare Pages
  bool   cloudflareEnabled;
  String cloudflareProject; // Cloudflare project name
  // Custom domain
  String customDomain;

  DeploySettings({
    this.githubPagesEnabled = false,
    this.githubRepo         = '',
    this.githubBranch       = 'gh-pages',
    this.cloudflareEnabled  = false,
    this.cloudflareProject  = '',
    this.customDomain       = '',
  });

  Map<String, dynamic> toJson() => {
    'githubPagesEnabled': githubPagesEnabled, 'githubRepo': githubRepo,
    'githubBranch': githubBranch,
    'cloudflareEnabled': cloudflareEnabled,
    'cloudflareProject': cloudflareProject,
    'customDomain': customDomain,
  };

  factory DeploySettings.fromJson(Map<String, dynamic> j) => DeploySettings(
    githubPagesEnabled: j['githubPagesEnabled'] ?? false,
    githubRepo:         j['githubRepo']         ?? '',
    githubBranch:       j['githubBranch']       ?? 'gh-pages',
    cloudflareEnabled:  j['cloudflareEnabled']  ?? false,
    cloudflareProject:  j['cloudflareProject']  ?? '',
    customDomain:       j['customDomain']       ?? '',
  );
}

// ── FULL WEBSITE ──────────────────────────────────────────────────────────────

class ChurchWebsite {
  WebsiteSettings settings;
  List<WebPage> pages;

  ChurchWebsite({
    WebsiteSettings? settings,
    List<WebPage>? pages,
  })  : settings = settings ?? WebsiteSettings(),
        pages    = pages    ?? [];

  WebPage? get homePage =>
      pages.where((p) => p.isHomePage).isNotEmpty
          ? pages.firstWhere((p) => p.isHomePage)
          : pages.isNotEmpty ? pages.first : null;

  Map<String, dynamic> toJson() => {
    'settings': settings.toJson(),
    'pages': pages.map((p) => p.toJson()).toList(),
  };

  factory ChurchWebsite.fromJson(Map<String, dynamic> j) => ChurchWebsite(
    settings: j['settings'] != null
        ? WebsiteSettings.fromJson(j['settings'])
        : WebsiteSettings(),
    pages: (j['pages'] as List? ?? [])
        .map((p) => WebPage.fromJson(p)).toList(),
  );
}

// ── TEMPLATE DEFINITIONS ──────────────────────────────────────────────────────

class SiteTemplate {
  final String id;
  final String name;
  final String description;
  final bool   isMultiPage;
  final String previewEmoji;

  const SiteTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.isMultiPage,
    required this.previewEmoji,
  });
}

const siteTemplates = <SiteTemplate>[
  SiteTemplate(
    id: 'classic_single',
    name: 'Classic Single Page',
    description: 'Everything on one scrolling page. Great for new churches.',
    isMultiPage: false,
    previewEmoji: '📜',
  ),
  SiteTemplate(
    id: 'modern_multi',
    name: 'Modern Multi-Page',
    description: 'Home, About, Events, Sermons, and Contact pages.',
    isMultiPage: true,
    previewEmoji: '🏛️',
  ),
  SiteTemplate(
    id: 'bold_landing',
    name: 'Bold Landing',
    description: 'High-impact hero, service times, and a clear CTA.',
    isMultiPage: false,
    previewEmoji: '🔥',
  ),
  SiteTemplate(
    id: 'minimal_clean',
    name: 'Minimal & Clean',
    description: 'Simple, elegant layout. Let your message speak.',
    isMultiPage: false,
    previewEmoji: '🕊️',
  ),
  SiteTemplate(
    id: 'community_hub',
    name: 'Community Hub',
    description: 'Multi-page with events, team, map, and social links.',
    isMultiPage: true,
    previewEmoji: '🌍',
  ),
];