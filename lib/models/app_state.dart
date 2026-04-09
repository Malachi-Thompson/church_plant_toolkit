// lib/models/app_state.dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'church_profile.dart';
import '../services/bible_service.dart';

// ── PIN HASHING ───────────────────────────────────────────────────────────────
// SHA-256 so the PIN is never stored as plain text.
String hashPin(String pin) =>
    sha256.convert(utf8.encode(pin)).toString();

class AppState extends ChangeNotifier {
  ChurchProfile? _churchProfile;
  bool _isSetupComplete = false;
  bool _isLoading       = true;

  // BibleService is owned here so it's always in sync with the profile
  final BibleService bibleService = BibleService();

  // Presentation decks cached as raw JSON
  String _presentationDecksJson = '[]';
  String get presentationDecksJson => _presentationDecksJson;

  // ── Admin / lock system ───────────────────────────────────────────────────
  // _adminPinHash  - SHA-256 of the admin PIN; empty = no admin set up.
  // _isAdminLocked - when true, settings/setup/app-management are hidden
  //                  until the correct PIN is entered this session.
  // _isAdminUnlocked - true after a successful PIN entry this session.
  String _adminPinHash    = '';
  bool   _isAdminLocked   = false;
  bool   _isAdminUnlocked = false;

  bool   get hasAdminPin      => _adminPinHash.isNotEmpty;
  bool   get isAdminLocked    => hasAdminPin && _isAdminLocked && !_isAdminUnlocked;
  bool   get isAdminUnlocked  => _isAdminUnlocked;
  /// Raw persisted lock flag — true even while unlocked this session.
  bool   get adminLockEnabled => _isAdminLocked;

  ChurchProfile? get churchProfile  => _churchProfile;
  bool get isSetupComplete          => _isSetupComplete;
  bool get isLoading                => _isLoading;

  Color get brandPrimary   =>
      _churchProfile?.primaryColor  ?? const Color(0xFF1A3A5C);
  Color get brandSecondary =>
      _churchProfile?.secondaryColor ?? const Color(0xFFD4A843);
  ThemeData get churchTheme =>
      buildChurchTheme(brandPrimary, brandSecondary);

  AppState() { _loadData(); }

  // ── LOAD ──────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    final prefs       = await SharedPreferences.getInstance();
    _isSetupComplete  = prefs.getBool('setup_complete') ?? false;
    final profileJson = prefs.getString('church_profile');
    if (profileJson != null) {
      _churchProfile = ChurchProfile.fromJson(jsonDecode(profileJson));
      await bibleService.setTranslation(_churchProfile!.bibleTranslationId);
    }
    _presentationDecksJson = prefs.getString('presentation_decks') ?? '[]';
    _adminPinHash  = prefs.getString('admin_pin_hash') ?? '';
    _isAdminLocked = prefs.getBool('admin_is_locked')  ?? false;
    _isLoading = false;
    notifyListeners();
  }

  // ── PRESENTATION ──────────────────────────────────────────────────────────

  Future<void> savePresentationDecksJson(String json) async {
    _presentationDecksJson = json;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('presentation_decks', json);
  }

  // ── CHURCH PROFILE ────────────────────────────────────────────────────────

  Future<void> saveChurchProfile(ChurchProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    _churchProfile = profile;
    await prefs.setString('church_profile', jsonEncode(profile.toJson()));
    await prefs.setBool('setup_complete', true);
    _isSetupComplete = true;
    await bibleService.setTranslation(profile.bibleTranslationId);
    notifyListeners();
  }

  Future<void> updateBibleTranslation(String translationId) async {
    if (_churchProfile == null) return;
    await saveChurchProfile(
        _churchProfile!.copyWith(bibleTranslationId: translationId));
  }

  Future<String> saveLogo(String sourcePath) async {
    final dir     = await getApplicationDocumentsDirectory();
    final logoDir = Directory('${dir.path}/church_logos');
    if (!await logoDir.exists()) await logoDir.create(recursive: true);

    // Delete the old logo file so stale files don't accumulate
    final oldPath = _churchProfile?.logoPath ?? '';
    if (oldPath.isNotEmpty) {
      try { await File(oldPath).delete(); } catch (_) {}
    }

    // Use a timestamp in the filename so the path is always unique.
    // This guarantees didUpdateWidget fires in ChurchLogo and ValueKey
    // changes on every Image.file — forcing a fresh decode from disk.
    final ext  = sourcePath.split('.').last.toLowerCase();
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final dest = File('${logoDir.path}/church_logo_$ts.$ext');
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  Future<void> installApp(String appId) async {
    if (_churchProfile == null) return;
    final updated = List<String>.from(_churchProfile!.installedApps);
    if (!updated.contains(appId)) {
      updated.add(appId);
      _churchProfile = _churchProfile!.copyWith(installedApps: updated);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('church_profile', jsonEncode(_churchProfile!.toJson()));
      notifyListeners();
    }
  }

  Future<void> removeApp(String appId) async {
    if (_churchProfile == null) return;
    final updated = List<String>.from(_churchProfile!.installedApps)
      ..remove(appId);
    _churchProfile = _churchProfile!.copyWith(installedApps: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('church_profile', jsonEncode(_churchProfile!.toJson()));
    notifyListeners();
  }

  Future<void> resetSetup() async {
    if (_churchProfile?.logoPath.isNotEmpty == true) {
      try { await File(_churchProfile!.logoPath).delete(); } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _churchProfile         = null;
    _isSetupComplete       = false;
    _presentationDecksJson = '[]';
    _adminPinHash          = '';
    _isAdminLocked         = false;
    _isAdminUnlocked       = false;
    notifyListeners();
  }

  // ── ADMIN PIN ─────────────────────────────────────────────────────────────

  Future<void> setAdminPin(String plainPin) async {
    _adminPinHash    = hashPin(plainPin);
    _isAdminUnlocked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_pin_hash', _adminPinHash);
    notifyListeners();
  }

  Future<void> removeAdminPin() async {
    _adminPinHash    = '';
    _isAdminLocked   = false;
    _isAdminUnlocked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_pin_hash');
    await prefs.setBool('admin_is_locked', false);
    notifyListeners();
  }

  bool verifyPin(String plainPin) => hashPin(plainPin) == _adminPinHash;

  void unlockAdmin() {
    _isAdminUnlocked = true;
    notifyListeners();
  }

  Future<void> lockAdmin() async {
    _isAdminUnlocked = false;
    notifyListeners();
  }

  Future<void> setAdminLockEnabled(bool enabled) async {
    _isAdminLocked = enabled;
    if (!enabled) _isAdminUnlocked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('admin_is_locked', enabled);
    notifyListeners();
  }

  // ── PROFILE EXPORT / IMPORT ───────────────────────────────────────────────

  Future<String?> exportProfile() async {
    if (_churchProfile == null) return null;
    try {
      final profileMap = Map<String, dynamic>.from(_churchProfile!.toJson());
      profileMap['logoPath'] = ''; // logo paths are device-local
      final data = {
        'version':       1,
        'exportedAt':    DateTime.now().toIso8601String(),
        'churchProfile': profileMap,
      };
      final dir  = await getApplicationDocumentsDirectory();
      final safe = _churchProfile!.name
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim()
          .replaceAll(' ', '_');
      final file = File('${dir.path}/${safe}_church_profile.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Returns null on success, or an error message string on failure.
  Future<String?> importProfile(String filePath) async {
    try {
      final raw  = await File(filePath).readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if ((data['version'] as int?) != 1) return 'Unsupported profile version.';
      final profile = ChurchProfile.fromJson(
          data['churchProfile'] as Map<String, dynamic>);
      await saveChurchProfile(profile);
      return null;
    } catch (e) {
      return 'Import failed: $e';
    }
  }
}

// ── THEME ─────────────────────────────────────────────────────────────────────

ThemeData buildChurchTheme(Color primary, Color secondary) {
  final onPrimary = primary.computeLuminance() > 0.4
      ? Colors.black
      : Colors.white;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary:   primary,
      secondary: secondary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      elevation: 0,
    ),
    useMaterial3: true,
  );
}