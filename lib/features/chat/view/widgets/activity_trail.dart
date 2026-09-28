import 'package:flutter/material.dart';

import '../../../../core/design/tokens.dart';
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
    const muted = Ds.muted;
    final n = steps.length;
    final elapsed = widget.elapsed > 0
        ? ' · ${widget.elapsed.toStringAsFixed(1)}s'
        : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: Ds.card(radius: Ds.rChip + 2),
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
              constraints: const BoxConstraints(maxHeight: 168),
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

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: child),
      );
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.step});
  final ChatStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = step.failed;
    final color = failed ? Ds.red : (step.done ? Ds.inkSoft : Ds.ink);

    final Widget icon;
    if (failed) {
      icon = const _Dot(color: Ds.red, child: Icon(Icons.close, size: 11, color: Colors.white));
    } else if (step.done) {
      icon = const _Dot(color: Ds.green, child: Icon(Icons.check, size: 11, color: Colors.white));
    } else {
      icon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: Ds.blue),
      );
    }
    final secs = step.seconds;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 18, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: step.done ? FontWeight.w400 : FontWeight.w500,
              ),
            ),
          ),
          // An instant step says nothing useful as "0.0s".
          if (secs != null && step.done && secs >= 0.1)
            Text('${secs.toStringAsFixed(1)}s',
                style: theme.textTheme.labelSmall?.copyWith(color: Ds.muted)),
        ],
      ),
    );
  }
}
