import 'package:flutter/material.dart';

import '../data/canvass_service.dart';
import 'coordinator_home.dart';
import 'onboarding_screen.dart';
import 'voter_list_screen.dart';

/// Gives the screens below the canvasser's [CanvassService].
class CanvassScope extends InheritedNotifier<CanvassService> {
  const CanvassScope({super.key, required CanvassService service, required super.child})
      : super(notifier: service);

  static CanvassService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvassScope>()!.notifier!;

  /// For callbacks, which shouldn't rebuild on every change.
  static CanvassService read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CanvassScope>()!.notifier!;
}

/// Opens [screen] with the canvasser's service; routes sit beside the shell
/// in the app's navigator, not under it.
Future<T?> openScreen<T>(BuildContext context, Widget screen, {bool replace = false}) {
  final service = CanvassScope.read(context);
  final route = MaterialPageRoute<T>(builder: (_) => CanvassScope(service: service, child: screen));
  final nav = Navigator.of(context);
  return replace ? nav.pushReplacement(route) : nav.push(route);
}

/// Opens the signed-in person's data on the device, then shows onboarding
/// (first sign-in here), a canvasser's voter list or a coordinator's area.
class CanvassShell extends StatefulWidget {
  const CanvassShell({super.key, required this.userId});

  final String userId;

  @override
  State<CanvassShell> createState() => _CanvassShellState();
}

class _CanvassShellState extends State<CanvassShell> {
  CanvassService? _service;

  @override
  void initState() {
    super.initState();
    CanvassService.start(widget.userId).then((s) {
      if (!mounted) return s.dispose();
      setState(() => _service = s);
      if (s.onboarded) s.sync();
    });
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return CanvassScope(
      service: service,
      child: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final p = service.profile;
          if (p == null) return const OnboardingScreen();
          if (p.isCoordinator) return const CoordinatorHome();
          return VoterListScreen(pollingUnit: p.pollingUnits.first, isHome: true);
        },
      ),
    );
  }
}
