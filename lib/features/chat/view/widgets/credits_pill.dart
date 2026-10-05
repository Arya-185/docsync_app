import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/tokens.dart';
import '../../model/ai_credits.dart';

/// "250 / 500 used" — the Ask AI credits counter for the header. Nothing at all for a member the
/// owner has not limited (the server sends no counter). Amber from 80 %, red at 100 %.
class CreditsPill extends ConsumerWidget {
  const CreditsPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(aiCreditsProvider);
    if (c == null) return const SizedBox.shrink();
    final over = c.ratio >= 1, warn = !over && c.ratio >= 0.8;
    final fg = over ? Ds.red : (warn ? const Color(0xFF93370D) : Ds.inkSoft);
    final bg = over ? const Color(0xFFFEF3F2) : (warn ? const Color(0xFFFFFAEB) : Colors.white);
    final icon = over ? Ds.red : (warn ? Ds.amber : Ds.indigo);
    return Tooltip(
      message: c.tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Ds.rPill),
          border: Border.all(color: over ? const Color(0xFFFDA29B) : Ds.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.toll_rounded, size: 15, color: icon),
          const SizedBox(width: 5),
          Text(c.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
      ),
    );
  }
}
