// lib/models/app_state.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'church_profile.dart';
import '../services/bible_service.dart';

class AppState extends ChangeNotifier {
  ChurchProfile? _churchProfile;
  bool _isSetupComplete = false;
  bool _isLoading       = true;

  // BibleService is owned here so it's always in sync with the profile
  final BibleService bibleService = BibleService();

  // ── Presentation decks cached as raw JSON so AppState has no dependency
  //    on the Slide/Deck types defined in presentation_screen.dart.
  //    The presentation screen reads/writes this via presentationDecksJson
  //    and savePresentationDecksJson().
  String _presentationDecksJson = '[]';
  String get presentationDecksJson => _presentationDecksJson;

  ChurchProfile? get churchProfile  => _churchProfile;
  bool get isSetupComplete          => _isSetupComplete;
  bool get isLoading                => _isLoading;

  Color get brandPrimary   =>
      _churchProfile?.primaryColor  ?? const Color(0xFF1A3A5C);
  Color get brandSecondary =>
      _churchProfile?.secondaryColor ?? const Color(0xFFD4A843);
  ThemeData get churchTheme =>
      buildChurchTheme(brandPrimary, brandSecondary);

  AppState() {
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs       = await SharedPreferences.getInstance();
    _isSetupComplete  = prefs.getBool('setup_complete') ?? false;
    final profileJson = prefs.getString('church_profile');
    if (profileJson != null) {
      _churchProfile = ChurchProfile.fromJson(jsonDecode(profileJson));
      await bibleService.setTranslation(_churchProfile!.bibleTranslationId);
    }

    // Load presentation decks raw JSON into memory cache
    _presentationDecksJson =
        prefs.getString('presentation_decks') ?? '[]';

    _isLoading = false;
    notifyListeners();
  }

  // ── PRESENTATION DECK PERSISTENCE ────────────────────────────────────────
  // Called by PresentationScreen whenever decks change.
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
    final updated = _churchProfile!.copyWith(
        bibleTranslationId: translationId);
    await saveChurchProfile(updated);
  }

  Future<String> saveLogo(String sourcePath) async {
    final dir     = await getApplicationDocumentsDirectory();
    final logoDir = Directory('${dir.path}/church_logos');
    if (!await logoDir.exists()) await logoDir.create(recursive: true);
    final ext  = sourcePath.split('.').last.toLowerCase();
    final dest = File('${logoDir.path}/church_logo.$ext');
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
      await prefs.setString(
          'church_profile', jsonEncode(_churchProfile!.toJson()));
      notifyListeners();
    }
  }

  Future<void> removeApp(String appId) async {
    if (_churchProfile == null) return;
    final updated = List<String>.from(_churchProfile!.installedApps)
      ..remove(appId);
    _churchProfile = _churchProfile!.copyWith(installedApps: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'church_profile', jsonEncode(_churchProfile!.toJson()));
    notifyListeners();
  }

  Future<void> resetSetup() async {
    if (_churchProfile?.logoPath.isNotEmpty == true) {
      try { await File(_churchProfile!.logoPath).delete(); } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _churchProfile           = null;
    _isSetupComplete         = false;
    _presentationDecksJson   = '[]';
    notifyListeners();
  }
}

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