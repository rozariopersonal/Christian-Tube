import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechRecognitionService {
  final SpeechToText _speech;
  bool _isAvailable = false;

  SpeechRecognitionService({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  bool get isAvailable => _isAvailable;
  bool get isListening => _speech.isListening;

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
  }) async {
    try {
      _isAvailable = await _speech.initialize(
        onStatus: onStatus,
        onError: onError,
        debugLogging: kDebugMode,
      );
      return _isAvailable;
    } catch (e) {
      debugPrint('SpeechRecognitionService: initialize error: $e');
      _isAvailable = false;
      return false;
    }
  }

  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevelChange,
    String? localeId,
  }) async {
    if (!_isAvailable) {
      final ok = await initialize();
      if (!ok) return;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        onSoundLevelChange: onSoundLevelChange,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } catch (e) {
      debugPrint('SpeechRecognitionService: listen error: $e');
    }
  }

  Future<void> stopListening() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint('SpeechRecognitionService: stop error: $e');
    }
  }

  Future<void> cancelListening() async {
    try {
      if (_speech.isListening) {
        await _speech.cancel();
      }
    } catch (e) {
      debugPrint('SpeechRecognitionService: cancel error: $e');
    }
  }
}
