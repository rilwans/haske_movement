import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../auth/phone.dart';
import '../data/models.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'visit_form_screen.dart';

/// Someone met who isn't on the polling unit's list. They're added at the
/// polling unit being canvassed; if their VIN is already in erims, the
/// server merges them into that voter.
class AddVoterScreen extends StatefulWidget {
  const AddVoterScreen({super.key, required this.pollingUnitId, this.initialName = ''});

  /// Where they vote: the polling unit being canvassed.
  final String pollingUnitId;

  /// What they searched for before deciding to add.
  final String initialName;

  @override
  State<AddVoterScreen> createState() => _AddVoterScreenState();
}

class _AddVoterScreenState extends State<AddVoterScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    // A search by phone or VIN isn't a name.
    text: RegExp(r'\d').hasMatch(widget.initialName) ? '' : widget.initialName.trim(),
  );
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _vin = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _whatsapp, _vin, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final email = _email.text.trim().toLowerCase();
    final voter = Voter(
      id: const Uuid().v4(),
      name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      pollingUnitId: widget.pollingUnitId,
      phone: toE164(_phone.text),
      whatsappNumber: toE164(_whatsapp.text),
      vin: normalizeVin(_vin.text),
      email: email.isEmpty ? null : email,
      addedLocally: true,
      pending: true,
    );
    await CanvassScope.read(context).addVoter(voter);
    if (!mounted) return;
    // Straight on to the conversation they're having.
    await openScreen(context, VisitFormScreen(voter: voter), replace: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add voter')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofocus: _name.text.isEmpty,
              decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person)),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter their name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone)),
              validator: _optionalPhone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _whatsapp,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'WhatsApp number', prefixIcon: Icon(Icons.chat)),
              validator: _optionalPhone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _vin,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'VIN (on their PVC)',
                prefixIcon: Icon(Icons.badge),
                helperText: 'If they have it. Helps avoid adding the same person twice.',
              ),
              validator: (v) {
                final vin = normalizeVin(v ?? '');
                return vin == null || isValidVin(vin) ? null : 'A VIN is 19 letters and numbers';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
              validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim())
                  ? null
                  : 'Enter a valid email, or leave it blank',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Add and record conversation'),
            ),
          ],
        ),
      ),
    );
  }
}

String? _optionalPhone(String? v) =>
    (v ?? '').trim().isEmpty || toE164(v!) != null ? null : 'Enter a phone number, e.g. 0803 123 4567';
