import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme.dart';
import 'canvass_shell.dart';
import 'format.dart';
import 'visit_form_screen.dart';

/// A voter's details and the conversations recorded with them on this phone.
class VoterScreen extends StatelessWidget {
  const VoterScreen({super.key, required this.voterId});

  final String voterId;

  @override
  Widget build(BuildContext context) {
    final s = CanvassScope.of(context);
    return FutureBuilder(
      // Reloads after each change, e.g. a visit saved or a sync.
      key: ValueKey(s.revision),
      future: Future.wait([s.db.voter(voterId), s.db.visitsFor(voterId)]),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final voter = snap.data![0] as Voter?;
        final visits = snap.data![1] as List<Visit>;
        if (voter == null) {
          // Merged into a voter the server already had, or removed by an admin.
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This voter is no longer on your list.')),
          );
        }
        return _VoterView(voter: voter, visits: visits);
      },
    );
  }
}

class _VoterView extends StatelessWidget {
  const _VoterView({required this.voter, required this.visits});

  final Voter voter;
  final List<Visit> visits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(voter.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (voter.syncError != null)
            _ErrorCard('Not accepted by the server: ${voter.syncError}'),
          Card(
            child: Column(
              children: [
                _Detail(Icons.phone, 'Phone', displayPhone(voter.phone)),
                _Detail(Icons.chat, 'WhatsApp', displayPhone(voter.whatsappNumber)),
                _Detail(Icons.badge, 'VIN', voter.vin ?? ''),
                if (voter.email != null) _Detail(Icons.email, 'Email', voter.email!),
                if (voter.addedLocally)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_add),
                    title: Text(voter.pending ? 'Added by you · not sent yet' : 'Added by you'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            visits.isEmpty ? 'No conversations yet' : 'Conversations',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final v in visits) _VisitCard(visit: v),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openScreen(context, VisitFormScreen(voter: voter)),
        icon: const Icon(Icons.record_voice_over),
        label: Text(visits.isEmpty ? 'Record conversation' : 'Record another'),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(
          value.isEmpty ? 'Not known' : value,
          style: value.isEmpty ? TextStyle(color: Colors.grey.shade600) : null,
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: HaskeColors.red.withValues(alpha: 0.08),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: HaskeColors.red),
          title: Text(message),
        ),
      );
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit});

  final Visit visit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = [
      if (visit.support != null) 'Support: ${Options.support[visit.support]}',
      if (visit.pvcStatus != null) 'PVC: ${Options.pvcStatus[visit.pvcStatus]}',
      if (visit.plansToVote != null) 'Plans to vote: ${Options.plansToVote[visit.plansToVote]}',
      if (visit.issues.isNotEmpty) 'Issues: ${visit.issues.map((i) => Options.issues[i] ?? i).join(', ')}',
      if (visit.notes != null) visit.notes!,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(dateTime(visit.visitedAt), style: theme.textTheme.labelLarge)),
                if (visit.syncError != null)
                  const Icon(Icons.error_outline, size: 18, color: HaskeColors.red)
                else if (visit.synced)
                  const Icon(Icons.cloud_done, size: 18, color: HaskeColors.green)
                else
                  const Icon(Icons.cloud_upload_outlined, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            for (final l in lines) Text(l),
            if (visit.syncError != null) ...[
              const SizedBox(height: 6),
              Text('Not accepted: ${visit.syncError}', style: const TextStyle(color: HaskeColors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
