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
