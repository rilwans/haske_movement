import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import '../theme.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'lga_choice.dart';
import 'panels.dart';
import 'voter_stats_tab.dart';

/// Needs attention, always with an icon and words.
const _warning = Color(0xFFFAB219);

/// LGAs listed under Needs attention before "Show all".
const _attentionShown = 5;

enum _Rank {
  unreached('Most not canvassed'),
  persuadable('Most persuadable'),
  supporting('Most supporting'),
  active('Most active'),
  name('Name');

  const _Rank(this.label);

  final String label;

  int compare(LgaOverview a, LgaOverview b) => switch (this) {
    _Rank.unreached => b.unreached.compareTo(a.unreached),
    _Rank.persuadable => b.persuadable.compareTo(a.persuadable),
    _Rank.supporting => (percent(b.supporters, b.canvassed) ?? -1).compareTo(percent(a.supporters, a.canvassed) ?? -1),
    _Rank.active => b.active7d.compareTo(a.active7d),
    _Rank.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  };
}

/// A state coordinator's Stats tab while they're on the whole state: what to
/// act on across its LGAs, beside the voter figures.
class StateStatsTab extends StatefulWidget {
  const StateStatsTab({super.key});

  @override
  State<StateStatsTab> createState() => _StateStatsTabState();
}

class _StateStatsTabState extends State<StateStatsTab> {
  bool _voters = false;

  /// The voter figures load when first opened, then keep their choices.
  bool _votersOpened = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Overview')),
                ButtonSegment(value: true, label: Text('Voters')),
              ],
              selected: {_voters},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() {
                _voters = v.first;
                _votersOpened |= _voters;
              }),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _voters ? 1 : 0,
            children: [const StateOverviewTab(), _votersOpened ? const VoterStatsTab() : const SizedBox.shrink()],
          ),
        ),
      ],
    );
  }
}

/// Where a state coordinator should act: LGAs needing attention, the pace
/// towards the election, the vote count, LGAs ranked, gaps in the team, and
/// what voters care about. Needs internet; the last figures show offline.
class StateOverviewTab extends StatefulWidget {
  const StateOverviewTab({super.key, this.onOpen});

  /// What tapping an LGA does, instead of moving to it.
  final ValueChanged<LgaOverview>? onOpen;

  @override
  State<StateOverviewTab> createState() => _StateOverviewTabState();
}

class _StateOverviewTabState extends State<StateOverviewTab> {
  StateOverview? _overview;
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
    final cached = await s.db.cached(CanvassService.stateOverviewKey);
    if (!mounted) return;
    if (_overview == null && cached != null) setState(() => _overview = StateOverview.fromJson(cached));
    try {
      final fresh = await s.fetchStateOverview();
      if (mounted) setState(() => _overview = fresh);
    } catch (e) {
      if (mounted) setState(() => _error = CanvassService.describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Moves to [lga], which replaces this tab once it's open.
  Future<void> _open(LgaOverview lga) async {
    final chosen = CanvassScope.read(context).profile!.lga(lga.id);
    if (chosen == null || _loading) return;
    setState(() => _loading = true);
    await chooseLga(context, chosen);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = CanvassScope.of(context).profile!;
    final o = _overview;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SizedBox(height: 4, child: _loading ? const LinearProgressIndicator() : null),
          if (_error != null && o == null)
            Notice(
              icon: Icons.error_outline,
              color: HaskeColors.red,
              title: "Couldn't load the overview",
              text: _error!,
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          else if (_error != null)
            Notice(
              icon: Icons.cloud_off,
              color: Colors.grey.shade700,
              title: 'Showing the overview from ${timeAgo(o!.fetchedAt)}',
              text: _error!,
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          else if (o == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Loading the overview…', textAlign: TextAlign.center),
            ),
          if (o != null)
            StateOverviewPanels(
              overview: o,
              areaLabel: p.areaLabel,
              onOpen: widget.onOpen ?? _open,
              forCandidate: p.isCandidate,
            ),
        ],
      ),
    );
  }
}

/// The overview's figures for [overview]; tapping an LGA calls [onOpen].
class StateOverviewPanels extends StatefulWidget {
  const StateOverviewPanels({
    super.key,
    required this.overview,
    required this.areaLabel,
    required this.onOpen,
    this.forCandidate = false,
  });

  final StateOverview overview;
  final String areaLabel;
  final ValueChanged<LgaOverview> onOpen;

  /// Adds the headline figures and the size of the team.
  final bool forCandidate;

  @override
  State<StateOverviewPanels> createState() => _StateOverviewPanelsState();
}

class _StateOverviewPanelsState extends State<StateOverviewPanels> {
  _Rank _rank = _Rank.unreached;
  bool _allAttention = false;
  bool _persuadableIssues = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.overview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${widget.areaLabel} · ${o.lgas.length} LGAs · updated ${timeAgo(o.fetchedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (widget.forCandidate) _Headline(overview: o),
        _attention(context, o),
        _Momentum(overview: o),
        _VoteCount(overview: o),
        _ranking(context, o),
        if (widget.forCandidate) _TeamStrength(overview: o),
        _coverage(context, o),
        _issues(context, o),
      ],
    );
  }

  Widget _attention(BuildContext context, StateOverview o) {
    final lgas = o.needingAttention;
    final shown = _allAttention ? lgas : lgas.take(_attentionShown).toList();
    return Panel(
      title: 'Needs attention',
      child: lgas.isEmpty
          ? const Text('Nothing stands out across the LGAs right now.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in shown)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber_rounded, color: _warning),
                    title: Text(l.name),
                    subtitle: Text(l.concerns.join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onOpen(l),
                  ),
                if (lgas.length > shown.length)
                  TextButton(
                    onPressed: () => setState(() => _allAttention = true),
                    child: Text('Show all ${lgas.length}'),
                  ),
              ],
            ),
    );
  }

  Widget _ranking(BuildContext context, StateOverview o) {
    final lgas = [...o.lgas]..sort(_rank.compare);
    return Panel(
      title: 'LGAs ranked',
      action: PopupMenuButton<_Rank>(
        tooltip: 'Rank by',
        initialValue: _rank,
        onSelected: (v) => setState(() => _rank = v),
        itemBuilder: (context) => [for (final v in _Rank.values) PopupMenuItem(value: v, child: Text(v.label))],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sort, size: 18),
              const SizedBox(width: 4),
              Text(_rank.label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
      child: Column(children: [for (final l in lgas) _LgaRow(lga: l, onTap: () => widget.onOpen(l))]),
    );
  }

  Widget _coverage(BuildContext context, StateOverview o) {
    final t = Theme.of(context).textTheme;
    final gaps = o.lgas.where((l) => l.hasGaps).toList()
      ..sort((a, b) => (b.wardsNoCoordinator + b.unitsNoCanvasser).compareTo(a.wardsNoCoordinator + a.unitsNoCanvasser));
    return Panel(
      title: 'Coverage gaps',
      child: gaps.isEmpty
          ? const Text('Every ward has a coordinator and every polling unit a canvasser.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatCount(o.total((l) => l.wardsNoCoordinator))} of ${formatCount(o.total((l) => l.wards))} wards '
                  'have no coordinator, and ${formatCount(o.total((l) => l.unitsNoCanvasser))} of '
                  '${formatCount(o.total((l) => l.units))} polling units have no canvasser.',
                  style: t.bodySmall,
                ),
                for (final l in gaps)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.name),
                    subtitle: Text(
                      '${formatCount(l.wardsNoCoordinator)} of ${formatCount(l.wards)} wards · '
                      '${formatCount(l.unitsNoCanvasser)} of ${formatCount(l.units)} polling units',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onOpen(l),
                  ),
              ],
            ),
    );
  }

  Widget _issues(BuildContext context, StateOverview o) {
    final t = Theme.of(context).textTheme;
    final top = o.topIssues(persuadableOnly: _persuadableIssues).take(5).toList();
    final byLga = [
      for (final l in o.lgas)
        if (l.topIssues(persuadableOnly: _persuadableIssues).isNotEmpty) l,
    ];
    return Panel(
      title: 'Top issues',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('All canvassed')),
                ButtonSegment(value: true, label: Text('Persuadable')),
              ],
              selected: {_persuadableIssues},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _persuadableIssues = v.first),
            ),
          ),
          const SizedBox(height: 8),
          if (top.isEmpty) const Text('No issues recorded yet.'),
          for (final e in top)
            _Meter(
              label: Options.issues[e.key] ?? e.key,
              value: formatCount(e.value),
              fill: e.value / top.first.value,
            ),
          if (byLga.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('By LGA', style: t.labelLarge),
            const SizedBox(height: 4),
            for (final l in byLga)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${l.name}: ${l.topIssues(persuadableOnly: _persuadableIssues).map((k) => Options.issues[k] ?? k).join(', ')}',
                  style: t.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The three figures a candidate looks at first.
class _Headline extends StatelessWidget {
  const _Headline({required this.overview});

  final StateOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final t = Theme.of(context).textTheme;
    final days = o.daysLeft(DateTime.now());
    final canvassed = percent(o.total((l) => l.canvassed), o.total((l) => l.voters));
    Widget figure(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: t.headlineSmall),
          Text(label, style: t.bodySmall),
        ],
      ),
    );
    return Panel(
      title: o.electionName ?? 'At a glance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (o.electionDate != null) ...[
            Text(shortDate(o.electionDate!), style: t.bodySmall),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              figure(days == null || days < 0 ? '–' : formatCount(days), days == 1 ? 'day to go' : 'days to go'),
              const SizedBox(width: 8),
              figure(canvassed == null ? '–' : '$canvassed%', 'canvassed'),
              const SizedBox(width: 8),
              figure(formatCount(o.total((l) => l.ready)), 'ready to vote'),
            ],
          ),
        ],
      ),
    );
  }
}

/// How many people are working each LGA, without who they are.
class _TeamStrength extends StatelessWidget {
  const _TeamStrength({required this.overview});

  final StateOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final t = Theme.of(context).textTheme;
    String people(int n, String one, String many) => '${formatCount(n)} ${n == 1 ? one : many}';
    String line(int lga, int ward, int canvassers) => [
      people(lga, 'LGA coordinator', 'LGA coordinators'),
      people(ward, 'ward coordinator', 'ward coordinators'),
      people(canvassers, 'canvasser', 'canvassers'),
    ].join(' · ');
    return Panel(
      title: 'Team strength',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${line(o.total((l) => l.lgaCoordinators), o.total((l) => l.wardCoordinators), o.total((l) => l.canvassers))}. '
            '${formatCount(o.total((l) => l.active7d))} active in the last 7 days.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 4),
          for (final l in o.lgas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    '${line(l.lgaCoordinators, l.wardCoordinators, l.canvassers)} · ${formatCount(l.active7d)} active',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The last 7 days against the 7 before, and where this pace ends up.
class _Momentum extends StatelessWidget {
  const _Momentum({required this.overview});

  final StateOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final today = DateTime.now();
    final voters = o.total((l) => l.voters);
    final canvassed = o.total((l) => l.canvassed);
    final days = o.daysLeft(today);
    final projected = o.projectedCanvassed(today);
    final now = percent(canvassed, voters) ?? 0;
    final String pace;
    if (o.electionDate == null) {
      pace = "$now% of voters canvassed so far. No upcoming election is set, so there's no projection.";
    } else if (projected == null) {
      pace = "$now% of voters canvassed so far. Nobody new has been canvassed in the last 14 days, so there's no projection.";
    } else {
      pace =
          "$now% of voters canvassed so far. At the last 14 days' pace, ${percent(projected, voters) ?? 0}% will be "
          'by ${o.electionName} on ${shortDate(o.electionDate!)}, $days ${days == 1 ? 'day' : 'days'} away.';
    }
    return Panel(
      title: 'Momentum',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Change(
                  label: 'Visits, last 7 days',
                  now: o.total((l) => l.visits7d),
                  before: o.total((l) => l.visitsPrev7d),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Change(
                  label: 'Newly canvassed',
                  now: o.total((l) => l.new7d),
                  before: o.total((l) => l.newPrev7d),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(pace, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A figure with how it compares with the week before, in words.
class _Change extends StatelessWidget {
  const _Change({required this.label, required this.now, required this.before});

  final String label;
  final int now;
  final int before;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (IconData icon, String change) = before == 0
        ? (Icons.remove, 'None the week before')
        : now == before
        ? (Icons.trending_flat, 'Same as the week before')
        : now > before
        ? (Icons.trending_up, '${percent100(now - before, before)}% up on the week before')
        : (Icons.trending_down, '${percent100(before - now, before)}% down on the week before');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatCount(now), style: t.headlineSmall),
        Text(label, style: t.bodySmall),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text(change, style: t.bodySmall)),
          ],
        ),
      ],
    );
  }
}

/// Where the canvassed voters stand, as what to do next about them.
class _VoteCount extends StatelessWidget {
  const _VoteCount({required this.overview});

  final StateOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final canvassed = o.total((l) => l.canvassed);
    if (canvassed == 0) {
      return const Panel(title: 'Vote count', child: Text('Nobody has been canvassed yet.'));
    }
    Widget row(String label, int n) =>
        _Meter(label: label, value: '${formatCount(n)} · ${percent(n, canvassed)}%', fill: n / canvassed);
    return Panel(
      title: 'Vote count',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Ready to vote', o.total((l) => l.ready)),
          row('Supporters needing a PVC', o.total((l) => l.needPvc)),
          row('Supporters unsure of voting', o.total((l) => l.wavering)),
          row('Persuadable', o.total((l) => l.persuadable)),
          const SizedBox(height: 8),
          Text(
            'Of ${formatCount(canvassed)} canvassed voters, by their latest visit and what they told canvassers. '
            'Ready means a supporter with a PVC who says they will vote. Supporters without those answers '
            'are in none of these groups.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// An LGA in the ranking, with what it's canvassed so far as a bar.
class _LgaRow extends StatelessWidget {
  const _LgaRow({required this.lga, required this.onTap});

  final LgaOverview lga;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = lga;
    final t = Theme.of(context).textTheme;
    final canvassed = percent(l.canvassed, l.voters);
    final supporting = percent(l.supporters, l.canvassed);
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
                  child: Text(l.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text(canvassed == null ? '–' : '$canvassed% canvassed', style: t.bodyMedium),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            _Bar(fill: l.voters == 0 ? 0 : l.canvassed / l.voters),
            const SizedBox(height: 4),
            Text(
              '${formatCount(l.unreached)} not canvassed · Supporting ${supporting == null ? '–' : '$supporting%'} · '
              'Persuadable ${formatCount(l.persuadable)} · ${formatCount(l.active7d)} active this week',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled figure over a bar.
class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.value, required this.fill});

  final String label;
  final String value;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: t.bodySmall)),
              Text(value, style: t.bodySmall),
            ],
          ),
          const SizedBox(height: 2),
          _Bar(fill: fill),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
    value: fill,
    minHeight: 8,
    borderRadius: BorderRadius.circular(4),
    color: HaskeColors.green,
    backgroundColor: Colors.grey.shade200,
  );
}
