import 'package:flutter/material.dart';

import '../data/models.dart';

/// Narrows an LGA coordinator's polling units to one ward. Shows nothing
/// when [units] are all in one ward, as a ward coordinator's are.
class WardFilter extends StatelessWidget {
  const WardFilter({super.key, required this.units, required this.value, required this.onChanged});

  final List<PollingUnit> units;

  /// The chosen ward, or null for all.
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final u in units) {
      counts.update(u.wardName, (n) => n + 1, ifAbsent: () => 1);
    }
    if (counts.length < 2) return const SizedBox.shrink();
    final wards = counts.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Ward',
        prefixIcon: Icon(Icons.filter_list),
        isDense: true,
      ),
      items: [
        DropdownMenuItem(value: null, child: Text('All wards (${units.length} polling units)')),
        for (final w in wards) DropdownMenuItem(value: w, child: Text('$w (${counts[w]})')),
      ],
      onChanged: onChanged,
    );
  }
}

/// [units] in [ward] (all when null) whose code, name or ward contains [search].
List<PollingUnit> filterPollingUnits(List<PollingUnit> units, {String? ward, String search = ''}) {
  final q = search.trim().toLowerCase();
  return units
      .where((u) => ward == null || u.wardName == ward)
      .where((u) => q.isEmpty || '${u.code} ${u.name} ${u.wardName}'.toLowerCase().contains(q))
      .toList();
}

/// A bottom sheet to choose one of [units], searchable and by ward.
class PollingUnitPicker extends StatefulWidget {
  const PollingUnitPicker({super.key, required this.units});

  final List<PollingUnit> units;

  @override
  State<PollingUnitPicker> createState() => _PollingUnitPickerState();
}

class _PollingUnitPickerState extends State<PollingUnitPicker> {
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

/// A bottom sheet to choose one of [wards].
class WardPicker extends StatefulWidget {
  const WardPicker({super.key, required this.wards});

  final List<Ward> wards;

  @override
  State<WardPicker> createState() => _WardPickerState();
}

class _WardPickerState extends State<WardPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final wards = widget.wards.where((w) => q.isEmpty || w.name.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: 'Search wards',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          if (widget.wards.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Sync once with internet to load the wards in your LGA.', textAlign: TextAlign.center),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: wards.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(wards[i].name),
                subtitle: Text('${wards[i].pollingUnits} polling units'),
                onTap: () => Navigator.pop(context, wards[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
