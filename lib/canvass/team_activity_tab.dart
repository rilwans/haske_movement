import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import '../theme.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'panels.dart';

/// Visits that need a look: far, without a location, or rushed.
const _warningColor = Color(0xFFFAB219);

enum _Period {
  today('Today'),
  week('7 days'),
  month('30 days'),
  ever('All time');

  const _Period(this.label);

  final String label;

  DateTime? since(DateTime now) => switch (this) {
        _Period.today => DateTime(now.year, now.month, now.day),
        _Period.week => DateTime(now.year, now.month, now.day - 6),
        _Period.month => DateTime(now.year, now.month, now.day - 29),
        _Period.ever => null,
      };
}

enum _Sort {
  visits('Most visits'),
  quiet('Least active'),
  flagged('Most to check');

  const _Sort(this.label);

  final String label;

  int compare(TeamMember a, TeamMember b) => switch (this) {
        _Sort.visits => b.visits.compareTo(a.visits),
        // Never visited first, then the longest since their last visit.
        _Sort.quiet => (a.lastVisitAt?.millisecondsSinceEpoch ?? 0).compareTo(b.lastVisitAt?.millisecondsSinceEpoch ?? 0),
        _Sort.flagged => b.flagged.compareTo(a.flagged),
      };
}

/// What a coordinator's team has done: each canvasser's (and, for an LGA or
/// state coordinator, coordinator's) visits in a period, who's gone quiet,
/// and visits to check. Needs internet; the last figures show offline.
class TeamActivityTab extends StatefulWidget {
  const TeamActivityTab({super.key});

  @override
  State<TeamActivityTab> createState() => _TeamActivityTabState();
}

class _TeamActivityTabState extends State<TeamActivityTab> {
  _Period _period = _Period.week;
  _Sort _sort = _Sort.visits;
  String? _wardId;
  TeamActivity? _activity;
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = CanvassScope.read(context);
    final ward = _wardId, since = _period.since(DateTime.now()), request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    final cached = await s.db.cached(CanvassService.teamActivityKey(ward, since, s.profile?.selectedLgaId));
    if (!mounted || request != _request) return;
    setState(() => _activity = cached == null ? null : TeamActivity.fromJson(cached));
    try {
      final fresh = await s.fetchTeamActivity(wardId: ward, since: since);
      if (!mounted || request != _request) return;
      setState(() => _activity = fresh);
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _error = CanvassService.describeError(e));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = CanvassScope.of(context).profile!;
    final theme = Theme.of(context);
    final a = _activity;
    final people = a == null ? <TeamMember>[] : ([...a.people]..sort(_sort.compare));
    final active = people.where((m) => m.visits > 0).length;
    final visits = people.fold<int>(0, (n, m) => n + m.visits);
    final flagged = people.fold<int>(0, (n, m) => n + m.flagged);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          SegmentedButton<_Period>(
            segments: [for (final v in _Period.values) ButtonSegment(value: v, label: Text(v.label))],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (v) {
              _period = v.first;
              _load();
            },
          ),
          if (p.coversWards && p.wards.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _wardId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ward', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('All wards')),
                for (final w in p.wards) DropdownMenuItem(value: w.id, child: Text(w.name)),
              ],
              onChanged: (w) {
                _wardId = w;
                _load();
              },
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(height: 4, child: _loading ? const LinearProgressIndicator() : null),
          if (_error != null && a == null)
            Notice(
              icon: Icons.error_outline,
              color: HaskeColors.red,
              title: "Couldn't load your team's activity",
              text: _error!,
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          else if (_error != null)
            Notice(
              icon: Icons.cloud_off,
              color: Colors.grey.shade700,
              title: 'Showing activity from ${timeAgo(a!.fetchedAt)}',
              text: _error!,
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          else if (a == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text("Loading your team's activity…", textAlign: TextAlign.center),
            ),
          if (a != null) ...[
            Row(
              children: [
                Expanded(child: _Figure(value: '$active of ${people.length}', label: 'out canvassing')),
                const SizedBox(width: 8),
                Expanded(child: _Figure(value: formatCount(visits), label: visits == 1 ? 'visit' : 'visits')),
                const SizedBox(width: 8),
                Expanded(child: _Figure(value: formatCount(flagged), label: 'to check', warn: flagged > 0)),
              ],
            ),
            Panel(
              title: people.isEmpty ? 'Nobody on your team yet' : 'People',
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
                      Text(_sort.label, style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
              ),
              child: people.isEmpty
                  ? const Text('Canvassers in your area appear here once they are onboarded.')
                  : Column(children: [for (final m in people) _MemberTile(member: m, farKm: a.farKm)]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'To check: visits over ${a.farKm} km from the polling unit (or from where most visits there '
                'were recorded), recorded without the phone\'s location, or within a minute of the person\'s '
                'previous visit. Updated ${timeAgo(a.fetchedAt)}.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.warn = false});

  final String value;
  final String label;
  final bool warn;

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
            Row(
              children: [
                if (warn) ...[
                  const Icon(Icons.warning_amber_rounded, size: 18, color: _warningColor),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    value,
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(label, style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.farKm});

  final TeamMember member;
  final int farKm;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final activity = m.visits > 0
        ? '${formatCount(m.visits)} ${m.visits == 1 ? 'visit' : 'visits'} · ${formatCount(m.voters)} '
              '${m.voters == 1 ? 'voter' : 'voters'} · ${m.units} PU${m.units == 1 ? '' : 's'}'
        : m.lastVisitAt == null
        ? 'No visits yet'
        : 'No visits in this period';
    final last = m.lastVisitAt == null ? null : 'Last visit ${timeAgo(m.lastVisitAt!)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: m.visits > 0 ? HaskeColors.green : Colors.grey.shade300,
        foregroundColor: m.visits > 0 ? Colors.white : Colors.grey.shade800,
        child: Text(m.name.characters.first.toUpperCase()),
      ),
      title: Text(m.isMe ? '${m.name} (you)' : m.name),
      subtitle: Text(
        '${m.kindLabel} · ${m.area}\n$activity'
        '${last == null ? '' : ' · $last'}${m.hasLogin ? '' : ' · No login yet'}',
      ),
      trailing: m.flagged > 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: _warningColor),
                const SizedBox(width: 2),
                Text('${m.flagged}'),
              ],
            )
          : const Icon(Icons.chevron_right),
      onTap: () => openScreen(context, PersonVisitsScreen(member: m, farKm: farKm)),
    );
  }
}

/// Someone on the team's latest visits, with erims's checks, for a
/// coordinator to look into. Needs internet.
class PersonVisitsScreen extends StatefulWidget {
  const PersonVisitsScreen({super.key, required this.member, required this.farKm});

  final TeamMember member;

  /// How far from the polling unit a visit counts as far.
  final int farKm;

  @override
  State<PersonVisitsScreen> createState() => _PersonVisitsScreenState();
}

class _PersonVisitsScreenState extends State<PersonVisitsScreen> {
  late Future<List<TeamVisit>> _visits = _fetch();

  Future<List<TeamVisit>> _fetch() => CanvassScope.read(context).fetchPersonVisits(widget.member);

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.name, overflow: TextOverflow.ellipsis),
            Text('${m.kindLabel} · ${m.area}', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      body: FutureBuilder<List<TeamVisit>>(
        future: _visits,
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Notice(
                  icon: Icons.error_outline,
                  color: HaskeColors.red,
                  title: "Couldn't load their visits",
                  text: CanvassService.describeError(snap.error!),
                  action: TextButton(
                    onPressed: () => setState(() => _visits = _fetch()),
                    child: const Text('Retry'),
                  ),
                ),
              ],
            );
          }
          final visits = snap.data;
          if (visits == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone),
                title: Text(displayPhone(m.phone)),
                subtitle: Text(m.hasLogin ? 'Can sign in to the app' : 'No login yet'),
              ),
              Text(
                visits.isEmpty ? 'No visits yet' : 'Latest ${visits.length} ${visits.length == 1 ? 'visit' : 'visits'}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final v in visits) _VisitCard(visit: v, farKm: widget.farKm),
            ],
          );
        },
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit, required this.farKm});

  final TeamVisit visit;
  final int farKm;

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final theme = Theme.of(context);
    final checks = [
      if (v.distanceKm != null && v.distanceKm! > farKm) '${v.distanceKm!.toStringAsFixed(1)} km from the polling unit',
      if (!v.located) 'No location',
      if (v.rushed) 'Within a minute of the previous visit',
    ];
    final answers = [
      if (v.support != null) Options.support[v.support] ?? v.support!,
      if (v.pvcStatus != null) Options.pvcStatus[v.pvcStatus] ?? v.pvcStatus!,
      if (v.plansToVote != null) 'Plans to vote: ${Options.plansToVote[v.plansToVote] ?? v.plansToVote}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(v.voterName, style: theme.textTheme.titleSmall)),
                Text(dateTime(v.visitedAt), style: theme.textTheme.bodySmall),
              ],
            ),
            Text(v.pollingUnit, style: theme.textTheme.bodySmall),
            if (answers.isNotEmpty) ...[const SizedBox(height: 4), Text(answers.join(' · '))],
            if (v.distanceKm != null && checks.isEmpty)
              Text('${v.distanceKm!.toStringAsFixed(1)} km from the polling unit', style: theme.textTheme.bodySmall),
            for (final c in checks)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: _warningColor),
                    const SizedBox(width: 4),
                    Expanded(child: Text(c, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
