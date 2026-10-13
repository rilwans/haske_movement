import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../auth/phone.dart';
import '../config.dart';
import '../data/models.dart';
import 'canvass_shell.dart';
import 'ward_filter.dart';

/// A coordinator adds a canvasser at a polling unit in their area. Saved on
/// the phone; erims makes the canvasser and their login when it's sent, and
/// records this coordinator as who onboarded them.
class OnboardCanvasserScreen extends StatefulWidget {
  const OnboardCanvasserScreen({super.key});

  @override
  State<OnboardCanvasserScreen> createState() => _OnboardCanvasserScreenState();
}

class _OnboardCanvasserScreenState extends State<OnboardCanvasserScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  PollingUnit? _pollingUnit;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _phone, _whatsapp, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPollingUnit() async {
    final units = CanvassScope.read(context).profile!.pollingUnits;
    final picked = await showModalBottomSheet<PollingUnit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PollingUnitPicker(units: units),
    );
    if (picked != null) setState(() => _pollingUnit = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final service = CanvassScope.read(context);
    final phone = toE164(_phone.text)!;
    if (await service.db.hasCanvasserPhone(phone)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already onboarded someone with this phone number.')),
      );
      return;
    }
    setState(() => _saving = true);
    final email = _email.text.trim().toLowerCase();
    await service.addCanvasser(NewCanvasser(
      id: const Uuid().v4(),
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      phone: phone,
      whatsappNumber: toE164(_whatsapp.text),
      email: email.isEmpty ? null : email,
      pollingUnitId: _pollingUnit!.id,
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_firstName.text.trim()} saved. They can sign in once it has been sent.'),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Onboard canvasser')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _firstName,
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'First name'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter their first name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Last name'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter their last name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                prefixIcon: Icon(Icons.phone),
                helperText: 'They sign in with this number',
              ),
              validator: (v) => toE164(v ?? '') == null ? 'Enter their phone number, e.g. 0803 123 4567' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _whatsapp,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'WhatsApp number (if different)', prefixIcon: Icon(Icons.chat)),
              validator: (v) =>
                  (v ?? '').trim().isEmpty || toE164(v!) != null ? null : 'Enter a phone number, e.g. 0803 123 4567',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)', prefixIcon: Icon(Icons.email)),
              validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim())
                  ? null
                  : 'Enter a valid email, or leave it blank',
            ),
            const SizedBox(height: 12),
            FormField<PollingUnit>(
              validator: (_) => _pollingUnit == null ? 'Choose where they will canvass' : null,
              builder: (field) => InkWell(
                onTap: () async {
                  await _pickPollingUnit();
                  field.didChange(_pollingUnit);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Polling unit',
                    prefixIcon: const Icon(Icons.place),
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                    errorText: field.errorText,
                  ),
                  child: Text(_pollingUnit == null ? 'Choose' : '${_pollingUnit!.name} (${_pollingUnit!.code})'),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
            const SizedBox(height: 8),
            Text(
              'Saved on this phone and sent when you have internet. They then sign in with '
              'their phone number and the password ${Config.defaultPassword}, and choose their own.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PollingUnitPicker extends StatefulWidget {
  const _PollingUnitPicker({required this.units});

  final List<PollingUnit> units;

  @override
  State<_PollingUnitPicker> createState() => _PollingUnitPickerState();
}

class _PollingUnitPickerState extends State<_PollingUnitPicker> {
  String _q = '';
  String? _ward;

  @override
  Widget build(BuildContext context) {
    final units = filterPollingUnits(widget.units, ward: _ward, search: _q);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: 'Search polling units',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: WardFilter(
              units: widget.units,
              value: _ward,
              onChanged: (w) => setState(() => _ward = w),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: units.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(units[i].name),
                subtitle: Text('${units[i].code} · ${units[i].wardName}'),
                onTap: () => Navigator.pop(context, units[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
