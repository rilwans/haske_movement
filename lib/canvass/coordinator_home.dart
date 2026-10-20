import 'package:flutter/material.dart';

import '../config.dart';
import '../data/canvass_service.dart';
import '../data/models.dart';
import '../theme.dart';
import 'account_menu.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'onboard_canvasser_screen.dart';
import 'sync_bar.dart';
import 'voter_list_screen.dart';
import 'voter_stats_tab.dart';
import 'ward_filter.dart';

/// A ward or LGA coordinator's home: the polling units in their area to
/// canvass, the voter figures for it, and the canvassers (and, for an LGA
/// coordinator, ward coordinators) they've onboarded.
class CoordinatorHome extends StatefulWidget {
  const CoordinatorHome({super.key});

  @override
  State<CoordinatorHome> createState() => _CoordinatorHomeState();
}

class _CoordinatorHomeState extends State<CoordinatorHome> {
  int _tab = 0;

  /// On the team tab, whether an LGA coordinator is looking at ward coordinators.
  bool _wardCoordinators = false;

  /// The stats tab, once opened, keeps its area and figures across tabs.
  bool _statsOpened = false;

  @override
  Widget build(BuildContext context) {
    final p = CanvassScope.of(context).profile!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.areaLabel, overflow: TextOverflow.ellipsis),
            Text(p.roleLabel, style: theme.textTheme.bodySmall),
          ],
        ),
        actions: const [AccountMenu()],
      ),
      body: Column(
        children: [
          const SyncBar(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                const _PollingUnitsTab(),
                _statsOpened ? const VoterStatsTab() : const SizedBox.shrink(),
                Column(
                  children: [
                    if (p.isLgaCoordinator)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Canvassers'),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('Ward coordinators'),
                              ),
                            ],
                            selected: {_wardCoordinators},
                            showSelectedIcon: false,
                            onSelectionChanged: (v) =>
                                setState(() => _wardCoordinators = v.first),
                          ),
                        ),
                      ),
                    Expanded(
                      child: p.isLgaCoordinator && _wardCoordinators
                          ? const _WardCoordinatorsTab()
                          : const _CanvassersTab(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tab == 2
          ? p.isLgaCoordinator && _wardCoordinators
                ? FloatingActionButton.extended(
                    onPressed: () => openScreen(
                      context,
                      const OnboardCanvasserScreen.wardCoordinator(),
                    ),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add ward coordinator'),
                  )
                : FloatingActionButton.extended(
                    onPressed: () =>
                        openScreen(context, const OnboardCanvasserScreen()),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Onboard canvasser'),
                  )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          if (i == 1) _statsOpened = true;
        }),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.how_to_vote_outlined),
            selectedIcon: Icon(Icons.how_to_vote),
            label: 'Canvass',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: const Icon(Icons.groups),
            label: p.isLgaCoordinator ? 'Team' : 'Canvassers',
          ),
        ],
      ),
    );
  }
}

/// Every polling unit in the area. One with its voters on the phone opens
/// offline; any other is downloaded first, which needs internet.
class _PollingUnitsTab extends StatefulWidget {
  const _PollingUnitsTab();

  @override
  State<_PollingUnitsTab> createState() => _PollingUnitsTabState();
}

class _PollingUnitsTabState extends State<_PollingUnitsTab> {
  final _search = TextEditingController();
  String? _ward;
  String? _downloading;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(PollingUnit pu) async {
    final s = CanvassScope.read(context);
    if (!s.downloaded.contains(pu.id)) {
      setState(() => _downloading = pu.id);
      try {
        await s.downloadPollingUnit(pu.id);
      } catch (e) {
        if (mounted) {
          setState(() => _downloading = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Couldn't download ${pu.name}. ${CanvassService.describeError(e)}",
              ),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _downloading = null);
    }
    await openScreen(context, VoterListScreen(pollingUnit: pu));
  }

  @override
  Widget build(BuildContext context) {
    final s = CanvassScope.of(context);
    final all = s.profile!.pollingUnits;
    final units =
        filterPollingUnits(all, ward: _ward, search: _search.text)
          // The ones ready offline first.
          ..sort((a, b) {
            final da = s.downloaded.contains(a.id),
                db = s.downloaded.contains(b.id);
            return da == db ? a.code.compareTo(b.code) : (da ? -1 : 1);
          });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
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
            units: all,
            value: _ward,
            onChanged: (w) => setState(() => _ward = w),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Download a polling unit while you have internet, then canvass it offline.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: units.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = units[i];
              final ready = s.downloaded.contains(u.id);
              return ListTile(
                title: Text(u.name),
                subtitle: Text('${u.code} · ${u.wardName}'),
                trailing: _downloading == u.id
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : ready
                    ? const Tooltip(
                        message: 'On this phone',
                        child: Icon(
                          Icons.offline_pin,
                          color: HaskeColors.green,
                        ),
                      )
                    : const Tooltip(
                        message: 'Download',
                        child: Icon(Icons.download),
                      ),
                onTap: _downloading == null ? () => _open(u) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The canvassers onboarded from this phone, and whether they can sign in yet.
class _CanvassersTab extends StatelessWidget {
  const _CanvassersTab();

  @override
  Widget build(BuildContext context) {
    final s = CanvassScope.of(context);
    return FutureBuilder<List<NewCanvasser>>(
      key: ValueKey(s.revision),
      future: s.db.canvassers(),
      builder: (context, snap) {
        final list = snap.data;
        if (list == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                "Canvassers you onboard appear here. You can onboard them offline; "
                "they can sign in once it's sent.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final c = list[i];
            final pu = s.profile!.pollingUnit(c.pollingUnitId);
            return _OnboardedTile(
              name: c.fullName,
              where: pu?.name ?? 'Polling unit',
              createdAt: c.createdAt,
              phone: c.phone,
              pending: c.pending,
              syncError: c.syncError,
              login: c.login,
            );
          },
        );
      },
    );
  }
}

/// The ward coordinators an LGA coordinator added from this phone, and
/// whether they can sign in yet.
class _WardCoordinatorsTab extends StatelessWidget {
  const _WardCoordinatorsTab();

  @override
  Widget build(BuildContext context) {
    final s = CanvassScope.of(context);
    return FutureBuilder<List<NewWardCoordinator>>(
      key: ValueKey(s.revision),
      future: s.db.wardCoordinators(),
      builder: (context, snap) {
        final list = snap.data;
        if (list == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                "Ward coordinators you add appear here. They can onboard canvassers in their ward "
                "once they sign in. You can add them offline; they can sign in once it's sent.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final c = list[i];
            return _OnboardedTile(
              name: c.fullName,
              where: '${c.wardName} ward',
              createdAt: c.createdAt,
              phone: c.phone,
              pending: c.pending,
              syncError: c.syncError,
              login: c.login,
            );
          },
        );
      },
    );
  }
}

/// Someone a coordinator onboarded, with where their login is.
class _OnboardedTile extends StatelessWidget {
  const _OnboardedTile({
    required this.name,
    required this.where,
    required this.createdAt,
    required this.phone,
    required this.pending,
    required this.syncError,
    required this.login,
  });

  final String name;
  final String where;
  final DateTime createdAt;
  final String phone;
  final bool pending;
  final String? syncError;
  final String? login;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String status) = syncError != null
        ? (
            Icons.error_outline,
            HaskeColors.red,
            '${pending ? 'Not accepted' : 'No login yet'}: $syncError',
          )
        : pending
        ? (
            Icons.cloud_upload_outlined,
            Colors.orange.shade800,
            'Waiting to send. They can sign in once it is.',
          )
        : login != 'made'
        ? (
            Icons.hourglass_top,
            Colors.orange.shade800,
            'Sent. Their login is made at the next sync.',
          )
        : (
            Icons.check_circle,
            HaskeColors.green,
            'Can sign in with ${displayPhone(phone)} and ${Config.defaultPassword}',
          );
    return ListTile(
      isThreeLine: true,
      leading: Icon(icon, color: color),
      title: Text(name),
      subtitle: Text('$where · ${dateTime(createdAt)}\n$status'),
    );
  }
}
