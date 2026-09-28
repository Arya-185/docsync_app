import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/model/chat_models.dart';
import '../../chat/view/widgets/activity_trail.dart';
import '../../chat/view/widgets/chat_bubble.dart';
import '../../settings/controller/settings_controller.dart';
import '../controller/voice_session.dart';
import '../controller/wake_word.dart';
import 'widgets/mic_orb.dart';

/// The voice-first home: one big orb, what you said, what it is doing, and the answer — spoken.
///
/// A question asked here is an ordinary chat turn — [ChatController.send] — so it lands in
/// the same conversation, shows in Recent, and can be carried on in Chat. [VoiceSession] owns
/// the audio either side of it; everything in between is the chat's state, drawn bigger.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key, required this.onOpenChat});

  /// Switch to the Chat tab (the answer is already there).
  final VoidCallback onOpenChat;

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /* Voice is foreground-only: the mic and the speaker are released the moment the app is
     not on screen. A phone that keeps listening in someone's pocket is the one thing this
     feature must never do. */
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final away = s == AppLifecycleState.paused || s == AppLifecycleState.inactive ||
        s == AppLifecycleState.hidden;
    if (away) ref.read(voiceSessionProvider.notifier).cancel();
    ref.read(voiceForegroundProvider.notifier).setResumed(s == AppLifecycleState.resumed);
  }

  static const _suggestions = [
    'Which clients have pending GST filings?',
    'Remind me to call Amit Traders tomorrow at 11',
    'Show the latest invoice for a client',
  ];

  VoiceSession get _session => ref.read(voiceSessionProvider.notifier);

  void _clear() {
    if (ref.read(chatControllerProvider).sending) return;
    ref.read(chatControllerProvider.notifier).newChat();
    _session.reset();
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(voiceSessionProvider);
    ref.watch(wakeWordProvider); // keeps the wake-word listener alive while this screen exists
    final stopping = ref.watch(chatControllerProvider.select((s) => s.stopping));
    final mode = switch (v.phase) {
      VoicePhase.idle => OrbMode.idle,
      VoicePhase.listening => OrbMode.listening,
      VoicePhase.transcribing || VoicePhase.thinking => OrbMode.thinking,
      VoicePhase.speaking => OrbMode.speaking,
    };

    /* The question stays null until one is asked HERE, so a conversation opened from Recent
       does not suddenly appear on this screen as if it had been spoken. */
    return v.asked != null
        ? _ResultLayout(
            asked: v.asked!,
            note: v.note,
            mode: mode,
            level: v.level,
            stopping: stopping,
            onOrb: _session.tap,
            onOpenChat: widget.onOpenChat,
            onClear: _clear,
          )
        : _IdleLayout(
            note: v.note,
            mode: mode,
            level: v.level,
            onOrb: _session.tap,
            suggestions: _suggestions,
            onSuggestion: (s) => _session.ask(s,
                lang: ref.read(settingsControllerProvider).voiceLang.code),
          );
  }
}

class _IdleLayout extends StatelessWidget {
  const _IdleLayout({
    required this.note,
    required this.mode,
    required this.level,
    required this.onOrb,
    required this.suggestions,
    required this.onSuggestion,
  });

  final String? note;
  final OrbMode mode;
  final double level;
  final VoidCallback onOrb;
  final List<String> suggestions;
  final void Function(String) onSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listening = mode == OrbMode.listening;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Ds.s6),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(height: Ds.s4),
              Text(
                switch (mode) {
                  OrbMode.listening => 'Go ahead,\nI\'m listening',
                  OrbMode.thinking => 'One moment…',
                  _ => 'What can I do\nfor you today?',
                },
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(height: 1.25),
              ),
              const SizedBox(height: Ds.s2),
              MicOrb(mode: mode, level: level, onTap: onOrb),
              _StatusPill(mode: mode),
              if (note != null) _Note(text: note!),
              const SizedBox(height: Ds.s4),
              if (!listening) _Suggestions(items: suggestions, onTap: onSuggestion),
              const SizedBox(height: Ds.s4),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultLayout extends ConsumerWidget {
  const _ResultLayout({
    required this.asked,
    required this.note,
    required this.mode,
    required this.level,
    required this.stopping,
    required this.onOrb,
    required this.onOpenChat,
    required this.onClear,
  });

  final String asked;
  final String? note;
  final OrbMode mode;
  final double level;
  final bool stopping;
  final VoidCallback onOrb;
  final VoidCallback onOpenChat;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trail = ref.watch(chatControllerProvider
        .select((s) => (steps: s.trail, done: s.trailDone, elapsed: s.elapsed)));
    final ChatMessage? answer = ref.watch(chatControllerProvider.select((s) =>
        s.messages.isNotEmpty && !s.messages.last.isUser ? s.messages.last : null));
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, Ds.s2, 0, Ds.s4),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Ds.s5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text('“$asked”',
                          style: theme.textTheme.titleLarge?.copyWith(height: 1.3)),
                    ),
                    IconButton(
                      tooltip: 'New conversation',
                      onPressed: mode == OrbMode.thinking ? null : onClear,
                      icon: const Icon(Icons.refresh_rounded, color: Ds.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Ds.s3),
              ActivityTrail(steps: trail.steps, done: trail.done, elapsed: trail.elapsed),
              if (answer != null &&
                  (answer.content.isNotEmpty ||
                      answer.a2ui.isNotEmpty ||
                      answer.confirm != null ||
                      answer.citations.isNotEmpty))
                ChatBubble(message: answer),
              if (answer != null && !answer.streaming)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s2, Ds.s4, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onOpenChat,
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      label: const Text('Continue in Chat'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (note != null) _Note(text: note!),
        MicOrb(mode: mode, level: level, size: 76, onTap: onOrb),
        Padding(
          padding: const EdgeInsets.only(bottom: Ds.s3),
          child: _StatusPill(mode: mode, stopping: stopping, compact: true),
        ),
      ],
    );
  }
}

/// A one-line notice: "I didn't hear anything", or why voice is unavailable.
class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Ds.s6, Ds.s2, Ds.s6, 0),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Ds.muted)),
      );
}

/// "Listening…" / "Working on it — tap to stop" under the orb.
class _StatusPill extends ConsumerWidget {
  const _StatusPill({required this.mode, this.stopping = false, this.compact = false});
  final OrbMode mode;
  final bool stopping;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wakeState = ref.watch(wakeWordProvider);
    final wake = wakeState.status;
    final listenFor = ref.watch(voiceSessionProvider.select((v) => v.listenFor));
    final (String text, Color dot) = switch (mode) {
      OrbMode.listening => switch (listenFor) {
          ListenFor.question => ('Listening…  tap when done', Ds.red),
          ListenFor.followUp => ('Anything else? I\'m listening', Ds.red),
          ListenFor.confirm => ('Say yes or no', Ds.amber),
          ListenFor.outboundCancel => ('Say "cancel" to stop it', Ds.amber),
          ListenFor.choice => ('Say which one', Ds.amber),
        },
      OrbMode.idle when wake == WakeWordStatus.listening =>
        ('Say "${wakeState.phrase}" or tap the orb', Ds.green),
      OrbMode.thinking => (stopping ? 'Stopping…' : 'Working on it — tap to stop', Ds.blue),
      OrbMode.speaking => ('Speaking — tap to stop', Ds.indigo),
      OrbMode.idle => (compact ? 'Tap to ask a follow-up' : 'Tap the orb to speak', Ds.green),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Ds.rPill),
          boxShadow: Ds.cardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(text,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Ds.inkSoft, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.items, required this.onTap});
  final List<String> items;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You can also say',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: Ds.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: Ds.s2),
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(bottom: Ds.s2),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Ds.rChip),
              child: InkWell(
                borderRadius: BorderRadius.circular(Ds.rChip),
                onTap: () => onTap(s),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Ds.rChip),
                    border: Border.all(color: Ds.line),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Ds.blue),
                      const SizedBox(width: 10),
                      Expanded(child: Text('“$s”', style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
