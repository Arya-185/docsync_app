import 'package:docsync_app/features/voice/model/device_tts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the phone voice picks the reply language', () {
    test('the language the user spoke wins', () {
      expect(DeviceSpeechPlayer.languageFor('You have 3 pending tasks.', 'hi-IN'), 'hi-IN');
    });

    test('automatic: Devanagari is spoken in Hindi', () {
      expect(DeviceSpeechPlayer.languageFor('आपके 3 काम बाकी हैं।', null), 'hi-IN');
    });

    test('automatic: anything else in Indian English', () {
      expect(DeviceSpeechPlayer.languageFor('Aapke 3 tasks pending hain.', null), 'en-IN');
      expect(DeviceSpeechPlayer.languageFor('Done.', ''), 'en-IN');
    });
  });
}
