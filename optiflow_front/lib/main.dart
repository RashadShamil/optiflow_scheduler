import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mobile/core/app_theme.dart';
import 'mobile/core/auth_service.dart';
import 'mobile/screens/login_screen.dart';
import 'mobile/screens/main_hub.dart';
import 'slices/engine/dashboard/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY. '
      'Pass them with --dart-define or --dart-define-from-file=.env',
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const OptiFlowApp());
}

/// Returns true when OptiFlow is running as a desktop application.
///
/// Desktop:
///   Windows / Linux / macOS
///
/// Mobile:
///   Android / iOS
bool get isDesktopPlatform {
  if (kIsWeb) {
    return false;
  }

  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// Decides which part of OptiFlow an already authenticated user should enter.
///
/// Desktop is the print-shop manager control centre.
/// Mobile uses MainHub, which handles the WORKER / EXTERNAL role-based screens.
Widget getAuthenticatedHome() {
  if (isDesktopPlatform) {
    return const DashboardScreen();
  }

  return const MainHub();
}

class OptiFlowApp extends StatelessWidget {
  const OptiFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OptiFlow',

      // Mobile theme.
      theme: AppTheme.theme,

      // Desktop manager interface mainly uses the dark theme.
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF141518),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5E6AD2),
          secondary: Color(0xFF8B75D7),
          surface: Color(0xFF1A1B1E),
        ),
      ),

      themeMode: ThemeMode.dark,

      // If the user already has a Supabase session:
      //
      // Windows/Linux/macOS -> Manager desktop dashboard
      // Android/iOS         -> Role-based mobile app
      //
      // Otherwise show the login screen.
      home: AuthService.instance.isAuthenticated
          ? getAuthenticatedHome()
          : const LoginScreen(),
    );
  }
}