import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/change_password_screen.dart';
import '../auth/phone.dart';
import '../canvass/format.dart';
import '../data/canvass_service.dart';
import 'account_api.dart';
import 'bank_details_screen.dart';

/// The signed-in person's own details in erims: contact details and bank
/// details they can change, and their name and phone, which only an admin can.
/// Needs internet.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _api = AccountApi(Supabase.instance.client);
  final _form = GlobalKey<FormState>();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  AccountDetails? _account;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _whatsapp.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      _show(await _api.get());
    } catch (e) {
      if (mounted) setState(() => _error = CanvassService.describeError(e));
    }
  }

  void _show(AccountDetails a) {
    if (!mounted) return;
    setState(() => _account = a);
    _whatsapp.text = displayPhone(a.whatsappNumber);
    _email.text = a.email ?? '';
  }

  bool get _contactChanged {
    final a = _account!;
    final email = _email.text.trim().toLowerCase();
    return toE164(_whatsapp.text) != a.whatsappNumber || (email.isEmpty ? null : email) != a.email;
  }

  Future<void> _saveContact() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final whatsapp = toE164(_whatsapp.text);
    final email = _email.text.trim().toLowerCase();
    try {
      _show(await _api.update(
        whatsappNumber: whatsapp,
        email: email.isEmpty ? null : email,
        clear: {if (whatsapp == null) 'whatsapp_number', if (email.isEmpty) 'email'},
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact details saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(CanvassService.describeError(e))));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _changeBank() async {
    final updated = await Navigator.push<AccountDetails>(
      context,
      MaterialPageRoute(builder: (_) => BankDetailsScreen(api: _api)),
    );
    if (updated == null || !mounted) return;
    _show(updated);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bank details saved')));
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    return Scaffold(
      appBar: AppBar(title: const Text('My account')),
      body: a == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 48),
                          const SizedBox(height: 16),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          const Text('You need internet to see or change your account.', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _load, child: const Text('Try again')),
                        ],
                      ),
                    ),
            )
          : _buildDetails(context, a),
    );
  }

  Widget _buildDetails(BuildContext context, AccountDetails a) {
    final theme = Theme.of(context);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text('${a.firstName} ${a.lastName}'),
                  subtitle: const Text('Name'),
                ),
                ListTile(
                  leading: const Icon(Icons.phone),
                  title: Text(displayPhone(a.phone)),
                  subtitle: const Text('Phone number, used to sign in'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'To change your name or phone number, ask an Erims administrator.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Contact details', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'WhatsApp number', prefixIcon: Icon(Icons.chat)),
            validator: (v) =>
                (v ?? '').trim().isEmpty || toE164(v!) != null ? null : 'Enter a phone number, e.g. 0803 123 4567',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
            validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim())
                ? null
                : 'Enter a valid email, or leave it blank',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _contactChanged && !_saving ? _saveContact : null,
              child: Text(_saving ? 'Saving…' : 'Save contact details'),
            ),
          ),
          const SizedBox(height: 20),
          Text('Bank details', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: a.hasBank
                ? Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.verified),
                        title: Text(a.accountName ?? ''),
                        subtitle: Text('${a.bankName} · ${a.accountNumber}'),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: _changeBank, child: const Text('Change bank details')),
                      ),
                    ],
                  )
                : ListTile(
                    leading: const Icon(Icons.account_balance),
                    title: const Text('No bank details yet'),
                    subtitle: const Text('Add the account you are paid into'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _changeBank,
                  ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen(forced: false)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
