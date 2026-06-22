import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'auth/auth_gate.dart';
import 'theme/trucost_theme.dart';

/// Goes in: lib/main.dart

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const TruCostApp());
}

class TruCostApp extends StatelessWidget {
  const TruCostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruCost',
      debugShowCheckedModeBanner: false,
      theme: TruCostTheme.theme(TruCostThemeId.green),
      home: const AuthGate(),
    );
  }
}
