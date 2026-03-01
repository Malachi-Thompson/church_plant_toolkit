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
      // Sync bible service with stored translation preference
      await bibleService.setTranslation(_churchProfile!.bibleTranslationId);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveChurchProfile(ChurchProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    _churchProfile = profile;
    await prefs.setString('church_profile', jsonEncode(profile.toJson()));
    await prefs.setBool('setup_complete', true);
    _isSetupComplete = true;
    // Keep BibleService in sync
    await bibleService.setTranslation(profile.bibleTranslationId);
    notifyListeners();
  }

  /// Updates ONLY the translation preference without changing anything else.
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
    _churchProfile   = null;
    _isSetupComplete = false;
    notifyListeners();
  }
}

ThemeData buildChurchTheme(Color primary, Color secondary) {
  final onPrimary = primary.computeLuminance() > 0.4
      ? Colors.black87 : Colors.white;

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      surface: const Color(0xFFF5F7FA),
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    appBarTheme: AppBarTheme(
      backgroundColor: primary, foregroundColor: onPrimary, elevation: 0),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary, foregroundColor: onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFDDE1EC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFDDE1EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 14),
    ),
    cardTheme: CardThemeData(
      color: Colors.white, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEAEDF3), width: 1),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primary : null),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? primary : Colors.grey.shade300),
      thumbColor: WidgetStateProperty.all(Colors.white),
    ),
  );
}