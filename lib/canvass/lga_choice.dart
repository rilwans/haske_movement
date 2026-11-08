import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import 'canvass_shell.dart';
import 'format.dart';

/// Moves a state coordinator to [lga], or the whole state when null, saying
/// so if it can't. Returns whether it worked.
Future<bool> chooseLga(BuildContext context, Lga? lga) async {
  final s = CanvassScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await s.chooseLga(lga);
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text("Couldn't open ${lga?.name ?? 'the state'}. ${CanvassService.describeError(e)}")),
    );
    return false;
  }
}

/// Which LGA a state coordinator is working in, on every tab of their home.
class LgaBar extends StatefulWidget {
  const LgaBar({super.key});

  @override
  State<LgaBar> createState() => _LgaBarState();
}

class _LgaBarState extends State<LgaBar> {
  bool _busy = false;

  Future<void> _pick() async {
    final p = CanvassScope.read(context).profile!;
    final picked = await showModalBottomSheet<(Lga?,)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => LgaPicker(lgas: p.lgas, allLabel: p.allLgasLabel),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    await chooseLga(context, picked.$1);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = CanvassScope.of(context).profile!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        onTap: _busy ? null : _pick,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'LGA',
            isDense: true,
            prefixIcon: const Icon(Icons.map_outlined),
            suffixIcon: _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : const Icon(Icons.arrow_drop_down),
          ),
          child: Text(p.lgaName ?? 'All LGAs', overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Shown on the tabs that work one LGA at a time, until a state coordinator
/// has chosen one.
class ChooseLga extends StatefulWidget {
  const ChooseLga({super.key, required this.reason});

  final String reason;

  @override
  State<ChooseLga> createState() => _ChooseLgaState();
}

class _ChooseLgaState extends State<ChooseLga> {
  String? _opening;

  Future<void> _open(Lga lga) async {
    setState(() => _opening = lga.id);
    await chooseLga(context, lga);
    if (mounted) setState(() => _opening = null);
  }

  @override
  Widget build(BuildContext context) {
    final lgas = CanvassScope.of(context).profile!.lgas;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: lgas.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(widget.reason, style: Theme.of(context).textTheme.bodyMedium),
          );
        }
        final lga = lgas[i - 1];
        return ListTile(
          title: Text(lga.name),
          subtitle: Text(lgaCounts(lga)),
          trailing: _opening == lga.id
              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Icon(Icons.chevron_right),
          onTap: _opening == null ? () => _open(lga) : null,
        );
      },
    );
  }
}

/// "12 wards · 240 polling units".
String lgaCounts(Lga lga) =>
    '${formatCount(lga.wards)} ${lga.wards == 1 ? 'ward' : 'wards'} · '
    '${formatCount(lga.pollingUnits)} ${lga.pollingUnits == 1 ? 'polling unit' : 'polling units'}';

/// A bottom sheet to choose one of [lgas], or with [allLabel] the whole
/// state. Pops the choice in a record, so that the whole state (null) isn't
/// taken for the sheet being dismissed.
class LgaPicker extends StatefulWidget {
  const LgaPicker({super.key, required this.lgas, this.allLabel});

  final List<Lga> lgas;
  final String? allLabel;

  @override
  State<LgaPicker> createState() => _LgaPickerState();
}

class _LgaPickerState extends State<LgaPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final lgas = widget.lgas.where((l) => q.isEmpty || l.name.toLowerCase().contains(q)).toList();
    final all = widget.allLabel;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: 'Search LGAs',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (all != null && q.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: Text(all),
                    onTap: () => Navigator.pop(context, (null as Lga?,)),
                  ),
                for (final l in lgas)
                  ListTile(
                    title: Text(l.name),
                    subtitle: Text(lgaCounts(l)),
                    onTap: () => Navigator.pop(context, (l as Lga?,)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
