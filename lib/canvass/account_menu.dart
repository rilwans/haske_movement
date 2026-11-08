import 'package:flutter/material.dart';

import '../account/account_screen.dart';
import '../data/canvass_service.dart';
import 'canvass_shell.dart';

/// Who's signed in, and signing out, for the app bar of a home screen.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CanvassScope.of(context).profile!;
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle),
      onSelected: (v) => switch (v) {
        'account' => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen())),
        'signout' => _signOut(context),
        _ => null,
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p.fullName),
            subtitle: Text('${p.roleLabel} · ${p.areaLabel}'),
          ),
        ),
        if (!p.isCandidate) const PopupMenuItem(value: 'account', child: Text('My account')),
        const PopupMenuItem(value: 'signout', child: Text('Sign out')),
      ],
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final service = CanvassScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          "${service.profile!.isCandidate ? 'The figures saved' : 'The voters downloaded'} to this phone will be "
          "removed. You'll need internet to sign in again.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await service.signOut();
    } on CanvassException catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Can't sign out yet"),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                service.sync();
              },
              child: const Text('Sync now'),
            ),
          ],
        ),
      );
    }
  }
}
