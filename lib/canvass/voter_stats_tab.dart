import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import '../theme.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'lga_choice.dart';
import 'panels.dart';
import 'voter_list_screen.dart';
import 'ward_filter.dart';

/// Men and women in the charts, as on erims's voter dashboard.
const _menColor = Color(0xFF2A78D6);
const _womenColor = Color(0xFFEB6834);
const _unknownColor = Color(0xFFB4B2AA);

/// Canvassed voters with fewer than this aren't compared for support.
const _minCanvassed = 10;

const _ageBands = {
  '18_24': '18–24',
  '25_34': '25–34',
  '35_44': '35–44',
  '45_54': '45–54',
  '55_64': '55–64',
  '65_plus': '65+',
  'unknown': 'Not recorded',
};

/// A coordinator's voter figures, as erims's voter dashboard shows them:
/// their state, LGA or ward, narrowed to an LGA, ward or polling unit. Needs
/// internet; the last figures fetched for each area show offline.
class VoterStatsTab extends StatefulWidget {
  const VoterStatsTab({super.key});

  @override
  State<VoterStatsTab> createState() => _VoterStatsTabState();
}

class _VoterStatsTabState extends State<VoterStatsTab> {
  /// Chosen by an LGA or state coordinator; a ward coordinator's is always theirs.
  String? _wardId;
  String? _pollingUnitId;
  VoterStats? _stats;
  bool _loading = false;
  String? _error;
  _Sort _sort = _Sort.voters;

  /// A polling unit being downloaded to open its voter lists.
  String? _opening;

  /// Answers to a load that's been overtaken by another are dropped.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = CanvassScope.read(context);
    final ward = _wardId, unit = _pollingUnitId, request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    final cached = await s.db.stats(ward, unit, lgaId: s.profile?.selectedLgaId);
    if (!mounted || request != _request) return;
    setState(() => _stats = cached);
    try {
      final fresh = await s.fetchStats(wardId: ward, pollingUnitId: unit);
      if (!mounted || request != _request) return;
      setState(() => _stats = fresh);
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _error = CanvassService.describeError(e));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _setArea({required String? ward, required String? unit}) {
    if (ward == _wardId && unit == _pollingUnitId) return;
    _wardId = ward;
    _pollingUnitId = unit;
    _load();
  }

  Future<void> _pickPollingUnit() async {
    final p = CanvassScope.read(context).profile!;
    final units = p.pollingUnits.where((u) => _wardId == null || u.wardId == _wardId).toList();
    final picked = await showModalBottomSheet<PollingUnit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => PollingUnitPicker(units: units),
    );
    if (picked != null) _choosePollingUnit(picked.id);
  }

  void _choosePollingUnit(String id) {
    final p = CanvassScope.read(context).profile!;
    _setArea(ward: p.coversWards ? (p.pollingUnit(id)?.wardId ?? _wardId) : null, unit: id);
  }

  /// Looks into an area of the table, one level down.
  void _open(AreaStats a) {
    if (_stats?.level == 'lga') {
      final lga = CanvassScope.read(context).profile!.lga(a.id);
      if (lga != null) chooseLga(context, lga);
    } else if (_stats?.level == 'ward') {
      _setArea(ward: a.id, unit: null);
    } else if (_pollingUnitId == null) {
      _choosePollingUnit(a.id);
    }
  }

  /// A polling unit's voters on [lead], downloaded first if they aren't on
  /// the phone, which needs internet.
  Future<void> _openList(String pollingUnitId, Lead lead) async {
    final s = CanvassScope.read(context);
    final pu = s.profile!.pollingUnit(pollingUnitId);
    if (pu == null || _opening != null) return;
    if (!s.downloaded.contains(pu.id)) {
      setState(() => _opening = pu.id);
      try {
        await s.downloadPollingUnit(pu.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Couldn't download ${pu.name}. ${CanvassService.describeError(e)}")));
        }
        return;
      } finally {
        if (mounted) setState(() => _opening = null);
      }
      if (!mounted) return;
    }
    await openScreen(context, VoterListScreen(pollingUnit: pu, lead: lead));
  }

  /// A "Where to focus" card: a ward opens a level down; a polling unit its
  /// voters on the matching list.
  void _openFocus(_Focus f) {
    if (_stats?.level == 'polling_unit') {
      _openList(f.area!.id, f.lead);
    } else {
      _open(f.area!);
    }
  }

  /// The area the figures are for, as a heading.
  String _areaName(AppProfile p) {
    if (_pollingUnitId != null) {
      final u = p.pollingUnit(_pollingUnitId!);
      return u == null ? 'Polling unit' : '${u.code} · ${u.name}';
    }
    if (_wardId != null) return '${p.ward(_wardId!)?.name ?? 'Ward'} ward';
    if (p.isStateCoordinator && p.lgaName != null) return '${p.lgaName} LGA';
    return p.areaLabel;
  }

  @override
  Widget build(BuildContext context) {
    final p = CanvassScope.of(context).profile!;
    final stats = _stats;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _Filters(
            profile: p,
            wardId: _wardId,
            pollingUnitId: _pollingUnitId,
            onWard: (w) => _setArea(ward: w, unit: null),
            onPickPollingUnit: _pickPollingUnit,
            onClearPollingUnit: () => _setArea(ward: _wardId, unit: null),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 4, child: _loading ? const LinearProgressIndicator() : null),
          if (_error != null && stats == null)
            Notice(
              icon: Icons.error_outline,
              color: HaskeColors.red,
              title: "Couldn't load the voter figures",
              text: _error!,
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          else if (_error != null)
            Notice(
              icon: Icons.cloud_off,
              color: Colors.grey.shade700,
              title: 'Showing the figures from ${timeAgo(stats!.fetchedAt)}',
              text: _error!,
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          else if (stats == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Loading the voter figures…', textAlign: TextAlign.center),
            ),
          if (stats != null) ..._figures(context, p, stats),
        ],
      ),
    );
  }

  List<Widget> _figures(BuildContext context, AppProfile p, VoterStats s) {
    final theme = Theme.of(context);
    final asked = s.canvassed - s.count('support:unanswered');
    final supporters = s.count('support:strong_support') + s.count('support:leaning_support');
    String share(int? v) => v == null ? '–' : '$v%';
    final team = [
      '${formatCount(s.canvassers)} ${s.canvassers == 1 ? 'canvasser' : 'canvassers'}',
      if (p.coversWards && _pollingUnitId == null)
        '${formatCount(s.wardCoordinators)} ${s.wardCoordinators == 1 ? 'ward coordinator' : 'ward coordinators'}',
    ];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_areaName(p), style: theme.textTheme.titleMedium),
            Text('${team.join(' and ')} · updated ${timeAgo(s.fetchedAt)}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.2,
        children: [
          _Kpi(
            label: 'Voters on the list',
            value: formatCount(s.voters),
            note: 'INEC registers ${formatCount(s.registered)} in ${formatCount(s.units)} polling units',
          ),
          _Kpi(
            label: 'Canvassed',
            value: share(percent(s.canvassed, s.voters)),
            note: '${formatCount(s.canvassed)} voters visited at least once',
          ),
          _Kpi(
            label: 'Supporting',
            value: share(percent(supporters, asked)),
            note: 'strong or leaning, of ${formatCount(asked)} asked',
          ),
          _Kpi(
            label: 'Can be phoned',
            value: share(percent(s.reachable, s.voters)),
            note: '${formatCount(s.reachable)} have a phone or WhatsApp number',
          ),
        ],
      ),
      if (s.voters == 0)
        const Notice(
          icon: Icons.groups_outlined,
          title: 'No voters in this area yet',
          text: 'Figures appear once voters are added or imported.',
        )
      else ...[
        if (_focus(s).isNotEmpty)
          Panel(
            title: 'Where to focus',
            child: Column(
              children: [
                for (final f in _focus(s))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(f.icon, color: theme.colorScheme.primary),
                    title: Text(f.title),
                    subtitle: Text(f.text),
                    trailing: f.area != null && _opening == f.area!.id
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : f.area != null && _canOpen
                        ? Icon(s.level == 'polling_unit' ? Icons.list_alt : Icons.chevron_right)
                        : null,
                    onTap: f.area != null && _canOpen ? () => _openFocus(f) : null,
                  ),
              ],
            ),
          ),
        if (_pollingUnitId != null)
          Panel(
            title: 'Who to visit here',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "This polling unit's voters, by their latest visit: not yet canvassed, persuadable, "
                  'supporters to turn out, and supporters who need a PVC or are unsure of voting.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _opening == null ? () => _openList(_pollingUnitId!, Lead.notReached) : null,
                  icon: _opening == _pollingUnitId
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.list_alt),
                  label: const Text('Open voter lists'),
                ),
              ],
            ),
          ),
        Panel(
          title: 'Gender',
          child: _GenderChart(stats: s),
        ),
        Panel(
          title: 'Age',
          child: _AgeChart(stats: s),
        ),
        Panel(
          title: 'Canvassing answers',
          child: s.canvassed == 0
              ? const Text('Nobody in this area has been canvassed yet.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AnswerBars(title: 'Support', options: Options.support, prefix: 'support', stats: s),
                    const SizedBox(height: 16),
                    _AnswerBars(title: 'PVC', options: Options.pvcStatus, prefix: 'pvc', stats: s),
                    const SizedBox(height: 16),
                    _AnswerBars(title: 'Plans to vote', options: Options.plansToVote, prefix: 'plans', stats: s),
                  ],
                ),
        ),
        if (_pollingUnitId == null) _areasSection(context, s),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Ages are this year less the year of birth. Support, PVC and plans count each canvassed voter once, '
            'by their latest visit; persuadable voters are undecided or leaning against. '
            "INEC's register is the polling units' registered voters.",
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    ];
  }

  /// Whether the table's areas open one level down.
  bool get _canOpen => _pollingUnitId == null;

  /// What the table's areas are, in words.
  static String _levelName(VoterStats s) => switch (s.level) {
    'lga' => 'LGA',
    'ward' => 'ward',
    _ => 'polling unit',
  };

  Widget _areasSection(BuildContext context, VoterStats s) {
    final areas = [...s.areas]..sort(_sort.compare);
    final most = s.areas.fold<int>(0, (m, a) => a.voters > m ? a.voters : m);
    return Panel(
      title: 'By ${_levelName(s)}',
      action: PopupMenuButton<_Sort>(
        tooltip: 'Sort',
        initialValue: _sort,
        onSelected: (v) => setState(() => _sort = v),
        itemBuilder: (context) => [for (final v in _Sort.values) PopupMenuItem(value: v, child: Text(v.label))],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sort, size: 18),
              const SizedBox(width: 4),
              Text(_sort.label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
      child: Column(
        children: [for (final a in areas) _AreaRow(area: a, most: most, onTap: _canOpen ? () => _open(a) : null)],
      ),
    );
  }

  /// What to act on first, as erims's dashboard picks it.
  List<_Focus> _focus(VoterStats s) {
    if (s.areas.length < 2) return const [];
    AreaStats? most(int Function(AreaStats) score) => s.areas.fold<AreaStats?>(
      null,
      (best, a) => score(a) > 0 && (best == null || score(a) > score(best)) ? a : best,
    );
    final out = <_Focus>[];
    final unreached = most((a) => a.voters - a.canvassed);
    if (unreached != null) {
      out.add(
        _Focus(
          Icons.door_front_door_outlined,
          'Most voters not yet canvassed',
          '${unreached.name}: ${formatCount(unreached.voters - unreached.canvassed)} of '
              "${formatCount(unreached.voters)} voters haven't been visited.",
          unreached,
          Lead.notReached,
        ),
      );
    }
    final persuadable = most((a) => a.persuadable);
    if (persuadable != null) {
      out.add(
        _Focus(
          Icons.record_voice_over_outlined,
          'Most persuadable voters',
          '${persuadable.name}: ${formatCount(persuadable.persuadable)} canvassed voters are undecided or leaning against.',
          persuadable,
          Lead.persuadable,
        ),
      );
    }
    final compared = s.areas.where((a) => a.canvassed >= _minCanvassed).toList();
    if (compared.length > 1) {
      double share(AreaStats a) => a.supporters / a.canvassed;
      final strongest = compared.reduce((b, a) => share(a) > share(b) ? a : b);
      final weakest = compared.reduce((w, a) => share(a) < share(w) ? a : w);
      final name = _levelName(s);
      out.add(
        _Focus(
          Icons.trending_up,
          'Strongest $name',
          '${strongest.name}: ${percent(strongest.supporters, strongest.canvassed)}% of '
              '${formatCount(strongest.canvassed)} canvassed support us. Make sure they turn out.',
          strongest,
          Lead.turnout,
        ),
      );
      if (weakest != strongest) {
        out.add(
          _Focus(
            Icons.trending_down,
            'Weakest $name',
            '${weakest.name}: ${percent(weakest.supporters, weakest.canvassed)}% of '
                '${formatCount(weakest.canvassed)} canvassed support us.',
            weakest,
            Lead.persuadable,
          ),
        );
      }
    }
    final unphoned = most((a) => a.voters - a.reachable);
    if (unphoned != null) {
      out.add(
        _Focus(
          Icons.phone_disabled_outlined,
          'Fewest phone numbers',
          '${unphoned.name}: ${formatCount(unphoned.voters - unphoned.reachable)} voters have no phone or '
              'WhatsApp number. Ask for them when canvassing.',
          unphoned,
          Lead.all,
        ),
      );
    }
    return out;
  }
}

class _Focus {
  const _Focus(this.icon, this.title, this.text, this.area, this.lead);

  final IconData icon;
  final String title;
  final String text;
  final AreaStats? area;

  /// The voter list a polling unit's card opens on.
  final Lead lead;
}

enum _Sort {
  voters('Most voters'),
  unreached('Most not canvassed'),
  supporting('Most supporting'),
  name('Name');

  const _Sort(this.label);

  final String label;

  int compare(AreaStats a, AreaStats b) => switch (this) {
    _Sort.voters => b.voters.compareTo(a.voters),
    _Sort.unreached => (b.voters - b.canvassed).compareTo(a.voters - a.canvassed),
    _Sort.supporting => b.supporters.compareTo(a.supporters),
    _Sort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  };
}

/// LGA, ward and polling unit, as erims's area filter: an LGA or state
/// coordinator chooses the ward; a ward coordinator's is fixed. A state
/// coordinator chooses the LGA above the tabs, and has nothing to narrow
/// until they do.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.profile,
    required this.wardId,
    required this.pollingUnitId,
    required this.onWard,
    required this.onPickPollingUnit,
    required this.onClearPollingUnit,
  });

  final AppProfile profile;
  final String? wardId;
  final String? pollingUnitId;
  final ValueChanged<String?> onWard;
  final VoidCallback onPickPollingUnit;
  final VoidCallback onClearPollingUnit;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final lgaName = p.lgaName;
    if (lgaName == null) return const SizedBox.shrink();
    final wards = p.wards;
    final unit = pollingUnitId == null ? null : p.pollingUnit(pollingUnitId!);
    Widget fixed(String label, String value) => InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true, enabled: false),
      child: Text(value, overflow: TextOverflow.ellipsis),
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: fixed('LGA', lgaName)),
            const SizedBox(width: 8),
            Expanded(
              child: !p.coversWards
                  ? fixed('Ward', p.wardName ?? '')
                  : DropdownButtonFormField<String?>(
                      // Rebuilt when a drill-down changes the ward.
                      key: ValueKey(wardId),
                      initialValue: wardId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Ward', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All wards')),
                        for (final w in wards)
                          DropdownMenuItem(
                            value: w.id,
                            child: Text(w.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: wards.isEmpty ? null : onWard,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPickPollingUnit,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Polling unit',
              isDense: true,
              suffixIcon: unit == null
                  ? const Icon(Icons.arrow_drop_down)
                  : IconButton(
                      tooltip: 'All polling units',
                      icon: const Icon(Icons.close),
                      onPressed: onClearPollingUnit,
                    ),
            ),
            child: Text(
              unit == null ? 'All polling units' : '${unit.code} · ${unit.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.note});

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(note, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// A bar split into [parts] by value, with a 2px gap between them. [fill]
/// is how much of the width the whole bar takes, from 0 to 1.
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.parts, this.fill = 1, this.height = 12});

  final List<(int, Color)> parts;
  final double fill;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shown = parts.where((p) => p.$1 > 0).toList();
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth * fill.clamp(0, 1);
        return Container(
          height: height,
          decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(4)),
          alignment: Alignment.centerLeft,
          child: shown.isEmpty || width < 1
              ? null
              : ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: width,
                    child: Row(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: shown[i].$1,
                            child: ColoredBox(color: shown[i].$2),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final (color, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
              Text(label, style: t),
            ],
          ),
      ],
    );
  }
}

class _GenderChart extends StatelessWidget {
  const _GenderChart({required this.stats});

  final VoterStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final men = s.count('gender:M'), women = s.count('gender:F'), unknown = s.count('gender:unknown');
    String share(int n) => '${percent(n, s.voters) ?? 0}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SplitBar(parts: [(women, _womenColor), (men, _menColor), (unknown, _unknownColor)], height: 16),
        const SizedBox(height: 8),
        _Legend(
          items: [
            (_womenColor, 'Women ${share(women)} (${formatCount(women)})'),
            (_menColor, 'Men ${share(men)} (${formatCount(men)})'),
            if (unknown > 0) (_unknownColor, 'Not recorded ${share(unknown)} (${formatCount(unknown)})'),
          ],
        ),
      ],
    );
  }
}

/// Each age band's voters, women and men, against the largest band.
class _AgeChart extends StatelessWidget {
  const _AgeChart({required this.stats});

  final VoterStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final bands = [
      for (final e in _ageBands.entries)
        if (e.key != 'unknown' || s.count('age:unknown') > 0) e,
    ];
    final most = bands.fold<int>(0, (m, e) => s.count('age:${e.key}') > m ? s.count('age:${e.key}') : m);
    final t = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Legend(items: const [(_womenColor, 'Women'), (_menColor, 'Men')]),
        const SizedBox(height: 8),
        for (final e in bands)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 84, child: Text(e.value, style: t)),
                Expanded(
                  child: _SplitBar(
                    fill: most == 0 ? 0 : s.count('age:${e.key}') / most,
                    parts: [
                      (s.count('age:${e.key}:F'), _womenColor),
                      (s.count('age:${e.key}:M'), _menColor),
                      (s.count('age:${e.key}:unknown'), _unknownColor),
                    ],
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(formatCount(s.count('age:${e.key}')), style: t, textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// How canvassed voters answered one question, by their latest visit.
class _AnswerBars extends StatelessWidget {
  const _AnswerBars({required this.title, required this.options, required this.prefix, required this.stats});

  final String title;
  final Map<String, String> options;
  final String prefix;
  final VoterStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final theme = Theme.of(context);
    final answers = {...options, if (s.count('$prefix:unanswered') > 0) 'unanswered': 'Not asked'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        for (final e in answers.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.value, style: theme.textTheme.bodySmall)),
                    Text(
                      '${formatCount(s.count('$prefix:${e.key}'))} · '
                      '${percent(s.count('$prefix:${e.key}'), s.canvassed) ?? 0}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                _SplitBar(
                  height: 8,
                  fill: s.canvassed == 0 ? 0 : s.count('$prefix:${e.key}') / s.canvassed,
                  parts: [(1, e.key == 'unanswered' ? _unknownColor : HaskeColors.green)],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One ward or polling unit: its voters against the largest, and its shares.
class _AreaRow extends StatelessWidget {
  const _AreaRow({required this.area, required this.most, this.onTap});

  final AreaStats area;
  final int most;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = area;
    final t = Theme.of(context).textTheme;
    String share(int part, int whole) => percent(part, whole) == null ? '–' : '${percent(part, whole)}%';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(a.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text(formatCount(a.voters), style: t.bodyMedium),
                if (onTap != null) const Icon(Icons.chevron_right, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            _SplitBar(height: 6, fill: most == 0 ? 0 : a.voters / most, parts: [(1, HaskeColors.green)]),
            const SizedBox(height: 4),
            Text(
              'Canvassed ${share(a.canvassed, a.voters)} · Supporting ${share(a.supporters, a.canvassed)} · '
              'Persuadable ${formatCount(a.persuadable)} · Women ${share(a.female, a.male + a.female)} · '
              'Phones ${share(a.reachable, a.voters)} · INEC ${formatCount(a.registered)}',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
