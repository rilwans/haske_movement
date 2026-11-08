import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'panels.dart';

/// Needs attention, always with an icon and words.
const _warning = Color(0xFFFAB219);

/// What a candidate wants to know before visiting an LGA. Pops true to see
/// its wards.
class LgaBriefScreen extends StatefulWidget {
  const LgaBriefScreen({super.key, required this.lga});

  final LgaOverview lga;

  @override
  State<LgaBriefScreen> createState() => _LgaBriefScreenState();
}

class _LgaBriefScreenState extends State<LgaBriefScreen> {
  List<LgaContact>? _contacts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = CanvassScope.read(context);
    try {
      final contacts = await s.fetchLgaContacts(widget.lga.id);
      if (mounted) setState(() => _contacts = contacts);
    } catch (e) {
      if (mounted) setState(() => _error = CanvassService.describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.lga.name} LGA')),
      body: LgaBrief(
        lga: widget.lga,
        contacts: _contacts,
        contactsError: _error,
        onSeeWards: () => Navigator.pop(context, true),
      ),
    );
  }
}

/// The brief for [lga]; [contacts] are null while they load.
class LgaBrief extends StatelessWidget {
  const LgaBrief({
    super.key,
    required this.lga,
    required this.contacts,
    required this.contactsError,
    required this.onSeeWards,
  });

  final LgaOverview lga;
  final List<LgaContact>? contacts;
  final String? contactsError;
  final VoidCallback onSeeWards;

  @override
  Widget build(BuildContext context) {
    final l = lga;
    final t = Theme.of(context).textTheme;
    String share(int part, int whole) => percent(part, whole) == null ? '–' : '${percent(part, whole)}%';
    String issues(List<String> keys) => keys.map((k) => Options.issues[k] ?? k).join(', ');
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.bodyMedium)),
          Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
    final top = l.topIssues(), topPersuadable = l.topIssues(persuadableOnly: true);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Panel(
          title: 'At a glance',
          child: Column(
            children: [
              fact('Voters on the list', formatCount(l.voters)),
              fact('Canvassed', share(l.canvassed, l.voters)),
              fact('Supporting, of those canvassed', share(l.supporters, l.canvassed)),
              fact('Persuadable voters', formatCount(l.persuadable)),
              fact('Ready to vote', formatCount(l.ready)),
              fact('Supporters needing a PVC', formatCount(l.needPvc)),
            ],
          ),
        ),
        Panel(
          title: 'What voters here care about',
          child: top.isEmpty
              ? const Text('No issues recorded here yet.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(issues(top), style: t.bodyMedium),
                    if (topPersuadable.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Among persuadable voters', style: t.labelLarge),
                      Text(issues(topPersuadable), style: t.bodyMedium),
                    ],
                  ],
                ),
        ),
        if (l.concerns.isNotEmpty)
          Panel(
            title: 'Worth knowing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in l.concerns)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: _warning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c, style: t.bodyMedium)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Panel(
          title: 'Team here',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${formatCount(l.wardCoordinators)} ward coordinators · ${formatCount(l.canvassers)} canvassers · '
                '${formatCount(l.active7d)} active in the last 7 days',
                style: t.bodySmall,
              ),
              const SizedBox(height: 8),
              if (contactsError != null)
                Text("Couldn't load the LGA coordinator. $contactsError", style: t.bodySmall)
              else if (contacts == null)
                const LinearProgressIndicator()
              else if (contacts!.isEmpty)
                Text('No LGA coordinator yet.', style: t.bodyMedium)
              else
                for (final c in contacts!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c.name, style: t.bodyMedium)),
                        SelectableText(displayPhone(c.phone), style: t.bodyMedium),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: onSeeWards, child: const Text('See ward by ward')),
      ],
    );
  }
}
