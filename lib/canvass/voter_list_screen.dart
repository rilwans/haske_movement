import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import '../theme.dart';
import 'account_menu.dart';
import 'add_voter_screen.dart';
import 'announcements.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'sync_bar.dart';
import 'voter_screen.dart';

/// A polling unit's voters, searchable, sorted into who to visit next by
/// their latest visit: a canvasser's home screen, or one a coordinator opened.
class VoterListScreen extends StatefulWidget {
  const VoterListScreen({super.key, required this.pollingUnit, this.isHome = false, this.lead = Lead.all});

  final PollingUnit pollingUnit;

  /// The canvasser's home screen, with their account menu.
  final bool isHome;

  /// The list to open on.
  final Lead lead;

  @override
  State<VoterListScreen> createState() => _VoterListScreenState();
}

class _VoterListScreenState extends State<VoterListScreen> {
  final _search = TextEditingController();
  late Lead _lead = widget.lead;
  Future<List<Voter>>? _voters;
  Future<Map<Lead, int>>? _counts;
  int? _countedAt;
  Future<int>? _today;
  Object? _loadedFor;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _loadIfChanged(CanvassService s) {
    final key = (s.revision, _search.text, _lead);
    if (key == _loadedFor) return;
    _loadedFor = key;
    _voters = s.db.voters(widget.pollingUnit.id, search: _search.text, lead: _lead);
    // The counts change with the voters, not with the search or list chosen.
    if (_countedAt != s.revision) {
      _countedAt = s.revision;
      _counts = s.db.leadCounts(widget.pollingUnit.id);
    }
    final now = DateTime.now();
    _today = s.db.visitCountSince(DateTime(now.year, now.month, now.day), pollingUnitId: widget.pollingUnit.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = CanvassScope.of(context);
    final pu = widget.pollingUnit;
    final profile = s.profile!;
    _loadIfChanged(s);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pu.name, overflow: TextOverflow.ellipsis),
            Text(
              '${pu.code} · ${pu.wardName}, ${profile.lgaName ?? profile.stateName}',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [if (widget.isHome) ...const [AnnouncementsButton(), AccountMenu()]],
      ),
      body: Column(
        children: [
          const SyncBar(),
          if (widget.isHome) const AnnouncementBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name, phone or VIN',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          FutureBuilder<Map<Lead, int>>(
            future: _counts,
            builder: (context, snap) => SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: [
                  for (final l in Lead.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(snap.data == null ? l.label : '${l.label} (${formatCount(snap.data![l]!)})'),
                        selected: _lead == l,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _lead = l),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_lead != Lead.all)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_lead.hint, style: theme.textTheme.bodySmall),
              ),
            ),
          FutureBuilder<int>(
            future: _today,
            builder: (context, snap) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Today: ${snap.data ?? 0} ${snap.data == 1 ? 'conversation' : 'conversations'}',
                  style: theme.textTheme.labelLarge?.copyWith(color: HaskeColors.green),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Voter>>(
              future: _voters,
              builder: (context, snap) {
                final voters = snap.data;
                if (voters == null) return const Center(child: CircularProgressIndicator());
                if (voters.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _search.text.isNotEmpty
                            ? 'No voter matches "${_search.text}"${_lead == Lead.all ? '' : ' in this list'}. '
                                  'Add them if you met someone new.'
                            : switch (_lead) {
                                Lead.all => 'No voters here yet.',
                                Lead.notReached => 'Everyone here has been visited.',
                                Lead.visited => 'Nobody here has been visited yet.',
                                _ => 'Nobody here is in this list yet. It fills as voters are canvassed.',
                              },
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: voters.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _VoterTile(voter: voters[i]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openScreen(context, AddVoterScreen(pollingUnitId: pu.id, initialName: _search.text)),
        icon: const Icon(Icons.person_add),
        label: const Text('Add voter'),
      ),
    );
  }
}

class _VoterTile extends StatelessWidget {
  const _VoterTile({required this.voter});

  final Voter voter;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (voter.phone != null) displayPhone(voter.phone),
      if (voter.vin != null) 'VIN …${voter.vin!.substring(voter.vin!.length - 4)}',
      if (voter.addedLocally) 'Added by you',
    ].join(' · ');
    final visited = voter.latestVisitedAt;
    // Their latest answers, for what to say at the door.
    final latest = visited == null
        ? null
        : [
            Options.support[voter.latestSupport] ?? 'Support not asked',
            ?Options.pvcStatus[voter.latestPvcStatus],
            'visited ${timeAgo(visited)}',
          ].join(' · ');
    final subtitle = [if (details.isNotEmpty) details, ?latest].join('\n');
    return ListTile(
      isThreeLine: details.isNotEmpty && latest != null,
      leading: CircleAvatar(
        backgroundColor: visited != null ? HaskeColors.green : Colors.grey.shade300,
        foregroundColor: visited != null ? Colors.white : Colors.grey.shade800,
        child: visited != null ? const Icon(Icons.check) : Text(voter.name.characters.first.toUpperCase()),
      ),
      title: Text(voter.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: voter.syncError != null
          ? const Icon(Icons.error_outline, color: HaskeColors.red)
          : voter.pending
          ? const Icon(Icons.cloud_upload_outlined)
          : null,
      onTap: () => openScreen(context, VoterScreen(voterId: voter.id)),
    );
  }
}
