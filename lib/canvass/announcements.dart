import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/canvass_service.dart';
import '../data/models.dart';
import '../theme.dart';
import 'canvass_shell.dart';
import 'format.dart';

/// The latest unopened announcement, above a home screen; nothing without one.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = CanvassScope.of(context).unreadAnnouncements;
    if (unread.isEmpty) return const SizedBox.shrink();
    return UnreadAnnouncementCard(
      unread: unread,
      onTap: () => openScreen(context, const AnnouncementsScreen()),
    );
  }
}

class UnreadAnnouncementCard extends StatelessWidget {
  const UnreadAnnouncementCard({super.key, required this.unread, required this.onTap});

  final List<Announcement> unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = unread.first;
    return Material(
      color: HaskeColors.gold.withValues(alpha: 0.22),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.campaign),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unread.length == 1 ? latest.authorName : '${latest.authorName} and ${unread.length - 1} more',
                      style: theme.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(latest.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the announcements, showing how many are unopened.
class AnnouncementsButton extends StatelessWidget {
  const AnnouncementsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = CanvassScope.of(context).unreadAnnouncements.length;
    return IconButton(
      tooltip: 'Announcements',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.campaign_outlined),
      ),
      onPressed: () => openScreen(context, const AnnouncementsScreen()),
    );
  }
}

/// Everything sent to the person's area, and what they sent with how many have
/// read it. Works offline; opening it counts as reading what's new.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  /// What was unopened when it appeared here, to mark as new while they look.
  final _new = <String>{};
  Future<List<Announcement>>? _announcements;
  int? _loadedAt;

  void _load(CanvassService s) {
    if (s.unreadAnnouncements.isNotEmpty || _loadedAt == null) {
      _new.addAll(s.unreadAnnouncements.map((a) => a.id));
      WidgetsBinding.instance.addPostFrameCallback((_) => s.openAnnouncements());
    }
    if (_loadedAt == s.revision) return;
    _loadedAt = s.revision;
    _announcements = s.db.announcements();
  }

  Future<void> _withdraw(Announcement a) async {
    final s = CanvassScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw this announcement?'),
        content: const Text('It goes from everyone\'s phone the next time they sync.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await s.withdrawAnnouncement(a.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't withdraw it. ${CanvassService.describeError(e)}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = CanvassScope.of(context);
    _load(s);
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: RefreshIndicator(
        onRefresh: s.sync,
        child: FutureBuilder<List<Announcement>>(
          future: _announcements,
          builder: (context, snap) {
            final all = snap.data;
            if (all == null) return const Center(child: CircularProgressIndicator());
            if (all.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  Text(
                    s.profile!.canAnnounce
                        ? 'Nothing yet. You can send an announcement from the Team tab.'
                        : 'Announcements from your coordinators appear here.',
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: all.length,
              itemBuilder: (context, i) => AnnouncementCard(
                announcement: all[i],
                isNew: _new.contains(all[i].id),
                onWithdraw: () => _withdraw(all[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({super.key, required this.announcement, required this.isNew, required this.onWithdraw});

  final Announcement announcement;
  final bool isNew;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('New', style: theme.textTheme.labelMedium?.copyWith(color: HaskeColors.green)),
              ),
            SelectableText(a.body, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              '${a.mine ? 'You' : '${a.authorName}, ${a.authorRoleLabel}'} · to ${a.areaName} · ${timeAgo(a.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
            if (a.mine)
              Row(
                children: [
                  Expanded(child: Text(a.readLabel, style: theme.textTheme.labelLarge)),
                  TextButton(onPressed: onWithdraw, child: const Text('Withdraw')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A coordinator writes an announcement and chooses who it's for. Needs internet.
class NewAnnouncementScreen extends StatefulWidget {
  const NewAnnouncementScreen({super.key});

  @override
  State<NewAnnouncementScreen> createState() => _NewAnnouncementScreenState();
}

class _NewAnnouncementScreenState extends State<NewAnnouncementScreen> {
  static const _maxLength = 500;

  final _body = TextEditingController();

  /// Kept across retries, so an answer that got lost doesn't send it twice.
  final _id = const Uuid().v4();
  AnnouncementAudience? _audience;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send(AnnouncementAudience to) async {
    final s = CanvassScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await s.postAnnouncement(id: _id, body: _body.text.trim(), lgaId: to.lgaId, wardId: to.wardId);
      messenger.showSnackBar(SnackBar(content: Text('Sent to ${to.label}')));
      navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = CanvassService.describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = CanvassScope.of(context).profile!.announcementAudiences;
    final to = _audience ?? options.first;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New announcement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (options.length > 1)
            DropdownButtonFormField<AnnouncementAudience>(
              initialValue: to,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Send to'),
              items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o.label))],
              onChanged: _sending ? null : (o) => setState(() => _audience = o),
            )
          else
            Text('To everyone in ${to.label}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _body,
            enabled: !_sending,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            maxLength: _maxLength,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Message',
              alignLabelWithHint: true,
              helperText: "Don't include voters' details.",
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending || _body.text.trim().isEmpty ? null : () => _send(to),
            child: _sending
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text('Send to ${to.label}', overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
