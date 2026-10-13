import 'package:flutter/material.dart';

import '../theme.dart';
import 'canvass_shell.dart';
import 'format.dart';

/// One line saying whether the canvasser's work has reached the server, with
/// a button to try now.
class SyncBar extends StatelessWidget {
  const SyncBar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = CanvassScope.of(context);
    final (IconData icon, Color color, String text) = switch (s) {
      _ when s.syncing => (Icons.sync, HaskeColors.green, 'Syncing…'),
      _ when s.lastError != null => (Icons.error_outline, HaskeColors.red, s.lastError!),
      _ when !s.online => (
          Icons.cloud_off,
          Colors.grey.shade700,
          s.pending > 0 ? 'Offline. ${s.pending} saved on this phone, will send when online' : 'Offline. You can keep canvassing',
        ),
      _ when s.failed > 0 => (Icons.error_outline, HaskeColors.red, '${s.failed} not accepted by the server. Tap a voter to see why'),
      _ when s.pending > 0 => (Icons.cloud_upload_outlined, Colors.orange.shade800, '${s.pending} waiting to send'),
      _ => (
          Icons.cloud_done,
          HaskeColors.green,
          s.lastSyncedAt == null ? 'All sent' : 'All sent · synced ${timeAgo(s.lastSyncedAt!)}',
        ),
    };
    return Material(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: color))),
            TextButton(
              onPressed: s.syncing ? null : s.sync,
              child: const Text('Sync now'),
            ),
          ],
        ),
      ),
    );
  }
}
