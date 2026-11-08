import 'dart:io';

import 'package:flutter/foundation.dart';

/// Supabase connection for the Erims project.
///
/// Debug builds default to the local stack (`supabase start` in
/// ~/Projects/erims). Production builds take the server from env/prod.json
/// (see env/README.md):
///
///   flutter build appbundle --dart-define-from-file=env/prod.json
///
/// Only the publishable key belongs in the app, never the secret key.
class Config {
  static const _url = String.fromEnvironment('SUPABASE_URL');

  /// The Android emulator reaches this computer's localhost at 10.0.2.2.
  static String get supabaseUrl {
    if (_url.isNotEmpty) return _url;
    if (kReleaseMode) {
      throw StateError('This build has no server. Build it with --dart-define-from-file=env/prod.json');
    }
    final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
    return 'http://$host:58321';
  }

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );

  /// The roles this app signs in: canvassers, the ward, LGA and state
  /// coordinators who onboard them, and candidates following the campaign.
  static const appRoles = {'Canvasser', 'Coordinator', 'Candidate'};

  /// What erims sets new and reset canvasser logins to, for coordinators to
  /// tell the people they onboard. Must match CANVASSER_DEFAULT_PASSWORD on
  /// erims's canvasser-logins function.
  static const defaultPassword = String.fromEnvironment('DEFAULT_PASSWORD', defaultValue: '@Haske123');
}
