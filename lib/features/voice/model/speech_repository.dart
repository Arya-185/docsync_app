import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

/// Why a speech call failed, in terms the voice screen can act on. Mirrors the error codes of
/// the server proxy (app/ai_speech.php).
enum SpeechError {
  /// Signed out / session expired.
  auth,

  /// The firm does not have the Ask AI chat, or no speech key is configured on the server.
  unavailable,

  /// The speech account is out of credits or rate-limited — nothing the user can fix.
  quota,

  /// Nothing usable was recorded.
  noAudio,

  /// Network or upstream failure; worth trying again.
  failed,

  /// The phone's own (Google) recogniser is missing or broken; the server recogniser can
  /// hear the next utterance instead.
  recognizer,
}

class SpeechException implements Exception {
  SpeechException(this.error, [this.detail = '']);
  final SpeechError error;
  final String detail;

  /// A sentence for the screen (and, where it makes sense, for speaking).
  String get message => switch (error) {
        SpeechError.auth => 'Your session expired. Please sign in again.',
        SpeechError.unavailable => 'Voice isn\'t available for this company yet.',
        SpeechError.quota => 'Voice is out of credits right now. You can still type.',
        SpeechError.noAudio => 'I didn\'t hear anything.',
        SpeechError.failed => 'Voice didn\'t go through. Please try again.',
        SpeechError.recognizer => 'The phone\'s speech recogniser isn\'t working.',
      };

  @override
  String toString() => message;
}

class Transcript {
  const Transcript(this.text, this.languageCode);
  final String text;

  /// 'en-IN' / 'hi-IN', or '' when the recogniser was unsure.
  final String languageCode;
}

/// Speech-to-text and text-to-speech through the DocSync server, which holds the Sarvam key
/// (it never ships in the app). Same session cookie as every other call.
class SpeechRepository {
  SpeechRepository(this._api);
  final ApiClient _api;

  String get _endpoint => _api.url('/app/ai_speech.php');

  /// Transcribe a 16 kHz mono WAV. [lang] is a hint ('en-IN' / 'hi-IN'); null lets the
  /// server detect it (Hinglish included).
  Future<Transcript> transcribe(Uint8List wav, {String? lang, CancelToken? cancel}) async {
    final Response<dynamic> r;
    try {
      r = await _api.dio.post(
        _endpoint,
        data: FormData.fromMap({
          'action': 'stt',
          if (lang != null && lang.isNotEmpty) 'lang': lang,
          'audio': MultipartFile.fromBytes(wav, filename: 'speech.wav'),
        }),
        cancelToken: cancel,
        options: Options(receiveTimeout: const Duration(seconds: 50)),
      );
    } on DioException catch (e) {
      throw _fromDio(e);
    }
    final body = _json(r.data);
    if (r.statusCode != 200 || body == null || body['ok'] != true) {
      throw _fromStatus(r.statusCode, body);
    }
    return Transcript(
      (body['transcript'] ?? '').toString().trim(),
      (body['language_code'] ?? '').toString(),
    );
  }

  /// Speak [text]: returns MP3 bytes.
  Future<Uint8List> synthesize(String text,
      {String? lang, String? speaker, double pace = 1.0, CancelToken? cancel}) async {
    final Response<List<int>> r;
    try {
      r = await _api.dio.post<List<int>>(
        _endpoint,
        data: {
          'action': 'tts',
          'text': text,
          if (lang != null && lang.isNotEmpty) 'lang': lang,
          if (speaker != null && speaker.isNotEmpty) 'speaker': speaker,
          'pace': pace.toStringAsFixed(2),
        },
        cancelToken: cancel,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 50),
        ),
      );
    } on DioException catch (e) {
      throw _fromDio(e);
    }
    final bytes = Uint8List.fromList(r.data ?? const []);
    final type = r.headers.value(Headers.contentTypeHeader) ?? '';
    if (r.statusCode == 200 && type.startsWith('audio/') && bytes.isNotEmpty) return bytes;
    Map<String, dynamic>? body;
    try {
      body = _json(utf8.decode(bytes));
    } catch (_) {}
    throw _fromStatus(r.statusCode, body);
  }

  SpeechException _fromDio(DioException e) {
    if (CancelToken.isCancel(e)) return SpeechException(SpeechError.failed, 'cancelled');
    final code = e.response?.statusCode;
    return code != null ? _fromStatus(code, _json(e.response?.data)) : SpeechException(SpeechError.failed);
  }

  static SpeechException _fromStatus(int? status, Map<String, dynamic>? body) {
    final err = (body?['error'] ?? '').toString();
    switch (err) {
      case 'not_authenticated':
        return SpeechException(SpeechError.auth, err);
      case 'disabled':
      case 'speech_unavailable':
        return SpeechException(SpeechError.unavailable, err);
      case 'speech_quota':
        return SpeechException(SpeechError.quota, err);
      case 'no_audio':
      case 'audio_too_large':
      case 'empty_text':
        return SpeechException(SpeechError.noAudio, err);
    }
    return SpeechException(
      status == 401
          ? SpeechError.auth
          : status == 402
              ? SpeechError.quota
              : status == 403 || status == 503
                  ? SpeechError.unavailable
                  : SpeechError.failed,
      err,
    );
  }

  static Map<String, dynamic>? _json(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final d = jsonDecode(data);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }
}
