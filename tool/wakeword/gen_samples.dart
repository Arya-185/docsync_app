// Generate "Hey DocSync" training clips in Indian voices with Sarvam text-to-speech.
//
//   SARVAM_API_KEY=sk_... dart run tool/wakeword/gen_samples.dart [out_dir] [--negatives]
//
// openWakeWord's training notebook makes its own synthetic positives with Piper voices, which
// are mostly American/European. The people saying this phrase will be Indian CA-office staff,
// so these clips — every Sarvam speaker, three paces, the spellings people actually say — are
// added as extra positives (see README.md). With --negatives it also writes near-miss phrases
// ("Hey Doc", "DocSync", "hey dog sink") that must NOT wake it.
//
// Output: 16 kHz mono 16-bit WAV, the format the trainer expects. Idempotent: a clip that
// already exists is skipped, so a rerun after a failure only fills the gaps.

import 'dart:convert';
import 'dart:io';

const speakers = [
  'shubh', 'anushka', 'manisha', 'vidya', 'arya', 'karun', 'hitesh', 'abhilash', 'aditya',
  'ritu', 'priya', 'neha', 'rahul', 'pooja', 'rohan', 'simran', 'kavya', 'amit', 'ishita',
  'shreya', 'varun', 'kabir', 'tanya', 'shruti', 'mohit',
];

const paces = [0.85, 1.0, 1.2];

/// (text, language) — how the phrase is written changes how the voice says it.
const positives = [
  ('Hey DocSync', 'en-IN'),
  ('Hey Doc Sync', 'en-IN'),
  ('Hey DocSync!', 'hi-IN'),
  ('हे डॉकसिंक', 'hi-IN'),
];

const negatives = [
  ('Hey Doc', 'en-IN'),
  ('DocSync', 'en-IN'),
  ('Hey dog sink', 'en-IN'),
  ('Hey Siri', 'en-IN'),
  ('Hey Jarvis', 'en-IN'),
  ('Okay docs', 'en-IN'),
  ('Hey, sync the docs', 'en-IN'),
  ('हे भगवान', 'hi-IN'),
];

Future<void> main(List<String> args) async {
  final key = Platform.environment['SARVAM_API_KEY'] ?? '';
  if (key.isEmpty) {
    stderr.writeln('Set SARVAM_API_KEY (the speech key; never commit it).');
    exit(2);
  }
  final withNegatives = args.contains('--negatives');
  final outDir = args.firstWhere((a) => !a.startsWith('--'), orElse: () => 'tool/wakeword/out');

  final client = HttpClient();
  var made = 0, skipped = 0, failed = 0;
  Future<void> run(String kind, List<(String, String)> phrases) async {
    final dir = Directory('$outDir/$kind')..createSync(recursive: true);
    for (var p = 0; p < phrases.length; p++) {
      final (text, lang) = phrases[p];
      for (final s in speakers) {
        for (final pace in paces) {
          final f = File('${dir.path}/${kind}_p${p}_${s}_${(pace * 100).round()}.wav');
          if (f.existsSync() && f.lengthSync() > 44) {
            skipped++;
            continue;
          }
          try {
            f.writeAsBytesSync(await _tts(client, key, text, lang, s, pace));
            made++;
          } catch (e) {
            failed++;
            stderr.writeln('  $s @$pace "$text": $e');
            if ('$e'.contains('402') || '$e'.contains('429')) {
              stderr.writeln('Out of credits / rate limited — stopping.');
              client.close();
              exit(1);
            }
          }
        }
      }
      stdout.writeln('$kind "$text": done');
    }
  }

  await run('positive', positives);
  if (withNegatives) await run('negative', negatives);
  client.close();
  stdout.writeln('made $made, skipped $skipped, failed $failed -> $outDir');
  exit(failed > 0 && made == 0 ? 1 : 0);
}

Future<List<int>> _tts(HttpClient c, String key, String text, String lang, String speaker, double pace) async {
  final req = await c.postUrl(Uri.parse('https://api.sarvam.ai/text-to-speech'));
  req.headers
    ..set('api-subscription-key', key)
    ..contentType = ContentType.json;
  req.write(jsonEncode({
    'text': text,
    'language_code': lang,
    'speaker': speaker,
    'model': 'bulbul:v3',
    'pace': pace,
    'speech_sample_rate': 16000,
    'output_audio_codec': 'wav',
  }));
  final res = await req.close();
  final body = await utf8.decodeStream(res);
  if (res.statusCode != 200) throw 'HTTP ${res.statusCode}: ${body.length > 160 ? body.substring(0, 160) : body}';
  final audios = (jsonDecode(body) as Map)['audios'] as List;
  return base64Decode(audios.first as String);
}
