// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/app_state.dart';
import 'services/bible_service.dart';
import 'screens/setup_screen.dart';
import 'screens/dashboard_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const ChurchPlantToolkit(),
    ),
  );
}

class ChurchPlantToolkit extends StatelessWidget {
  const ChurchPlantToolkit({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Expose BibleService (owned by AppState) as its own provider so any
    // widget can read it with context.watch<BibleService>()
    return ChangeNotifierProvider<BibleService>.value(
      value: state.bibleService,
      child: MaterialApp(
        title: 'Church Plant Toolkit',
        debugShowCheckedModeBanner: false,
        theme: state.isLoading
            ? buildChurchTheme(primaryColor, accentColor)
            : state.churchTheme,
        home: const AppRouter(),
      ),
    );
  }
}

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              const Text('Loading Church Plant Toolkit…',
                  style: TextStyle(color: textMid, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return state.isSetupComplete
        ? const DashboardScreen()
        : const SetupScreen();
  }
}