import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../canvass/canvass_shell.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';

/// Shows the screen for where the canvasser is in signing in: the login, a
/// new password on first sign-in (or after an admin reset), then the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final user = auth.currentUser;
        if (user == null || !isAppUser(user)) {
          // Signed out from a screen above the shell, e.g. a revoked login.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          });
          return const LoginScreen();
        }
        if (user.userMetadata?['must_change_password'] == true) {
          return const ChangePasswordScreen();
        }
        // Keyed by login, so another canvasser on this phone gets their own data.
        return CanvassShell(key: ValueKey(user.id), userId: user.id);
      },
    );
  }
}

bool isAppUser(User user) => Config.appRoles.contains(user.appMetadata['role']);
