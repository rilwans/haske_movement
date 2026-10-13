import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';
import 'phone.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      final res = await auth.signInWithPassword(
        phone: toE164(_phone.text)!,
        password: _password.text,
      );
      // Erims staff can't use this app, and its users can't use Erims.
      if (res.user != null && !isAppUser(res.user!)) {
        await auth.signOut();
        _error = 'This app is for canvassers and coordinators only.';
      }
    } on AuthException catch (e) {
      _error = e.code == 'invalid_credentials'
          ? 'Wrong phone number or password.'
          : e.message;
    } catch (_) {
      _error = "Can't reach the server. Check your internet connection.";
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/images/logo.png', height: 220),
                    const SizedBox(height: 16),
                    Text(
                      'Sign in',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        hintText: '0803 123 4567',
                        prefixIcon: Icon(Icons.phone),
                      ),
                      validator: (v) => toE164(v ?? '') == null
                          ? 'Enter your phone number, e.g. 0803 123 4567'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _busy ? null : _signIn(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: (v) =>
                          (v ?? '').isEmpty ? 'Enter your password' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Forgot your password? Ask an Erims administrator to reset it.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
