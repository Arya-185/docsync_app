import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/controller/settings_controller.dart';
import '../services/voice_service.dart';

/// A mic button that dictates into [controller] using on-device speech-to-text.
/// Optionally calls [onFinal] once a final transcript arrives.
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

class _MicButtonState extends ConsumerState<MicButton> {
  bool _listening = false;

  Future<void> _toggle() async {
    final voice = ref.read(voiceServiceProvider);
    if (_listening) {
      await voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await voice.start(
      localeId: ref.read(settingsControllerProvider).voiceLang.localeId,
      onResult: (text, isFinal) {
        if (!mounted) return;
        widget.controller.text = text;
        widget.controller.selection =
            TextSelection.collapsed(offset: text.length);
        if (isFinal) widget.onFinal?.call(text);
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

  @override
  Widget build(BuildContext context) {
    final icon = Icon(_listening ? Icons.mic : Icons.mic_none,
        color: _listening ? Colors.red : null);
    final onPressed = widget.enabled ? _toggle : null;
    return widget.filled
        ? IconButton.filledTonal(onPressed: onPressed, icon: icon)
        : IconButton(onPressed: onPressed, icon: icon);
  }
}
