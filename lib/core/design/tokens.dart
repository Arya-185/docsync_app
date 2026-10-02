import 'package:flutter/material.dart';

/// The visual language of the app, in one place: the colours, radii, spacing and shadows
/// taken from the voice-first mockups. Widgets read these instead of inventing their own
/// numbers, so the screens stay one family.
class Ds {
  Ds._();

  // Brand.
  /// The "DocSync" wordmark colour: bold #1967CB, exactly as on docsync.in and every web page.
  static const brand = Color(0xFF1967CB);
  static const blue = Color(0xFF2563EB);
  static const indigo = Color(0xFF4F46E5);
  static const violet = Color(0xFF7C3AED);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const amber = Color(0xFFF59E0B);

  // Ink and surfaces.
  static const ink = Color(0xFF0F172A);
  static const inkSoft = Color(0xFF334155);
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE2E8F0);
  static const surface = Colors.white;
  static const tint = Color(0xFFEEF2FF); // selected pill, soft chips
  static const bgTop = Color(0xFFF4F7FF);
  static const bgBottom = Color(0xFFFFFFFF);

  // Radii.
  static const rCard = 20.0;
  static const rChip = 14.0;
  static const rPill = 28.0;
  static const rField = 16.0;

  // Spacing scale.
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;

  /// The page background: a faint cool wash at the top fading to white.
  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
  );

  /// The mic orb and primary accents.
  static const orbGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, indigo, violet],
  );

  /// Cards sit on a hairline border plus a faint, wide shadow — enough lift to read as a
  /// card, never a grey band under it.
  static const cardShadow = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const pillShadow = [
    BoxShadow(color: Color(0x120F172A), blurRadius: 24, offset: Offset(0, 6)),
  ];

  static BoxDecoration card({
    Color color = surface,
    double radius = rCard,
    bool flat = false,
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: line.withValues(alpha: flat ? 1 : 0.7)),
        boxShadow: flat ? null : cardShadow,
      );
}
