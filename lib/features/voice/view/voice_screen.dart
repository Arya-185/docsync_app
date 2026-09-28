import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../shared/services/voice_service.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/model/chat_models.dart';
import '../../chat/view/widgets/activity_trail.dart';
import '../../chat/view/widgets/chat_bubble.dart';
import '../../settings/controller/settings_controller.dart';
import 'widgets/mic_orb.dart';

/// The voice-first home: one big orb, what you said, what it is doing, and the answer.
///
/// A question asked here is an ordinary chat turn — [ChatController.send] — so it lands in
/// the same conversation, shows in Recent, and can be carried on in Chat. This screen only
/// owns the listening; everything after the question is the chat's state, drawn bigger.
///
/// Listening is on-device dictation for now. The server speech path (Sarvam STT, spoken
/// replies, follow-up listening, wake word) replaces [VoiceService] behind this same UI.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key, required this.onOpenChat});

  /// Switch to the Chat tab (the answer is already there).
  final VoidCallback onOpenChat;

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  bool _listening = false;
  String _heard = '';
  double _level = 0;

  /// The question this screen last asked. Null until one is asked, so a conversation
  /// opened from Recent does not suddenly appear here as if it had been spoken.
  String? _asked;

  static const _suggestions = [
    'Which clients have pending GST filings?',
    'Remind me to call Amit Traders tomorrow at 11',
    'Show the latest invoice for a client',
  ];

  Future<void> _toggleListening() async {
    final voice = ref.read(voiceServiceProvider);
    final chat = ref.read(chatControllerProvider);
    if (chat.sending) {
      await ref.read(chatControllerProvider.notifier).stop();
      return;
    }
    if (_listening) {
      await voice.stop();
      return;
    }
    setState(() {
      _heard = '';
      _level = 0;
    });
    final ok = await voice.start(
      localeId: ref.read(settingsControllerProvider).voiceLang.localeId,
      // The recogniser reports roughly -2..10; the orb wants 0..1.
      onLevel: (l) {
        if (mounted) setState(() => _level = ((l + 2) / 12).clamp(0.0, 1.0));
      },
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _heard = text);
        if (isFinal) _ask(text);
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Microphone unavailable or permission denied.'),
      ));
      return;
    }
    setState(() => _listening = true);
  }

  Future<void> _ask(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final sent = await ref.read(chatControllerProvider.notifier).send(q);
    if (!mounted) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Still answering — tap the orb to stop it first.'),
      ));
    }
  }

  void _askTyped(String text) {
    setState(() {
      _asked = text;
      _heard = '';
    });
    _ask(text);
  }

  void _clear() {
    if (ref.read(chatControllerProvider).sending) return;
    ref.read(chatControllerProvider.notifier).newChat();
    setState(() {
      _asked = null;
      _heard = '';
    });
  }

  @override
  void dispose() {
    if (_listening) ref.read(voiceServiceProvider).cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A final transcript becomes the asked question the moment the turn starts.
    ref.listen(chatControllerProvider.select((s) => s.sending), (was, now) {
      if (now && _heard.isNotEmpty) {
        setState(() {
          _asked = _heard;
          _heard = '';
        });
      }
    });

    final sending = ref.watch(chatControllerProvider.select((s) => s.sending));
    final stopping = ref.watch(chatControllerProvider.select((s) => s.stopping));
    final mode = _listening
        ? OrbMode.listening
        : sending
            ? OrbMode.thinking
            : OrbMode.idle;

    final hasResult = _asked != null;
    return hasResult
        ? _ResultLayout(
            asked: _asked!,
            heard: _heard,
            mode: mode,
            level: _level,
            stopping: stopping,
            onOrb: _toggleListening,
            onOpenChat: widget.onOpenChat,
            onClear: _clear,
          )
        : _IdleLayout(
            heard: _heard,
            mode: mode,
            level: _level,
            onOrb: _toggleListening,
            suggestions: _suggestions,
            onSuggestion: _askTyped,
          );
  }
}

class _IdleLayout extends StatelessWidget {
  const _IdleLayout({
    required this.heard,
    required this.mode,
    required this.level,
    required this.onOrb,
    required this.suggestions,
    required this.onSuggestion,
  });

  final String heard;
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
                listening
                    ? (heard.isEmpty ? 'Go ahead, I\'m listening' : heard)
                    : 'What can I do\nfor you today?',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(height: 1.25),
              ),
              const SizedBox(height: Ds.s2),
              MicOrb(mode: mode, level: level, onTap: onOrb),
              _StatusPill(mode: mode),
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
    required this.heard,
    required this.mode,
    required this.level,
    required this.stopping,
    required this.onOrb,
    required this.onOpenChat,
    required this.onClear,
  });

  final String asked;
  final String heard;
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
    final listening = mode == OrbMode.listening;

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
        if (listening && heard.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Ds.s6),
            child: Text(heard,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: Ds.inkSoft)),
          ),
        MicOrb(mode: mode, level: level, size: 76, onTap: onOrb),
        Padding(
          padding: const EdgeInsets.only(bottom: Ds.s3),
          child: _StatusPill(mode: mode, stopping: stopping, compact: true),
        ),
      ],
    );
  }
}

/// "Listening…" / "Working on it — tap to stop" under the orb.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.mode, this.stopping = false, this.compact = false});
  final OrbMode mode;
  final bool stopping;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (String text, Color dot) = switch (mode) {
      OrbMode.listening => ('Listening…  tap to stop', Ds.red),
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
