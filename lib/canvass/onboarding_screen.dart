import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import '../data/location.dart';
import 'canvass_shell.dart';

/// First sign-in on this phone: who they are and, for a canvasser, their
/// polling unit's voters, so they can canvass with no internet afterwards.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _download());
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = CanvassScope.read(context);
    try {
      await service.onboard();
      // Asked now, while they're set up, rather than at their first door.
      await currentPosition();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = CanvassService.describeError(e);
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await CanvassScope.read(context).signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', height: 160),
                const SizedBox(height: 32),
                if (_busy) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text('Setting up this phone', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Downloading what you need to canvass without internet.',
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text("Couldn't set up this phone", style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(_error ?? '', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'You need internet once to set up. After that you can canvass offline.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _download, child: const Text('Try again')),
                  TextButton(onPressed: _signOut, child: const Text('Sign out')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
