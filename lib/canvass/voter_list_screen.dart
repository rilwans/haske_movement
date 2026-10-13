import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import '../theme.dart';
import 'account_menu.dart';
import 'add_voter_screen.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'sync_bar.dart';
import 'voter_screen.dart';

/// A polling unit's voters, searchable, with who's already been talked to:
/// a canvasser's home screen, or one a coordinator opened.
class VoterListScreen extends StatefulWidget {
  const VoterListScreen({super.key, required this.pollingUnit, this.isHome = false});

  final PollingUnit pollingUnit;

  /// The canvasser's home screen, with their account menu.
  final bool isHome;

  @override
  State<VoterListScreen> createState() => _VoterListScreenState();
}

enum _Filter { all, notVisited, visited }

class _VoterListScreenState extends State<VoterListScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  Future<List<Voter>>? _voters;
  Future<int>? _today;
  Object? _loadedFor;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _loadIfChanged(CanvassService s) {
    final key = (s.revision, _search.text, _filter);
    if (key == _loadedFor) return;
    _loadedFor = key;
    _voters = s.db.voters(
      widget.pollingUnit.id,
      search: _search.text,
      visited: switch (_filter) {
        _Filter.all => null,
        _Filter.notVisited => false,
        _Filter.visited => true,
      },
    );
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
              '${pu.code} · ${pu.wardName}, ${profile.lgaName}',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [if (widget.isHome) const AccountMenu()],
      ),
      body: Column(
        children: [
          const SyncBar(),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<_Filter>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: _Filter.all, label: Text('All')),
                      ButtonSegment(value: _Filter.notVisited, label: Text('To visit')),
                      ButtonSegment(value: _Filter.visited, label: Text('Visited')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (v) => setState(() => _filter = v.first),
                  ),
                ),
              ],
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
                            ? 'No voter matches "${_search.text}". Add them if you met someone new.'
                            : _filter == _Filter.visited
                                ? "You haven't recorded any conversations yet."
                                : 'No voters here yet.',
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
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: voter.visitCount > 0 ? HaskeColors.green : Colors.grey.shade300,
        foregroundColor: voter.visitCount > 0 ? Colors.white : Colors.grey.shade800,
        child: voter.visitCount > 0 ? const Icon(Icons.check) : Text(voter.name.characters.first.toUpperCase()),
      ),
      title: Text(voter.name),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: voter.syncError != null
          ? const Icon(Icons.error_outline, color: HaskeColors.red)
          : voter.pending
              ? const Icon(Icons.cloud_upload_outlined)
              : null,
      onTap: () => openScreen(context, VoterScreen(voterId: voter.id)),
    );
  }
}
