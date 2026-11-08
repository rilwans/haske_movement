import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../auth/phone.dart';
import '../config.dart';
import '../data/models.dart';
import 'canvass_shell.dart';
import 'lga_choice.dart';
import 'ward_filter.dart';

enum _Adding { canvasser, wardCoordinator, lgaCoordinator }

/// A coordinator adds a canvasser at a polling unit in their area, an LGA or
/// state coordinator a ward coordinator for a ward in theirs, or a state
/// coordinator an LGA coordinator for an LGA in theirs. Saved on the phone;
/// erims makes the person and their login when it's sent, and records this
/// coordinator as who onboarded them.
class OnboardCanvasserScreen extends StatefulWidget {
  const OnboardCanvasserScreen({super.key}) : _adding = _Adding.canvasser;

  const OnboardCanvasserScreen.wardCoordinator({super.key}) : _adding = _Adding.wardCoordinator;

  const OnboardCanvasserScreen.lgaCoordinator({super.key}) : _adding = _Adding.lgaCoordinator;

  final _Adding _adding;

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
  Ward? _ward;
  Lga? _lga;
  bool _saving = false;

  bool get _forWard => widget._adding == _Adding.wardCoordinator;
  bool get _forLga => widget._adding == _Adding.lgaCoordinator;

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
      builder: (context) => PollingUnitPicker(units: units),
    );
    if (picked != null) setState(() => _pollingUnit = picked);
  }

  Future<void> _pickWard() async {
    final wards = CanvassScope.read(context).profile!.wards;
    final picked = await showModalBottomSheet<Ward>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => WardPicker(wards: wards),
    );
    if (picked != null) setState(() => _ward = picked);
  }

  Future<void> _pickLga() async {
    final lgas = CanvassScope.read(context).profile!.lgas;
    final picked = await showModalBottomSheet<(Lga?,)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => LgaPicker(lgas: lgas),
    );
    if (picked != null) setState(() => _lga = picked.$1);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final service = CanvassScope.read(context);
    final phone = toE164(_phone.text)!;
    if (await service.db.hasOnboardedPhone(phone)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already onboarded someone with this phone number.')),
      );
      return;
    }
    setState(() => _saving = true);
    final email = _email.text.trim().toLowerCase();
    if (_forLga) {
      await service.addLgaCoordinator(NewLgaCoordinator(
        id: const Uuid().v4(),
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: phone,
        whatsappNumber: toE164(_whatsapp.text),
        email: email.isEmpty ? null : email,
        lgaId: _lga!.id,
        lgaName: _lga!.name,
        createdAt: DateTime.now(),
      ));
    } else if (_forWard) {
      await service.addWardCoordinator(NewWardCoordinator(
        id: const Uuid().v4(),
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: phone,
        whatsappNumber: toE164(_whatsapp.text),
        email: email.isEmpty ? null : email,
        wardId: _ward!.id,
        wardName: _ward!.name,
        createdAt: DateTime.now(),
      ));
    } else {
      await service.addCanvasser(NewCanvasser(
        id: const Uuid().v4(),
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: phone,
        whatsappNumber: toE164(_whatsapp.text),
        email: email.isEmpty ? null : email,
        pollingUnitId: _pollingUnit!.id,
        pollingUnitName: _pollingUnit!.name,
        createdAt: DateTime.now(),
      ));
    }
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
      appBar: AppBar(title: Text(_forLga ? 'Add LGA coordinator' : _forWard ? 'Add ward coordinator' : 'Onboard canvasser')),
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
            if (_forLga)
              FormField<Lga>(
                validator: (_) => _lga == null ? 'Choose the LGA they will coordinate' : null,
                builder: (field) => InkWell(
                  onTap: () async {
                    await _pickLga();
                    field.didChange(_lga);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'LGA',
                      prefixIcon: const Icon(Icons.map_outlined),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      errorText: field.errorText,
                    ),
                    child: Text(_lga == null ? 'Choose' : _lga!.name),
                  ),
                ),
              )
            else if (_forWard)
              FormField<Ward>(
                validator: (_) => _ward == null ? 'Choose the ward they will coordinate' : null,
                builder: (field) => InkWell(
                  onTap: () async {
                    await _pickWard();
                    field.didChange(_ward);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Ward',
                      prefixIcon: const Icon(Icons.map_outlined),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      errorText: field.errorText,
                    ),
                    child: Text(_ward == null ? 'Choose' : _ward!.name),
                  ),
                ),
              )
            else
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
              'their phone number and the password ${Config.defaultPassword}, and choose their own.'
              '${_forLga ? ' They can then add ward coordinators and canvassers in their LGA.' : _forWard ? ' They can then onboard canvassers in their ward.' : ''}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
