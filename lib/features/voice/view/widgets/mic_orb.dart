import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design/tokens.dart';

/// What the orb is showing. It never decides anything; the screen tells it.
enum OrbMode { idle, listening, thinking, speaking }

/// The big gradient mic orb of the voice screen, with soft waves around it.
///
/// [level] (0..1) is the live input loudness while listening, so the waves visibly move
/// with the user's voice — the cue that the phone is actually hearing them. In the other
/// modes the waves run on their own clock: a slow breath when idle, a steady ripple while
/// thinking.
class MicOrb extends StatefulWidget {
  const MicOrb({
    super.key,
    required this.mode,
    this.level = 0,
    this.size = 168,
    this.onTap,
  });

  final OrbMode mode;
  final double level;
  final double size;
  final VoidCallback? onTap;

  @override
  State<MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  // The level is smoothed here: raw recogniser levels jump every callback, and a
  // twitching orb reads as a glitch rather than as listening.
  double _smooth = 0;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (widget.mode) {
      OrbMode.idle => Icons.mic_rounded,
      OrbMode.listening => Icons.graphic_eq_rounded,
      OrbMode.thinking => Icons.auto_awesome,
      OrbMode.speaking => Icons.volume_up_rounded,
    };
    final extent = widget.size * 1.9;

    return Semantics(
      button: true,
      label: switch (widget.mode) {
        OrbMode.idle => 'Tap to speak',
        OrbMode.listening => 'Listening. Tap to stop',
        OrbMode.thinking => 'Working on it',
        OrbMode.speaking => 'Speaking. Tap to stop',
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: extent,
          height: extent,
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) {
              final target = widget.mode == OrbMode.listening
                  ? widget.level.clamp(0.0, 1.0)
                  : 0.0;
              _smooth += (target - _smooth) * 0.18;
              final t = _clock.value;
              final breath = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
              final scale = switch (widget.mode) {
                OrbMode.idle => 1 + 0.02 * breath,
                OrbMode.listening => 1 + 0.08 * _smooth,
                OrbMode.thinking => 1 + 0.03 * breath,
                OrbMode.speaking => 1 + 0.05 * breath,
              };
              return CustomPaint(
                painter: WavePainter(
                  phase: t,
                  energy: switch (widget.mode) {
                    OrbMode.idle => 0.25,
                    OrbMode.listening => 0.35 + 0.65 * _smooth,
                    OrbMode.thinking => 0.45,
                    OrbMode.speaking => 0.6,
                  },
                  orbRadius: widget.size / 2,
                ),
                child: Center(
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: Ds.orbGradient,
                        boxShadow: [
                          BoxShadow(
                            color: Ds.indigo.withValues(alpha: 0.35 + 0.25 * _smooth),
                            blurRadius: 40 + 30 * _smooth,
                            spreadRadius: 2 + 8 * _smooth,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // A soft highlight so the orb reads as a sphere, not a flat disc.
                          Positioned(
                            top: widget.size * 0.12,
                            left: widget.size * 0.2,
                            child: Container(
                              width: widget.size * 0.42,
                              height: widget.size * 0.26,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(widget.size),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.35),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          widget.mode == OrbMode.thinking
                              ? SizedBox(
                                  width: widget.size * 0.34,
                                  height: widget.size * 0.34,
                                  child: const CircularProgressIndicator(
                                      strokeWidth: 3, color: Colors.white),
                                )
                              : Icon(icon, color: Colors.white, size: widget.size * 0.34),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Three translucent sine rings around the orb. [energy] (0..1) is how far they swell.
class WavePainter extends CustomPainter {
  WavePainter({required this.phase, required this.energy, required this.orbRadius});

  final double phase;
  final double energy;
  final double orbRadius;

  static const _colors = [Ds.blue, Ds.indigo, Ds.violet];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var ring = 0; ring < 3; ring++) {
      final base = orbRadius + 10 + ring * 14.0;
      final amp = (4 + ring * 3) * energy;
      final lobes = 5 + ring;
      final spin = phase * 2 * math.pi * (ring.isEven ? 1 : -1);
      final path = Path();
      const steps = 120;
      for (var i = 0; i <= steps; i++) {
        final a = i / steps * 2 * math.pi;
        final r = base + amp * math.sin(lobes * a + spin);
        final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _colors[ring].withValues(alpha: (0.28 - ring * 0.07) + 0.2 * energy),
      );
    }
  }

  @override
  bool shouldRepaint(WavePainter old) =>
      old.phase != phase || old.energy != energy || old.orbRadius != orbRadius;
}
