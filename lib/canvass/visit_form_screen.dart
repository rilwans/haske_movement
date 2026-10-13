import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../auth/phone.dart';
import '../data/location.dart';
import '../data/models.dart';
import 'canvass_shell.dart';
import 'format.dart';

/// What the voter said in one conversation. Saved on the phone and sent
/// when there's internet.
class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({super.key, required this.voter});

  final Voter voter;

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: displayPhone(widget.voter.phone));
  late final _whatsapp = TextEditingController(text: displayPhone(widget.voter.whatsappNumber));
  late final _vin = TextEditingController(text: widget.voter.vin ?? '');
  final _notes = TextEditingController();
  String? _support;
  String? _pvcStatus;
  String? _plansToVote;
  final _issues = <String>{};
  bool _saving = false;

  /// Started on opening, so it's usually ready by the time they save.
  late final Future<Position?> _position = currentPosition();

  @override
  void dispose() {
    for (final c in [_phone, _whatsapp, _vin, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_support == null && _pvcStatus == null && _plansToVote == null && _issues.isEmpty && _notes.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record at least one answer or a note.')),
      );
      return;
    }
    setState(() => _saving = true);
    final service = CanvassScope.read(context);
    // Don't hold the canvasser at the door for GPS.
    final pos = await _position.timeout(const Duration(seconds: 3), onTimeout: () => null);
    final notes = _notes.text.trim();
    await service.recordVisit(Visit(
      id: const Uuid().v4(),
      voterId: widget.voter.id,
      visitedAt: DateTime.now(),
      support: _support,
      pvcStatus: _pvcStatus,
      plansToVote: _plansToVote,
      issues: Options.issues.keys.where(_issues.contains).toList(),
      notes: notes.isEmpty ? null : notes,
      reportedPhone: toE164(_phone.text),
      reportedWhatsapp: toE164(_whatsapp.text),
      reportedVin: normalizeVin(_vin.text),
      latitude: pos?.latitude,
      longitude: pos?.longitude,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved conversation with ${widget.voter.name}')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.voter.name)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _Section('Do they support Kollo Baba Jiya?'),
            _Choices(options: Options.support, value: _support, onChanged: (v) => setState(() => _support = v)),
            _Section('PVC'),
            _Choices(options: Options.pvcStatus, value: _pvcStatus, onChanged: (v) => setState(() => _pvcStatus = v)),
            _Section('Do they plan to vote?'),
            _Choices(options: Options.plansToVote, value: _plansToVote, onChanged: (v) => setState(() => _plansToVote = v)),
            _Section('What matters most to them?'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in Options.issues.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: _issues.contains(e.key),
                    onSelected: (on) => setState(() => on ? _issues.add(e.key) : _issues.remove(e.key)),
                  ),
              ],
            ),
            _Section('Contact details'),
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
                helperText: '19 letters and numbers',
              ),
              validator: (v) {
                final vin = normalizeVin(v ?? '');
                return vin == null || isValidVin(vin) ? null : 'A VIN is 19 letters and numbers';
              },
            ),
            _Section('Notes'),
            TextFormField(
              controller: _notes,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Anything else they said'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
            const SizedBox(height: 8),
            Text(
              'Saved on this phone, and sent when you have internet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String? _optionalPhone(String? v) =>
    (v ?? '').trim().isEmpty || toE164(v!) != null ? null : 'Enter a phone number, e.g. 0803 123 4567';

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// One answer from [options], or none; tapping the chosen one clears it.
class _Choices extends StatelessWidget {
  const _Choices({required this.options, required this.value, required this.onChanged});

  final Map<String, String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final e in options.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: value == e.key,
              onSelected: (on) => onChanged(on ? e.key : null),
            ),
        ],
      );
}
