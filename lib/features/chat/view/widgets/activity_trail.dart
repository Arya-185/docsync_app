import 'package:flutter/material.dart';

import '../../model/chat_models.dart';

/// The activity trail: what the assistant is doing, line by line, while it does it.
///
/// A turn can run for tens of seconds with nothing to show — most of it is the model
/// reasoning before it calls anything, which used to look identical to a hang. The
/// server announces each step as it STARTS and closes it when it finishes; this draws
/// the result.
///
/// Placement (above the input bar rather than inside the assistant bubble, which is
/// where the web draws it) and its reasoning are documented on [ChatState.trail].
///
/// Once the turn is over the whole thing folds behind a one-line summary — the same
/// collapse-on-complete-with-a-user-override behaviour as the thinking panel in
/// chat_bubble.dart, so the two feel like one idea.
class ActivityTrail extends StatefulWidget {
  const ActivityTrail({
    super.key,
    required this.steps,
    required this.done,
    this.elapsed = 0,
  });

  final List<ChatStep> steps;

  /// The turn has ended: every line is closed and the trail collapses.
  final bool done;

  /// Seconds the turn took, shown in the collapsed summary when known.
  final double elapsed;

  @override
  State<ActivityTrail> createState() => _ActivityTrailState();
}

class _ActivityTrailState extends State<ActivityTrail> {
  bool _expanded = true;
  bool _userToggled = false;

  @override
  void didUpdateWidget(ActivityTrail old) {
    super.didUpdateWidget(old);
    if (!old.done && widget.done && !_userToggled) {
      _expanded = false; // the answer is in; fold away
    }
    if (old.done && !widget.done) {
      // a new turn started in the same strip — start open again
      _expanded = true;
      _userToggled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    if (steps.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final n = steps.length;
    final elapsed = widget.elapsed > 0
        ? ' · ${widget.elapsed.toStringAsFixed(1)}s'
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.done)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() {
                _expanded = !_expanded;
                _userToggled = true;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16, color: muted),
                    const SizedBox(width: 4),
                    Text(
                      '$n ${n == 1 ? 'step' : 'steps'}$elapsed',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          if (_expanded)
            ConstrainedBox(
              // The trail must never grow tall enough to squeeze the answer or the
              // input bar off a phone screen.
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                reverse: !widget.done, // keep the newest line in view while running
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final s in steps) _StepLine(step: s)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.step});
  final ChatStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = step.failed;
    final color = failed
        ? scheme.error
        : scheme.onSurface.withValues(alpha: step.done ? 0.55 : 0.85);

    final Widget icon;
    if (failed) {
      icon = Icon(Icons.error_outline, size: 14, color: scheme.error);
    } else if (step.done) {
      icon = Icon(Icons.check, size: 14, color: color);
    } else {
      icon = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 16, child: Center(child: icon)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              step.label,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
