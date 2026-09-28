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
  const AppSettings({this.voiceLang = VoiceLang.auto});
  final VoiceLang voiceLang;

  AppSettings copyWith({VoiceLang? voiceLang}) =>
      AppSettings(voiceLang: voiceLang ?? this.voiceLang);
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  static const _kVoiceLang = 'voice_lang';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs.getString(_kVoiceLang);
    return AppSettings(
      voiceLang: VoiceLang.values
          .firstWhere((v) => v.name == saved, orElse: () => VoiceLang.auto),
    );
  }

  Future<void> setVoiceLang(VoiceLang v) async {
    state = state.copyWith(voiceLang: v);
    await ref.read(sharedPreferencesProvider).setString(_kVoiceLang, v.name);
  }
}
