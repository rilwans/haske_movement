import 'package:flutter/material.dart';

/// A card with something to know: an error, the figures being old, or nothing to show.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.icon, required this.title, required this.text, this.color, this.action});

  final IconData icon;
  final String title;
  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(text),
        trailing: action,
      ),
    );
  }
}

/// A titled card of figures, with an optional control beside the title.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                ?action,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
