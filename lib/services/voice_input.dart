import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Listening to what the person says, for voice search. A small interface so screens and tests do not
/// depend on the platform's speech service.
abstract class VoiceInput {
  /// Starts listening. [onWords] gets the words heard so far and whether that is the final result.
  /// False when speech recognition is not available (no service on the device, or the microphone or
  /// speech permission was refused); [onError] then says why in plain words.
  Future<bool> start({
    required void Function(String words, bool done) onWords,
    void Function(String message)? onError,
    String? localeId,
  });

  /// Ends listening and delivers what was heard as the final result.
  Future<void> stop();

  /// Ends listening and throws away what was heard.
  Future<void> cancel();
}

/// Where voice search may work at all: phones, tablets, Android TV and Google TV, Macs. (Fire TV remotes
/// use Alexa and the device has no speech service, which shows up as "not available" when tried.)
bool get voiceSearchPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// The device's own speech recognition, through the `speech_to_text` plugin.
class SpeechVoiceInput implements VoiceInput {
  final SpeechToText _speech = SpeechToText();
  void Function(String message)? _onError;

  @override
  Future<bool> start({
    required void Function(String words, bool done) onWords,
    void Function(String message)? onError,
    String? localeId,
  }) async {
    _onError = onError;
    try {
      final ok = await _speech.initialize(
          onError: (e) => _onError?.call(_explain(e.errorMsg)));
      if (!ok) {
        onError?.call(
            'Voice search is not available on this device, or the microphone is not allowed.');
        return false;
      }
      await _speech.listen(
        onResult: (r) => onWords(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 12),
          pauseFor: const Duration(seconds: 2),
          localeId: localeId,
          partialResults: true,
        ),
      );
      return true;
    } catch (_) {
      onError?.call('Voice search is not available on this device.');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  static String _explain(String code) => switch (code) {
        'error_no_match' ||
        'error_speech_timeout' =>
          'Nothing was heard. Try again.',
        'error_permission' =>
          'Allow the microphone for StreamBoss to use voice search.',
        'error_network' ||
        'error_network_timeout' =>
          'Voice search needs an internet connection.',
        _ => 'Voice search stopped ($code).',
      };
}
