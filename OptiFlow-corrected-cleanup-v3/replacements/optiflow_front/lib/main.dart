import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mobile/core/app_theme.dart';
import 'mobile/core/auth_service.dart';
import 'mobile/screens/login_screen.dart';
import 'mobile/screens/main_hub.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY. Pass them with --dart-define.',
    );
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const OptiFlowApp());
}

class OptiFlowApp extends StatelessWidget {
  const OptiFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OptiFlow',
      theme: AppTheme.theme,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF141518),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5E6AD2),
          secondary: Color(0xFF8B75D7),
          surface: Color(0xFF1A1B1E),
        ),
      ),
      themeMode: ThemeMode.dark,
      home: AuthService.instance.isAuthenticated
          ? const MainHub()
          : const LoginScreen(),
    );
  }
}
