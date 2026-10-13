import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/canvass_service.dart';
import '../theme.dart';
import 'account_api.dart';

/// Choose a bank and enter an account number; the bank says whose account
/// it is before anything is saved, and erims checks it again when saving.
class BankDetailsScreen extends StatefulWidget {
  const BankDetailsScreen({super.key, required this.api});

  final AccountApi api;

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _number = TextEditingController();
  List<Bank>? _banks;
  String? _banksError;
  Bank? _bank;

  /// The account name for the bank and number entered, once looked up.
  String? _accountName;
  String? _lookupError;
  bool _lookingUp = false;
  bool _saving = false;
  int _lookup = 0;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _loadBanks() async {
    setState(() => _banksError = null);
    try {
      final banks = await widget.api.banks();
      if (mounted) setState(() => _banks = banks);
    } catch (e) {
      if (mounted) setState(() => _banksError = CanvassService.describeError(e));
    }
  }

  Future<void> _pickBank() async {
    final picked = await showModalBottomSheet<Bank>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _BankPicker(banks: _banks!),
    );
    if (picked != null) {
      setState(() => _bank = picked);
      _resolve();
    }
  }

  /// Looks up the name once there's a bank and ten digits; a newer lookup
  /// replaces an older one still on its way.
  Future<void> _resolve() async {
    final bank = _bank;
    final number = _number.text;
    final id = ++_lookup;
    setState(() {
      _accountName = null;
      _lookupError = null;
      _lookingUp = bank != null && number.length == 10;
    });
    if (!_lookingUp) return;
    try {
      final name = await widget.api.resolve(bank!.code, number);
      if (mounted && id == _lookup) setState(() => _accountName = name);
    } catch (e) {
      if (mounted && id == _lookup) setState(() => _lookupError = CanvassService.describeError(e));
    } finally {
      if (mounted && id == _lookup) setState(() => _lookingUp = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await widget.api.update(bank: (bankCode: _bank!.code, accountNumber: _number.text));
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(CanvassService.describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bank details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Where you are paid. Use an account in your own name.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          if (_banksError != null) ...[
            Text(_banksError!, style: TextStyle(color: theme.colorScheme.error)),
            TextButton(onPressed: _loadBanks, child: const Text('Try again')),
          ] else
            InkWell(
              onTap: _banks == null ? null : _pickBank,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Bank',
                  prefixIcon: Icon(Icons.account_balance),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: Text(_banks == null ? 'Loading banks…' : _bank?.name ?? 'Choose your bank'),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            onChanged: (_) => _resolve(),
            decoration: const InputDecoration(
              labelText: 'Account number',
              prefixIcon: Icon(Icons.pin),
              helperText: '10 digits (NUBAN)',
            ),
          ),
          const SizedBox(height: 20),
          if (_lookingUp)
            const Row(children: [
              SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              SizedBox(width: 12),
              Text('Checking with the bank…'),
            ])
          else if (_lookupError != null)
            Text(_lookupError!, style: TextStyle(color: theme.colorScheme.error))
          else if (_accountName != null)
            Card(
              color: HaskeColors.green.withValues(alpha: 0.08),
              child: ListTile(
                leading: const Icon(Icons.verified, color: HaskeColors.green),
                title: Text(_accountName!, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Is this your account?'),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _accountName != null && !_saving ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Yes, save this account'),
          ),
        ],
      ),
    );
  }
}

class _BankPicker extends StatefulWidget {
  const _BankPicker({required this.banks});

  final List<Bank> banks;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final banks = widget.banks.where((b) => q.isEmpty || b.name.toLowerCase().contains(q)).toList();
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
                hintText: 'Search banks',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: banks.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(banks[i].name),
                onTap: () => Navigator.pop(context, banks[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
