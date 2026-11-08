import 'package:flutter/material.dart';

import '../data/models.dart';
import 'account_menu.dart';
import 'canvass_shell.dart';
import 'lga_brief_screen.dart';
import 'lga_choice.dart';
import 'state_overview_tab.dart';
import 'voter_stats_tab.dart';

/// A candidate's home: how the campaign stands across their election's LGAs,
/// and the figures for each LGA and ward. Read only, with no individual
/// voters. Tapping an LGA opens a brief for visiting it.
class CandidateHome extends StatefulWidget {
  const CandidateHome({super.key});

  @override
  State<CandidateHome> createState() => _CandidateHomeState();
}

class _CandidateHomeState extends State<CandidateHome> {
  int _tab = 0;

  /// Areas loads from the server when first opened.
  bool _areasOpened = false;

  void _openAreas() => setState(() {
    _tab = 1;
    _areasOpened = true;
  });

  Future<void> _brief(LgaOverview lga) async {
    final seeWards = await openScreen<bool>(context, LgaBriefScreen(lga: lga));
    if (seeWards != true || !mounted) return;
    final chosen = CanvassScope.read(context).profile!.lga(lga.id);
    if (chosen == null) return;
    if (await chooseLga(context, chosen) && mounted) _openAreas();
  }

  @override
  Widget build(BuildContext context) {
    final p = CanvassScope.of(context).profile!;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.areaLabel, overflow: TextOverflow.ellipsis),
            Text(p.roleLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: const [AccountMenu()],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          StateOverviewTab(onOpen: _brief),
          _areasOpened
              ? Column(
                  children: [
                    const LgaBar(),
                    Expanded(child: VoterStatsTab(key: ValueKey(p.selectedLgaId))),
                  ],
                )
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => i == 1 ? _openAreas() : setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Areas',
          ),
        ],
      ),
    );
  }
}
