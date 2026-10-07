import 'package:flutter_tts/flutter_tts.dart';

class NarrativeAudioService {
  final FlutterTts _tts = FlutterTts();

  static const Map<String, String> _languageMap = {
    'en': 'en-US',
    'fil': 'fil-PH',
    'ko': 'ko-KR',
    'ja': 'ja-JP',
    'zh': 'zh-CN',
    'nl': 'nl-NL',
    'es': 'es-ES',
  };

  Future<void> speak({
    required String text,
    required String languageCode,
  }) async {
    final cleanedText = text.trim();

    if (cleanedText.isEmpty) {
      throw Exception('There is no narrative available for audio playback.');
    }

    await _tts.stop();
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    final requestedLanguage = _languageMap[languageCode] ?? 'en-US';

    final languageAvailable = await _tts.isLanguageAvailable(requestedLanguage);

    if (languageAvailable == true) {
      await _tts.setLanguage(requestedLanguage);
    } else {
      // Use English as a safe fallback when the selected
      // phone voice/language pack is not installed.
      await _tts.setLanguage('en-US');
    }

    final result = await _tts.speak(cleanedText);

    if (result != 1) {
      throw Exception('Your phone could not start the audio narration.');
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
