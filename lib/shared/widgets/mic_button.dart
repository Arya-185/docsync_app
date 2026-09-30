import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../features/settings/controller/settings_controller.dart';
import '../../features/voice/controller/dictation.dart';
import '../../features/voice/model/speech_repository.dart';

/// A mic button that dictates into [controller]: tap, speak, and the words appear when you
/// stop talking (or tap again). Optionally calls [onFinal] with the text.
class MicButton extends ConsumerStatefulWidget {
  const MicButton({
    super.key,
    required this.controller,
    this.onFinal,
    this.filled = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onFinal;
  final bool filled;
  final bool enabled;

  @override
  ConsumerState<MicButton> createState() => _MicButtonState();
}

enum _Mic { idle, listening, transcribing }

class _MicButtonState extends ConsumerState<MicButton> {
  _Mic _state = _Mic.idle;
  double _level = 0;

  Future<void> _toggle() async {
    final d = ref.read(dictationProvider);
    if (_state == _Mic.listening) {
      d.finish();
      return;
    }
    if (_state == _Mic.transcribing || d.active) return;
    setState(() => _state = _Mic.listening);
    final base = widget.controller.text.trim();
    var shownPartial = false;
    String join(String words) => base.isEmpty ? words : '$base $words';
    void show(String text) {
      widget.controller.text = text;
      widget.controller.selection = TextSelection.collapsed(offset: text.length);
    }

    try {
      final text = await d.run(
        lang: ref.read(settingsControllerProvider).voiceLang.code,
        onLevel: (l) {
          if (mounted) setState(() => _level = l);
        },
        onTranscribing: () {
          if (mounted) setState(() => _state = _Mic.transcribing);
        },
        // The words so far, in the field, while the user is still talking.
        onPartial: (words) {
          if (!mounted) return;
          shownPartial = true;
          show(join(words));
        },
      );
      if (!mounted) return;
      if (text.isNotEmpty) {
        final joined = join(text);
        show(joined);
        widget.onFinal?.call(joined);
      } else if (shownPartial) {
        show(base); // a partial that came to nothing
      }
    } on SpeechException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.detail == 'permission'
              ? 'Allow the microphone to dictate.'
              : e.message),
        ));
      }
    } finally {
      if (mounted) setState(() => _state = _Mic.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.enabled ? _toggle : null;
    final Widget icon = switch (_state) {
      _Mic.idle => const Icon(Icons.mic_none_rounded),
      // The icon swells with the voice so it is obvious the phone is hearing you.
      _Mic.listening => Transform.scale(
          scale: 1 + 0.35 * _level,
          child: const Icon(Icons.mic_rounded, color: Ds.red),
        ),
      _Mic.transcribing => const SizedBox(
          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
    };
    final tip = switch (_state) {
      _Mic.idle => 'Dictate',
      _Mic.listening => 'Listening — tap when done',
      _Mic.transcribing => 'Writing it down…',
    };
    return widget.filled
        ? IconButton.filledTonal(tooltip: tip, onPressed: onPressed, icon: icon)
        : IconButton(tooltip: tip, onPressed: onPressed, icon: icon);
  }
}
