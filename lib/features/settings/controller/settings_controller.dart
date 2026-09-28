import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// The language the user speaks to the app in.
///
/// [auto] lets Sarvam's recogniser detect it. Hinglish is not a separate choice: it is what
/// the code-mixed mode handles under [auto]. The code is also sent with a voice turn so the
/// server can ask for a reply in the same language.
enum VoiceLang {
  auto('Automatic', null),
  english('English (India)', 'en-IN'),
  hindi('हिन्दी (Hindi)', 'hi-IN');

  const VoiceLang(this.label, this.code);
  final String label;

  /// BCP-47 code sent with a voice turn, or null for automatic.
  final String? code;
}

class AppSettings {
  const AppSettings({
    this.voiceLang = VoiceLang.auto,
    this.followUp = true,
    this.bargeIn = true,
    this.wakeWord = false,
    this.wakeSensitivity = 0.5,
  });
  final VoiceLang voiceLang;

  /// After a spoken reply, keep listening a few seconds for a follow-up without a tap.
  final bool followUp;

  /// While it talks, speaking over it interrupts (off = tap to interrupt only).
  final bool bargeIn;

  /// Listen for "Hey DocSync" while the app is open on the Voice tab.
  final bool wakeWord;

  /// 0..1; higher wakes more easily (and falsely more often).
  final double wakeSensitivity;

  AppSettings copyWith({
    VoiceLang? voiceLang,
    bool? followUp,
    bool? bargeIn,
    bool? wakeWord,
    double? wakeSensitivity,
  }) =>
      AppSettings(
        voiceLang: voiceLang ?? this.voiceLang,
        followUp: followUp ?? this.followUp,
        bargeIn: bargeIn ?? this.bargeIn,
        wakeWord: wakeWord ?? this.wakeWord,
        wakeSensitivity: wakeSensitivity ?? this.wakeSensitivity,
      );
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  static const _kVoiceLang = 'voice_lang';
  static const _kFollowUp = 'voice_follow_up';
  static const _kBargeIn = 'voice_barge_in';
  static const _kWakeWord = 'voice_wake_word';
  static const _kWakeSensitivity = 'voice_wake_sensitivity';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs.getString(_kVoiceLang);
    return AppSettings(
      voiceLang: VoiceLang.values
          .firstWhere((v) => v.name == saved, orElse: () => VoiceLang.auto),
      followUp: prefs.getBool(_kFollowUp) ?? true,
      bargeIn: prefs.getBool(_kBargeIn) ?? true,
      wakeWord: prefs.getBool(_kWakeWord) ?? false,
      wakeSensitivity: (prefs.getDouble(_kWakeSensitivity) ?? 0.5).clamp(0.0, 1.0),
    );
  }

  Future<void> setVoiceLang(VoiceLang v) async {
    state = state.copyWith(voiceLang: v);
    await ref.read(sharedPreferencesProvider).setString(_kVoiceLang, v.name);
  }

  Future<void> setFollowUp(bool v) async {
    state = state.copyWith(followUp: v);
    await ref.read(sharedPreferencesProvider).setBool(_kFollowUp, v);
  }

  Future<void> setBargeIn(bool v) async {
    state = state.copyWith(bargeIn: v);
    await ref.read(sharedPreferencesProvider).setBool(_kBargeIn, v);
  }

  Future<void> setWakeWord(bool v) async {
    state = state.copyWith(wakeWord: v);
    await ref.read(sharedPreferencesProvider).setBool(_kWakeWord, v);
  }

  Future<void> setWakeSensitivity(double v) async {
    state = state.copyWith(wakeSensitivity: v.clamp(0.0, 1.0));
    await ref.read(sharedPreferencesProvider).setDouble(_kWakeSensitivity, state.wakeSensitivity);
  }
}
