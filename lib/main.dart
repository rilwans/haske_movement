import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'config.dart';
import 'splash/splash_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Starts while the splash animation plays; the app shows once both are done.
  // In a future, so a build with no server shows why on the splash.
  final ready = Future(() => Supabase.initialize(
        url: Config.supabaseUrl,
        publishableKey: Config.supabasePublishableKey,
      ));
  runApp(HaskeApp(ready: ready));
}

class HaskeApp extends StatelessWidget {
  const HaskeApp({super.key, required this.ready});

  final Future<void> ready;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haske Movement',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: SplashGate(ready: ready, child: const AuthGate()),
    );
  }
}
