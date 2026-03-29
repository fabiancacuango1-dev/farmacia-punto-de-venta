import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'platform/desktop_init.dart'
    if (dart.library.js_interop) 'platform/web_init.dart';
import 'core/theme/app_theme.dart';
import 'presentation/navigation/app_router.dart';
import 'data/database/app_database.dart';
import 'services/auth/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize locale data for Spanish date formatting
  await initializeDateFormatting('es');

  // Allow Google Fonts to fallback gracefully when offline
  GoogleFonts.config.allowRuntimeFetching = true;

  // Platform-specific initialization (desktop window config)
  await platformInit();

  // Initialize database
  final database = AppDatabase();

  // Initialize auth service
  final authService = AuthService(database);

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(authService),
      ],
      child: const FarmaPosApp(),
    ),
  );
}

class FarmaPosApp extends ConsumerWidget {
  const FarmaPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'FarmaPos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
