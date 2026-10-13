import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Plays the logo animation while the app starts, then fades to [child].
///
/// It begins exactly where the still launch screen leaves off (the logo at
/// 144 dp on white, see flutter_native_splash in pubspec.yaml): the logo
/// grows into place as a gold glow rises behind it like the sun, a sweep of
/// light (haske) passes across it, and three dots in the logo's colours
/// pulse if starting up takes longer than the animation.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.ready, required this.child});

  /// Completes when the app can show [child].
  final Future<void> ready;
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with TickerProviderStateMixin {
  /// Logo width once it has grown into place; the launch screen shows it at 0.6 of this.
  static const _logoWidth = 240.0;
  static const _startScale = 0.6;

  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _ready = false;
  bool _showApp = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed) _maybeFinish();
    });
    widget.ready.then(
      (_) {
        _ready = true;
        _maybeFinish();
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "remove animations": straight to the finished logo.
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
      _maybeFinish();
    } else if (_intro.isDismissed) {
      _intro.forward();
    }
  }

  void _maybeFinish() {
    if (!mounted || _showApp) return;
    if (_ready && _intro.isCompleted) {
      _dots.stop();
      setState(() => _showApp = true);
    } else if (_intro.isCompleted && !_dots.isAnimating && !MediaQuery.of(context).disableAnimations) {
      // Still starting up: show we're working on it.
      _dots.repeat();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      child: _showApp ? widget.child : _buildSplash(context),
    );
  }

  Widget _buildSplash(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The sun rising behind the logo.
            AnimatedBuilder(
              animation: _intro,
              builder: (context, _) {
                final t = const Interval(0.15, 0.7, curve: Curves.easeOutCubic).transform(_intro.value);
                final size = _logoWidth * (0.8 + 1.2 * t);
                return Opacity(
                  opacity: t,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          HaskeColors.gold.withValues(alpha: 0.35),
                          HaskeColors.gold.withValues(alpha: 0.12),
                          HaskeColors.gold.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.5, 1],
                      ),
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _intro,
              builder: (context, child) {
                final grow = const Interval(0, 0.55, curve: Curves.easeOutBack).transform(_intro.value);
                final sweep = const Interval(0.45, 0.95, curve: Curves.easeInOut).transform(_intro.value);
                return Transform.scale(
                  scale: _startScale + (1 - _startScale) * grow,
                  child: ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (rect) => _lightSweep(rect, sweep),
                    child: child,
                  ),
                );
              },
              // Transparent, so the glow shows through around it.
              child: Image.asset(
                'assets/images/logo_transparent.png',
                width: _logoWidth,
                semanticLabel: 'Haske Movement',
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              top: MediaQuery.of(context).size.height / 2 + _logoWidth / 2 + 40,
              child: _error != null
                  ? Text(
                      "Couldn't start the app. Close it and open it again.\n$_error",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: HaskeColors.red),
                    )
                  : _dots.isAnimating
                  ? _Dots(animation: _dots)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// A soft diagonal band of light at [t] (0 → 1) across the logo; outside
  /// the sweep it's fully transparent, so the logo shows as it is.
  static Shader _lightSweep(Rect rect, double t) {
    final centre = -0.3 + 1.6 * t;
    double stop(double d) => (centre + d).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: t > 0 && t < 1 ? 0.55 : 0),
        Colors.white.withValues(alpha: 0),
      ],
      stops: [stop(-0.12), stop(0), stop(0.12)],
    ).createShader(rect);
  }
}

/// Three dots in the logo's green, red and gold, pulsing in turn.
class _Dots extends StatelessWidget {
  const _Dots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    const colors = [HaskeColors.green, HaskeColors.red, HaskeColors.gold];
    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Transform.scale(
                  // Each dot peaks a third of a cycle after the last.
                  scale: 0.6 + 0.4 * (0.5 + 0.5 * math.sin(2 * math.pi * (animation.value - i / 3))),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
