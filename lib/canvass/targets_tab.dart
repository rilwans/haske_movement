import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import '../theme.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'panels.dart';

/// Status colours, always with an icon and a label.
const _good = Color(0xFF0CA30C);
const _warning = Color(0xFFFAB219);
const _critical = Color(0xFFD03B3B);

/// Each ward's canvassing against its target: how far along, whether it's on
/// pace, and when it'll get there at the recent rate. LGA and state
/// coordinators set their wards' targets; a ward coordinator sees theirs.
/// Needs internet; the last figures show offline.
class TargetsTab extends StatefulWidget {
  const TargetsTab({super.key});

  @override
  State<TargetsTab> createState() => _TargetsTabState();
}

class _TargetsTabState extends State<TargetsTab> {
  WardTargets? _targets;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = CanvassScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    final cached = await s.db.cached(CanvassService.targetsKey(s.profile?.selectedLgaId));
    if (!mounted) return;
    if (_targets == null && cached != null) setState(() => _targets = WardTargets.fromJson(cached));
    try {
      final fresh = await s.fetchTargets();
      if (mounted) setState(() => _targets = fresh);
    } catch (e) {
      if (mounted) setState(() => _error = CanvassService.describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(WardProgress w) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CanvassScope(service: CanvassScope.read(context), child: _TargetSheet(ward: w)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _targets;
    final today = DateTime.now();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SizedBox(height: 4, child: _loading ? const LinearProgressIndicator() : null),
          if (_error != null && t == null)
            Notice(
              icon: Icons.error_outline,
              color: HaskeColors.red,
              title: "Couldn't load the targets",
              text: _error!,
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          else if (_error != null)
            Notice(
              icon: Icons.cloud_off,
              color: Colors.grey.shade700,
              title: 'Showing progress from ${timeAgo(t!.fetchedAt)}',
              text: _error!,
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          else if (t == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Loading the targets…', textAlign: TextAlign.center),
            ),
          if (t != null) ...[
            if (t.wards.length > 1) _Overview(targets: t, today: today),
            for (final w in t.wards)
              _WardCard(ward: w, today: today, onEdit: t.canSet && _error == null ? () => _edit(w) : null),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "Canvassed means visited at least once, by anyone. A ward is on pace if it's canvassed as many "
                "voters as it would going evenly from when its target was set to its date. The projected date "
                "assumes the last ${t.recentDays} days' rate of newly canvassed voters carries on.",
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How the LGA's wards stand, counted by status.
class _Overview extends StatelessWidget {
  const _Overview({required this.targets, required this.today});

  final WardTargets targets;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final wards = targets.wards;
    final voters = wards.fold<int>(0, (n, w) => n + w.voters);
    final canvassed = wards.fold<int>(0, (n, w) => n + w.canvassed);
    final by = <TargetStatus, int>{};
    for (final w in wards) {
      by.update(w.statusOn(today), (n) => n + 1, ifAbsent: () => 1);
    }
    return Panel(
      title: '${percent(canvassed, voters) ?? 0}% of the LGA canvassed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatCount(canvassed)} of ${formatCount(voters)} voters on the list, across ${wards.length} wards.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final s in [
                TargetStatus.behind,
                TargetStatus.missed,
                TargetStatus.onPace,
                TargetStatus.done,
                TargetStatus.none,
              ])
                if ((by[s] ?? 0) > 0) _StatusLabel(status: s, count: by[s]),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status, this.count});

  final TargetStatus status;
  final int? count;

  @override
  Widget build(BuildContext context) {
    // The label alone on a ward; after a count of wards in the overview.
    final (IconData icon, Color color, String label, String counted) = switch (status) {
      TargetStatus.done => (Icons.check_circle, _good, 'Reached', 'reached'),
      TargetStatus.onPace => (Icons.trending_up, _good, 'On pace', 'on pace'),
      TargetStatus.behind => (Icons.warning_amber_rounded, _warning, 'Behind', 'behind'),
      TargetStatus.missed => (Icons.error_outline, _critical, 'Missed', 'missed'),
      TargetStatus.none => (Icons.flag_outlined, Colors.grey.shade600, 'No target', 'without a target'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(count == null ? label : '$count $counted'),
      ],
    );
  }
}

class _WardCard extends StatelessWidget {
  const _WardCard({required this.ward, required this.today, this.onEdit});

  final WardProgress ward;
  final DateTime today;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final w = ward;
    final t = w.target;
    final theme = Theme.of(context);
    final status = w.statusOn(today);
    final share = percent(w.canvassed, w.voters) ?? 0;
    final expected = w.expectedBy(today);
    final projected = w.projectedOn(today);
    final lines = <String>[
      '$share% canvassed · ${formatCount(w.canvassed)} of ${formatCount(w.voters)} voters',
      if (t != null) 'Target ${t.percent}% by ${shortDate(t.dueOn)} · ${formatCount(w.targetCount!)} voters',
      if (status == TargetStatus.onPace || status == TargetStatus.behind)
        'Expected by today: ${percent(expected!, w.voters) ?? 0}% (${formatCount(expected)})',
      if (status == TargetStatus.onPace || status == TargetStatus.behind || status == TargetStatus.missed)
        projected == null
            ? 'Nobody new canvassed in the last ${w.recentDays} days'
            : 'At the recent pace: ${shortDate(projected)}',
      if (status == TargetStatus.none) 'No target set',
    ];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(w.name, style: theme.textTheme.titleMedium)),
                  _StatusLabel(status: status),
                  if (onEdit != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined, size: 18, color: theme.colorScheme.primary),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              _ProgressBar(value: w.voters == 0 ? 0 : w.canvassed / w.voters, target: t == null ? null : t.percent / 100),
              const SizedBox(height: 8),
              for (final l in lines) Text(l, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// How much of the ward is canvassed, with a mark at the target.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, this.target});

  final double value;
  final double? target;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: 16,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
            ),
            Container(
              height: 10,
              width: box.maxWidth * value.clamp(0, 1),
              decoration: BoxDecoration(color: HaskeColors.green, borderRadius: BorderRadius.circular(4)),
            ),
            if (target != null)
              Positioned(
                left: (box.maxWidth * target!.clamp(0, 1) - 1).clamp(0, box.maxWidth - 2),
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: scheme.onSurface),
              ),
          ],
        ),
      ),
    );
  }
}

/// An LGA coordinator sets a ward's target, changes it (counted from today),
/// or removes it.
class _TargetSheet extends StatefulWidget {
  const _TargetSheet({required this.ward});

  final WardProgress ward;

  @override
  State<_TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends State<_TargetSheet> {
  late double _percent = (widget.ward.target?.percent ?? _suggested).toDouble();
  late DateTime? _dueOn = widget.ward.target?.dueOn;
  bool _saving = false;
  String? _error;

  /// Ten points above where the ward is now, in steps of five.
  int get _suggested {
    final now = percent(widget.ward.canvassed, widget.ward.voters) ?? 0;
    return (((now + 10) / 5).ceil() * 5).clamp(5, 100);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueOn ?? now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _dueOn = picked);
  }

  Future<void> _save({bool remove = false}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await CanvassScope.read(context).setWardTarget(
        widget.ward.id,
        percent: remove ? null : _percent.round(),
        dueOn: remove ? null : _dueOn,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = CanvassService.describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.ward;
    final theme = Theme.of(context);
    final goal = (w.voters * _percent / 100).ceil();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Target for ${w.name}', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Now ${percent(w.canvassed, w.voters) ?? 0}% canvassed: ${formatCount(w.canvassed)} of '
            '${formatCount(w.voters)} voters.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('Canvass ${_percent.round()}% of voters (${formatCount(goal)})', style: theme.textTheme.titleSmall),
          Slider(
            value: _percent,
            min: 5,
            max: 100,
            divisions: 19,
            label: '${_percent.round()}%',
            onChanged: _saving ? null : (v) => setState(() => _percent = v),
          ),
          InkWell(
            onTap: _saving ? null : _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'By',
                prefixIcon: Icon(Icons.event),
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              child: Text(_dueOn == null ? 'Choose a date' : shortDate(_dueOn!)),
            ),
          ),
          if (w.target != null) ...[
            const SizedBox(height: 8),
            Text(
              'Saving counts the pace from today.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: HaskeColors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving || _dueOn == null ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save target'),
          ),
          if (w.target != null)
            TextButton(
              onPressed: _saving ? null : () => _save(remove: true),
              child: const Text('Remove target'),
            ),
        ],
      ),
    );
  }
}
