// lib/screens/setup_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/church_profile.dart';
import '../services/bible_service.dart';
import '../apps/bible/bible_screen.dart';
import '../theme.dart';

class SetupScreen extends StatefulWidget {
  final bool editMode;
  const SetupScreen({super.key, this.editMode = false});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl         = TextEditingController();
  final _taglineCtrl      = TextEditingController();
  final _denominationCtrl = TextEditingController();
  final _plantingYearCtrl = TextEditingController();
  final _cityCtrl         = TextEditingController();
  final _stateCtrl        = TextEditingController();
  final _countryCtrl      = TextEditingController(text: 'United States');
  final _websiteCtrl      = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _phoneCtrl        = TextEditingController();
  final _pastorCtrl       = TextEditingController();
  final _visionCtrl       = TextEditingController();
  final _missionCtrl      = TextEditingController();

  List<String> _selectedApps = ['notes', 'bible', 'website', 'presentation'];

  // Branding
  Color  _primaryColor   = primaryColor;
  Color  _secondaryColor = accentColor;
  String _logoPath       = '';
  String _existingLogoPath = '';

  // Bible translation
  String _bibleTranslationId = 'BSB';

  @override
  void initState() {
    super.initState();
    if (widget.editMode) _populateExisting();
  }

  void _populateExisting() {
    final state = context.read<AppState>();
    final p     = state.churchProfile;
    if (p == null) return;
    _nameCtrl.text         = p.name;
    _taglineCtrl.text      = p.tagline;
    _denominationCtrl.text = p.denomination;
    _plantingYearCtrl.text = p.plantingYear;
    _cityCtrl.text         = p.city;
    _stateCtrl.text        = p.state;
    _countryCtrl.text      = p.country;
    _websiteCtrl.text      = p.website;
    _emailCtrl.text        = p.email;
    _phoneCtrl.text        = p.phone;
    _pastorCtrl.text       = p.leadPastorName;
    _visionCtrl.text       = p.vision;
    _missionCtrl.text      = p.missionStatement;
    _selectedApps          = List<String>.from(p.installedApps);
    _primaryColor          = p.primaryColor;
    _secondaryColor        = p.secondaryColor;
    _existingLogoPath      = p.logoPath;
    _bibleTranslationId    = p.bibleTranslationId;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _taglineCtrl, _denominationCtrl, _plantingYearCtrl,
      _cityCtrl, _stateCtrl, _countryCtrl, _websiteCtrl, _emailCtrl,
      _phoneCtrl, _pastorCtrl, _visionCtrl, _missionCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  String _colorToHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
    if (picked != null) setState(() => _logoPath = picked.path);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final state    = context.read<AppState>();
    final existing = state.churchProfile;

    String savedLogoPath = _existingLogoPath;
    if (_logoPath.isNotEmpty) {
      savedLogoPath = await state.saveLogo(_logoPath);
    }

    final profile = ChurchProfile(
      name:               _nameCtrl.text.trim(),
      tagline:            _taglineCtrl.text.trim(),
      denomination:       _denominationCtrl.text.trim(),
      city:               _cityCtrl.text.trim(),
      state:              _stateCtrl.text.trim(),
      country:            _countryCtrl.text.trim(),
      website:            _websiteCtrl.text.trim(),
      email:              _emailCtrl.text.trim(),
      phone:              _phoneCtrl.text.trim(),
      leadPastorName:     _pastorCtrl.text.trim(),
      plantingYear:       _plantingYearCtrl.text.trim(),
      vision:             _visionCtrl.text.trim(),
      missionStatement:   _missionCtrl.text.trim(),
      installedApps:      widget.editMode
          ? (existing?.installedApps ?? _selectedApps)
          : _selectedApps,
      primaryColorHex:    _colorToHex(_primaryColor),
      secondaryColorHex:  _colorToHex(_secondaryColor),
      logoPath:           savedLogoPath,
      bibleTranslationId: _bibleTranslationId,
    );

    await state.saveChurchProfile(profile);

    if (mounted && widget.editMode) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Church profile updated!'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.editMode ? _editScaffold() : _setupScaffold();
  }

  Widget _editScaffold() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Church Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryColor,
        foregroundColor: contrastOn(_primaryColor),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: Icon(Icons.check, color: contrastOn(_primaryColor)),
            label: Text('Save',
                style: TextStyle(
                    color: contrastOn(_primaryColor),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _buildForm(showAppPicker: false),
      bottomNavigationBar: _saveBar('Save Changes'),
    );
  }

  Widget _setupScaffold() {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _brandedHeader(),
            Expanded(child: _buildForm(showAppPicker: true)),
            _saveBar('Finish Setup 🎉'),
          ],
        ),
      ),
    );
  }

  Widget _buildForm({required bool showAppPicker}) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── BRANDING ──────────────────────────────────────────────────
            _section('Branding & Identity'),
            _BrandingSection(
              primaryColor:    _primaryColor,
              secondaryColor:  _secondaryColor,
              logoPath:  _logoPath.isNotEmpty ? _logoPath : _existingLogoPath,
              onPickLogo: _pickLogo,
              onRemoveLogo: () => setState(() {
                _logoPath = '';
                _existingLogoPath = '';
              }),
              onPickPrimary: () async {
                final c = await _showColorPicker(
                    context, _primaryColor, 'Primary Color');
                if (c != null) setState(() => _primaryColor = c);
              },
              onPickSecondary: () async {
                final c = await _showColorPicker(
                    context, _secondaryColor, 'Secondary / Accent Color');
                if (c != null) setState(() => _secondaryColor = c);
              },
            ),

            // ── BIBLE TRANSLATION ─────────────────────────────────────────
            _section('Bible Translation'),
            _BibleTranslationPicker(
              selectedId: _bibleTranslationId,
              primary:    _primaryColor,
              onChanged: (id) => setState(() => _bibleTranslationId = id),
            ),
            const SizedBox(height: 8),

            // ── CHURCH IDENTITY ───────────────────────────────────────────
            _section('Church Identity'),
            _field('Church Name *', _nameCtrl,
                hint: 'e.g. Grace Community Church', required: true),
            _field('Tagline / Slogan', _taglineCtrl,
                hint: 'e.g. Love God, Love People'),
            _field('Denomination / Network', _denominationCtrl,
                hint: 'e.g. Non-Denominational'),
            _field('Year Founded', _plantingYearCtrl,
                hint: 'e.g. 2024',
                keyboard: TextInputType.number),
            const SizedBox(height: 4),

            // ── LOCATION & CONTACT ────────────────────────────────────────
            _section('Location & Contact'),
            Row(children: [
              Expanded(child: _field('City *', _cityCtrl,
                  hint: 'Nashville', required: true)),
              const SizedBox(width: 12),
              Expanded(child: _field('State', _stateCtrl,
                  hint: 'Tennessee')),
            ]),
            _field('Country', _countryCtrl),
            _field('Contact Email', _emailCtrl,
                hint: 'info@mychurch.org',
                keyboard: TextInputType.emailAddress),
            _field('Phone', _phoneCtrl,
                hint: '(615) 555-1234',
                keyboard: TextInputType.phone),
            _field('Website', _websiteCtrl,
                hint: 'https://mychurch.org',
                keyboard: TextInputType.url),
            const SizedBox(height: 4),

            // ── LEADERSHIP ────────────────────────────────────────────────
            _section('Leadership'),
            _field('Lead Pastor / Planter', _pastorCtrl,
                hint: 'Pastor John Smith'),
            const SizedBox(height: 4),

            // ── VISION & MISSION ──────────────────────────────────────────
            _section('Vision & Mission'),
            _field('Vision Statement', _visionCtrl,
                hint: 'Where is God calling your church?', maxLines: 3),
            _field('Mission Statement', _missionCtrl,
                hint: 'The core purpose of your church.', maxLines: 3),

            // ── APP PICKER (first launch only) ────────────────────────────
            if (showAppPicker) ...[
              const SizedBox(height: 4),
              _section('Starting Apps'),
              const Text(
                  'Choose which tools to start with. You can add or remove apps anytime.',
                  style: TextStyle(fontSize: 13, color: textMid)),
              const SizedBox(height: 12),
              ...availableApps.map((app) => _AppCheckTile(
                    app: app,
                    selected: _selectedApps.contains(app.id),
                    accentColor: _primaryColor,
                    onToggle: (val) => setState(() {
                      val ? _selectedApps.add(app.id)
                          : _selectedApps.remove(app.id);
                    }),
                  )),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────────

  Widget _brandedHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _primaryColor,
            Color.lerp(_primaryColor, Colors.black, 0.3)!
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                    color: _secondaryColor,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.church,
                    color: contrastOn(_secondaryColor), size: 26),
              ),
              const SizedBox(width: 14),
              Text('Church Plant Toolkit',
                  style: TextStyle(
                      color: contrastOn(_primaryColor),
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          Text('WELCOME',
              style: TextStyle(
                  color: contrastOn(_primaryColor).withValues(alpha: 0.65),
                  fontSize: 12, letterSpacing: 1.6,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text("Let's set up your church profile",
              style: TextStyle(
                  color: contrastOn(_primaryColor),
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('Fill in what you know — everything can be updated later.',
              style: TextStyle(
                  color: contrastOn(_primaryColor).withValues(alpha: 0.65),
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _saveBar(String label) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEAEDF3))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: contrastOn(_primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 3, height: 16,
            decoration: BoxDecoration(
                color: _secondaryColor,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textDark)),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
    bool required = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty)
                ? 'This field is required'
                : null
            : null,
      ),
    );
  }
}

// ── BIBLE TRANSLATION PICKER ──────────────────────────────────────────────────
class _BibleTranslationPicker extends StatefulWidget {
  final String selectedId;
  final Color primary;
  final ValueChanged<String> onChanged;

  const _BibleTranslationPicker({
    required this.selectedId,
    required this.primary,
    required this.onChanged,
  });

  @override
  State<_BibleTranslationPicker> createState() =>
      _BibleTranslationPickerState();
}

class _BibleTranslationPickerState extends State<_BibleTranslationPicker> {
  // Popular free English translations with short descriptions
  static const _popular = <Map<String, String>>[
    {'id': 'BSB',   'name': 'Berean Standard Bible',      'desc': 'Modern, accurate, free to use'},
    {'id': 'KJV',   'name': 'King James Version',          'desc': 'Traditional, public domain (1611)'},
    {'id': 'WEB',   'name': 'World English Bible',         'desc': 'Modern, public domain'},
    {'id': 'ASV',   'name': 'American Standard Version',   'desc': 'Classic, public domain (1901)'},
    {'id': 'YLT',   'name': "Young's Literal Translation", 'desc': 'Word-for-word literal (1862)'},
    {'id': 'DARBY', 'name': 'Darby Translation',           'desc': 'Scholarly, public domain (1890)'},
    {'id': 'LSV',   'name': 'Literal Standard Version',    'desc': 'Modern literal, free to use'},
    {'id': 'NHEB',  'name': 'New Heart English Bible',     'desc': 'Modern, free to use'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAEDF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book_outlined,
                    color: Color(0xFF2E7D32), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Preferred Translation',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: textDark)),
                    Text('Used across all apps & scripture references',
                        style: TextStyle(fontSize: 11, color: textMid)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Quick-select popular translations
          ...List.generate(_popular.length, (i) {
            final entry = _popular[i];
            final id    = entry['id']!;
            final name  = entry['name']!;
            final desc  = entry['desc']!;
            final sel = widget.selectedId == id;
            return GestureDetector(
              onTap: () => widget.onChanged(id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                      ? widget.primary.withValues(alpha: 0.07)
                      : const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel
                        ? widget.primary
                        : const Color(0xFFDDE1EC),
                    width: sel ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Abbreviation badge
                    Container(
                      width: 48, height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel
                            ? widget.primary
                            : const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(id,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: sel
                                  ? contrastOn(widget.primary)
                                  : textMid)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: sel
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color:
                                      sel ? widget.primary : textDark)),
                          Text(desc,
                              style: const TextStyle(
                                  fontSize: 11, color: textMid)),
                        ],
                      ),
                    ),
                    if (sel)
                      Icon(Icons.check_circle,
                          color: widget.primary, size: 18),
                  ],
                ),
              ),
            );
          }),

          // Browse all button
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _browseAll(context),
              icon: const Icon(Icons.public, size: 16),
              label: const Text('Browse All 1,000+ Translations'),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.primary,
                side: BorderSide(
                    color: widget.primary.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),

          // Attribution
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 12, color: textMid),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                    'Powered by bible.helloao.org — free, no account needed, 1,000+ translations',
                    style: TextStyle(fontSize: 10, color: textMid)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _browseAll(BuildContext context) async {
    final svc = context.read<AppState>().bibleService;
    // Start loading translations in background
    if (svc.availableTranslations.isEmpty) svc.fetchTranslations();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider<BibleService>.value(
        value: svc,
        child: TranslationPickerSheet(
          service: svc,
          primary: widget.primary,
          onPicked: (id) {
            widget.onChanged(id);
          },
        ),
      ),
    );
  }
}

// ── COLOR PICKER DIALOG ───────────────────────────────────────────────────────
Future<Color?> _showColorPicker(
    BuildContext context, Color current, String title) async {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(initial: current, title: title),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final String title;
  const _ColorPickerDialog({required this.initial, required this.title});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _selected;
  late TextEditingController _hexCtrl;

  static const _palette = [
    Color(0xFF0D1B2A), Color(0xFF1A3A5C), Color(0xFF1565C0),
    Color(0xFF1976D2), Color(0xFF0288D1), Color(0xFF0097A7),
    Color(0xFF4A1A7C), Color(0xFF6A1B9A), Color(0xFF7B1FA2),
    Color(0xFF9C27B0), Color(0xFF673AB7), Color(0xFF3F51B5),
    Color(0xFF1B4332), Color(0xFF2E7D32), Color(0xFF388E3C),
    Color(0xFF43A047), Color(0xFF00796B), Color(0xFF00897B),
    Color(0xFF7B0000), Color(0xFFB71C1C), Color(0xFFC62828),
    Color(0xFFD32F2F), Color(0xFFAD1457), Color(0xFF880E4F),
    Color(0xFF6D4C00), Color(0xFFF57F17), Color(0xFFF9A825),
    Color(0xFFD4A843), Color(0xFFFF8F00), Color(0xFFE65100),
    Color(0xFF212121), Color(0xFF424242), Color(0xFF616161),
    Color(0xFF757575), Color(0xFF9E9E9E), Color(0xFFBDBDBD),
    Color(0xFFFFFFFF), Color(0xFFFFFDE7), Color(0xFFF5F5F5),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _hexCtrl  = TextEditingController(text: _colorToHex(widget.initial));
  }

  @override
  void dispose() { _hexCtrl.dispose(); super.dispose(); }

  String _colorToHex(Color c) {
    final hex = c.toARGB32().toRadixString(16).toUpperCase();
    return '#${hex.substring(2)}';
  }

  Color? _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
            const SizedBox(height: 20),
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _selected,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE1EC)),
              ),
              child: Center(
                child: Text('Preview',
                    style: TextStyle(
                        color: contrastOn(_selected),
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Hex:', style: TextStyle(color: textMid, fontSize: 13)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '#1A3A5C', isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) {
                      final c = _hexToColor(v);
                      if (c != null) setState(() => _selected = c);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Palette',
                style: TextStyle(
                    fontSize: 13, color: textMid, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _palette.map((c) {
                final sel = c.toARGB32() == _selected.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() {
                    _selected  = c;
                    _hexCtrl.text = _colorToHex(c);
                  }),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.black : Colors.grey.shade300,
                        width: sel ? 3 : 1,
                      ),
                      boxShadow: sel
                          ? [const BoxShadow(
                              color: Colors.black26, blurRadius: 4)]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _selected,
                      foregroundColor: contrastOn(_selected)),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── BRANDING SECTION ──────────────────────────────────────────────────────────
class _BrandingSection extends StatelessWidget {
  final Color primaryColor;
  final Color secondaryColor;
  final String logoPath;
  final VoidCallback onPickLogo;
  final VoidCallback onRemoveLogo;
  final VoidCallback onPickPrimary;
  final VoidCallback onPickSecondary;

  const _BrandingSection({
    required this.primaryColor,
    required this.secondaryColor,
    required this.logoPath,
    required this.onPickLogo,
    required this.onRemoveLogo,
    required this.onPickPrimary,
    required this.onPickSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAEDF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo row
          Row(
            children: [
              GestureDetector(
                onTap: onPickLogo,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3), width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: logoPath.isNotEmpty
                      ? Image.file(File(logoPath), fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                color: primaryColor, size: 28),
                            const SizedBox(height: 4),
                            Text('Logo',
                                style: TextStyle(
                                    color: primaryColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Church Logo',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14, color: textDark)),
                    const SizedBox(height: 4),
                    const Text('PNG or JPG, shown in dashboard and apps',
                        style: TextStyle(fontSize: 12, color: textMid)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: onPickLogo,
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: Text(
                              logoPath.isNotEmpty ? 'Change' : 'Upload'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryColor,
                            side: BorderSide(color: primaryColor),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (logoPath.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: onRemoveLogo,
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red, size: 20),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Color pickers
          const Text('Brand Colors',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14, color: textDark)),
          const SizedBox(height: 4),
          const Text('Applied across all apps.',
              style: TextStyle(fontSize: 12, color: textMid)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ColorSwatch(
                  label: 'Primary',
                  sublabel: 'Headers, buttons, banners',
                  color: primaryColor,
                  onTap: onPickPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ColorSwatch(
                  label: 'Secondary',
                  sublabel: 'Accents, highlights',
                  color: secondaryColor,
                  onTap: onPickSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Live mini-preview
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(
              children: [
                Container(
                  height: 36, color: primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Text('My Church',
                          style: TextStyle(
                              color: contrastOn(primaryColor),
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                            color: secondaryColor,
                            shape: BoxShape.circle),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 28,
                  color: Color.lerp(primaryColor, Colors.white, 0.88),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: secondaryColor,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('Preview of your brand colors',
                          style: TextStyle(
                              fontSize: 11, color: primaryColor,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;
  const _ColorSwatch({
    required this.label, required this.sublabel,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDE1EC)),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.black.withValues(alpha: 0.1)),
              ),
              child: Icon(Icons.edit, size: 16,
                  color: contrastOn(color).withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13, color: textDark)),
                  Text(sublabel,
                      style: const TextStyle(fontSize: 10, color: textMid),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── APP CHECK TILE ────────────────────────────────────────────────────────────
class _AppCheckTile extends StatelessWidget {
  final AppDefinition app;
  final bool selected;
  final Color accentColor;
  final ValueChanged<bool> onToggle;

  const _AppCheckTile({
    required this.app, required this.selected,
    required this.accentColor, required this.onToggle,
  });

  static const _icons = {
    'notes':        Icons.note_alt_outlined,
    'bible':        Icons.menu_book_outlined,
    'website':      Icons.web_outlined,
    'presentation': Icons.present_to_all_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(
            color: selected ? accentColor : const Color(0xFFDDE1EC),
            width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
        color: selected
            ? Color.lerp(accentColor, Colors.white, 0.92)
            : Colors.white,
      ),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: selected ? accentColor : const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_icons[app.id] ?? Icons.apps,
              color: selected ? contrastOn(accentColor) : accentColor,
              size: 20),
        ),
        title: Text(app.title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(app.description,
            style: const TextStyle(fontSize: 12, color: textMid)),
        trailing: Checkbox(
          value: selected,
          onChanged: (v) => onToggle(v ?? false),
          activeColor: accentColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4)),
        ),
        onTap: () => onToggle(!selected),
      ),
    );
  }
}