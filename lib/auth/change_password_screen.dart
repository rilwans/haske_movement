import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// New logins and admin resets come with the default password and
/// must_change_password set, so the person picks their own first ([forced]).
/// Also opened from My account to change it any time.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = true});

  final bool forced;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  /// Matches minimum_password_length in Erims's Supabase config.
  static const _minLength = 8;

  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The gate moves on to the app once must_change_password is cleared.
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          password: _password.text,
          data: {'must_change_password': false},
        ),
      );
      if (!widget.forced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed')));
        Navigator.pop(context);
        return;
      }
    } on AuthException catch (e) {
      _error = e.code == 'same_password'
          ? 'Choose a password different from your current one.'
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
      appBar: AppBar(
        title: Text(widget.forced ? 'Set your password' : 'Change password'),
        actions: [
          if (widget.forced)
            TextButton(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              child: const Text('Sign out'),
            ),
        ],
      ),
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
                    Text(
                      widget.forced
                          ? 'You signed in with the password you were given. '
                              'Choose your own before you continue.'
                          : 'Choose a new password. You need internet for this.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        helperText: 'At least $_minLength characters',
                      ),
                      validator: (v) => (v ?? '').length < _minLength
                          ? 'Use at least $_minLength characters'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _busy ? null : _save(),
                      decoration: const InputDecoration(labelText: 'Confirm new password'),
                      validator: (v) =>
                          v != _password.text ? "Passwords don't match" : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Text('Save password'),
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
