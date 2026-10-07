import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'firebase_options.dart';

import 'core/constants/app_colors.dart';
import 'models/community_submission.dart';
import 'models/heritage_place.dart';
import 'models/journal_entry.dart';
import 'models/user_profile.dart';
import 'models/historical_content.dart';
import 'models/ai_narrative_record.dart';
import 'models/discovered_heritage_place.dart';
import 'models/navigation_route.dart';

import 'services/ai_image_service.dart';
import 'services/auth_service.dart';
import 'services/community_submission_service.dart';
import 'services/community_media_service.dart';
import 'services/journal_service.dart';
import 'services/heritage_site_service.dart';
import 'services/bookmark_service.dart';
import 'services/narrative_audio_service.dart';
import 'services/admin_analytics_service.dart';
import 'services/admin_report_service.dart';
import 'services/heritage_media_service.dart';
import 'services/knowledge_base_service.dart';
import 'services/ai_narrative_service.dart';
import 'services/language_service.dart';
import 'services/user_service.dart';
import 'services/heritage_discovery_service.dart';
import 'services/navigation_service.dart';

const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const String geminiModel = 'gemini-3.6-flash';
const String geminiImageModel = 'gemini-3.1-flash-image';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await GoogleSignIn.instance.initialize();
  await LanguageController.load();

  // Firestore becomes the source of truth after the Administrator
  // initializes the heritage_sites collection. Until then, the local
  // four-site development defaults remain available.
  await HeritageSiteService().initializeRuntimeSites();

  runApp(const HeritageBotApp());
}

class HeritageBotApp extends StatelessWidget {
  const HeritageBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeritageBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brown,
          primary: AppColors.brown,
          secondary: AppColors.gold,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.brown,
          foregroundColor: Colors.white,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class PlaceImageService {
  static final Map<String, List<String>> _cache = {};

  // STRICT MODE:
  // Only these manually verified Wikimedia Commons file titles are used.
  // This prevents wrong nearby photos, parade photos, logos, seals, and random search results.
  // If a place has fewer than 5 verified files, the carousel shows fewer correct photos instead
  // of forcing 5 inaccurate images.
  static const Map<String, List<String>> _verifiedCommonsFiles = {
    'uclm': [
      'File:Chooks Express! at the University Of Cebu Lapu-Lapu and Mandaue (2024-03-23).jpg',
      'File:Mister Donut at the University Of Cebu Lapu-Lapu and Mandaue (2024-03-23).jpg',
      'File:University-of-cebu-LM.jpg',
    ],
    'casa_gorordo': [
      'File:Night shot of Casa Gorordo.jpg',
      'File:Casa Gorordo Museum 10.jpg',
      'File:Casa Gorordo Museum (E. Aboitiz, Cebu City; 09-05-2022).jpg',
      "File:Suitor's Corner – Outside Casa Gorordo.jpg",
      'File:Casa Gorordo Cebu Philippines.jpg',
    ],
    'magellans_cross': [
      "File:Magellan's Cross, Cebu City.jpg",
      "File:Magellan's Cross Pavilion.jpg",
      "File:Magellan's Cross, Cebu.jpg",
    ],
    'fort_san_pedro': [
      'File:Fort San Pedro, Cebu City.jpg',
      'File:Fuerte de San Pedro Cebu.jpg',
      'File:Fort San Pedro, Cebu.jpg',
    ],
    'basilica_santo_nino': [
      'File:Basilica Minore del Santo Niño de Cebu.jpg',
      'File:Basilica del Santo Niño, Cebu City.jpg',
      'File:Basilica Minore del Santo Niño Cebu.jpg',
    ],
  };

  final Set<String> _addedFileKeys = <String>{};

  Future<List<String>> getPlaceImageUrls(
    HeritagePlace place, {
    int limit = 5,
  }) async {
    final cacheKey = '${place.id}-$limit-strict-v1';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final urls = <String>[];
    _addedFileKeys.clear();

    // Exact verified files only. Do NOT use geosearch/text search because it can return
    // nearby buildings, logos, seals, parades, or unrelated images.
    await _addExactWikimediaFiles(place, urls, limit);

    // Only when no verified file exists for a place, try the Wikipedia lead image.
    // This is safer than loose search but still not forced for places with verified files.
    if (urls.isEmpty && place.id != 'uclm') {
      await _addWikipediaSummaryImage(place, urls, 1);
    }

    final result = urls.take(limit).toList();
    _cache[cacheKey] = result;
    return result;
  }

  Future<void> _addExactWikimediaFiles(
    HeritagePlace place,
    List<String> urls,
    int limit,
  ) async {
    final titles = _verifiedCommonsFiles[place.id];
    if (titles == null || titles.isEmpty || urls.length >= limit) return;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'titles': titles.join('|'),
        'prop': 'imageinfo',
        'iiprop': 'url|mime',
        'iiurlwidth': '1200',
        'format': 'json',
        'origin': '*',
      });

      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'HeritageBot/1.0 (educational capstone app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final decoded = jsonDecode(response.body);
      _addImagesFromQueryPages(decoded, urls, limit, strictTitleFilter: false);
    } catch (_) {
      // Keep the app working even when Wikimedia is offline or slow.
    }
  }

  Future<void> _addGeotaggedCommonsImages(
    HeritagePlace place,
    List<String> urls,
    int limit,
  ) async {
    if (urls.length >= limit) return;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'geosearch',
        'ggscoord': '${place.lat}|${place.lng}',
        'ggsradius': '700',
        'ggsnamespace': '6',
        'ggslimit': '20',
        'prop': 'imageinfo',
        'iiprop': 'url|mime',
        'iiurlwidth': '1200',
        'format': 'json',
        'origin': '*',
      });

      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'HeritageBot/1.0 (educational capstone app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final decoded = jsonDecode(response.body);
      _addImagesFromQueryPages(decoded, urls, limit, strictTitleFilter: true);
    } catch (_) {
      // Ignore failed online image requests so the app still works offline.
    }
  }

  Future<void> _addWikipediaSummaryImage(
    HeritagePlace place,
    List<String> urls,
    int limit,
  ) async {
    final title = place.wikipediaTitle.trim();

    if (title.isEmpty || urls.length >= limit) return;

    try {
      final uri = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
      );

      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'HeritageBot/1.0 (educational capstone app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final decoded = jsonDecode(response.body);

      if (decoded is Map) {
        final originalImage = decoded['originalimage'];
        final thumbnail = decoded['thumbnail'];

        final originalSource = originalImage is Map
            ? originalImage['source']
            : null;
        final thumbnailSource = thumbnail is Map ? thumbnail['source'] : null;

        _safeAddImageUrl(
          urls,
          thumbnailSource ?? originalSource,
          limit,
          sourceKey: 'summary-${place.id}',
          title: place.wikipediaTitle,
          strictTitleFilter: true,
        );
      }
    } catch (_) {
      // Ignore failed online image requests so the app still works offline.
    }
  }

  Future<void> _addWikimediaCommonsImages({
    required String searchTerm,
    required List<String> urls,
    required int limit,
  }) async {
    if (searchTerm.trim().isEmpty || urls.length >= limit) return;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': '$searchTerm -logo -seal -emblem -icon',
        'gsrnamespace': '6',
        'gsrlimit': '20',
        'prop': 'imageinfo',
        'iiprop': 'url|mime',
        'iiurlwidth': '1200',
        'format': 'json',
        'origin': '*',
      });

      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'HeritageBot/1.0 (educational capstone app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final decoded = jsonDecode(response.body);
      _addImagesFromQueryPages(decoded, urls, limit, strictTitleFilter: true);
    } catch (_) {
      // Ignore failed online image requests so the app still works offline.
    }
  }

  void _addImagesFromQueryPages(
    dynamic decoded,
    List<String> urls,
    int limit, {
    required bool strictTitleFilter,
  }) {
    if (decoded is! Map) return;
    final query = decoded['query'];
    if (query is! Map) return;
    final pages = query['pages'];
    if (pages is! Map) return;

    for (final page in pages.values) {
      if (urls.length >= limit) break;
      if (page is! Map) continue;

      final title = page['title']?.toString() ?? '';
      final imageInfo = page['imageinfo'];
      if (imageInfo is! List || imageInfo.isEmpty) continue;

      final firstInfo = imageInfo.first;
      if (firstInfo is! Map) continue;

      final mime = firstInfo['mime']?.toString().toLowerCase() ?? '';
      if (!mime.startsWith('image/')) continue;
      if (mime.contains('svg')) continue;

      // Use only one URL per file to avoid duplicate carousel items.
      final thumbUrl = firstInfo['thumburl'];
      final originalUrl = firstInfo['url'];

      _safeAddImageUrl(
        urls,
        thumbUrl ?? originalUrl,
        limit,
        sourceKey: title,
        title: title,
        strictTitleFilter: strictTitleFilter,
      );
    }
  }

  void _safeAddImageUrl(
    List<String> urls,
    dynamic value,
    int limit, {
    required String sourceKey,
    required String title,
    required bool strictTitleFilter,
  }) {
    if (urls.length >= limit) return;
    if (value is! String) return;

    final url = value.trim();
    if (url.isEmpty) return;
    if (!_looksLikeImageUrl(url)) return;
    if (_isBlockedLogoOrSeal(title) || _isBlockedLogoOrSeal(url)) return;
    if (strictTitleFilter && _isLikelyNonPhoto(title, url)) return;

    final key = _normalizeFileKey(sourceKey.isEmpty ? url : sourceKey);
    if (_addedFileKeys.contains(key)) return;
    if (urls.contains(url)) return;

    _addedFileKeys.add(key);
    urls.add(url);
  }

  String _normalizeFileKey(String value) {
    return value
        .toLowerCase()
        .replaceAll('https://commons.wikimedia.org/wiki/', '')
        .replaceAll('https://upload.wikimedia.org/wikipedia/commons/thumb/', '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  bool _isBlockedLogoOrSeal(String value) {
    final lower = value.toLowerCase();
    return lower.contains('logo') ||
        lower.contains('seal') ||
        lower.contains('emblem') ||
        lower.contains('crest') ||
        lower.contains('badge') ||
        lower.contains('icon') ||
        lower.contains('.svg');
  }

  bool _isLikelyNonPhoto(String title, String url) {
    final combined = '$title $url'.toLowerCase();
    return combined.contains('map') ||
        combined.contains('diagram') ||
        combined.contains('marker') ||
        combined.contains('qr') ||
        combined.contains('symbol');
  }

  bool _looksLikeImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('https://') &&
        (lower.contains('.jpg') ||
            lower.contains('.jpeg') ||
            lower.contains('.png') ||
            lower.contains('.webp'));
  }
}

class GeminiStoryService {
  Future<String> generateContextAwareStory({
    required HeritagePlace place,
    required double distanceMeters,
    required double speedMetersPerSecond,
    required List<JournalEntry> memories,
    required AppLanguage preferredLanguage,
  }) async {
    if (geminiApiKey.isEmpty) {
      return _fallbackStory(
        place,
        distanceMeters,
        speedMetersPerSecond,
        memories,
        preferredLanguage,
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent',
    );

    final memoryText = memories.isEmpty
        ? 'The user has no saved memories for this place yet.'
        : memories.take(3).map((memory) => '- ${memory.letter}').join('\n');

    final speedText = speedMetersPerSecond < 1.2
        ? 'walking or staying nearby'
        : speedMetersPerSecond < 7
        ? 'slowly moving'
        : 'driving or moving fast';

    final targetLanguage = preferredLanguage.storyInstruction;

    final knowledgeBase = KnowledgeBaseService(geminiApiKey: geminiApiKey);

    final ragResult = await knowledgeBase.retrieveForSite(
      place: place,
      query:
          '${place.name} history cultural significance important events architecture local heritage',
    );

    final retrievedContext = ragResult.context.trim().isEmpty
        ? place.historicalFacts
        : ragResult.context.trim();

    final retrievedSources = ragResult.sourceTitles.isEmpty
        ? 'HeritageBot site record'
        : ragResult.sourceTitles.join('; ');

    final prompt =
        '''
You are HeritageBot, an AI-based historical narrative generator for Cebu heritage tourism.

Generate a context-aware story for the user.

Place: ${place.name}
Location: ${place.location}
Distance from user: ${(distanceMeters / 1000).toStringAsFixed(2)} km
User movement context: $speedText

RETRIEVED VERIFIED CONTEXT:
$retrievedContext

Retrieved source titles:
$retrievedSources

Saved personal memories from this user:
$memoryText

TARGET LANGUAGE: $targetLanguage

STRICT LANGUAGE RULES:
- Write the entire final answer only in $targetLanguage.
- Do not write English sentences unless the selected target language is English.
- Translate the title, location sentence, historical facts, and memory reminder into $targetLanguage.
- Do not include an English translation beside the target language.

Content requirements:
- Use simple, friendly words for tourists and students.
- Make it immersive and meaningful.
- Base historical claims only on the RETRIEVED VERIFIED CONTEXT above.
- Do not invent fake dates, names, events, or unsupported historical claims.
- If the retrieved context does not support a detail, leave that detail out.
- If the user has saved memories, connect them gently to the place without treating personal memories as verified historical facts.
- Keep it around 2 to 4 short paragraphs.
''';

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': geminiApiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.45, 'maxOutputTokens': 650},
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        debugPrint(
          'Gemini narrative generation failed: HTTP ${response.statusCode} ${response.body}',
        );
        return _fallbackStory(
          place,
          distanceMeters,
          speedMetersPerSecond,
          memories,
          preferredLanguage,
        );
      }

      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];

      if (text is String && text.trim().isNotEmpty) {
        final generatedNarrative = text.trim();

        try {
          await AiNarrativeService().recordGeneratedNarrative(
            siteId: place.id,
            siteName: place.name,
            narrative: generatedNarrative,
            languageCode: preferredLanguage.code,
            modelName: geminiModel,
            retrievalMode: ragResult.retrievalMode,
            retrievedContentIds: ragResult.documentIds,
            retrievedSourceTitles: ragResult.sourceTitles,
            distanceMeters: distanceMeters,
          );
        } catch (_) {
          // Narrative delivery should still succeed if logging is unavailable.
        }

        return generatedNarrative;
      }

      return _fallbackStory(
        place,
        distanceMeters,
        speedMetersPerSecond,
        memories,
        preferredLanguage,
      );
    } catch (error) {
      debugPrint('Gemini narrative generation error: $error');
      return _fallbackStory(
        place,
        distanceMeters,
        speedMetersPerSecond,
        memories,
        preferredLanguage,
      );
    }
  }

  Future<String> translateNarrative({
    required String narrative,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
  }) async {
    final cleanedNarrative = narrative.trim();

    if (cleanedNarrative.isEmpty) {
      throw Exception('There is no narrative available to translate.');
    }

    if (sourceLanguage.code == targetLanguage.code) {
      return cleanedNarrative;
    }

    if (geminiApiKey.isEmpty) {
      throw Exception(
        'The translation service is unavailable because the Gemini API key is missing.',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent',
    );

    final prompt =
        '''
You are the translation component of HeritageBot, an AI-based historical narrative generator.

Translate the heritage narrative below from ${sourceLanguage.storyInstruction} into ${targetLanguage.storyInstruction}.

STRICT TRANSLATION RULES:
- Return only the translated narrative.
- Preserve the meaning, historical facts, names, dates, place names, and paragraph structure.
- Do not add new historical facts, explanations, warnings, headings, citations, or commentary.
- Do not remove factual information from the original narrative.
- Keep the same friendly, simple storytelling tone.
- Write the entire output only in ${targetLanguage.storyInstruction}.

HERITAGE NARRATIVE:
$cleanedNarrative
''';

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': geminiApiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.15, 'maxOutputTokens': 900},
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        debugPrint(
          'Gemini narrative translation failed: HTTP ${response.statusCode} ${response.body}',
        );
        throw Exception(
          'HeritageBot could not translate the narrative right now. Please try again.',
        );
      }

      final data = jsonDecode(response.body);
      final translatedText =
          data['candidates']?[0]?['content']?['parts']?[0]?['text'];

      if (translatedText is String && translatedText.trim().isNotEmpty) {
        return translatedText.trim();
      }

      throw Exception(
        'HeritageBot did not receive a translated narrative. Please try again.',
      );
    } catch (error) {
      debugPrint('Gemini narrative translation error: $error');

      if (error is Exception) {
        rethrow;
      }

      throw Exception(
        'HeritageBot could not translate the narrative right now. Please try again.',
      );
    }
  }

  String _fallbackStory(
    HeritagePlace place,
    double distanceMeters,
    double speedMetersPerSecond,
    List<JournalEntry> memories,
    AppLanguage preferredLanguage,
  ) {
    final distanceKm = (distanceMeters / 1000).toStringAsFixed(2);
    final fact = _localizedFact(place, preferredLanguage.code);
    final hasMemory = memories.isNotEmpty;

    switch (preferredLanguage.code) {
      case 'fil':
        final movement = speedMetersPerSecond < 1.2
            ? 'Mukhang naglalakad ka o nananatili malapit sa lugar na ito.'
            : speedMetersPerSecond < 7
            ? 'Mukhang dahan-dahan kang gumagalaw malapit sa lugar na ito.'
            : 'Mukhang dumadaan ka sa lugar na ito habang mabilis na gumagalaw.';
        final memoryLine = hasMemory
            ? 'Mayroon kang naka-save na alaala tungkol sa lugar na ito, kaya matutulungan ka ng HeritageBot na balikan ang iyong dating karanasan habang muli mo itong binibisita.'
            : 'Wala ka pang naka-save na alaala para sa lugar na ito, ngunit maaari kang magdagdag ng personal na sulat, larawan, o video upang maging mas makabuluhan ang iyong susunod na pagbisita.';
        return '''Kuwento ng Pamana Batay sa Iyong Lokasyon

Malapit ka ngayon sa ${place.name}, na matatagpuan sa ${place.location}. Ito ay humigit-kumulang $distanceKm km mula sa iyong kasalukuyang lokasyon. $movement

$fact

$memoryLine''';

      case 'ko':
        final movement = speedMetersPerSecond < 1.2
            ? '현재 이 지역 근처를 걷고 있거나 머무르고 있는 것으로 보입니다.'
            : speedMetersPerSecond < 7
            ? '현재 이 장소 근처에서 천천히 이동하고 있는 것으로 보입니다.'
            : '현재 빠르게 이동하면서 이 지역을 지나가고 있는 것으로 보입니다.';
        final memoryLine = hasMemory
            ? '이 장소와 연결된 저장된 추억이 있으므로, HeritageBot은 다시 방문하는 동안 이전 경험을 떠올릴 수 있도록 도와줍니다.'
            : '아직 이 장소에 저장된 추억이 없습니다. 다음 방문을 더 의미 있게 만들기 위해 개인적인 글, 사진 또는 영상을 추가할 수 있습니다.';
        return '''위치 기반 문화유산 이야기

현재 ${place.location}에 있는 ${place.name} 근처에 있습니다. 현재 위치에서 약 $distanceKm km 떨어져 있습니다. $movement

$fact

$memoryLine''';

      case 'ja':
        final movement = speedMetersPerSecond < 1.2
            ? 'この地域の近くを歩いている、または滞在しているようです。'
            : speedMetersPerSecond < 7
            ? 'この場所の近くをゆっくり移動しているようです。'
            : '速い速度でこの地域を通過しているようです。';
        final memoryLine = hasMemory
            ? 'この場所に関連する保存済みの思い出があります。HeritageBotは、再び訪れるときに以前の体験を思い出す手助けをします。'
            : 'この場所にはまだ保存された思い出がありません。次の訪問をより意味のあるものにするために、手紙、写真、または動画を追加できます。';
        return '''位置情報に基づく文化遺産ストーリー

あなたは現在、${place.location}にある${place.name}の近くにいます。現在地から約$distanceKm km離れています。$movement

$fact

$memoryLine''';

      case 'zh':
        final movement = speedMetersPerSecond < 1.2
            ? '你似乎正在这个区域附近步行或停留。'
            : speedMetersPerSecond < 7
            ? '你似乎正在这个地点附近缓慢移动。'
            : '你似乎正在快速经过这个区域。';
        final memoryLine = hasMemory
            ? '你已经保存了与这个地点相关的回忆，因此 HeritageBot 可以在你再次探索这里时帮助你回顾之前的经历。'
            : '你还没有为这个地点保存回忆，但你可以添加个人文字、照片或视频，让下一次参观更有意义。';
        return '''基于位置的文化遗产故事

你现在靠近位于${place.location}的${place.name}。它距离你当前的位置约 $distanceKm 公里。$movement

$fact

$memoryLine''';

      case 'nl':
        final movement = speedMetersPerSecond < 1.2
            ? 'Je lijkt in de buurt van dit gebied te wandelen of te blijven.'
            : speedMetersPerSecond < 7
            ? 'Je lijkt langzaam in de buurt van deze plaats te bewegen.'
            : 'Je lijkt dit gebied snel te passeren.';
        final memoryLine = hasMemory
            ? 'Je hebt herinneringen opgeslagen die verbonden zijn met deze plaats, zodat HeritageBot je kan helpen je eerdere bezoek opnieuw te beleven.'
            : 'Je hebt nog geen herinneringen voor deze plaats opgeslagen, maar je kunt een persoonlijke tekst, foto of video toevoegen om je volgende bezoek betekenisvoller te maken.';
        return '''Locatiebewust erfgoedverhaal

Je bent in de buurt van ${place.name}, gelegen aan ${place.location}. Het is ongeveer $distanceKm km verwijderd van je huidige locatie. $movement

$fact

$memoryLine''';

      case 'es':
        final movement = speedMetersPerSecond < 1.2
            ? 'Parece que estás caminando o permaneciendo cerca de esta zona.'
            : speedMetersPerSecond < 7
            ? 'Parece que te estás moviendo lentamente cerca de este lugar.'
            : 'Parece que estás pasando rápidamente por esta zona.';
        final memoryLine = hasMemory
            ? 'Tienes recuerdos guardados relacionados con este lugar, por lo que HeritageBot puede ayudarte a recordar tu visita anterior mientras lo exploras de nuevo.'
            : 'Aún no tienes recuerdos guardados para este lugar, pero puedes agregar una carta personal, una foto o un video para que tu próxima visita sea más significativa.';
        return '''Historia patrimonial basada en tu ubicación

Estás cerca de ${place.name}, ubicado en ${place.location}. Se encuentra aproximadamente a $distanceKm km de tu ubicación actual. $movement

$fact

$memoryLine''';

      default:
        final movement = speedMetersPerSecond < 1.2
            ? 'You seem to be walking or staying near this area.'
            : speedMetersPerSecond < 7
            ? 'You seem to be slowly moving near this place.'
            : 'You seem to be passing by this area while moving fast.';
        final memoryLine = hasMemory
            ? 'You have saved memories connected to this place, so HeritageBot can help you remember your previous visit while exploring it again.'
            : 'You do not have saved memories for this place yet, but you can add a personal letter, picture, or video to make your next visit more meaningful.';
        return '''Context-Aware Heritage Story

You are near ${place.name}, located in ${place.location}. It is around $distanceKm km from your current position. $movement

$fact

$memoryLine''';
    }
  }

  String _localizedFact(HeritagePlace place, String code) {
    final facts = <String, Map<String, String>>{
      'uclm': {
        'fil':
            'Ang University of Cebu Lapu-Lapu and Mandaue, na kilala rin bilang UCLM, ay isang institusyong pang-edukasyon sa A.C. Cortes Avenue sa Mandaue City. Mahalaga ito para sa mga estudyante, alumni, pamilya, at bisita dahil iniuugnay nito ang edukasyon, personal na pag-unlad, pagkakaibigan, at mga alaala sa paaralan.',
        'ko':
            'University of Cebu Lapu-Lapu and Mandaue, 또는 UCLM은 만다우에 시의 A.C. Cortes Avenue에 위치한 교육 기관입니다. 이곳은 교육, 개인적 성장, 우정, 학교생활의 추억을 연결하기 때문에 학생, 동문, 가족, 방문객에게 의미 있는 장소입니다.',
        'ja':
            'University of Cebu Lapu-Lapu and Mandaue、通称UCLMは、マンダウエ市のA.C. Cortes Avenue沿いにある教育機関です。教育、個人の成長、友情、学校での思い出を結びつける場所として、学生、卒業生、家族、訪問者にとって意味のある場所です。',
        'zh':
            '宿务大学拉普拉普和曼达维校区，也称为 UCLM，是位于曼达维市 A.C. Cortes Avenue 的一所教育机构。它对学生、校友、家庭和访客都具有意义，因为这里承载着教育、个人成长、友谊和校园回忆。',
        'nl':
            'De University of Cebu Lapu-Lapu and Mandaue, ook bekend als UCLM, is een onderwijsinstelling aan A.C. Cortes Avenue in Mandaue City. De plaats is betekenisvol voor studenten, alumni, families en bezoekers omdat zij onderwijs, persoonlijke groei, vriendschappen en schoolherinneringen met elkaar verbindt.',
        'es':
            'La University of Cebu Lapu-Lapu and Mandaue, también conocida como UCLM, es una institución educativa ubicada en A.C. Cortes Avenue, en la ciudad de Mandaue. Es un lugar significativo para estudiantes, exalumnos, familias y visitantes porque conecta la educación, el crecimiento personal, las amistades y los recuerdos escolares.',
      },
      'magellans_cross': {
        'fil':
            'Ang Magellan’s Cross ay isa sa pinakakilalang palatandaan sa Cebu. Ito ay kaugnay ng pagdating ng Kristiyanismo sa Pilipinas at mahalagang simbolo ng kasaysayan, pananampalataya, at turismo ng Cebu.',
        'ko':
            '마젤란의 십자가는 세부에서 가장 잘 알려진 랜드마크 중 하나입니다. 필리핀에 기독교가 전래된 역사와 관련이 있으며, 세부의 역사, 신앙, 관광을 상징하는 중요한 장소입니다.',
        'ja':
            'マゼラン・クロスは、セブで最もよく知られたランドマークの一つです。フィリピンへのキリスト教伝来と結びついており、セブの歴史、信仰、観光を象徴する重要な場所です。',
        'zh': '麦哲伦十字架是宿务最知名的地标之一。它与基督教传入菲律宾的历史有关，是宿务历史、信仰和旅游的重要象征。',
        'nl':
            'Magellan’s Cross is een van de bekendste bezienswaardigheden van Cebu. Het wordt verbonden met de komst van het christendom in de Filipijnen en is een belangrijk symbool van Cebuano geschiedenis, geloof en toerisme.',
        'es':
            'La Cruz de Magallanes es uno de los monumentos más reconocidos de Cebú. Está asociada con la llegada del cristianismo a Filipinas y es un símbolo importante de la historia, la fe y el turismo cebuano.',
      },
      'cebu_heritage_monument': {
        'fil':
            'Ang Heritage of Cebu Monument sa Pari-an ay isang malaking eskulturang naglalarawan ng mahahalagang pangyayari, tao, at simbolo sa kasaysayan ng Cebu. Nilikha ito ni Eduardo Castrillo at nagsisilbing biswal na pagpapakilala sa makasaysayang pag-unlad ng Cebu.',
        'ko':
            '파리안의 Heritage of Cebu Monument는 세부 역사에서 중요한 사건, 인물, 상징을 묘사한 대형 조각 기념물입니다. 조각가 Eduardo Castrillo가 제작했으며 세부의 역사적 발전을 시각적으로 소개합니다.',
        'ja':
            'パリアンにある Heritage of Cebu Monument は、セブの歴史における重要な出来事、人物、象徴を表した大規模な彫刻記念碑です。彫刻家 Eduardo Castrillo によって制作され、セブの歴史的発展を視覚的に紹介しています。',
        'zh':
            '位于帕里安的宿务遗产纪念碑是一座大型雕塑群，描绘了宿务历史上的重要事件、人物和象征。该纪念碑由雕塑家 Eduardo Castrillo 创作，以视觉方式呈现宿务的历史发展。',
        'nl':
            'Het Heritage of Cebu Monument in Pari-an is een groot sculpturaal monument dat belangrijke gebeurtenissen, personen en symbolen uit de geschiedenis van Cebu uitbeeldt. Het werd gemaakt door beeldhouwer Eduardo Castrillo en biedt een visuele kennismaking met de historische ontwikkeling van Cebu.',
        'es':
            'El Heritage of Cebu Monument de Pari-an es un gran conjunto escultórico que representa acontecimientos, personajes y símbolos importantes de la historia de Cebú. Fue creado por el escultor Eduardo Castrillo y ofrece una introducción visual al desarrollo histórico de Cebú.',
      },
      'fort_san_pedro': {
        'fil':
            'Ang Fort San Pedro ay isang estrukturang pandepensa mula sa panahon ng kolonyalismong Espanyol sa Cebu City. Ginamit ito bilang kuta noong panahon ng kolonyalismo at ngayon ay pinangangalagaan bilang pook-pamana at destinasyong panturismo.',
        'ko':
            '산 페드로 요새는 세부 시에 있는 스페인 식민지 시대의 군사 방어 시설입니다. 과거에는 방어 요새로 사용되었으며, 현재는 문화유산 및 관광지로 보존되고 있습니다.',
        'ja':
            'サン・ペドロ要塞は、セブ市にあるスペイン植民地時代の軍事防衛施設です。植民地時代には要塞として使われ、現在は文化遺産および観光地として保存されています。',
        'zh': '圣佩德罗堡是宿务市的一座西班牙殖民时期军事防御建筑。它曾作为防御堡垒使用，如今被保存为文化遗产和旅游景点。',
        'nl':
            'Fort San Pedro is een Spaans-koloniale militaire verdedigingsstructuur in Cebu City. Het diende vroeger als fortificatie en wordt tegenwoordig bewaard als erfgoed- en toeristische locatie.',
        'es':
            'El Fuerte de San Pedro es una estructura militar defensiva de la época colonial española en la ciudad de Cebú. Sirvió como fortificación durante el período colonial y actualmente se conserva como sitio patrimonial y turístico.',
      },
      'basilica_santo_nino': {
        'fil':
            'Ang Basilica Minore del Santo Niño ay isa sa pinakamatandang simbahang Katoliko Romano sa Pilipinas. Malapit itong kaugnay ng debosyon sa Santo Niño, pananampalatayang Cebuano, at pagdiriwang ng Sinulog.',
        'ko':
            '산토 니뇨 성당은 필리핀에서 가장 오래된 로마 가톨릭 성당 중 하나입니다. 산토 니뇨 신앙, 세부아노의 경건함, 그리고 시눌로그 축제와 깊이 연결되어 있습니다.',
        'ja':
            'サント・ニーニョ聖堂は、フィリピンで最も古いローマ・カトリック教会の一つです。サント・ニーニョへの信仰、セブアノの信心、シヌログ祭りと深く結びついています。',
        'zh': '圣婴圣殿是菲律宾最古老的罗马天主教堂之一。它与宿务人对圣婴的虔诚信仰以及 Sinulog 节庆紧密相连。',
        'nl':
            'De Basilica Minore del Santo Niño is een van de oudste rooms-katholieke kerken in de Filipijnen. De kerk is nauw verbonden met de verering van de Santo Niño en het Sinulog-festival.',
        'es':
            'La Basílica Menor del Santo Niño es una de las iglesias católicas romanas más antiguas de Filipinas. Está estrechamente relacionada con la devoción al Santo Niño y la celebración del Sinulog.',
      },
      'casa_gorordo': {
        'fil':
            'Ipinapakita ng Casa Gorordo Museum ang pamumuhay ng isang pamilyang Cebuano noong panahon ng kolonyalismong Espanyol. Pinangangalagaan nito ang mga antigong kasangkapan, relihiyosong bagay, at materyales na nagpapakita ng dating pamumuhay sa Cebu.',
        'ko':
            '카사 고로르도 박물관은 스페인 식민지 시대 세부아노 가정의 생활 방식을 보여줍니다. 오래된 가구, 종교적 물건, 생활용품을 보존하여 옛 세부의 문화를 전합니다.',
        'ja':
            'カーサ・ゴロルド博物館は、スペイン植民地時代のセブアノ家族の暮らしを紹介しています。古い家具、宗教的な品々、生活用品を保存し、昔のセブの文化を伝えています。',
        'zh': '卡萨戈罗多博物馆展示了西班牙殖民时期宿务家庭的生活方式。馆内保存着古董家具、宗教物品和生活用品，展现了旧时宿务人的日常生活。',
        'nl':
            'Het Casa Gorordo Museum toont de levensstijl van een Cebuano familie tijdens de Spaanse koloniale periode. Het bewaart antieke meubels, religieuze voorwerpen en huishoudelijke materialen die het vroegere leven in Cebu laten zien.',
        'es':
            'El Museo Casa Gorordo muestra el estilo de vida de una familia cebuana durante el período colonial español. Conserva muebles antiguos, objetos religiosos y materiales domésticos que muestran cómo vivían las familias antiguas de Cebú.',
      },
    };

    return facts[place.id]?[code] ?? place.historicalFacts;
  }
}

class LocationService {
  Future<void> ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) {
      throw Exception('Please turn on your GPS/location service.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Enable it in app settings.',
      );
    }
  }

  Future<Position> getCurrentPosition() async {
    await ensurePermission();

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
  }

  Stream<Position> getLivePositionStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  double distanceToPlace(Position position, HeritagePlace place) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      place.lat,
      place.lng,
    );
  }

  HeritagePlace nearestPlace(Position position) {
    final sorted = [...heritagePlaces];

    sorted.sort(
      (a, b) =>
          distanceToPlace(position, a).compareTo(distanceToPlace(position, b)),
    );

    return sorted.first;
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brown,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.deepBrown, AppColors.brown, AppColors.clay],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.travel_explore_rounded, size: 92, color: AppColors.gold),
            SizedBox(height: 18),
            Text(
              'HeritageBot',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 40,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'AI-Based Historical Narrative\nand Memory Companion',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                height: 1.4,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 34),
            CircularProgressIndicator(color: AppColors.gold),
          ],
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final userService = UserService();

    return StreamBuilder<User?>(
      stream: authService.authChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginSignupScreen();
        }

        if (authService.needsEmailVerification(user)) {
          return EmailVerificationScreen(email: user.email ?? '');
        }

        return FutureBuilder<UserProfile?>(
          future: userService.getUserProfile(user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingScreen();
            }

            if (profileSnapshot.hasError) {
              return RoleLoadErrorScreen(
                message: profileSnapshot.error.toString(),
              );
            }

            final profile = profileSnapshot.data;

            if (profile == null || !UserRoles.isValidRole(profile.role)) {
              return RoleSetupScreen(firebaseUser: user);
            }

            if (profile.accountStatus.toLowerCase() != 'active') {
              return AccountStatusScreen(profile: profile);
            }

            switch (profile.role) {
              case UserRoles.admin:
                return AdminDashboardScreen(profile: profile);
              case UserRoles.communityContributor:
                return const MainShell(
                  userRole: UserRoles.communityContributor,
                );
              case UserRoles.tourist:
              default:
                return const MainShell(userRole: UserRoles.tourist);
            }
          },
        );
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class RoleLoadErrorScreen extends StatelessWidget {
  final String message;

  const RoleLoadErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Error')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const InfoCard(
            icon: Icons.cloud_off_rounded,
            title: 'Could Not Load Account Profile',
            body:
                'HeritageBot could not load your account role from Cloud Firestore. Check your internet connection and try again.',
          ),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              await AuthService().logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Return to Login'),
            style: mainButtonStyle(),
          ),
        ],
      ),
    );
  }
}

class AccountStatusScreen extends StatelessWidget {
  final UserProfile profile;

  const AccountStatusScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Status')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          InfoCard(
            icon: Icons.manage_accounts_rounded,
            title: 'Account ${profile.accountStatus}',
            body:
                'This account is currently marked as "${profile.accountStatus}". Please contact the HeritageBot administrator if you believe this is incorrect.',
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              await AuthService().logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
            style: mainButtonStyle(),
          ),
        ],
      ),
    );
  }
}

class RoleSetupScreen extends StatefulWidget {
  final User firebaseUser;

  const RoleSetupScreen({super.key, required this.firebaseUser});

  @override
  State<RoleSetupScreen> createState() => _RoleSetupScreenState();
}

class _RoleSetupScreenState extends State<RoleSetupScreen> {
  final UserService _userService = UserService();
  late final TextEditingController fullNameController;

  String selectedRole = UserRoles.tourist;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    fullNameController = TextEditingController(
      text: widget.firebaseUser.displayName ?? '',
    );
  }

  @override
  void dispose() {
    fullNameController.dispose();
    super.dispose();
  }

  Future<void> saveRole() async {
    final fullName = fullNameController.text.trim();

    if (fullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your full name.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => saving = true);

    try {
      await _userService.savePublicProfile(
        firebaseUser: widget.firebaseUser,
        fullName: fullName,
        role: selectedRole,
        preferredLanguage: LanguageController.current.value.code,
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Account Type')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionTitle(
            title: 'Complete Your HeritageBot Profile',
            subtitle:
                'Choose whether you will use HeritageBot as a Tourist or Community Contributor.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: fullNameController,
            decoration: inputDecoration(
              label: 'Full Name',
              icon: Icons.person_rounded,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: selectedRole,
            decoration: inputDecoration(
              label: 'Account Type',
              icon: Icons.badge_rounded,
            ),
            items: const [
              DropdownMenuItem(
                value: UserRoles.tourist,
                child: Text('Tourist'),
              ),
              DropdownMenuItem(
                value: UserRoles.communityContributor,
                child: Text('Community Contributor'),
              ),
            ],
            onChanged: saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => selectedRole = value);
                  },
          ),
          const SizedBox(height: 12),
          const InfoCard(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Administrator Accounts',
            body:
                'Administrator accounts are not available through public registration. They are assigned only by the authorized system manager.',
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: saving ? null : saveRole,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(saving ? 'Saving...' : 'Save Account Type'),
            style: mainButtonStyle(),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: saving
                ? null
                : () async {
                    await AuthService().logout();
                  },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Use Another Account'),
          ),
        ],
      ),
    );
  }
}

class ContributorDashboardScreen extends StatefulWidget {
  const ContributorDashboardScreen({super.key});

  @override
  State<ContributorDashboardScreen> createState() =>
      _ContributorDashboardScreenState();
}

class _ContributorDashboardScreenState
    extends State<ContributorDashboardScreen> {
  final CommunitySubmissionService _submissionService =
      CommunitySubmissionService();
  final CommunityMediaService _mediaService = CommunityMediaService();

  late Future<List<CommunitySubmission>> _submissionsFuture;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  void _loadSubmissions() {
    _submissionsFuture = _submissionService.getMySubmissions();
  }

  Future<void> _refresh() async {
    setState(_loadSubmissions);
    await _submissionsFuture;
  }

  Future<void> _openSubmitScreen() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SubmitCommunityStoryScreen()),
    );

    if (created == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _editSubmission(CommunitySubmission submission) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCommunityStoryScreen(submission: submission),
      ),
    );

    if (updated == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _deleteSubmission(CommunitySubmission submission) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Submission?'),
          content: Text(
            'Delete "${submission.title}"? Only pending submissions can be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      await _mediaService.deleteMediaUrls([
        ...submission.imageUrls,
        ...submission.videoUrls,
      ]);
      await _submissionService.deletePendingSubmission(submission);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submission deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await _refresh();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Bad state: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case CommunitySubmissionStatus.approved:
        return Icons.check_circle_rounded;
      case CommunitySubmissionStatus.rejected:
        return Icons.cancel_rounded;
      case CommunitySubmissionStatus.pending:
      default:
        return Icons.schedule_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Contributor'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSubmitScreen,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Submit Story'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<CommunitySubmission>>(
          future: _submissionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  const InfoCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could Not Load Submissions',
                    body:
                        'HeritageBot could not load your community story submissions from Cloud Firestore.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              );
            }

            final submissions = snapshot.data ?? const [];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
              children: [
                const SectionTitle(
                  title: 'Community Contributions',
                  subtitle:
                      'Submit local heritage stories for administrator review and track whether they are Pending, Approved, or Rejected.',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openSubmitScreen,
                    icon: const Icon(Icons.history_edu_rounded),
                    label: const Text('Submit Heritage Story'),
                    style: mainButtonStyle(),
                  ),
                ),
                const SizedBox(height: 22),
                const SectionTitle(
                  title: 'My Submissions',
                  subtitle:
                      'Administrator feedback will appear here after review.',
                ),
                const SizedBox(height: 12),
                if (submissions.isEmpty)
                  const InfoCard(
                    icon: Icons.inbox_rounded,
                    title: 'No Submissions Yet',
                    body:
                        'Tap Submit Heritage Story to send your first local heritage contribution.',
                  )
                else
                  ...submissions.map(
                    (submission) => Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _statusIcon(submission.status),
                                  color: AppColors.brown,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        submission.title,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.deepBrown,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        submission.heritagePlaceName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    CommunitySubmissionStatus.label(
                                      submission.status,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.brown,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              submission.story,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(height: 1.45),
                            ),
                            if (submission.imageUrls.isNotEmpty ||
                                submission.videoUrls.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  if (submission.imageUrls.isNotEmpty)
                                    _AttachmentCount(
                                      icon: Icons.photo_library_rounded,
                                      label:
                                          '${submission.imageUrls.length} photo${submission.imageUrls.length == 1 ? '' : 's'}',
                                    ),
                                  if (submission.videoUrls.isNotEmpty)
                                    _AttachmentCount(
                                      icon: Icons.video_library_rounded,
                                      label:
                                          '${submission.videoUrls.length} video${submission.videoUrls.length == 1 ? '' : 's'}',
                                    ),
                                ],
                              ),
                            ],
                            if (submission.adminFeedback.trim().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.bg,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  'Admin Feedback: ${submission.adminFeedback}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            if (submission.status ==
                                CommunitySubmissionStatus.pending) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () =>
                                        _editSubmission(submission),
                                    icon: const Icon(Icons.edit_rounded),
                                    label: const Text('Edit'),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton.icon(
                                    onPressed: () =>
                                        _deleteSubmission(submission),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    label: const Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class EditCommunityStoryScreen extends StatefulWidget {
  final CommunitySubmission submission;

  const EditCommunityStoryScreen({super.key, required this.submission});

  @override
  State<EditCommunityStoryScreen> createState() =>
      _EditCommunityStoryScreenState();
}

class _EditCommunityStoryScreenState extends State<EditCommunityStoryScreen> {
  final CommunitySubmissionService _submissionService =
      CommunitySubmissionService();
  final CommunityMediaService _mediaService = CommunityMediaService();
  final ImagePicker _imagePicker = ImagePicker();

  late final TextEditingController titleController;
  late final TextEditingController storyController;

  String? selectedPlaceId;
  bool saving = false;
  String uploadStatus = '';

  late List<String> existingImageUrls;
  late List<String> existingVideoUrls;
  final List<XFile> newImages = [];
  final List<XFile> newVideos = [];

  @override
  void initState() {
    super.initState();

    titleController = TextEditingController(text: widget.submission.title);
    storyController = TextEditingController(text: widget.submission.story);

    final hasExistingPlace = heritagePlaces.any(
      (place) => place.id == widget.submission.heritagePlaceId,
    );

    selectedPlaceId = hasExistingPlace
        ? widget.submission.heritagePlaceId
        : (heritagePlaces.isNotEmpty ? heritagePlaces.first.id : null);

    existingImageUrls = List<String>.of(widget.submission.imageUrls);
    existingVideoUrls = List<String>.of(widget.submission.videoUrls);
  }

  @override
  void dispose() {
    titleController.dispose();
    storyController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _pickEditPhotos() async {
    if (saving) return;

    final remaining =
        CommunityMediaService.maxImages -
        existingImageUrls.length -
        newImages.length;

    if (remaining <= 0) {
      _showMessage('This submission already has the maximum number of photos.');
      return;
    }

    final picked = await _imagePicker.pickMultiImage(imageQuality: 88);

    if (picked.isEmpty || !mounted) return;

    setState(() {
      newImages.addAll(picked.take(remaining));
    });
  }

  Future<void> _pickEditVideo() async {
    if (saving) return;

    final remaining =
        CommunityMediaService.maxVideos -
        existingVideoUrls.length -
        newVideos.length;

    if (remaining <= 0) {
      _showMessage('This submission already has the maximum number of videos.');
      return;
    }

    final picked = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );

    if (picked == null || !mounted) return;

    setState(() => newVideos.add(picked));
  }

  Future<void> _saveChanges() async {
    FocusScope.of(context).unfocus();

    if (widget.submission.status != CommunitySubmissionStatus.pending) {
      _showMessage('Only pending submissions can be edited.');
      return;
    }

    final title = titleController.text.trim();
    final story = storyController.text.trim();

    if (selectedPlaceId == null) {
      _showMessage('Please choose a heritage place.');
      return;
    }

    if (title.length < 3) {
      _showMessage('Please enter a story title.');
      return;
    }

    if (story.length < 20) {
      _showMessage(
        'Please write a more complete heritage story before saving.',
      );
      return;
    }

    final place = heritagePlaces.firstWhere(
      (item) => item.id == selectedPlaceId,
    );

    setState(() => saving = true);

    try {
      var uploadedImages = <String>[];
      var uploadedVideos = <String>[];

      if (newImages.isNotEmpty) {
        setState(() => uploadStatus = 'Uploading new photos...');
        uploadedImages = await _mediaService.uploadImages(
          submissionId: widget.submission.id,
          images: newImages,
        );
      }

      if (newVideos.isNotEmpty) {
        setState(() => uploadStatus = 'Uploading new videos...');
        uploadedVideos = await _mediaService.uploadVideos(
          submissionId: widget.submission.id,
          videos: newVideos,
        );
      }

      await _submissionService.updatePendingSubmission(
        submission: widget.submission,
        heritagePlaceId: place.id,
        heritagePlaceName: place.name,
        title: title,
        story: story,
        imageUrls: [...existingImageUrls, ...uploadedImages],
        videoUrls: [...existingVideoUrls, ...uploadedVideos],
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pending submission updated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Submission')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionTitle(
            title: 'Edit Pending Heritage Story',
            subtitle:
                'You can update the heritage place, title, story, photos, and videos while the submission is still Pending.',
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: selectedPlaceId,
            isExpanded: true,
            decoration: inputDecoration(
              label: 'Heritage Place',
              icon: Icons.place_rounded,
            ),
            items: heritagePlaces
                .map(
                  (place) => DropdownMenuItem<String>(
                    value: place.id,
                    child: Text(place.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: saving
                ? null
                : (value) {
                    setState(() => selectedPlaceId = value);
                  },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: titleController,
            enabled: !saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: inputDecoration(
              label: 'Story Title',
              icon: Icons.title_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: storyController,
            enabled: !saving,
            minLines: 8,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            decoration: inputDecoration(
              label: 'Heritage Story',
              icon: Icons.history_edu_rounded,
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 18),
          const SectionTitle(
            title: 'Attached Media',
            subtitle:
                'Remove existing attachments or add new photos/videos before saving.',
          ),
          const SizedBox(height: 10),
          if (existingImageUrls.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: existingImageUrls.map((url) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 88,
                          height: 88,
                          color: Colors.black12,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_rounded),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: saving
                              ? null
                              : () {
                                  setState(() {
                                    existingImageUrls.remove(url);
                                  });
                                },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          if (existingVideoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...existingVideoUrls.map(
              (url) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.video_file_rounded,
                  color: AppColors.brown,
                ),
                title: const Text('Attached Video'),
                subtitle: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Remove video',
                  onPressed: saving
                      ? null
                      : () {
                          setState(() {
                            existingVideoUrls.remove(url);
                          });
                        },
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ],
          if (newImages.isNotEmpty || newVideos.isNotEmpty) ...[
            const SizedBox(height: 8),
            InfoCard(
              icon: Icons.cloud_upload_rounded,
              title: 'New Media Selected',
              body:
                  '${newImages.length} new photo${newImages.length == 1 ? '' : 's'} and '
                  '${newVideos.length} new video${newVideos.length == 1 ? '' : 's'} will upload when saved.',
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving ? null : _pickEditPhotos,
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: const Text('Add Photos'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving ? null : _pickEditVideo,
                  icon: const Icon(Icons.video_library_rounded),
                  label: const Text('Add Video'),
                ),
              ),
            ],
          ),
          if (uploadStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              uploadStatus,
              style: const TextStyle(
                color: AppColors.brown,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 14),
          const InfoCard(
            icon: Icons.schedule_rounded,
            title: 'Pending Only',
            body:
                'After an Administrator approves or rejects the contribution, this Edit option is no longer available.',
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: saving ? null : _saveChanges,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(saving ? 'Saving...' : 'Save Changes'),
            style: mainButtonStyle(),
          ),
        ],
      ),
    );
  }
}

class _AttachmentCount extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AttachmentCount({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.brown),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}

class SubmitCommunityStoryScreen extends StatefulWidget {
  const SubmitCommunityStoryScreen({super.key});

  @override
  State<SubmitCommunityStoryScreen> createState() =>
      _SubmitCommunityStoryScreenState();
}

class _SubmitCommunityStoryScreenState
    extends State<SubmitCommunityStoryScreen> {
  final CommunitySubmissionService _submissionService =
      CommunitySubmissionService();
  final CommunityMediaService _mediaService = CommunityMediaService();
  final UserService _userService = UserService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController titleController = TextEditingController();
  final TextEditingController storyController = TextEditingController();

  final List<XFile> selectedImages = [];
  final List<XFile> selectedVideos = [];

  String? selectedPlaceId;
  String contributorName = '';
  bool loadingProfile = true;
  bool submitting = false;
  String uploadStatus = '';

  @override
  void initState() {
    super.initState();

    if (heritagePlaces.isNotEmpty) {
      selectedPlaceId = heritagePlaces.first.id;
    }

    _loadContributorName();
  }

  Future<void> _loadContributorName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final profile = await _userService.getUserProfile(user.uid);

        contributorName = profile?.fullName.trim().isNotEmpty == true
            ? profile!.fullName.trim()
            : (user.displayName?.trim() ?? '');
      }
    } finally {
      if (mounted) {
        setState(() => loadingProfile = false);
      }
    }
  }

  Future<void> _pickPhotos() async {
    if (submitting) return;

    final remaining = CommunityMediaService.maxImages - selectedImages.length;

    if (remaining <= 0) {
      _showMessage(
        'You can attach up to ${CommunityMediaService.maxImages} photos.',
      );
      return;
    }

    try {
      final picked = await _imagePicker.pickMultiImage(imageQuality: 88);

      if (picked.isEmpty || !mounted) return;

      final accepted = picked.take(remaining).toList();

      setState(() {
        selectedImages.addAll(accepted);
      });

      if (picked.length > remaining) {
        _showMessage(
          'Only $remaining more photo${remaining == 1 ? '' : 's'} could be added.',
        );
      }
    } catch (e) {
      _showMessage('Could not select photos: $e');
    }
  }

  Future<void> _pickVideo() async {
    if (submitting) return;

    if (selectedVideos.length >= CommunityMediaService.maxVideos) {
      _showMessage(
        'You can attach up to ${CommunityMediaService.maxVideos} videos.',
      );
      return;
    }

    try {
      final picked = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (picked == null || !mounted) return;

      setState(() {
        selectedVideos.add(picked);
      });
    } catch (e) {
      _showMessage('Could not select video: $e');
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    storyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final title = titleController.text.trim();
    final story = storyController.text.trim();

    if (selectedPlaceId == null) {
      _showMessage('Please choose a heritage place.');
      return;
    }

    if (title.length < 3) {
      _showMessage('Please enter a story title.');
      return;
    }

    if (story.length < 20) {
      _showMessage(
        'Please write a more complete heritage story before submitting.',
      );
      return;
    }

    final place = heritagePlaces.firstWhere(
      (item) => item.id == selectedPlaceId,
    );

    final submissionId = _submissionService.createSubmissionId();

    setState(() {
      submitting = true;
      uploadStatus = selectedImages.isEmpty && selectedVideos.isEmpty
          ? 'Saving submission...'
          : 'Preparing media upload...';
    });

    var imageUrls = <String>[];
    var videoUrls = <String>[];

    try {
      if (selectedImages.isNotEmpty) {
        setState(() => uploadStatus = 'Uploading photos...');

        imageUrls = await _mediaService.uploadImages(
          submissionId: submissionId,
          images: selectedImages,
          onProgress: (uploaded, total) {
            if (!mounted) return;
            setState(
              () => uploadStatus = 'Uploading photos $uploaded of $total...',
            );
          },
        );
      }

      if (selectedVideos.isNotEmpty) {
        setState(() => uploadStatus = 'Uploading videos...');

        videoUrls = await _mediaService.uploadVideos(
          submissionId: submissionId,
          videos: selectedVideos,
          onProgress: (uploaded, total) {
            if (!mounted) return;
            setState(
              () => uploadStatus = 'Uploading videos $uploaded of $total...',
            );
          },
        );
      }

      if (mounted) {
        setState(() => uploadStatus = 'Saving submission...');
      }

      await _submissionService.submitStory(
        submissionId: submissionId,
        contributorName: contributorName,
        heritagePlaceId: place.id,
        heritagePlaceName: place.name,
        title: title,
        story: story,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Heritage story submitted for administrator review.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      await _mediaService.deleteMediaUrls([...imageUrls, ...videoUrls]);

      if (!mounted) return;

      _showMessage(
        e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          submitting = false;
          uploadStatus = '';
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Submit Heritage Story')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionTitle(
            title: 'Community Heritage Story',
            subtitle:
                'Share a local story or cultural memory with optional photos and videos. It will remain Pending until reviewed by the HeritageBot Administrator.',
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: selectedPlaceId,
            isExpanded: true,
            decoration: inputDecoration(
              label: 'Heritage Place',
              icon: Icons.place_rounded,
            ),
            items: heritagePlaces
                .map(
                  (place) => DropdownMenuItem<String>(
                    value: place.id,
                    child: Text(place.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: submitting
                ? null
                : (value) {
                    setState(() => selectedPlaceId = value);
                  },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: titleController,
            enabled: !submitting,
            textCapitalization: TextCapitalization.sentences,
            decoration: inputDecoration(
              label: 'Story Title',
              icon: Icons.title_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: storyController,
            enabled: !submitting,
            minLines: 8,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            decoration:
                inputDecoration(
                  label: 'Heritage Story',
                  icon: Icons.history_edu_rounded,
                ).copyWith(
                  alignLabelWithHint: true,
                  hintText:
                      'Write the local story, cultural memory, oral history, or heritage information you want to contribute.',
                ),
          ),
          const SizedBox(height: 18),
          const SectionTitle(
            title: 'Supporting Media',
            subtitle:
                'Optional: attach up to 5 photos and 2 videos. Photos must be 10 MB or smaller and videos 60 MB or smaller.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: submitting ? null : _pickPhotos,
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: Text(
                    'Photos (${selectedImages.length}/${CommunityMediaService.maxImages})',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: submitting ? null : _pickVideo,
                  icon: const Icon(Icons.video_library_rounded),
                  label: Text(
                    'Videos (${selectedVideos.length}/${CommunityMediaService.maxVideos})',
                  ),
                ),
              ),
            ],
          ),
          if (selectedImages.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: selectedImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final image = selectedImages[index];

                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          File(image.path),
                          width: 104,
                          height: 104,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: submitting
                                ? null
                                : () {
                                    setState(
                                      () => selectedImages.removeAt(index),
                                    );
                                  },
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          if (selectedVideos.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...List.generate(
              selectedVideos.length,
              (index) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(
                    Icons.video_file_rounded,
                    color: AppColors.brown,
                  ),
                  title: Text(
                    selectedVideos[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove video',
                    onPressed: submitting
                        ? null
                        : () {
                            setState(() => selectedVideos.removeAt(index));
                          },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const InfoCard(
            icon: Icons.verified_user_rounded,
            title: 'Administrator Review',
            body:
                'Your story and attached media will be saved with Pending status. They will not become approved community content until reviewed by an Administrator.',
          ),
          if (submitting && uploadStatus.isNotEmpty) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              uploadStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.brown,
              ),
            ),
          ],
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: submitting || loadingProfile ? null : _submit,
            icon: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              submitting ? 'Uploading & Submitting...' : 'Submit for Review',
            ),
            style: mainButtonStyle(),
          ),
        ],
      ),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  final UserProfile profile;

  const AdminDashboardScreen({super.key, required this.profile});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final CommunitySubmissionService _submissionService =
      CommunitySubmissionService();
  final AdminAnalyticsService _analyticsService = AdminAnalyticsService();
  final AdminReportService _reportService = AdminReportService();

  late Future<List<CommunitySubmission>> _submissionsFuture;
  late Future<AdminAnalyticsSnapshot> _analyticsFuture;

  String selectedFilter = 'all';
  bool _generatingReport = false;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
    _loadAnalytics();
  }

  void _loadSubmissions() {
    _submissionsFuture = _submissionService.getAllSubmissions();
  }

  void _loadAnalytics() {
    _analyticsFuture = _analyticsService.loadSnapshot();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadSubmissions();
      _loadAnalytics();
    });

    await Future.wait<dynamic>([_submissionsFuture, _analyticsFuture]);
  }

  Future<void> _generateReport() async {
    if (_generatingReport) {
      return;
    }

    setState(() => _generatingReport = true);

    try {
      final analytics = await _analyticsService.loadSnapshot();

      await _reportService.generateSystemReport(analytics);

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('HeritageBot PDF report generated successfully.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not generate report: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _generatingReport = false);
      }
    }
  }

  Future<void> _openSubmission(CommunitySubmission submission) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminReviewSubmissionScreen(submission: submission),
      ),
    );

    if (changed == true && mounted) {
      await _refresh();
    }
  }

  List<CommunitySubmission> _filtered(List<CommunitySubmission> submissions) {
    if (selectedFilter == 'all') {
      return submissions;
    }

    return submissions
        .where((submission) => submission.status == selectedFilter)
        .toList();
  }

  int _countStatus(List<CommunitySubmission> submissions, String status) {
    return submissions
        .where((submission) => submission.status == status)
        .length;
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case CommunitySubmissionStatus.approved:
        return Icons.check_circle_rounded;
      case CommunitySubmissionStatus.rejected:
        return Icons.cancel_rounded;
      case CommunitySubmissionStatus.pending:
      default:
        return Icons.schedule_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.profile.fullName.isEmpty
        ? 'Administrator'
        : widget.profile.fullName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HeritageBot Admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await AuthService().logout();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<CommunitySubmission>>(
          future: _submissionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  const InfoCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could Not Load Contributions',
                    body:
                        'HeritageBot could not load community submissions from Cloud Firestore.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              );
            }

            final submissions = snapshot.data ?? const [];
            final filteredSubmissions = _filtered(submissions);

            final pendingCount = _countStatus(
              submissions,
              CommunitySubmissionStatus.pending,
            );
            final approvedCount = _countStatus(
              submissions,
              CommunitySubmissionStatus.approved,
            );
            final rejectedCount = _countStatus(
              submissions,
              CommunitySubmissionStatus.rejected,
            );

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
              children: [
                SectionTitle(
                  title: 'Welcome, $displayName',
                  subtitle:
                      'Review community-contributed heritage stories and provide approval, rejection, and feedback.',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _AdminSummaryChip(
                      label: 'Total',
                      count: submissions.length,
                      icon: Icons.inbox_rounded,
                    ),
                    _AdminSummaryChip(
                      label: 'Pending',
                      count: pendingCount,
                      icon: Icons.schedule_rounded,
                    ),
                    _AdminSummaryChip(
                      label: 'Approved',
                      count: approvedCount,
                      icon: Icons.check_circle_rounded,
                    ),
                    _AdminSummaryChip(
                      label: 'Rejected',
                      count: rejectedCount,
                      icon: Icons.cancel_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FutureBuilder<AdminAnalyticsSnapshot>(
                  future: _analyticsFuture,
                  builder: (context, analyticsSnapshot) {
                    if (analyticsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const InfoCard(
                        icon: Icons.insights_rounded,
                        title: 'Loading System Summary',
                        body:
                            'HeritageBot is calculating current users, heritage sites, and submission statistics.',
                      );
                    }

                    if (analyticsSnapshot.hasError ||
                        !analyticsSnapshot.hasData) {
                      return const InfoCard(
                        icon: Icons.info_outline_rounded,
                        title: 'System Summary Unavailable',
                        body:
                            'Submission review is still available. Pull down to refresh the administrator dashboard.',
                      );
                    }

                    final analytics = analyticsSnapshot.data!;

                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        leading: const Icon(
                          Icons.insights_rounded,
                          color: AppColors.brown,
                        ),
                        title: const Text(
                          'System Summary & Analytics',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.deepBrown,
                          ),
                        ),
                        subtitle: Text(
                          '${analytics.totalUsers} users • '
                          '${analytics.totalSites} heritage sites • '
                          '${analytics.totalSubmissions} submissions',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminAnalyticsScreen(),
                            ),
                          );

                          if (mounted) {
                            setState(_loadAnalytics);
                          }
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: _generatingReport
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.3),
                          )
                        : const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: AppColors.brown,
                          ),
                    title: const Text(
                      'Generate PDF Report',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                    subtitle: Text(
                      _generatingReport
                          ? 'Building the current HeritageBot system report...'
                          : 'Create an administrator PDF with user, site, analytics, and submission summaries.',
                    ),
                    trailing: _generatingReport
                        ? null
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: _generatingReport ? null : _generateReport,
                  ),
                ),
                const SizedBox(height: 22),
                const SectionTitle(
                  title: 'Review Community Contributions',
                  subtitle:
                      'Tap a submission to read the full story, approve or reject it, and add administrator feedback.',
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: selectedFilter == 'all',
                        onSelected: (_) {
                          setState(() => selectedFilter = 'all');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Pending'),
                        selected:
                            selectedFilter == CommunitySubmissionStatus.pending,
                        onSelected: (_) {
                          setState(
                            () => selectedFilter =
                                CommunitySubmissionStatus.pending,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Approved'),
                        selected:
                            selectedFilter ==
                            CommunitySubmissionStatus.approved,
                        onSelected: (_) {
                          setState(
                            () => selectedFilter =
                                CommunitySubmissionStatus.approved,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Rejected'),
                        selected:
                            selectedFilter ==
                            CommunitySubmissionStatus.rejected,
                        onSelected: (_) {
                          setState(
                            () => selectedFilter =
                                CommunitySubmissionStatus.rejected,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (filteredSubmissions.isEmpty)
                  const InfoCard(
                    icon: Icons.inbox_rounded,
                    title: 'No Contributions Found',
                    body:
                        'There are no community submissions in the selected status.',
                  )
                else
                  ...filteredSubmissions.map(
                    (submission) => Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openSubmission(submission),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _statusIcon(submission.status),
                                    color: AppColors.brown,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          submission.title,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.deepBrown,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          submission.heritagePlaceName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.black45,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Contributor: ${submission.contributorName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (submission.contributorEmail.isNotEmpty)
                                Text(
                                  submission.contributorEmail,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              const SizedBox(height: 10),
                              Text(
                                submission.story,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(height: 1.45),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  CommunitySubmissionStatus.label(
                                    submission.status,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.brown,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const Icon(
                      Icons.people_alt_rounded,
                      color: AppColors.brown,
                    ),
                    title: const Text(
                      'Manage Users',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                    subtitle: const Text(
                      'Search users, view account details, and manage account status.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminUsersScreen(),
                        ),
                      );
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const Icon(
                      Icons.location_city_rounded,
                      color: AppColors.brown,
                    ),
                    title: const Text(
                      'Manage Heritage Sites',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                    subtitle: const Text(
                      'Add, edit, activate, deactivate, or delete Firestore heritage-site records.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminHeritageSitesScreen(),
                        ),
                      );

                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const Icon(
                      Icons.hub_rounded,
                      color: AppColors.brown,
                    ),
                    title: const Text(
                      'Manage AI Knowledge Base',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                    subtitle: const Text(
                      'Add verified historical data, generate embeddings, sync approved stories, and inspect vector status.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminKnowledgeBaseScreen(),
                        ),
                      );
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const Icon(
                      Icons.fact_check_rounded,
                      color: AppColors.brown,
                    ),
                    title: const Text(
                      'Monitor AI Narratives',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                    subtitle: const Text(
                      'Review generated narratives and verify whether they align with retrieved historical sources.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminNarrativeMonitorScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AdminKnowledgeBaseScreen extends StatefulWidget {
  const AdminKnowledgeBaseScreen({super.key});

  @override
  State<AdminKnowledgeBaseScreen> createState() =>
      _AdminKnowledgeBaseScreenState();
}

class _AdminKnowledgeBaseScreenState extends State<AdminKnowledgeBaseScreen> {
  late final KnowledgeBaseService _knowledgeBase;

  late Future<List<HistoricalContent>> _contentFuture;
  bool working = false;
  String workMessage = '';

  @override
  void initState() {
    super.initState();
    _knowledgeBase = KnowledgeBaseService(geminiApiKey: geminiApiKey);
    _reload();
  }

  void _reload() {
    _contentFuture = _knowledgeBase.getAllContent();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _contentFuture;
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _initializeSiteFacts() async {
    if (working) return;

    setState(() {
      working = true;
      workMessage = 'Generating site embeddings...';
    });

    try {
      var sites = await HeritageSiteService().getAllSites();

      if (sites.isEmpty) {
        sites = List<HeritagePlace>.of(heritagePlaces);
      }

      final created = await _knowledgeBase.initializeSiteFacts(sites);

      _message(
        created == 0
            ? 'Current site records are already in the knowledge base.'
            : '$created heritage-site knowledge record${created == 1 ? '' : 's'} initialized.',
      );

      await _refresh();
    } catch (e) {
      _message('Knowledge base initialization failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          working = false;
          workMessage = '';
        });
      }
    }
  }

  Future<void> _updateKnowledgeBase() async {
    if (working) return;

    setState(() {
      working = true;
      workMessage = 'Syncing approved community stories...';
    });

    try {
      final approved = await CommunitySubmissionService()
          .getApprovedSubmissions();

      final synced = await _knowledgeBase.syncApprovedCommunityStories(
        approved,
      );

      if (mounted) {
        setState(() {
          workMessage = 'Rebuilding vector embeddings...';
        });
      }

      final rebuilt = await _knowledgeBase.rebuildAllEmbeddings();

      _message(
        'Knowledge base updated: $synced approved community stories synced and $rebuilt vector embeddings rebuilt.',
      );

      await _refresh();
    } catch (e) {
      _message('Knowledge base update failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          working = false;
          workMessage = '';
        });
      }
    }
  }

  Future<void> _openEditor({HistoricalContent? item}) async {
    var sites = await HeritageSiteService().getAllSites();

    if (sites.isEmpty) {
      sites = List<HeritagePlace>.of(heritagePlaces);
    }

    if (!mounted) return;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => HistoricalContentEditorScreen(sites: sites, item: item),
      ),
    );

    if (changed == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _delete(HistoricalContent item) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete Historical Data?'),
            content: Text('Delete "${item.title}" from the AI knowledge base?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await _knowledgeBase.deleteContent(item.id);
      _message('Historical data deleted.');
      await _refresh();
    } catch (e) {
      _message('Could not delete historical data: $e');
    }
  }

  Widget _summaryBox({
    required String label,
    required int value,
    required IconData icon,
  }) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.brown),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              color: AppColors.deepBrown,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Knowledge Base'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: working ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: working ? null : () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Historical Data'),
      ),
      body: FutureBuilder<List<HistoricalContent>>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const InfoCard(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could Not Load Knowledge Base',
                  body:
                      'Publish the Step 17 Firestore rules, then refresh this screen.',
                ),
                const SizedBox(height: 10),
                Text(snapshot.error.toString()),
              ],
            );
          }

          final contents = snapshot.data ?? const [];
          final status = _knowledgeBase.statusFrom(contents);

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
            children: [
              const SectionTitle(
                title: 'Historical Knowledge Base',
                subtitle:
                    'Verified historical data is converted into vector embeddings and retrieved as context before Gemini generates a narrative.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _summaryBox(
                    label: 'Records',
                    value: status.total,
                    icon: Icons.library_books_rounded,
                  ),
                  _summaryBox(
                    label: 'Approved',
                    value: status.approved,
                    icon: Icons.verified_rounded,
                  ),
                  _summaryBox(
                    label: 'Vector Ready',
                    value: status.vectorReady,
                    icon: Icons.hub_rounded,
                  ),
                  _summaryBox(
                    label: 'Community',
                    value: status.communitySources,
                    icon: Icons.groups_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (working)
                InfoCard(
                  icon: Icons.sync_rounded,
                  title: 'Updating Knowledge Base',
                  body: workMessage.isEmpty ? 'Please wait...' : workMessage,
                ),
              if (working) const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: working ? null : _initializeSiteFacts,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Initialize Current Site Facts'),
                style: mainButtonStyle(),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: working ? null : _updateKnowledgeBase,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Update Knowledge Base'),
              ),
              const SizedBox(height: 8),
              InfoCard(
                icon: status.missingVector == 0
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                title: 'Vector Data Status',
                body:
                    '${status.vectorReady}/${status.total} records have embeddings. '
                    '${status.missingVector == 0 ? 'The current knowledge records are vector-ready.' : '${status.missingVector} record(s) require embedding generation.'}',
              ),
              const SizedBox(height: 18),
              if (contents.isEmpty)
                const InfoCard(
                  icon: Icons.menu_book_rounded,
                  title: 'Knowledge Base Is Empty',
                  body:
                      'Initialize the current heritage-site facts or add verified historical data manually.',
                )
              else
                ...contents.map(
                  (item) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.deepBrown,
                                  ),
                                ),
                              ),
                              Icon(
                                item.hasEmbedding
                                    ? Icons.hub_rounded
                                    : Icons.warning_amber_rounded,
                                color: item.hasEmbedding
                                    ? AppColors.brown
                                    : Colors.orange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.siteName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.content,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Source: ${item.sourceTitle}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.sourceType == 'community' ? 'Community source' : 'Curated source'} • '
                            '${item.isApproved ? 'Approved for RAG' : 'Not approved'} • '
                            '${item.hasEmbedding ? '${item.embedding.length}-dimension vector' : 'No vector'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: working
                                    ? null
                                    : () => _openEditor(item: item),
                                icon: const Icon(Icons.edit_rounded),
                                label: const Text('Edit'),
                              ),
                              TextButton.icon(
                                onPressed: working ? null : () => _delete(item),
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class HistoricalContentEditorScreen extends StatefulWidget {
  final List<HeritagePlace> sites;
  final HistoricalContent? item;

  const HistoricalContentEditorScreen({
    super.key,
    required this.sites,
    this.item,
  });

  @override
  State<HistoricalContentEditorScreen> createState() =>
      _HistoricalContentEditorScreenState();
}

class _HistoricalContentEditorScreenState
    extends State<HistoricalContentEditorScreen> {
  late final KnowledgeBaseService _knowledgeBase;

  late final TextEditingController titleController;
  late final TextEditingController contentController;
  late final TextEditingController sourceTitleController;
  late final TextEditingController sourceUrlController;
  late final TextEditingController categoryController;

  late String selectedSiteId;
  late String languageCode;
  late bool isApproved;
  bool saving = false;

  bool get editing => widget.item != null;

  @override
  void initState() {
    super.initState();

    _knowledgeBase = KnowledgeBaseService(geminiApiKey: geminiApiKey);

    final item = widget.item;
    selectedSiteId =
        item?.siteId ?? (widget.sites.isNotEmpty ? widget.sites.first.id : '');
    languageCode = item?.languageCode ?? 'en';
    isApproved = item?.isApproved ?? true;

    titleController = TextEditingController(text: item?.title ?? '');
    contentController = TextEditingController(text: item?.content ?? '');
    sourceTitleController = TextEditingController(
      text: item?.sourceTitle ?? '',
    );
    sourceUrlController = TextEditingController(text: item?.sourceUrl ?? '');
    categoryController = TextEditingController(
      text: item?.category ?? 'historical_record',
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    sourceTitleController.dispose();
    sourceUrlController.dispose();
    categoryController.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _save() async {
    if (saving) return;

    if (selectedSiteId.isEmpty) {
      _message('Please choose a heritage site.');
      return;
    }

    final site = widget.sites.firstWhere((item) => item.id == selectedSiteId);

    setState(() => saving = true);

    try {
      if (editing) {
        final original = widget.item!;

        await _knowledgeBase.updateContent(
          original.copyWith(
            siteId: site.id,
            siteName: site.name,
            title: titleController.text.trim(),
            content: contentController.text.trim(),
            sourceTitle: sourceTitleController.text.trim(),
            sourceUrl: sourceUrlController.text.trim(),
            category: categoryController.text.trim(),
            languageCode: languageCode,
            isApproved: isApproved,
          ),
        );
      } else {
        await _knowledgeBase.addContent(
          siteId: site.id,
          siteName: site.name,
          title: titleController.text,
          content: contentController.text,
          sourceTitle: sourceTitleController.text,
          sourceUrl: sourceUrlController.text,
          category: categoryController.text,
          languageCode: languageCode,
          isApproved: isApproved,
        );
      }

      if (!mounted) return;

      _message(
        editing
            ? 'Historical data and embedding updated.'
            : 'Historical data added and vectorized.',
      );

      Navigator.pop(context, true);
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit Historical Data' : 'Add Historical Data'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          const SectionTitle(
            title: 'Verified Historical Content',
            subtitle:
                'Saving this record also generates a Gemini embedding for vector-based RAG retrieval.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: selectedSiteId,
            decoration: inputDecoration(
              label: 'Heritage Site',
              icon: Icons.location_city_rounded,
            ),
            items: widget.sites
                .map(
                  (site) =>
                      DropdownMenuItem(value: site.id, child: Text(site.name)),
                )
                .toList(),
            onChanged: saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => selectedSiteId = value);
                    }
                  },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: titleController,
            enabled: !saving,
            decoration: inputDecoration(
              label: 'Historical Data Title',
              icon: Icons.title_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: contentController,
            enabled: !saving,
            minLines: 8,
            maxLines: 15,
            decoration: inputDecoration(
              label: 'Verified Historical Content',
              icon: Icons.history_edu_rounded,
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: sourceTitleController,
            enabled: !saving,
            decoration: inputDecoration(
              label: 'Source / Reference',
              icon: Icons.menu_book_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: sourceUrlController,
            enabled: !saving,
            keyboardType: TextInputType.url,
            decoration: inputDecoration(
              label: 'Source URL',
              icon: Icons.link_rounded,
            ).copyWith(hintText: 'Optional URL'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: categoryController,
            enabled: !saving,
            decoration: inputDecoration(
              label: 'Content Category',
              icon: Icons.category_rounded,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: languageCode,
            decoration: inputDecoration(
              label: 'Content Language',
              icon: Icons.language_rounded,
            ),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'fil', child: Text('Filipino')),
            ],
            onChanged: saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => languageCode = value);
                    }
                  },
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Approved for RAG Retrieval',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Only approved historical records can be retrieved as grounding context.',
            ),
            value: isApproved,
            onChanged: saving
                ? null
                : (value) {
                    setState(() => isApproved = value);
                  },
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.hub_rounded),
            label: Text(
              saving ? 'Generating Embedding...' : 'Save & Generate Embedding',
            ),
            style: mainButtonStyle(),
          ),
        ],
      ),
    );
  }
}

class AdminNarrativeMonitorScreen extends StatefulWidget {
  const AdminNarrativeMonitorScreen({super.key});

  @override
  State<AdminNarrativeMonitorScreen> createState() =>
      _AdminNarrativeMonitorScreenState();
}

class _AdminNarrativeMonitorScreenState
    extends State<AdminNarrativeMonitorScreen> {
  final AiNarrativeService _service = AiNarrativeService();

  late Future<List<AiNarrativeRecord>> _future;
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.getRecentNarratives();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _open(AiNarrativeRecord record) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminNarrativeReviewScreen(record: record),
      ),
    );

    if (changed == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor AI Narratives'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<AiNarrativeRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const InfoCard(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could Not Load AI Narratives',
                  body: 'Publish the Step 17 Firestore rules, then refresh.',
                ),
                const SizedBox(height: 10),
                Text(snapshot.error.toString()),
              ],
            );
          }

          final records = snapshot.data ?? const [];
          final shown = filter == 'all'
              ? records
              : records.where((item) => item.reviewStatus == filter).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
            children: [
              const SectionTitle(
                title: 'AI Narrative Verification',
                subtitle:
                    'Generated narratives are logged so the Administrator can inspect retrieval sources and verify historical alignment.',
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: filter == 'all',
                      onSelected: (_) {
                        setState(() => filter = 'all');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Pending Review'),
                      selected: filter == AiNarrativeReviewStatus.pendingReview,
                      onSelected: (_) {
                        setState(
                          () => filter = AiNarrativeReviewStatus.pendingReview,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Verified'),
                      selected: filter == AiNarrativeReviewStatus.verified,
                      onSelected: (_) {
                        setState(
                          () => filter = AiNarrativeReviewStatus.verified,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Needs Review'),
                      selected: filter == AiNarrativeReviewStatus.needsReview,
                      onSelected: (_) {
                        setState(
                          () => filter = AiNarrativeReviewStatus.needsReview,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (shown.isEmpty)
                const InfoCard(
                  icon: Icons.fact_check_rounded,
                  title: 'No Generated Narratives',
                  body:
                      'Generate a new tourist AI narrative after Step 17 is installed. It will then appear here for verification.',
                )
              else
                ...shown.map(
                  (record) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      leading: Icon(
                        record.reviewStatus == AiNarrativeReviewStatus.verified
                            ? Icons.verified_rounded
                            : record.reviewStatus ==
                                  AiNarrativeReviewStatus.needsReview
                            ? Icons.warning_amber_rounded
                            : Icons.pending_actions_rounded,
                        color: AppColors.brown,
                      ),
                      title: Text(
                        record.siteName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.deepBrown,
                        ),
                      ),
                      subtitle: Text(
                        '${AiNarrativeReviewStatus.label(record.reviewStatus)} • '
                        '${record.retrievalMode == 'vector_rag' ? 'Vector RAG' : 'Fallback context'}\n'
                        '${record.narrative}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _open(record),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AdminNarrativeReviewScreen extends StatefulWidget {
  final AiNarrativeRecord record;

  const AdminNarrativeReviewScreen({super.key, required this.record});

  @override
  State<AdminNarrativeReviewScreen> createState() =>
      _AdminNarrativeReviewScreenState();
}

class _AdminNarrativeReviewScreenState
    extends State<AdminNarrativeReviewScreen> {
  final AiNarrativeService _service = AiNarrativeService();

  bool saving = false;
  bool changed = false;

  Future<String?> _reviewNote({required String title}) {
    final controller = TextEditingController(
      text: widget.record.adminReviewNote,
    );

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Administrator Note',
            hintText: 'Optional verification or correction note',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save Review'),
          ),
        ],
      ),
    );
  }

  Future<void> _review(String status) async {
    if (saving) return;

    final note = await _reviewNote(
      title: status == AiNarrativeReviewStatus.verified
          ? 'Mark Narrative Verified'
          : 'Mark Narrative Needs Review',
    );

    if (note == null || !mounted) return;

    setState(() => saving = true);

    try {
      await _service.reviewNarrative(
        narrativeId: widget.record.id,
        status: status,
        note: note,
      );

      if (!mounted) return;

      changed = true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == AiNarrativeReviewStatus.verified
                ? 'Narrative marked Verified.'
                : 'Narrative marked Needs Review.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final date = record.createdAtMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(record.createdAtMillis)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify AI Narrative')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          SectionTitle(
            title: record.siteName,
            subtitle:
                'Generated ${date == null ? '' : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'}',
          ),
          const SizedBox(height: 14),
          InfoCard(
            icon: Icons.auto_awesome_rounded,
            title: 'Generated Narrative',
            body: record.narrative,
          ),
          const SizedBox(height: 10),
          InfoCard(
            icon: Icons.hub_rounded,
            title: 'Retrieval Information',
            body:
                'Mode: ${record.retrievalMode == 'vector_rag' ? 'Vector RAG' : 'Site facts fallback'}\n'
                'Model: ${record.modelName}\n'
                'Language: ${record.languageCode}\n'
                'Distance: ${record.distanceMeters.toStringAsFixed(0)} meters',
          ),
          const SizedBox(height: 10),
          InfoCard(
            icon: Icons.menu_book_rounded,
            title: 'Retrieved Sources',
            body: record.retrievedSourceTitles.isEmpty
                ? 'No vector source was recorded. The site facts fallback was used.'
                : record.retrievedSourceTitles
                      .map((source) => '• $source')
                      .join('\n'),
          ),
          const SizedBox(height: 10),
          InfoCard(
            icon: Icons.fact_check_rounded,
            title: 'Current Review Status',
            body:
                '${AiNarrativeReviewStatus.label(record.reviewStatus)}'
                '${record.adminReviewNote.trim().isEmpty ? '' : '\n\nAdministrator note: ${record.adminReviewNote}'}',
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: saving
                ? null
                : () => _review(AiNarrativeReviewStatus.verified),
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Mark Verified'),
            style: mainButtonStyle(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: saving
                ? null
                : () => _review(AiNarrativeReviewStatus.needsReview),
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Needs Review'),
          ),
        ],
      ),
    );
  }
}

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final AdminAnalyticsService _analyticsService = AdminAnalyticsService();

  late Future<AdminAnalyticsSnapshot> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _analyticsFuture = _analyticsService.loadSnapshot();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _analyticsFuture;
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.gold.withOpacity(0.22),
              child: Icon(icon, color: AppColors.brown),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.black54, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakdownRow({
    required String label,
    required int value,
    required int total,
  }) {
    final ratio = total <= 0 ? 0.0 : value / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepBrown,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.brown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.black12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _analyticsSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.deepBrown,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.black54, height: 1.35),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<AdminAnalyticsSnapshot>(
          future: _analyticsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  const InfoCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could Not Load Analytics',
                    body:
                        'HeritageBot could not calculate the current administrator statistics.',
                  ),
                  if (snapshot.hasError) ...[
                    const SizedBox(height: 10),
                    Text(
                      snapshot.error.toString(),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ],
              );
            }

            final analytics = snapshot.data!;
            final approvalPercent = (analytics.approvalRate * 100).round();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
              children: [
                const SectionTitle(
                  title: 'System Summary',
                  subtitle:
                      'Current HeritageBot users, heritage sites, and community contribution statistics from Cloud Firestore.',
                ),
                const SizedBox(height: 14),
                _metricCard(
                  icon: Icons.people_alt_rounded,
                  label: 'Total Users',
                  value: '${analytics.totalUsers}',
                  subtitle:
                      '${analytics.activeUsers} active • ${analytics.suspendedUsers} suspended',
                ),
                _metricCard(
                  icon: Icons.location_city_rounded,
                  label: 'Total Heritage Sites',
                  value: '${analytics.totalSites}',
                  subtitle:
                      '${analytics.officialSites} official • ${analytics.testingSites} testing',
                ),
                _metricCard(
                  icon: Icons.inbox_rounded,
                  label: 'Community Submissions',
                  value: '${analytics.totalSubmissions}',
                  subtitle:
                      '${analytics.pendingSubmissions} pending • ${analytics.approvedSubmissions} approved • ${analytics.rejectedSubmissions} rejected',
                ),
                _metricCard(
                  icon: Icons.verified_rounded,
                  label: 'Approval Rate',
                  value: '$approvalPercent%',
                  subtitle:
                      'Approved contributions compared with all submitted community stories.',
                ),
                const SizedBox(height: 8),
                _analyticsSection(
                  title: 'User Distribution',
                  subtitle:
                      'Registered account distribution by HeritageBot role.',
                  children: [
                    _breakdownRow(
                      label: 'Tourists',
                      value: analytics.tourists,
                      total: analytics.totalUsers,
                    ),
                    _breakdownRow(
                      label: 'Community Contributors',
                      value: analytics.contributors,
                      total: analytics.totalUsers,
                    ),
                    _breakdownRow(
                      label: 'Administrators',
                      value: analytics.admins,
                      total: analytics.totalUsers,
                    ),
                  ],
                ),
                _analyticsSection(
                  title: 'Heritage Site Status',
                  subtitle:
                      'Current heritage-site records managed by the Administrator.',
                  children: [
                    _breakdownRow(
                      label: 'Active Sites',
                      value: analytics.activeSites,
                      total: analytics.totalSites,
                    ),
                    _breakdownRow(
                      label: 'Inactive Sites',
                      value: analytics.inactiveSites,
                      total: analytics.totalSites,
                    ),
                    _breakdownRow(
                      label: 'Official Sites',
                      value: analytics.officialSites,
                      total: analytics.totalSites,
                    ),
                    _breakdownRow(
                      label: 'Testing Sites',
                      value: analytics.testingSites,
                      total: analytics.totalSites,
                    ),
                  ],
                ),
                _analyticsSection(
                  title: 'Submission Status',
                  subtitle:
                      'Current moderation status of community-contributed heritage stories.',
                  children: [
                    _breakdownRow(
                      label: 'Pending',
                      value: analytics.pendingSubmissions,
                      total: analytics.totalSubmissions,
                    ),
                    _breakdownRow(
                      label: 'Approved',
                      value: analytics.approvedSubmissions,
                      total: analytics.totalSubmissions,
                    ),
                    _breakdownRow(
                      label: 'Rejected',
                      value: analytics.rejectedSubmissions,
                      total: analytics.totalSubmissions,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<UserProfile>> _usersFuture;
  String searchText = '';
  String selectedRole = 'all';
  String selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadUsers() {
    _usersFuture = _userService.getAllUsers();
  }

  Future<void> _refresh() async {
    setState(_loadUsers);
    await _usersFuture;
  }

  List<UserProfile> _filteredUsers(List<UserProfile> users) {
    final query = searchText.trim().toLowerCase();

    return users.where((profile) {
      final matchesSearch =
          query.isEmpty ||
          profile.fullName.toLowerCase().contains(query) ||
          profile.email.toLowerCase().contains(query) ||
          UserRoles.label(profile.role).toLowerCase().contains(query);

      final matchesRole = selectedRole == 'all' || profile.role == selectedRole;

      final matchesStatus =
          selectedStatus == 'all' ||
          profile.accountStatus.toLowerCase() == selectedStatus;

      return matchesSearch && matchesRole && matchesStatus;
    }).toList();
  }

  int _countRole(List<UserProfile> users, String role) {
    return users.where((user) => user.role == role).length;
  }

  Future<void> _openUser(UserProfile profile) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminUserDetailScreen(profile: profile),
      ),
    );

    if (changed == true && mounted) {
      await _refresh();
    }
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<UserProfile>>(
          future: _usersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  const InfoCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could Not Load Users',
                    body:
                        'HeritageBot could not load user accounts from Cloud Firestore.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              );
            }

            final users = snapshot.data ?? const [];
            final filtered = _filteredUsers(users);

            final touristCount = _countRole(users, UserRoles.tourist);
            final contributorCount = _countRole(
              users,
              UserRoles.communityContributor,
            );
            final adminCount = _countRole(users, UserRoles.admin);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
              children: [
                const SectionTitle(
                  title: 'Admin User Management',
                  subtitle:
                      'Search registered HeritageBot users, view account details, and manage account status.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _AdminSummaryChip(
                      label: 'Total Users',
                      count: users.length,
                      icon: Icons.people_alt_rounded,
                    ),
                    _AdminSummaryChip(
                      label: 'Tourists',
                      count: touristCount,
                      icon: Icons.travel_explore_rounded,
                    ),
                    _AdminSummaryChip(
                      label: 'Contributors',
                      count: contributorCount,
                      icon: Icons.edit_note_rounded,
                    ),
                    _AdminSummaryChip(
                      label: 'Admins',
                      count: adminCount,
                      icon: Icons.admin_panel_settings_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => searchText = value);
                  },
                  decoration:
                      inputDecoration(
                        label: 'Search Users',
                        icon: Icons.search_rounded,
                      ).copyWith(
                        hintText: 'Name, email, or role',
                        suffixIcon: searchText.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => searchText = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Role',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBrown,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(
                        label: 'All',
                        selected: selectedRole == 'all',
                        onTap: () {
                          setState(() => selectedRole = 'all');
                        },
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        label: 'Tourist',
                        selected: selectedRole == UserRoles.tourist,
                        onTap: () {
                          setState(() => selectedRole = UserRoles.tourist);
                        },
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        label: 'Contributor',
                        selected:
                            selectedRole == UserRoles.communityContributor,
                        onTap: () {
                          setState(
                            () => selectedRole = UserRoles.communityContributor,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        label: 'Administrator',
                        selected: selectedRole == UserRoles.admin,
                        onTap: () {
                          setState(() => selectedRole = UserRoles.admin);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Account Status',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBrown,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _filterChip(
                      label: 'All',
                      selected: selectedStatus == 'all',
                      onTap: () {
                        setState(() => selectedStatus = 'all');
                      },
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      label: 'Active',
                      selected: selectedStatus == 'active',
                      onTap: () {
                        setState(() => selectedStatus = 'active');
                      },
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      label: 'Suspended',
                      selected: selectedStatus == 'suspended',
                      onTap: () {
                        setState(() => selectedStatus = 'suspended');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (filtered.isEmpty)
                  const InfoCard(
                    icon: Icons.person_search_rounded,
                    title: 'No Users Found',
                    body:
                        'No registered account matches the current search and filters.',
                  )
                else
                  ...filtered.map(
                    (profile) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.gold.withOpacity(0.25),
                          child: Icon(
                            profile.isAdmin
                                ? Icons.admin_panel_settings_rounded
                                : profile.isCommunityContributor
                                ? Icons.edit_note_rounded
                                : Icons.person_rounded,
                            color: AppColors.brown,
                          ),
                        ),
                        title: Text(
                          profile.fullName.trim().isEmpty
                              ? 'HeritageBot User'
                              : profile.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.deepBrown,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            '${profile.email}\n'
                            '${UserRoles.label(profile.role)} • '
                            '${profile.accountStatus.toUpperCase()}',
                          ),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openUser(profile),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AdminUserDetailScreen extends StatefulWidget {
  final UserProfile profile;

  const AdminUserDetailScreen({super.key, required this.profile});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  final UserService _userService = UserService();

  late String accountStatus;
  bool saving = false;
  bool changed = false;

  UserProfile get profile => widget.profile;

  @override
  void initState() {
    super.initState();
    accountStatus = profile.accountStatus.toLowerCase();
  }

  String _formatCreatedDate() {
    if (profile.createdAtMillis <= 0) {
      return 'Not available';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(profile.createdAtMillis);

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _setStatus(String status) async {
    if (saving || status == accountStatus) {
      return;
    }

    if (profile.isAdmin || _userService.isAuthorizedAdminEmail(profile.email)) {
      _showMessage('Administrator accounts cannot be suspended.');
      return;
    }

    final action = status == 'suspended' ? 'Suspend' : 'Reactivate';

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text('$action Account?'),
              content: Text(
                status == 'suspended'
                    ? 'Suspend ${profile.fullName}? The user will be blocked from HeritageBot after the account status is refreshed.'
                    : 'Reactivate ${profile.fullName}? The user will regain access to HeritageBot.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(action),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => saving = true);

    try {
      await _userService.updateAccountStatus(profile: profile, status: status);

      if (!mounted) return;

      setState(() {
        accountStatus = status;
        changed = true;
      });

      _showMessage(
        status == 'suspended' ? 'Account suspended.' : 'Account reactivated.',
      );
    } catch (e) {
      _showMessage(
        e
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: AppColors.brown),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.trim().isEmpty ? 'Not available' : value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepBrown,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProtectedAdmin =
        profile.isAdmin || _userService.isAuthorizedAdminEmail(profile.email);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('User Details')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
          children: [
            SectionTitle(
              title: profile.fullName.trim().isEmpty
                  ? 'HeritageBot User'
                  : profile.fullName,
              subtitle: 'Registered HeritageBot account information.',
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _detailRow(
                      icon: Icons.email_rounded,
                      label: 'Email Address',
                      value: profile.email,
                    ),
                    const Divider(),
                    _detailRow(
                      icon: Icons.badge_rounded,
                      label: 'User Role',
                      value: UserRoles.label(profile.role),
                    ),
                    const Divider(),
                    _detailRow(
                      icon: Icons.language_rounded,
                      label: 'Preferred Language',
                      value: profile.preferredLanguage,
                    ),
                    const Divider(),
                    _detailRow(
                      icon: Icons.event_rounded,
                      label: 'Account Created',
                      value: _formatCreatedDate(),
                    ),
                    const Divider(),
                    _detailRow(
                      icon: Icons.manage_accounts_rounded,
                      label: 'Account Status',
                      value: accountStatus.toUpperCase(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isProtectedAdmin)
              const InfoCard(
                icon: Icons.admin_panel_settings_rounded,
                title: 'Protected Administrator',
                body:
                    'Authorized administrator accounts remain active and cannot be suspended from user management.',
              )
            else if (accountStatus == 'active')
              ElevatedButton.icon(
                onPressed: saving ? null : () => _setStatus('suspended'),
                icon: const Icon(Icons.person_off_rounded),
                label: Text(saving ? 'Updating...' : 'Suspend Account'),
                style: mainButtonStyle(),
              )
            else
              ElevatedButton.icon(
                onPressed: saving ? null : () => _setStatus('active'),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(saving ? 'Updating...' : 'Reactivate Account'),
                style: mainButtonStyle(),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminHeritageSitesScreen extends StatefulWidget {
  const AdminHeritageSitesScreen({super.key});

  @override
  State<AdminHeritageSitesScreen> createState() =>
      _AdminHeritageSitesScreenState();
}

class _AdminHeritageSitesScreenState extends State<AdminHeritageSitesScreen> {
  final HeritageSiteService _siteService = HeritageSiteService();

  late Future<List<HeritagePlace>> _sitesFuture;
  bool initializing = false;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  void _loadSites() {
    _sitesFuture = _siteService.getAllSites();
  }

  Future<void> _refresh() async {
    setState(_loadSites);
    await _sitesFuture;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _initializeDefaults() async {
    setState(() => initializing = true);

    try {
      await _siteService.seedDefaultSites();

      if (!mounted) return;

      _showMessage(
        'The 3 official heritage sites and UCLM test site were added to Firestore.',
      );

      await _refresh();
    } catch (e) {
      _showMessage(
        e
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => initializing = false);
      }
    }
  }

  Future<void> _openEditor({HeritagePlace? site}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => HeritageSiteEditorScreen(site: site)),
    );

    if (changed == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _toggleActive(HeritagePlace site, bool value) async {
    try {
      await _siteService.setActive(site, value);

      if (!mounted) return;

      _showMessage(
        value ? '${site.name} is now active.' : '${site.name} is now inactive.',
      );

      await _refresh();
    } catch (e) {
      _showMessage(
        e
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    }
  }

  Future<void> _deleteSite(HeritagePlace site) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Delete Heritage Site?'),
              content: Text(
                'Delete "${site.name}" from Firestore? '
                'Existing community submissions will keep their saved site name, '
                'but this site will no longer be available for new selections.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      await _siteService.deleteSite(site);

      if (!mounted) return;

      _showMessage('${site.name} was deleted.');
      await _refresh();
    } catch (e) {
      _showMessage(
        e
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    }
  }

  Widget _siteTypeChip(HeritagePlace site) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        site.isTesting ? 'TEST SITE' : 'OFFICIAL',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppColors.brown,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heritage Sites'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Site'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<HeritagePlace>>(
          future: _sitesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  const InfoCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could Not Load Heritage Sites',
                    body:
                        'Check that the Step 10 Firestore rules were published.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              );
            }

            final sites = snapshot.data ?? const [];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
              children: [
                const SectionTitle(
                  title: 'Heritage Site Management',
                  subtitle:
                      'The Administrator controls the heritage locations stored in Cloud Firestore.',
                ),
                const SizedBox(height: 14),
                if (sites.isEmpty) ...[
                  const InfoCard(
                    icon: Icons.cloud_upload_rounded,
                    title: 'Firestore Sites Not Initialized',
                    body:
                        'HeritageBot is currently using its local development fallback. Initialize Firestore once to create the 3 official sites and UCLM testing site.',
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: initializing ? null : _initializeDefaults,
                    icon: initializing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_rounded),
                    label: Text(
                      initializing
                          ? 'Initializing...'
                          : 'Initialize Current 4 Sites',
                    ),
                    style: mainButtonStyle(),
                  ),
                ] else ...[
                  InfoCard(
                    icon: Icons.storage_rounded,
                    title: 'Firestore Connected',
                    body:
                        '${sites.length} heritage-site record${sites.length == 1 ? '' : 's'} found. '
                        'Active records are used by the tourist map and contributor site selector.',
                  ),
                  const SizedBox(height: 14),
                  ...sites.map(
                    (site) => Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  site.isTesting
                                      ? Icons.science_rounded
                                      : Icons.account_balance_rounded,
                                  color: AppColors.brown,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    site.name,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.deepBrown,
                                    ),
                                  ),
                                ),
                                _siteTypeChip(site),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              site.location,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Lat ${site.lat.toStringAsFixed(5)} • '
                              'Lng ${site.lng.toStringAsFixed(5)} • '
                              'Radius ${site.detectionRadiusMeters.toStringAsFixed(0)} m',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              site.historicalFacts,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(height: 1.4),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Active in HeritageBot',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                site.isActive
                                    ? 'Shown in the active site list.'
                                    : 'Hidden from tourist/contributor site features.',
                              ),
                              value: site.isActive,
                              onChanged: (value) => _toggleActive(site, value),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _openEditor(site: site),
                                  icon: const Icon(Icons.edit_rounded),
                                  label: const Text('Edit'),
                                ),
                                const SizedBox(width: 6),
                                TextButton.icon(
                                  onPressed: () => _deleteSite(site),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  label: const Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class HeritageSiteEditorScreen extends StatefulWidget {
  final HeritagePlace? site;

  const HeritageSiteEditorScreen({super.key, this.site});

  @override
  State<HeritageSiteEditorScreen> createState() =>
      _HeritageSiteEditorScreenState();
}

class _HeritageSiteEditorScreenState extends State<HeritageSiteEditorScreen> {
  final HeritageSiteService _siteService = HeritageSiteService();
  final HeritageMediaService _mediaService = HeritageMediaService();
  final ImagePicker _imagePicker = ImagePicker();

  late final TextEditingController nameController;
  late final TextEditingController locationController;
  late final TextEditingController latitudeController;
  late final TextEditingController longitudeController;
  late final TextEditingController radiusController;
  late final TextEditingController factsController;
  late final TextEditingController wikipediaController;
  late final TextEditingController videoTitleController;
  late final TextEditingController videoAssetController;

  late bool isTesting;
  late bool isActive;
  bool saving = false;
  String uploadStatus = '';

  final List<XFile> selectedSiteImages = [];
  XFile? selectedSiteVideo;
  late List<String> existingSiteImages;

  bool get isEditing => widget.site != null;

  @override
  void initState() {
    super.initState();

    final site = widget.site;

    nameController = TextEditingController(text: site?.name ?? '');
    locationController = TextEditingController(text: site?.location ?? '');
    latitudeController = TextEditingController(
      text: site == null ? '' : site.lat.toString(),
    );
    longitudeController = TextEditingController(
      text: site == null ? '' : site.lng.toString(),
    );
    radiusController = TextEditingController(
      text: site == null
          ? '20000'
          : site.detectionRadiusMeters.toStringAsFixed(0),
    );
    factsController = TextEditingController(text: site?.historicalFacts ?? '');
    wikipediaController = TextEditingController(
      text: site?.wikipediaTitle ?? '',
    );
    videoTitleController = TextEditingController(text: site?.videoTitle ?? '');
    videoAssetController = TextEditingController(text: site?.videoAsset ?? '');

    isTesting = site?.isTesting ?? false;
    isActive = site?.isActive ?? true;
    existingSiteImages = List<String>.of(site?.imageUrls ?? const []);
  }

  @override
  void dispose() {
    nameController.dispose();
    locationController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
    radiusController.dispose();
    factsController.dispose();
    wikipediaController.dispose();
    videoTitleController.dispose();
    videoAssetController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _pickSitePhotos() async {
    if (saving) return;

    final remaining =
        HeritageMediaService.maxImages -
        existingSiteImages.length -
        selectedSiteImages.length;

    if (remaining <= 0) {
      _showMessage(
        'This heritage site already has the maximum number of photos.',
      );
      return;
    }

    final picked = await _imagePicker.pickMultiImage(imageQuality: 88);

    if (picked.isEmpty || !mounted) return;

    setState(() {
      selectedSiteImages.addAll(picked.take(remaining));
    });

    if (picked.length > remaining) {
      _showMessage(
        'Only $remaining more photo${remaining == 1 ? '' : 's'} can be added.',
      );
    }
  }

  Future<void> _pickSiteVideo() async {
    if (saving) return;

    final picked = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );

    if (picked == null || !mounted) return;

    setState(() {
      selectedSiteVideo = picked;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    final lat = double.tryParse(latitudeController.text.trim());
    final lng = double.tryParse(longitudeController.text.trim());
    final radius = double.tryParse(radiusController.text.trim());

    if (lat == null || lng == null) {
      _showMessage('Please enter valid latitude and longitude values.');
      return;
    }

    if (radius == null || radius < 10 || radius > 50000) {
      _showMessage('Detection radius must be between 10 and 50000 meters.');
      return;
    }

    setState(() {
      saving = true;
      uploadStatus = '';
    });

    try {
      if (isEditing) {
        final original = widget.site!;
        var uploadedImages = <String>[];
        String? uploadedVideo;

        if (selectedSiteImages.isNotEmpty) {
          setState(() => uploadStatus = 'Uploading heritage photos...');
          uploadedImages = await _mediaService.uploadImages(
            siteId: original.id,
            images: selectedSiteImages,
          );
        }

        if (selectedSiteVideo != null) {
          setState(() => uploadStatus = 'Uploading heritage video...');
          uploadedVideo = await _mediaService.uploadVideo(
            siteId: original.id,
            video: selectedSiteVideo!,
          );
        }

        final manualVideo = videoAssetController.text.trim();

        final updated = HeritagePlace(
          id: original.id,
          name: nameController.text.trim(),
          location: locationController.text.trim(),
          lat: lat,
          lng: lng,
          historicalFacts: factsController.text.trim(),
          videoTitle: videoTitleController.text.trim(),
          videoAsset:
              uploadedVideo ?? (manualVideo.isEmpty ? null : manualVideo),
          wikipediaTitle: wikipediaController.text.trim(),
          detectionRadiusMeters: radius,
          imageUrls: [...existingSiteImages, ...uploadedImages],
          isTesting: isTesting,
          isActive: isActive,
        );

        await _siteService.updateSite(updated);
      } else {
        final created = await _siteService.createSite(
          name: nameController.text,
          location: locationController.text,
          lat: lat,
          lng: lng,
          historicalFacts: factsController.text,
          videoTitle: videoTitleController.text,
          videoAsset: videoAssetController.text,
          wikipediaTitle: wikipediaController.text,
          detectionRadiusMeters: radius,
          imageUrls: const [],
          isTesting: isTesting,
          isActive: isActive,
        );

        var uploadedImages = <String>[];
        String? uploadedVideo;

        if (selectedSiteImages.isNotEmpty) {
          setState(() => uploadStatus = 'Uploading heritage photos...');
          uploadedImages = await _mediaService.uploadImages(
            siteId: created.id,
            images: selectedSiteImages,
          );
        }

        if (selectedSiteVideo != null) {
          setState(() => uploadStatus = 'Uploading heritage video...');
          uploadedVideo = await _mediaService.uploadVideo(
            siteId: created.id,
            video: selectedSiteVideo!,
          );
        }

        if (uploadedImages.isNotEmpty || uploadedVideo != null) {
          await _siteService.updateSite(
            created.copyWith(
              imageUrls: uploadedImages,
              videoAsset: uploadedVideo,
            ),
          );
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing ? 'Heritage site updated.' : 'Heritage site added.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      _showMessage(
        e
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      enabled: !saving,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.sentences,
      decoration: inputDecoration(
        label: label,
        icon: icon,
      ).copyWith(hintText: hint, alignLabelWithHint: maxLines > 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Heritage Site' : 'Add Heritage Site'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          SectionTitle(
            title: isEditing ? 'Edit Site Information' : 'New Heritage Site',
            subtitle:
                'These values are stored in Cloud Firestore and used by HeritageBot.',
          ),
          const SizedBox(height: 18),
          _field(
            controller: nameController,
            label: 'Site Name',
            icon: Icons.account_balance_rounded,
          ),
          const SizedBox(height: 14),
          _field(
            controller: locationController,
            label: 'Location / Address',
            icon: Icons.place_rounded,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: latitudeController,
                  label: 'Latitude',
                  icon: Icons.my_location_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  controller: longitudeController,
                  label: 'Longitude',
                  icon: Icons.explore_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _field(
            controller: radiusController,
            label: 'Detection Radius (meters)',
            icon: Icons.radar_rounded,
            keyboardType: TextInputType.number,
            hint: 'Testing value: 20000',
          ),
          const SizedBox(height: 14),
          _field(
            controller: factsController,
            label: 'Historical Information',
            icon: Icons.history_edu_rounded,
            minLines: 6,
            maxLines: 10,
          ),
          const SizedBox(height: 14),
          _field(
            controller: wikipediaController,
            label: 'Wikipedia / Reference Title',
            icon: Icons.menu_book_rounded,
            hint: 'Optional reference title',
          ),
          const SizedBox(height: 14),
          _field(
            controller: videoTitleController,
            label: 'Video Title',
            icon: Icons.video_library_rounded,
            hint: 'Optional',
          ),
          const SizedBox(height: 14),
          _field(
            controller: videoAssetController,
            label: 'Video Asset Path / URL',
            icon: Icons.link_rounded,
            hint: 'Optional',
          ),
          const SizedBox(height: 18),
          const SectionTitle(
            title: 'Heritage Media',
            subtitle:
                'Upload official site photos and an optional video through the existing Cloudinary setup.',
          ),
          const SizedBox(height: 10),
          if (existingSiteImages.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: existingSiteImages.map((url) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        width: 92,
                        height: 92,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 92,
                          height: 92,
                          alignment: Alignment.center,
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image_rounded),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: saving
                              ? null
                              : () {
                                  setState(() {
                                    existingSiteImages.remove(url);
                                  });
                                },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 17,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          if (selectedSiteImages.isNotEmpty)
            InfoCard(
              icon: Icons.add_photo_alternate_rounded,
              title: 'New Photos Selected',
              body:
                  '${selectedSiteImages.length} new photo${selectedSiteImages.length == 1 ? '' : 's'} will upload when you save.',
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: saving ? null : _pickSitePhotos,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text('Add Heritage Photos'),
          ),
          const SizedBox(height: 8),
          if (selectedSiteVideo != null)
            InfoCard(
              icon: Icons.video_file_rounded,
              title: 'New Video Selected',
              body:
                  '${selectedSiteVideo!.name} will replace the current heritage video when saved.',
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: saving ? null : _pickSiteVideo,
            icon: const Icon(Icons.video_library_rounded),
            label: const Text('Select / Replace Heritage Video'),
          ),
          if (uploadStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              uploadStatus,
              style: const TextStyle(
                color: AppColors.brown,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Testing Site',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Enable only for development locations such as UCLM.',
            ),
            value: isTesting,
            onChanged: saving
                ? null
                : (value) {
                    setState(() => isTesting = value);
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Active',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Active sites appear in HeritageBot site features.',
            ),
            value: isActive,
            onChanged: saving
                ? null
                : (value) {
                    setState(() => isActive = value);
                  },
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(saving ? 'Saving...' : 'Save Heritage Site'),
            style: mainButtonStyle(),
          ),
        ],
      ),
    );
  }
}

class _AdminSummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;

  const _AdminSummaryChip({
    required this.label,
    required this.count,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.brown),
          const SizedBox(width: 8),
          Text(
            '$label: $count',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.deepBrown,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminReviewSubmissionScreen extends StatefulWidget {
  final CommunitySubmission submission;

  const AdminReviewSubmissionScreen({super.key, required this.submission});

  @override
  State<AdminReviewSubmissionScreen> createState() =>
      _AdminReviewSubmissionScreenState();
}

class _AdminReviewSubmissionScreenState
    extends State<AdminReviewSubmissionScreen> {
  final CommunitySubmissionService _submissionService =
      CommunitySubmissionService();

  late final TextEditingController feedbackController;

  bool saving = false;

  @override
  void initState() {
    super.initState();
    feedbackController = TextEditingController(
      text: widget.submission.adminFeedback,
    );
  }

  @override
  void dispose() {
    feedbackController.dispose();
    super.dispose();
  }

  Future<void> _review(String status) async {
    final feedback = feedbackController.text.trim();

    if (status == CommunitySubmissionStatus.rejected && feedback.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please provide feedback explaining why the submission was rejected.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => saving = true);

    try {
      await _submissionService.reviewSubmission(
        submissionId: widget.submission.id,
        status: status,
        adminFeedback: feedback,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == CommunitySubmissionStatus.approved
                ? 'Community story approved.'
                : 'Community story rejected.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Contribution')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionTitle(
            title: submission.title,
            subtitle: submission.heritagePlaceName,
          ),
          const SizedBox(height: 16),
          InfoCard(
            icon: Icons.person_rounded,
            title: 'Contributor',
            body: submission.contributorEmail.isEmpty
                ? submission.contributorName
                : '${submission.contributorName}\n${submission.contributorEmail}',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              submission.story,
              style: const TextStyle(
                fontSize: 16,
                height: 1.55,
                color: AppColors.deepBrown,
              ),
            ),
          ),
          const SizedBox(height: 14),
          InfoCard(
            icon: Icons.info_rounded,
            title: 'Current Status',
            body: CommunitySubmissionStatus.label(submission.status),
          ),
          if (submission.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionTitle(
              title: 'Attached Photos',
              subtitle: 'Photos submitted by the Community Contributor.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: submission.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final url = submission.imageUrls[index];

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      url,
                      width: 190,
                      height: 150,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;

                        return const SizedBox(
                          width: 190,
                          height: 150,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (_, __, ___) {
                        return const SizedBox(
                          width: 190,
                          height: 150,
                          child: Center(
                            child: Icon(Icons.broken_image_rounded),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
          if (submission.videoUrls.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionTitle(
              title: 'Attached Videos',
              subtitle: 'Videos submitted by the Community Contributor.',
            ),
            const SizedBox(height: 10),
            ...submission.videoUrls.asMap().entries.map(
              (entry) => LocalJournalVideoPlayer(
                filePath: entry.value,
                title: 'Community Video ${entry.key + 1}',
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: feedbackController,
            minLines: 4,
            maxLines: 7,
            decoration:
                inputDecoration(
                  label: 'Administrator Feedback',
                  icon: Icons.rate_review_rounded,
                ).copyWith(
                  alignLabelWithHint: true,
                  hintText:
                      'Add feedback for the contributor. Feedback is required when rejecting.',
                ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () => _review(CommunitySubmissionStatus.rejected),
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () => _review(CommunitySubmissionStatus.approved),
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(saving ? 'Saving...' : 'Approve'),
                  style: mainButtonStyle(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({super.key});

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends State<LoginSignupScreen> {
  final AuthService _auth = AuthService();
  final UserService _userService = UserService();
  final LanguageService _languageService = LanguageService();

  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool isSignup = false;
  bool loading = false;
  bool hidePassword = true;
  bool hideConfirmPassword = true;
  String selectedLanguageCode = LanguageController.current.value.code;
  String selectedRole = UserRoles.tourist;

  String t(String key) => appText(selectedLanguageCode, key);

  @override
  void initState() {
    super.initState();
    selectedLanguageCode = LanguageController.current.value.code;
  }

  Future<void> submitEmail() async {
    FocusScope.of(context).unfocus();

    final fullName = fullNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (isSignup && fullName.isEmpty) {
      showMessage('Please enter your full name.');
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      showMessage(t('enterEmailPassword'));
      return;
    }

    if (password.length < 6) {
      showMessage(t('passwordLength'));
      return;
    }

    if (isSignup && confirmPassword.isEmpty) {
      showMessage(t('confirmYourPassword'));
      return;
    }

    if (isSignup && password != confirmPassword) {
      showMessage(t('passwordsDoNotMatch'));
      return;
    }

    setState(() => loading = true);

    try {
      if (isSignup) {
        final credential = await _auth.signupWithEmail(
          email,
          password,
          displayName: fullName,
        );

        final user = credential.user;
        if (user == null) {
          throw Exception(
            'Account was created but the user could not be loaded.',
          );
        }

        await _userService.savePublicProfile(
          firebaseUser: user,
          fullName: fullName,
          role: selectedRole,
          preferredLanguage: selectedLanguageCode,
        );

        await _languageService.savePreferredLanguageCode(selectedLanguageCode);

        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      } else {
        await _auth.loginWithEmail(email, password);
      }
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? t('authError'));
    } catch (e) {
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> forgotPassword() async {
    FocusScope.of(context).unfocus();

    final email = emailController.text.trim();

    if (email.isEmpty) {
      showMessage(t('enterEmailFirst'));
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      showMessage(t('validEmail'));
      return;
    }

    if (mounted) {
      setState(() => loading = true);
    }

    try {
      await _auth.sendPasswordResetEmail(email);

      if (!mounted) return;

      showMessage(t('resetSent'));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'user-not-found') {
        showMessage(t('noAccountFound'));
      } else if (e.code == 'invalid-email') {
        showMessage(t('invalidEmail'));
      } else {
        showMessage(e.message ?? t('resetFailed'));
      }
    } catch (_) {
      if (!mounted) return;
      showMessage(t('resetFailed'));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> googleLogin() async {
    setState(() => loading = true);

    try {
      await _auth.signInWithGoogle();

      final user = FirebaseAuth.instance.currentUser;

      if (user != null && isSignup) {
        await _userService.savePublicProfile(
          firebaseUser: user,
          fullName: fullNameController.text.trim(),
          role: selectedRole,
          preferredLanguage: selectedLanguageCode,
        );
        await _languageService.savePreferredLanguageCode(selectedLanguageCode);
      }
    } catch (e) {
      showMessage(e.toString());
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> facebookLogin() async {
    setState(() => loading = true);

    try {
      await _auth.signInWithFacebook();

      final user = FirebaseAuth.instance.currentUser;

      if (user != null && isSignup) {
        await _userService.savePublicProfile(
          firebaseUser: user,
          fullName: fullNameController.text.trim(),
          role: selectedRole,
          preferredLanguage: selectedLanguageCode,
        );
        await _languageService.savePreferredLanguageCode(selectedLanguageCode);
      }
    } catch (e) {
      showMessage(e.toString());
    }

    if (mounted) setState(() => loading = false);
  }

  void showMessage(String text) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);

    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget authTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.deepBrown,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: Colors.black45,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, color: AppColors.brown),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.gold, width: 1.7),
          ),
        ),
      ),
    );
  }

  Widget socialLoginButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.brown,
          side: const BorderSide(color: AppColors.gold, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 25),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget languageSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        initialValue: selectedLanguageCode,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.language_rounded,
            color: AppColors.brown,
          ),
          labelText: t('preferredLanguage'),
          labelStyle: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.gold, width: 1.7),
          ),
        ),
        items: supportedLanguages
            .map(
              (language) => DropdownMenuItem<String>(
                value: language.code,
                child: Text(
                  language.name,
                  style: const TextStyle(
                    color: AppColors.deepBrown,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: loading
            ? null
            : (value) {
                if (value == null) return;
                setState(() => selectedLanguageCode = value);
                LanguageController.setLanguageCode(value);
              },
      ),
    );
  }

  Widget roleSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        initialValue: selectedRole,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.badge_rounded, color: AppColors.brown),
          labelText: 'Account Type',
          labelStyle: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
        ),
        items: const [
          DropdownMenuItem(value: UserRoles.tourist, child: Text('Tourist')),
          DropdownMenuItem(
            value: UserRoles.communityContributor,
            child: Text('Community Contributor'),
          ),
        ],
        onChanged: loading
            ? null
            : (value) {
                if (value == null) return;
                setState(() => selectedRole = value);
              },
      ),
    );
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.brown,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.deepBrown, AppColors.brown, AppColors.clay],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            children: [
              SizedBox(height: size.height * 0.055),
              Center(
                child: Container(
                  width: 92,
                  height: 92,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.gold.withOpacity(0.45),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    size: 58,
                    color: AppColors.gold,
                  ),
                ),
              ),
              const Text(
                'HeritageBot',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 38,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                t('appSubtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.35,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 34),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 25,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      isSignup ? t('createAccount') : t('welcomeBack'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isSignup ? t('signupPrompt') : t('loginPrompt'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (isSignup) ...[
                      authTextField(
                        controller: fullNameController,
                        hint: 'Full name',
                        icon: Icons.person_rounded,
                        keyboardType: TextInputType.name,
                      ),
                      const SizedBox(height: 14),
                    ],
                    authTextField(
                      controller: emailController,
                      hint: t('emailAddress'),
                      icon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    authTextField(
                      controller: passwordController,
                      hint: t('password'),
                      icon: Icons.lock_rounded,
                      obscureText: hidePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: AppColors.brown,
                        ),
                        onPressed: () {
                          setState(() => hidePassword = !hidePassword);
                        },
                      ),
                    ),
                    if (!isSignup) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: loading ? null : forgotPassword,
                          child: Text(
                            t('forgotPassword'),
                            style: const TextStyle(
                              color: AppColors.brown,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (isSignup) ...[
                      const SizedBox(height: 14),
                      authTextField(
                        controller: confirmPasswordController,
                        hint: t('confirmPassword'),
                        icon: Icons.verified_user_rounded,
                        obscureText: hideConfirmPassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            hideConfirmPassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            color: AppColors.brown,
                          ),
                          onPressed: () {
                            setState(() {
                              hideConfirmPassword = !hideConfirmPassword;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      roleSelector(),
                      const SizedBox(height: 14),
                      languageSelector(),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: loading ? null : submitEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brown,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSignup
                                  ? Icons.mark_email_read_rounded
                                  : Icons.login_rounded,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              loading
                                  ? t('pleaseWait')
                                  : isSignup
                                  ? t('createAndSendLink')
                                  : t('login'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.black.withOpacity(0.14),
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            t('orContinueWith'),
                            style: const TextStyle(
                              color: Colors.black45,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.black.withOpacity(0.14),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    socialLoginButton(
                      label: t('continueWithGmail'),
                      icon: Icons.g_mobiledata_rounded,
                      onPressed: loading ? null : googleLogin,
                    ),
                    const SizedBox(height: 12),
                    socialLoginButton(
                      label: t('continueWithFacebook'),
                      icon: Icons.facebook_rounded,
                      onPressed: loading ? null : facebookLogin,
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () {
                              setState(() {
                                isSignup = !isSignup;
                                confirmPasswordController.clear();
                              });
                            },
                      child: Text(
                        isSignup ? t('alreadyHaveAccount') : t('noAccount'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.brown,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({super.key, required this.email});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _auth = AuthService();

  bool loading = false;
  bool resending = false;

  Future<void> checkVerification() async {
    setState(() => loading = true);

    try {
      final verified = await _auth.reloadAndCheckVerified();

      if (!mounted) return;

      if (verified) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      } else {
        showMessage('Email is not verified yet. Please check your Gmail.');
      }
    } catch (e) {
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> resendLink() async {
    setState(() => resending = true);

    try {
      await _auth.resendEmailVerification();
      showMessage('Verification link sent again. Please check your Gmail.');
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? 'Failed to resend verification link.');
    } catch (e) {
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    }

    if (mounted) setState(() => resending = false);
  }

  Future<void> logout() async {
    await _auth.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brown,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.deepBrown, AppColors.brown, AppColors.clay],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const SizedBox(height: 55),
              const Icon(
                Icons.mark_email_read_rounded,
                size: 90,
                color: AppColors.gold,
              ),
              const SizedBox(height: 18),
              const Text(
                'Verify Your Email',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 34,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A free verification link was sent to\n${widget.email}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.4,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 35),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 25,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const InfoCard(
                      icon: Icons.email_rounded,
                      title: 'Check Your Gmail',
                      body:
                          'Open your Gmail inbox, tap the Firebase verification link, then return here and press the button below.',
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        onPressed: loading ? null : checkVerification,
                        icon: const Icon(Icons.verified_rounded),
                        label: Text(
                          loading ? 'Checking...' : 'I Already Verified',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brown,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: resending ? null : resendLink,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        resending ? 'Sending...' : 'Resend Verification Link',
                      ),
                    ),
                    TextButton(
                      onPressed: logout,
                      child: const Text(
                        'Use another account',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.brown,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityStoriesScreen extends StatefulWidget {
  const CommunityStoriesScreen({super.key});

  @override
  State<CommunityStoriesScreen> createState() => _CommunityStoriesScreenState();
}

class _CommunityStoriesScreenState extends State<CommunityStoriesScreen> {
  final CommunitySubmissionService _submissionService =
      CommunitySubmissionService();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<CommunitySubmission>> _storiesFuture;
  String searchText = '';

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  void _loadStories() {
    _storiesFuture = _submissionService.getApprovedSubmissions();
  }

  Future<void> _refresh() async {
    setState(_loadStories);
    await _storiesFuture;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CommunitySubmission> _filtered(List<CommunitySubmission> stories) {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return stories;
    }

    return stories.where((story) {
      return story.title.toLowerCase().contains(query) ||
          story.heritagePlaceName.toLowerCase().contains(query) ||
          story.contributorName.toLowerCase().contains(query) ||
          story.story.toLowerCase().contains(query);
    }).toList();
  }

  void _openStory(CommunitySubmission story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityStoryDetailScreen(story: story),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Stories'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<CommunitySubmission>>(
          future: _storiesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  const InfoCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could Not Load Community Stories',
                    body:
                        'HeritageBot could not load approved community stories from Cloud Firestore.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              );
            }

            final stories = snapshot.data ?? const [];
            final filteredStories = _filtered(stories);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
              children: [
                const SectionTitle(
                  title: 'Approved Local Stories',
                  subtitle:
                      'Explore community-contributed heritage stories that have been reviewed and approved by a HeritageBot Administrator.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => searchText = value);
                  },
                  decoration:
                      inputDecoration(
                        label: 'Search Stories',
                        icon: Icons.search_rounded,
                      ).copyWith(
                        hintText:
                            'Search by title, heritage place, contributor, or story',
                        suffixIcon: searchText.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => searchText = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                ),
                const SizedBox(height: 18),
                if (stories.isEmpty)
                  const InfoCard(
                    icon: Icons.menu_book_rounded,
                    title: 'No Approved Stories Yet',
                    body:
                        'Approved community heritage stories will appear here after Administrator review.',
                  )
                else if (filteredStories.isEmpty)
                  const InfoCard(
                    icon: Icons.search_off_rounded,
                    title: 'No Matching Stories',
                    body:
                        'Try another title, heritage place, contributor name, or keyword.',
                  )
                else
                  ...filteredStories.map(
                    (story) => Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openStory(story),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (story.imageUrls.isNotEmpty)
                              Image.network(
                                story.imageUrls.first,
                                width: double.infinity,
                                height: 180,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;

                                  return const SizedBox(
                                    height: 180,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) {
                                  return Container(
                                    height: 180,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.broken_image_rounded,
                                      size: 42,
                                      color: Colors.black38,
                                    ),
                                  );
                                },
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.verified_rounded,
                                        color: AppColors.brown,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          story.title,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.deepBrown,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.black45,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    story.heritagePlaceName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.brown,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Shared by ${story.contributorName}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    story.story,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(height: 1.45),
                                  ),
                                  if (story.imageUrls.isNotEmpty ||
                                      story.videoUrls.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        if (story.imageUrls.isNotEmpty)
                                          _AttachmentCount(
                                            icon: Icons.photo_library_rounded,
                                            label:
                                                '${story.imageUrls.length} photo${story.imageUrls.length == 1 ? '' : 's'}',
                                          ),
                                        if (story.videoUrls.isNotEmpty)
                                          _AttachmentCount(
                                            icon: Icons.video_library_rounded,
                                            label:
                                                '${story.videoUrls.length} video${story.videoUrls.length == 1 ? '' : 's'}',
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class CommunityStoryDetailScreen extends StatelessWidget {
  final CommunitySubmission story;

  const CommunityStoryDetailScreen({super.key, required this.story});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community Story')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          SectionTitle(title: story.title, subtitle: story.heritagePlaceName),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 18, color: AppColors.brown),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Approved Community Story',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.brown,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          InfoCard(
            icon: Icons.person_rounded,
            title: 'Community Contributor',
            body: story.contributorName,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              story.story,
              style: const TextStyle(
                fontSize: 16,
                height: 1.6,
                color: AppColors.deepBrown,
              ),
            ),
          ),
          if (story.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionTitle(
              title: 'Story Photos',
              subtitle:
                  'Supporting photos shared with this approved community story.',
            ),
            const SizedBox(height: 10),
            ...story.imageUrls.map(
              (url) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    url,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;

                      return const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (_, __, ___) {
                      return const SizedBox(
                        height: 220,
                        child: Center(
                          child: Icon(Icons.broken_image_rounded, size: 42),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          if (story.videoUrls.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionTitle(
              title: 'Story Videos',
              subtitle:
                  'Supporting videos shared with this approved community story.',
            ),
            const SizedBox(height: 10),
            ...story.videoUrls.asMap().entries.map(
              (entry) => LocalJournalVideoPlayer(
                filePath: entry.value,
                title: 'Community Video ${entry.key + 1}',
              ),
            ),
          ],
          const SizedBox(height: 16),
          const InfoCard(
            icon: Icons.fact_check_rounded,
            title: 'Community-Contributed Content',
            body:
                'This story was contributed by a community member and approved through HeritageBot administrator review.',
          ),
        ],
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final String userRole;

  const MainShell({super.key, this.userRole = UserRoles.tourist});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageController.current,
      builder: (context, language, _) {
        final code = language.code;
        final isContributor = widget.userRole == UserRoles.communityContributor;

        final screens = <Widget>[
          const HomeScreen(),
          const GeolocationScreen(),
          const MyJournalScreen(),
          if (isContributor) const ContributorDashboardScreen(),
          const ProfileScreen(),
        ];

        final destinations = <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.home_rounded),
            label: appText(code, 'home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_rounded),
            label: appText(code, 'geolocation'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.book_rounded),
            label: appText(code, 'myJournal'),
          ),
          if (isContributor)
            const NavigationDestination(
              icon: Icon(Icons.history_edu_rounded),
              label: 'Contribute',
            ),
          NavigationDestination(
            icon: const Icon(Icons.person_rounded),
            label: appText(code, 'profile'),
          ),
        ];

        if (currentIndex >= screens.length) {
          currentIndex = 0;
        }

        return Scaffold(
          body: screens[currentIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) {
              setState(() => currentIndex = index);
            },
            destinations: destinations,
          ),
        );
      },
    );
  }
}

class HeritageSiteSearchScreen extends StatefulWidget {
  const HeritageSiteSearchScreen({super.key});

  @override
  State<HeritageSiteSearchScreen> createState() =>
      _HeritageSiteSearchScreenState();
}

class _HeritageSiteSearchScreenState extends State<HeritageSiteSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final HeritageDiscoveryService _discoveryService =
      const HeritageDiscoveryService(
        geminiApiKey: geminiApiKey,
        geminiModel: geminiModel,
      );

  HeritageDiscoveryResult? _discoveryResult;
  bool _searching = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (index) => index);

    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;

      for (var j = 1; j <= b.length; j++) {
        final substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + substitutionCost;

        current[j] = [
          deletion,
          insertion,
          substitution,
        ].reduce((left, right) => left < right ? left : right);
      }

      previous = current;
    }

    return previous[b.length];
  }

  int _registeredSiteScore(HeritagePlace site, String rawQuery) {
    final query = _normalizeSearchText(rawQuery);
    if (query.length < 2 || !site.isActive) return 0;

    final name = _normalizeSearchText(site.name);
    final location = _normalizeSearchText(site.location);

    if (name == query) return 120;
    if (name.startsWith(query)) return 110;
    if (name.contains(query)) return 100;

    final queryWords = query
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    final nameWords = name.split(' ').where((word) => word.isNotEmpty).toList();

    if (queryWords.isNotEmpty &&
        queryWords.every(
          (queryWord) => nameWords.any((nameWord) {
            if (nameWord.startsWith(queryWord)) return true;
            if (queryWord.length < 4) return false;

            final allowed = queryWord.length <= 5 ? 1 : 2;
            return _editDistance(queryWord, nameWord) <= allowed;
          }),
        )) {
      return 92;
    }

    if (query.length >= 4) {
      var bestDistance = 999;
      for (final nameWord in nameWords) {
        final distance = _editDistance(query, nameWord);
        if (distance < bestDistance) bestDistance = distance;
      }

      final wholeNameDistance = _editDistance(query, name);
      if (wholeNameDistance < bestDistance) bestDistance = wholeNameDistance;

      final allowedDistance = query.length <= 5 ? 1 : 2;
      if (bestDistance <= allowedDistance) {
        return 84 - bestDistance;
      }
    }

    if (location.startsWith(query)) return 58;
    if (location.contains(query)) return 52;

    return 0;
  }

  List<HeritagePlace> _registeredSuggestions(String rawQuery) {
    final scored =
        heritagePlaces
            .map((site) => MapEntry(site, _registeredSiteScore(site, rawQuery)))
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) {
            final byScore = b.value.compareTo(a.value);
            if (byScore != 0) return byScore;
            return a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase());
          });

    return scored.take(5).map((entry) => entry.key).toList();
  }

  void _openRegisteredSite(HeritagePlace site) {
    _searchController.text = site.name;
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HeritageSiteDetailScreen(site: site)),
    );
  }

  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.length < 2 || _searching) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _errorMessage = null;
      _discoveryResult = null;
    });

    try {
      final result = await _discoveryService.searchByLocation(query);
      if (!mounted) return;
      setState(() => _discoveryResult = result);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        _errorMessage = message.isEmpty
            ? 'Heritage discovery could not be completed. Please try again.'
            : message;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openDiscoveredSite(DiscoveredHeritagePlace place) {
    final result = _discoveryResult;
    if (result == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoveredHeritageDetailScreen(
          place: place,
          searchedArea: result.resolvedLocation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _discoveryResult;
    final typedQuery = _searchController.text.trim();
    final registeredSuggestions = _registeredSuggestions(typedQuery);

    return Scaffold(
      appBar: AppBar(title: const Text('Explore Heritage')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          const SectionTitle(
            title: 'Search Heritage or Location',
            subtitle:
                'Start typing a heritage-site name for instant matches, or enter any city, barangay, municipality, or place to discover heritage beyond your current GPS location.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchLocation(),
            decoration:
                inputDecoration(
                  label: 'Search heritage or location',
                  icon: Icons.travel_explore_rounded,
                ).copyWith(
                  hintText: 'Type a site name or location',
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _discoveryResult = null;
                              _errorMessage = null;
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
            onChanged: (_) {
              setState(() {
                _discoveryResult = null;
                _errorMessage = null;
              });
            },
          ),
          if (registeredSuggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.manage_search_rounded,
                          size: 19,
                          color: AppColors.brown,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Matching Heritage Sites',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.deepBrown,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...registeredSuggestions.map(
                    (site) => ListTile(
                      dense: true,
                      leading: Icon(
                        site.isTesting
                            ? Icons.science_rounded
                            : Icons.account_balance_rounded,
                        color: AppColors.brown,
                      ),
                      title: Text(
                        site.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(site.location),
                      trailing: const Icon(Icons.north_east_rounded, size: 18),
                      onTap: () => _openRegisteredSite(site),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: mainButtonStyle(),
              onPressed: _searching ? null : _searchLocation,
              icon: _searching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _searching
                    ? 'Discovering Heritage...'
                    : 'Search Any Location with AI',
              ),
            ),
          ),
          if (typedQuery.length >= 2 && registeredSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Tap a matching HeritageBot site above, or use the AI button to search the typed place dynamically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withValues(alpha: 0.58),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_errorMessage != null)
            InfoCard(
              icon: Icons.error_outline_rounded,
              title: 'Search Could Not Be Completed',
              body: _errorMessage!,
            )
          else if (result == null && !_searching && typedQuery.isEmpty)
            const InfoCard(
              icon: Icons.search_rounded,
              title: 'Start Typing',
              body:
                  'Typing part of a registered heritage-site name immediately shows matching sites. For other places, type the location or place name and use AI heritage search.',
            ),
          if (result != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          color: AppColors.brown,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Search Area',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.deepBrown,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(result.resolvedLocation),
                              const SizedBox(height: 8),
                              Text(
                                '${result.places.length} heritage result${result.places.length == 1 ? '' : 's'} found',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brown,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (result.places.isEmpty)
              const InfoCard(
                icon: Icons.search_off_rounded,
                title: 'No Heritage Places Found',
                body:
                    'No named heritage, historic, or museum records were found near that location. Try a nearby city, municipality, or a more specific place name.',
              )
            else ...[
              const SectionTitle(
                title: 'Discovered Heritage Places',
                subtitle:
                    'Tap a result to let HeritageBot explain what can be found there, its retrieved history, cultural significance, and what you can learn.',
              ),
              const SizedBox(height: 12),
              ...result.places.map(
                (place) => _DynamicHeritageSearchCard(
                  place: place,
                  onTap: () => _openDiscoveredSite(place),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DynamicHeritageSearchCard extends StatelessWidget {
  final DiscoveredHeritagePlace place;
  final VoidCallback onTap;

  const _DynamicHeritageSearchCard({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasWikipedia = place.sourceSummary.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: AppColors.gold.withOpacity(0.28),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: AppColors.brown,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      place.category,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brown,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(place.location),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(
                          Icons.source_rounded,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            hasWikipedia
                                ? 'External sources: OpenStreetMap + Wikipedia'
                                : 'External source: OpenStreetMap',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DiscoveredHeritageDetailScreen extends StatefulWidget {
  final DiscoveredHeritagePlace place;
  final String searchedArea;

  const DiscoveredHeritageDetailScreen({
    super.key,
    required this.place,
    required this.searchedArea,
  });

  @override
  State<DiscoveredHeritageDetailScreen> createState() =>
      _DiscoveredHeritageDetailScreenState();
}

class _DiscoveredHeritageDetailScreenState
    extends State<DiscoveredHeritageDetailScreen> {
  final HeritageDiscoveryService _discoveryService =
      const HeritageDiscoveryService(
        geminiApiKey: geminiApiKey,
        geminiModel: geminiModel,
      );

  bool _loading = true;
  String? _guide;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGuide();
  }

  Future<void> _loadGuide() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final guide = await _discoveryService.generateAiGuide(
        place: widget.place,
        searchedArea: widget.searchedArea,
      );
      if (!mounted) return;
      setState(() => _guide = guide);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '').trim();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Heritage Guide')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          Text(
            place.name,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.deepBrown,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${place.category} • ${place.location}',
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.brown,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          const InfoCard(
            icon: Icons.travel_explore_rounded,
            title: 'External Heritage Discovery',
            body:
                'This place was dynamically discovered from external sources. It is not automatically a registered HeritageBot geofence site or a verified record in the HeritageBot RAG knowledge base.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InAppNavigationScreen(
                      destinationName: place.name,
                      destinationLocation: place.location,
                      destinationLat: place.latitude,
                      destinationLng: place.longitude,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.directions_walk_rounded),
              label: const Text('Navigate Inside HeritageBot'),
              style: mainButtonStyle(),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: AppColors.brown),
                      SizedBox(width: 9),
                      Text(
                        'HeritageBot AI Explanation',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.deepBrown,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Preparing grounded heritage explanation...'),
                          ],
                        ),
                      ),
                    )
                  else if (_error != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadGuide,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                        ),
                      ],
                    )
                  else
                    SelectableText(
                      _guide ?? 'No explanation is available for this result.',
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Retrieved Source Information',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Coordinates: ${place.latitude.toStringAsFixed(6)}, ${place.longitude.toStringAsFixed(6)}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    place.sourceSummary.trim().isEmpty
                        ? 'No Wikipedia summary was retrieved for this result. HeritageBot will avoid inventing missing historical details.'
                        : place.sourceSummary,
                  ),
                  if (place.osmUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'OpenStreetMap source:',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SelectableText(place.osmUrl),
                  ],
                  if (place.wikipediaUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Wikipedia source:',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SelectableText(place.wikipediaUrl),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InAppNavigationScreen extends StatefulWidget {
  final String destinationName;
  final String destinationLocation;
  final double destinationLat;
  final double destinationLng;
  final HeritagePlace? registeredSite;

  const InAppNavigationScreen({
    super.key,
    required this.destinationName,
    required this.destinationLocation,
    required this.destinationLat,
    required this.destinationLng,
    this.registeredSite,
  });

  @override
  State<InAppNavigationScreen> createState() => _InAppNavigationScreenState();
}

class _InAppNavigationScreenState extends State<InAppNavigationScreen> {
  final LocationService _locationService = LocationService();
  final NavigationService _navigationService = const NavigationService();
  final MapController _mapController = MapController();
  final JournalService _journalService = JournalService();
  final GeminiStoryService _geminiStoryService = GeminiStoryService();
  final LanguageService _languageService = LanguageService();

  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  Position? _lastRouteOrigin;
  HeritageNavigationRoute? _route;
  DateTime? _lastRouteRequestAt;

  bool _loadingLocation = true;
  bool _loadingRoute = false;
  bool _arrivalNarrativeShown = false;
  bool _arrivalNoticeShown = false;
  String? _routeError;

  LatLng get _destination =>
      LatLng(widget.destinationLat, widget.destinationLng);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNavigation();
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startNavigation() async {
    setState(() {
      _loadingLocation = true;
      _routeError = null;
    });

    try {
      final position = await _locationService.getCurrentPosition();
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _loadingLocation = false;
      });

      await _loadRoute(position);
      await _positionSubscription?.cancel();
      _positionSubscription = _locationService.getLivePositionStream().listen(
        _handlePositionUpdate,
        onError: (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Live navigation location error: ${error.toString()}',
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _routeError = error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<void> _loadRoute(Position position, {bool silent = false}) async {
    if (_loadingRoute) return;

    setState(() {
      _loadingRoute = true;
      if (!silent) _routeError = null;
    });

    try {
      final route = await _navigationService.buildPedestrianRoute(
        start: LatLng(position.latitude, position.longitude),
        destination: _destination,
      );

      if (!mounted) return;

      setState(() {
        _route = route;
        _lastRouteOrigin = position;
        _lastRouteRequestAt = DateTime.now();
        _routeError = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || route.points.isEmpty) return;
        try {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(route.points),
              padding: const EdgeInsets.fromLTRB(42, 42, 42, 86),
              maxZoom: 18,
            ),
          );
        } catch (_) {}
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _routeError = error.toString().replaceFirst('Exception: ', '').trim();
      });
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  void _handlePositionUpdate(Position position) {
    if (!mounted) return;

    setState(() => _currentPosition = position);

    final directDistance = _distanceToDestination(position);
    final registeredSite = widget.registeredSite;

    if (registeredSite != null &&
        directDistance <= registeredSite.detectionRadiusMeters &&
        !_arrivalNarrativeShown) {
      _arrivalNarrativeShown = true;
      unawaited(_showArrivalNarrative(position, registeredSite));
    } else if (registeredSite == null &&
        directDistance <= 30 &&
        !_arrivalNoticeShown) {
      _arrivalNoticeShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You have reached ${widget.destinationName}. This dynamically discovered place is not a registered HeritageBot geofence site.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    unawaited(_maybeRefreshRoute(position));
  }

  Future<void> _maybeRefreshRoute(Position position) async {
    final previousOrigin = _lastRouteOrigin;
    final previousRequest = _lastRouteRequestAt;

    if (previousOrigin == null || previousRequest == null) return;

    final movedMeters = Geolocator.distanceBetween(
      previousOrigin.latitude,
      previousOrigin.longitude,
      position.latitude,
      position.longitude,
    );

    final secondsSinceRoute = DateTime.now()
        .difference(previousRequest)
        .inSeconds;

    if (movedMeters >= 60 && secondsSinceRoute >= 20) {
      await _loadRoute(position, silent: true);
    }
  }

  double _distanceToDestination(Position position) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      widget.destinationLat,
      widget.destinationLng,
    );
  }

  int _nearestRoutePointIndex(Position position) {
    final route = _route;
    if (route == null || route.points.isEmpty) return 0;

    var bestIndex = 0;
    var bestDistance = double.infinity;

    for (var index = 0; index < route.points.length; index++) {
      final point = route.points[index];
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }

    return bestIndex;
  }

  NavigationStep? _currentNavigationStep() {
    final route = _route;
    final position = _currentPosition;

    if (route == null || position == null || route.steps.isEmpty) return null;

    final shapeIndex = _nearestRoutePointIndex(position);

    for (final step in route.steps) {
      if (shapeIndex >= step.beginShapeIndex &&
          shapeIndex <= step.endShapeIndex) {
        return step;
      }
    }

    for (final step in route.steps) {
      if (step.beginShapeIndex >= shapeIndex) return step;
    }

    return route.steps.last;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$hours hr'
        : '$hours hr $remainingMinutes min';
  }

  void _centerOnUser() {
    final position = _currentPosition;
    if (position == null) return;

    try {
      _mapController.move(LatLng(position.latitude, position.longitude), 17);
    } catch (_) {}
  }

  void _fitWholeRoute() {
    final route = _route;
    if (route == null || route.points.isEmpty) return;

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(route.points),
          padding: const EdgeInsets.fromLTRB(42, 42, 42, 86),
          maxZoom: 18,
        ),
      );
    } catch (_) {}
  }

  Future<void> _showArrivalNarrative(
    Position position,
    HeritagePlace site,
  ) async {
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      site.lat,
      site.lng,
    );

    final preferredLanguage = await _languageService.getPreferredLanguage();
    final entries = await _journalService.getEntriesByPlace(site.id);

    if (!mounted) return;

    final storyFuture = _geminiStoryService.generateContextAwareStory(
      place: site,
      distanceMeters: distance,
      speedMetersPerSecond: position.speed,
      memories: entries,
      preferredLanguage: preferredLanguage,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bg,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.90,
          minChildSize: 0.45,
          maxChildSize: 0.97,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                const Row(
                  children: [
                    Icon(Icons.flag_circle_rounded, color: AppColors.brown),
                    SizedBox(width: 8),
                    Text(
                      'Heritage Site Reached',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  site.name,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBrown,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${site.location} • ${_formatDistance(distance)} away',
                  style: const TextStyle(
                    color: AppColors.clay,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                NarrativeTranslationPanel(
                  storyFuture: storyFuture,
                  initialLanguage: preferredLanguage,
                ),
                if (site.videoAsset != null) ...[
                  const SizedBox(height: 14),
                  HeritageVideoPlayer(
                    title: site.videoTitle,
                    assetPath: site.videoAsset!,
                  ),
                ],
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      this.context,
                      MaterialPageRoute(
                        builder: (_) => AddJournalScreen(place: site),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(appText(preferredLanguage.code, 'addMemoryHere')),
                  style: mainButtonStyle(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = _currentPosition;
    final route = _route;
    final currentStep = _currentNavigationStep();
    final directDistance = position == null
        ? null
        : _distanceToDestination(position);

    final center = position == null
        ? _destination
        : LatLng(position.latitude, position.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Heritage Navigation'),
        actions: [
          IconButton(
            tooltip: 'Fit Route',
            onPressed: route == null ? null : _fitWholeRoute,
            icon: const Icon(Icons.fit_screen_rounded),
          ),
        ],
      ),
      floatingActionButton: position == null
          ? null
          : FloatingActionButton.small(
              onPressed: _centerOnUser,
              tooltip: 'Center on my location',
              child: const Icon(Icons.my_location_rounded),
            ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: center, initialZoom: 16),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.heritagebot',
                    ),
                    if (route != null && route.points.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route.points,
                            strokeWidth: 6,
                            color: AppColors.brown,
                            borderStrokeWidth: 2,
                            borderColor: Colors.white,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (position != null)
                          Marker(
                            point: LatLng(
                              position.latitude,
                              position.longitude,
                            ),
                            width: 54,
                            height: 54,
                            child: const Icon(
                              Icons.navigation_rounded,
                              color: Colors.blue,
                              size: 42,
                            ),
                          ),
                        Marker(
                          point: _destination,
                          width: 54,
                          height: 54,
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.red,
                            size: 46,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_loadingLocation || _loadingRoute)
                  Positioned(
                    top: 14,
                    left: 14,
                    right: 14,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _loadingLocation
                                    ? 'Getting your current GPS location...'
                                    : 'Calculating pedestrian route...',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                children: [
                  Text(
                    widget.destinationName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.destinationLocation,
                    style: const TextStyle(
                      color: AppColors.clay,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (route != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.route_rounded, size: 18),
                          label: Text(
                            '${route.distanceKm.toStringAsFixed(2)} km route',
                          ),
                        ),
                        Chip(
                          avatar: const Icon(Icons.schedule_rounded, size: 18),
                          label: Text(_formatDuration(route.timeSeconds)),
                        ),
                        if (directDistance != null)
                          Chip(
                            avatar: const Icon(
                              Icons.social_distance_rounded,
                              size: 18,
                            ),
                            label: Text(
                              '${_formatDistance(directDistance)} remaining',
                            ),
                          ),
                      ],
                    ),
                  if (_routeError != null) ...[
                    const SizedBox(height: 8),
                    InfoCard(
                      icon: Icons.route_rounded,
                      title: 'Route Could Not Be Loaded',
                      body:
                          '${_routeError!}\n\nCheck your internet connection, then retry.',
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: position == null || _loadingRoute
                          ? null
                          : () => _loadRoute(position),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry Route'),
                      style: mainButtonStyle(),
                    ),
                  ] else if (currentStep != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.directions_walk_rounded,
                              color: AppColors.brown,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Current Direction',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.deepBrown,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    currentStep.instruction,
                                    style: const TextStyle(height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (route != null && route.steps.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Walking Directions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...route.steps.asMap().entries.map((entry) {
                      final step = entry.value;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.gold.withValues(
                            alpha: 0.28,
                          ),
                          child: Text(
                            '${entry.key + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppColors.deepBrown,
                            ),
                          ),
                        ),
                        title: Text(
                          step.instruction,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: step.distanceKm <= 0
                            ? null
                            : Text(
                                '${step.distanceKm.toStringAsFixed(2)} km • ${_formatDuration(step.timeSeconds)}',
                              ),
                      );
                    }),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'Route guidance uses OpenStreetMap routing data inside HeritageBot. GPS accuracy and route availability depend on the device, internet connection, and available map data.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeritageSearchCard extends StatelessWidget {
  final HeritagePlace site;
  final VoidCallback onTap;

  const _HeritageSearchCard({required this.site, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.gold.withOpacity(0.28),
          child: Icon(
            site.isTesting
                ? Icons.science_rounded
                : Icons.account_balance_rounded,
            color: AppColors.brown,
          ),
        ),
        title: Text(
          site.name,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.deepBrown,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            site.isTesting ? '${site.location}\nTEST SITE' : site.location,
          ),
        ),
        isThreeLine: site.isTesting,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class HeritageSiteDetailScreen extends StatefulWidget {
  final HeritagePlace site;

  const HeritageSiteDetailScreen({super.key, required this.site});

  @override
  State<HeritageSiteDetailScreen> createState() =>
      _HeritageSiteDetailScreenState();
}

class _HeritageSiteDetailScreenState extends State<HeritageSiteDetailScreen> {
  final BookmarkService _bookmarkService = BookmarkService();

  bool loadingBookmark = true;
  bool savingBookmark = false;
  bool bookmarked = false;

  HeritagePlace get site => widget.site;

  @override
  void initState() {
    super.initState();
    _loadBookmark();
  }

  Future<void> _loadBookmark() async {
    try {
      final value = await _bookmarkService.isBookmarked(site.id);

      if (!mounted) return;

      setState(() {
        bookmarked = value;
        loadingBookmark = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loadingBookmark = false;
      });
    }
  }

  Future<void> _toggleBookmark() async {
    if (savingBookmark) return;

    setState(() => savingBookmark = true);

    try {
      final newValue = await _bookmarkService.toggleBookmark(site);

      if (!mounted) return;

      setState(() {
        bookmarked = newValue;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              newValue
                  ? '${site.name} added to bookmarks.'
                  : '${site.name} removed from bookmarks.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => savingBookmark = false);
      }
    }
  }

  Widget _typeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        site.isTesting ? 'TEST SITE' : 'OFFICIAL SITE',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppColors.brown,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoAsset = site.videoAsset?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(site.name),
        actions: [
          IconButton(
            tooltip: bookmarked ? 'Remove Bookmark' : 'Add Bookmark',
            onPressed: loadingBookmark || savingBookmark
                ? null
                : _toggleBookmark,
            icon: savingBookmark
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    bookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionTitle(title: site.name, subtitle: site.location),
              ),
              const SizedBox(width: 10),
              _typeBadge(),
            ],
          ),
          const SizedBox(height: 14),
          InfoCard(
            icon: Icons.place_rounded,
            title: 'Location',
            body:
                '${site.location}\nLatitude: ${site.lat.toStringAsFixed(5)}\nLongitude: ${site.lng.toStringAsFixed(5)}\nNarrative trigger range: ${site.detectionRadiusMeters.toStringAsFixed(0)} meters',
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InAppNavigationScreen(
                      destinationName: site.name,
                      destinationLocation: site.location,
                      destinationLat: site.lat,
                      destinationLng: site.lng,
                      registeredSite: site,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.directions_walk_rounded),
              label: const Text('Navigate Inside HeritageBot'),
              style: mainButtonStyle(),
            ),
          ),
          const SizedBox(height: 10),
          InfoCard(
            icon: Icons.history_edu_rounded,
            title: 'Historical Information',
            body: site.historicalFacts,
          ),
          if (site.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionTitle(
              title: 'Heritage Photos',
              subtitle:
                  'Administrator-managed photos related to this heritage site.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: site.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      site.imageUrls[index],
                      width: 250,
                      height: 190,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 250,
                          height: 190,
                          alignment: Alignment.center,
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image_rounded),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loadingBookmark || savingBookmark
                  ? null
                  : _toggleBookmark,
              icon: Icon(
                bookmarked
                    ? Icons.bookmark_remove_rounded
                    : Icons.bookmark_add_rounded,
              ),
              label: Text(
                bookmarked ? 'Remove Bookmark' : 'Bookmark Heritage Site',
              ),
              style: mainButtonStyle(),
            ),
          ),
          if (videoAsset.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionTitle(
              title: 'Heritage Video',
              subtitle:
                  'Watch the media currently attached to this heritage site.',
            ),
            const SizedBox(height: 10),
            if (videoAsset.startsWith('http'))
              LocalJournalVideoPlayer(
                filePath: videoAsset,
                title: site.videoTitle.isEmpty
                    ? '${site.name} Video'
                    : site.videoTitle,
              )
            else
              HeritageVideoPlayer(
                title: site.videoTitle.isEmpty
                    ? '${site.name} Video'
                    : site.videoTitle,
                assetPath: videoAsset,
              ),
          ],
          if (site.wikipediaTitle.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            InfoCard(
              icon: Icons.menu_book_rounded,
              title: 'Reference Title',
              body: site.wikipediaTitle,
            ),
          ],
        ],
      ),
    );
  }
}

class BookmarkedSitesScreen extends StatefulWidget {
  const BookmarkedSitesScreen({super.key});

  @override
  State<BookmarkedSitesScreen> createState() => _BookmarkedSitesScreenState();
}

class _BookmarkedSitesScreenState extends State<BookmarkedSitesScreen> {
  final BookmarkService _bookmarkService = BookmarkService();

  late Future<Set<String>> _bookmarksFuture;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  void _loadBookmarks() {
    _bookmarksFuture = _bookmarkService.getBookmarkedSiteIds();
  }

  Future<void> _refresh() async {
    setState(_loadBookmarks);
    await _bookmarksFuture;
  }

  Future<void> _openSite(HeritagePlace site) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HeritageSiteDetailScreen(site: site)),
    );

    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarked Sites'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Set<String>>(
          future: _bookmarksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  const InfoCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could Not Load Bookmarks',
                    body:
                        'Check that the Step 11 Firestore rules were published.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              );
            }

            final ids = snapshot.data ?? <String>{};

            final sites =
                heritagePlaces
                    .where((site) => ids.contains(site.id) && site.isActive)
                    .toList()
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );

            final unavailableCount = ids.length - sites.length;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
              children: [
                const SectionTitle(
                  title: 'Saved Heritage Sites',
                  subtitle:
                      'Bookmarks are saved to your HeritageBot account in Cloud Firestore.',
                ),
                const SizedBox(height: 16),
                if (sites.isEmpty)
                  const InfoCard(
                    icon: Icons.bookmark_border_rounded,
                    title: 'No Bookmarked Sites',
                    body:
                        'Search for a heritage site and tap Bookmark Heritage Site to save it here.',
                  )
                else
                  ...sites.map(
                    (site) => _HeritageSearchCard(
                      site: site,
                      onTap: () => _openSite(site),
                    ),
                  ),
                if (unavailableCount > 0) ...[
                  const SizedBox(height: 10),
                  InfoCard(
                    icon: Icons.info_outline_rounded,
                    title: 'Unavailable Bookmark',
                    body:
                        '$unavailableCount saved site${unavailableCount == 1 ? ' is' : 's are'} currently inactive or no longer available in HeritageBot.',
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void openVideo(BuildContext context, HeritagePlace place) {
    if (!place.hasVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appText(LanguageController.current.value.code, 'noVideoBody'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HeritageVideoScreen(place: place)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoPlaces = heritagePlaces
        .where((place) => place.hasVideo)
        .toList();
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageController.current,
      builder: (context, language, _) {
        final code = language.code;
        return Scaffold(
          appBar: AppBar(title: const Text('HeritageBot')),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.brown, AppColors.clay],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.travel_explore_rounded,
                      size: 58,
                      color: AppColors.gold,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      appText(code, 'welcomeHome'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      appText(code, 'homeIntro'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle(
                title: appText(code, 'aboutSystem'),
                subtitle: appText(code, 'aboutSystemBody'),
              ),
              const SizedBox(height: 16),
              InfoCard(
                icon: Icons.auto_awesome_rounded,
                title: appText(code, 'aiStoryTitle'),
                body: appText(code, 'aiStoryBody'),
              ),
              InfoCard(
                icon: Icons.directions_walk_rounded,
                title: appText(code, 'liveMapTitle'),
                body: appText(code, 'liveMapBody'),
              ),
              InfoCard(
                icon: Icons.book_rounded,
                title: appText(code, 'memoryJournalTitle'),
                body: appText(code, 'memoryJournalBody'),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: const Icon(
                    Icons.search_rounded,
                    color: AppColors.brown,
                  ),
                  title: const Text(
                    'Explore Heritage by Location',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  ),
                  subtitle: const Text(
                    'Search any location to discover nearby heritage places and open an AI-grounded heritage guide.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HeritageSiteSearchScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: const Icon(
                    Icons.bookmark_rounded,
                    color: AppColors.brown,
                  ),
                  title: const Text(
                    'Bookmarked Sites',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  ),
                  subtitle: const Text(
                    'Open the heritage locations you saved for quick access.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BookmarkedSitesScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: const Icon(
                    Icons.groups_rounded,
                    color: AppColors.brown,
                  ),
                  title: const Text(
                    'Community Stories',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  ),
                  subtitle: const Text(
                    'Read heritage stories contributed by the community and approved by an Administrator.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CommunityStoriesScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SectionTitle(
                title: appText(code, 'heritageVideos'),
                subtitle: '',
              ),
              const SizedBox(height: 8),
              ...videoPlaces.map(
                (place) => VideoPlaceCard(
                  place: place,
                  onTap: () => openVideo(context, place),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class HeritageVideoScreen extends StatelessWidget {
  final HeritagePlace place;

  const HeritageVideoScreen({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageController.current,
      builder: (context, language, _) {
        final code = language.code;

        return Scaffold(
          appBar: AppBar(title: Text(place.name)),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (place.hasVideo && place.videoAsset != null)
                HeritageVideoPlayer(
                  title: place.videoTitle,
                  assetPath: place.videoAsset!,
                )
              else
                InfoCard(
                  icon: Icons.video_library_rounded,
                  title: appText(code, 'noVideoTitle'),
                  body: appText(code, 'noVideoBody'),
                ),
              const SizedBox(height: 18),
              InfoCard(
                icon: Icons.info_rounded,
                title: appText(code, 'verifiedFacts'),
                body: place.historicalFacts,
              ),
            ],
          ),
        );
      },
    );
  }
}

class NarrativeTranslationPanel extends StatefulWidget {
  final Future<String> storyFuture;
  final AppLanguage initialLanguage;

  const NarrativeTranslationPanel({
    super.key,
    required this.storyFuture,
    required this.initialLanguage,
  });

  @override
  State<NarrativeTranslationPanel> createState() =>
      _NarrativeTranslationPanelState();
}

class _NarrativeTranslationPanelState extends State<NarrativeTranslationPanel> {
  final GeminiStoryService _storyService = GeminiStoryService();

  String? _originalStory;
  String? _displayedStory;
  String? _errorMessage;
  late AppLanguage _displayedLanguage;
  late AppLanguage _targetLanguage;
  bool _loadingStory = true;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _displayedLanguage = widget.initialLanguage;
    _targetLanguage = widget.initialLanguage;
    _loadStory();
  }

  Future<void> _loadStory() async {
    try {
      final story = await widget.storyFuture;

      if (!mounted) return;

      setState(() {
        _originalStory = story;
        _displayedStory = story;
        _loadingStory = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingStory = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _translate() async {
    final originalStory = _originalStory?.trim() ?? '';

    if (originalStory.isEmpty || _translating) return;

    if (_targetLanguage.code == widget.initialLanguage.code) {
      setState(() {
        _displayedStory = _originalStory;
        _displayedLanguage = widget.initialLanguage;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _translating = true;
      _errorMessage = null;
    });

    try {
      final translated = await _storyService.translateNarrative(
        narrative: originalStory,
        sourceLanguage: widget.initialLanguage,
        targetLanguage: _targetLanguage,
      );

      if (!mounted) return;

      setState(() {
        _displayedStory = translated;
        _displayedLanguage = _targetLanguage;
        _translating = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _translating = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showOriginal() {
    setState(() {
      _targetLanguage = widget.initialLanguage;
      _displayedLanguage = widget.initialLanguage;
      _displayedStory = _originalStory;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingStory) {
      return InfoCard(
        icon: Icons.auto_awesome_rounded,
        title: appText(widget.initialLanguage.code, 'generatingStory'),
        body: appText(widget.initialLanguage.code, 'generatingStoryBody'),
      );
    }

    if (_displayedStory == null || _displayedStory!.trim().isEmpty) {
      return InfoCard(
        icon: Icons.error_outline_rounded,
        title: 'Narrative Unavailable',
        body: _errorMessage ?? 'HeritageBot could not load the narrative.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoCard(
          icon: Icons.auto_awesome_rounded,
          title: appText(widget.initialLanguage.code, 'contextStoryTitle'),
          body: _displayedStory!,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.gold.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.translate_rounded, color: AppColors.brown),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Translate Narrative',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Current narrative: ${_displayedLanguage.name}',
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _targetLanguage.code,
                decoration: const InputDecoration(
                  labelText: 'Translate to',
                  border: OutlineInputBorder(),
                ),
                items: supportedLanguages
                    .map(
                      (language) => DropdownMenuItem<String>(
                        value: language.code,
                        child: Text(language.name),
                      ),
                    )
                    .toList(),
                onChanged: _translating
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _targetLanguage = languageByCode(value);
                        });
                      },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _translating ? null : _translate,
                      icon: _translating
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.translate_rounded),
                      label: Text(
                        _translating ? 'Translating...' : 'Translate',
                      ),
                      style: mainButtonStyle(),
                    ),
                  ),
                  if (_displayedLanguage.code !=
                      widget.initialLanguage.code) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _translating ? null : _showOriginal,
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Original'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NarrativeAudioControls(
          key: ValueKey(
            '${_displayedLanguage.code}-${_displayedStory.hashCode}',
          ),
          storyFuture: Future<String>.value(_displayedStory!),
          languageCode: _displayedLanguage.code,
        ),
      ],
    );
  }
}

class NarrativeAudioControls extends StatefulWidget {
  final Future<String> storyFuture;
  final String languageCode;

  const NarrativeAudioControls({
    super.key,
    required this.storyFuture,
    required this.languageCode,
  });

  @override
  State<NarrativeAudioControls> createState() => _NarrativeAudioControlsState();
}

class _NarrativeAudioControlsState extends State<NarrativeAudioControls> {
  final NarrativeAudioService _audioService = NarrativeAudioService();

  bool preparing = false;
  bool speaking = false;
  String? errorMessage;

  Future<void> _listen() async {
    if (preparing || speaking) return;

    setState(() {
      preparing = true;
      errorMessage = null;
    });

    try {
      final story = await widget.storyFuture;

      if (!mounted) return;

      if (story.trim().isEmpty) {
        throw Exception('The narrative is empty and cannot be played.');
      }

      setState(() {
        preparing = false;
        speaking = true;
      });

      await _audioService.speak(text: story, languageCode: widget.languageCode);

      if (!mounted) return;

      setState(() => speaking = false);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        preparing = false;
        speaking = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _stop() async {
    await _audioService.stop();

    if (!mounted) return;

    setState(() {
      preparing = false;
      speaking = false;
    });
  }

  @override
  void dispose() {
    _audioService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.record_voice_over_rounded, color: AppColors.brown),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Audio Narrative',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBrown,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            speaking
                ? 'HeritageBot is reading the generated narrative aloud.'
                : preparing
                ? 'Preparing the generated narrative...'
                : 'Listen to the AI-generated historical narrative using your phone’s text-to-speech voice.',
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 9),
            Text(
              errorMessage!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: preparing || speaking ? null : _listen,
                  icon: preparing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.volume_up_rounded),
                  label: Text(
                    preparing
                        ? 'Preparing...'
                        : speaking
                        ? 'Playing...'
                        : 'Listen',
                  ),
                  style: mainButtonStyle(),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: preparing || speaking ? _stop : null,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GeolocationScreen extends StatefulWidget {
  const GeolocationScreen({super.key});

  @override
  State<GeolocationScreen> createState() => _GeolocationScreenState();
}

class _GeolocationScreenState extends State<GeolocationScreen> {
  final LocationService locationService = LocationService();
  final JournalService journalService = JournalService();
  final GeminiStoryService geminiStoryService = GeminiStoryService();
  final LanguageService languageService = LanguageService();
  final MapController mapController = MapController();

  Position? currentPosition;
  HeritagePlace? nearestPlace;
  double? nearestDistance;
  StreamSubscription<Position>? positionSubscription;

  bool loading = false;
  bool popupIsOpen = false;
  String? lastPopupPlaceId;
  DateTime? lastPopupTime;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      startLiveTracking();
    });
  }

  @override
  void dispose() {
    positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> startLiveTracking() async {
    setState(() => loading = true);

    try {
      final firstPosition = await locationService.getCurrentPosition();
      handleNewPosition(firstPosition, autoMode: true);

      await positionSubscription?.cancel();

      positionSubscription = locationService.getLivePositionStream().listen(
        (position) {
          handleNewPosition(position, autoMode: true);
        },
        onError: (_) {
          if (mounted) {
            setState(() => loading = false);
          }
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${appText(LanguageController.current.value.code, 'failedLocation')}: ${e.toString().replaceFirst('Exception: ', '')}",
          ),
        ),
      );
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> handleNewPosition(
    Position position, {
    required bool autoMode,
  }) async {
    final place = locationService.nearestPlace(position);
    final distance = locationService.distanceToPlace(position, place);

    if (!mounted) return;

    setState(() {
      currentPosition = position;
      nearestPlace = place;
      nearestDistance = distance;
    });

    try {
      mapController.move(LatLng(position.latitude, position.longitude), 17);
    } catch (_) {}

    if (distance <= place.detectionRadiusMeters) {
      final now = DateTime.now();
      final enoughTimePassed =
          lastPopupTime == null ||
          now.difference(lastPopupTime!).inSeconds >= 30;

      if (!popupIsOpen && (lastPopupPlaceId != place.id || enoughTimePassed)) {
        lastPopupPlaceId = place.id;
        lastPopupTime = now;

        final entries = await journalService.getEntriesByPlace(place.id);

        if (!mounted) return;

        await showPlacePopup(place, entries, distance, position.speed);
      }
    } else if (!autoMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nearest place: ${place.name}. Distance: ${distance.toStringAsFixed(0)} m. '
            'Narrative trigger range: ${place.detectionRadiusMeters.toStringAsFixed(0)} m.',
          ),
        ),
      );
    }
  }

  Future<void> forceRefresh() async {
    lastPopupPlaceId = null;
    lastPopupTime = null;

    setState(() => loading = true);

    try {
      final position = await locationService.getCurrentPosition();
      await handleNewPosition(position, autoMode: false);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${appText(LanguageController.current.value.code, 'failedLocation')}: ${e.toString().replaceFirst('Exception: ', '')}",
          ),
        ),
      );
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _showMapSiteOptions(HeritagePlace place) async {
    final position = currentPosition;
    final distance = position == null
        ? null
        : Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            place.lat,
            place.lng,
          );

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.bg,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBrown,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  distance == null
                      ? place.location
                      : '${place.location} • ${(distance / 1000).toStringAsFixed(2)} km away',
                  style: const TextStyle(
                    color: AppColors.clay,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  HeritageSiteDetailScreen(site: place),
                            ),
                          );
                        },
                        icon: const Icon(Icons.info_outline_rounded),
                        label: const Text('View Details'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InAppNavigationScreen(
                                destinationName: place.name,
                                destinationLocation: place.location,
                                destinationLat: place.lat,
                                destinationLng: place.lng,
                                registeredSite: place,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.directions_walk_rounded),
                        label: const Text('Navigate'),
                        style: mainButtonStyle(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showPlacePopup(
    HeritagePlace place,
    List<JournalEntry> entries,
    double distance,
    double speed,
  ) async {
    popupIsOpen = true;

    final preferredLanguage = await languageService.getPreferredLanguage();

    final storyFuture = geminiStoryService.generateContextAwareStory(
      place: place,
      distanceMeters: distance,
      speedMetersPerSecond: speed,
      memories: entries,
      preferredLanguage: preferredLanguage,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bg,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.90,
          minChildSize: 0.45,
          maxChildSize: 0.97,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  place.name,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBrown,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${place.location} • ${(distance / 1000).toStringAsFixed(2)} ${appText(preferredLanguage.code, 'kmAway')}',
                  style: const TextStyle(
                    color: AppColors.clay,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                NarrativeTranslationPanel(
                  storyFuture: storyFuture,
                  initialLanguage: preferredLanguage,
                ),
                const SizedBox(height: 12),
                AiGeneratedImageCard(
                  image: const GeneratedHeritageImage(
                    base64Data: '',
                    mimeType: 'application/x-heritagebot-photo-carousel',
                    promptSummary: '',
                    isFallback: true,
                  ),
                  languageCode: preferredLanguage.code,
                  place: place,
                ),
                const SizedBox(height: 12),
                if (place.videoAsset != null)
                  HeritageVideoPlayer(
                    title: place.videoTitle,
                    assetPath: place.videoAsset!,
                  )
                else
                  InfoCard(
                    icon: Icons.video_library_rounded,
                    title: appText(preferredLanguage.code, 'noVideo'),
                    body: appText(preferredLanguage.code, 'noVideoBody'),
                  ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddJournalScreen(place: place),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(appText(preferredLanguage.code, 'addMemoryHere')),
                  style: mainButtonStyle(),
                ),
                const SizedBox(height: 18),
                Text(
                  entries.isEmpty
                      ? appText(preferredLanguage.code, 'noSavedMemories')
                      : appText(preferredLanguage.code, 'previousMemories'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBrown,
                  ),
                ),
                const SizedBox(height: 10),
                ...entries.map(
                  (entry) => JournalCard(entry: entry, onDelete: null),
                ),
              ],
            );
          },
        );
      },
    );

    popupIsOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final LatLng center = currentPosition == null
        ? const LatLng(10.32639, 123.95451)
        : LatLng(currentPosition!.latitude, currentPosition!.longitude);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          appText(LanguageController.current.value.code, 'liveGeolocation'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(initialCenter: center, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.heritagebot',
                ),
                MarkerLayer(
                  markers: [
                    if (currentPosition != null)
                      Marker(
                        point: LatLng(
                          currentPosition!.latitude,
                          currentPosition!.longitude,
                        ),
                        width: 55,
                        height: 55,
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Colors.blue,
                          size: 42,
                        ),
                      ),
                    ...heritagePlaces.map(
                      (place) => Marker(
                        point: LatLng(place.lat, place.lng),
                        width: 48,
                        height: 48,
                        child: GestureDetector(
                          onTap: () => _showMapSiteOptions(place),
                          child: Icon(
                            place.isTesting
                                ? Icons.school_rounded
                                : place.hasVideo
                                ? Icons.video_library_rounded
                                : Icons.location_on_rounded,
                            color: place.isTesting
                                ? Colors.deepPurple
                                : place.hasVideo
                                ? Colors.orange
                                : Colors.red,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                if (loading)
                  Text(
                    appText(
                      LanguageController.current.value.code,
                      'startingLocation',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  )
                else if (nearestPlace != null && nearestDistance != null)
                  Text(
                    '${appText(LanguageController.current.value.code, 'nearest')}: ${nearestPlace!.name} • ${(nearestDistance! / 1000).toStringAsFixed(2)} km',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  )
                else
                  Text(
                    appText(LanguageController.current.value.code, 'mapReady'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  appText(
                    LanguageController.current.value.code,
                    'mapInstruction',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: loading ? null : forceRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    appText(
                      LanguageController.current.value.code,
                      'refreshLocation',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MyJournalScreen extends StatefulWidget {
  const MyJournalScreen({super.key});

  @override
  State<MyJournalScreen> createState() => _MyJournalScreenState();
}

class _MyJournalScreenState extends State<MyJournalScreen> {
  final JournalService journalService = JournalService();

  late Future<List<JournalEntry>> entriesFuture;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    entriesFuture = journalService.getEntries();
  }

  Future<void> deleteEntry(String id) async {
    await journalService.deleteEntry(id);
    setState(reload);
  }

  void openAddManual() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.bg,
      builder: (context) {
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SectionTitle(
              title: appText(
                LanguageController.current.value.code,
                'chooseHeritagePlace',
              ),
              subtitle: appText(
                LanguageController.current.value.code,
                'chooseHeritagePlaceBody',
              ),
            ),
            const SizedBox(height: 12),
            ...heritagePlaces.map(
              (place) => ListTile(
                leading: Icon(
                  place.isTesting
                      ? Icons.school_rounded
                      : Icons.location_on_rounded,
                ),
                title: Text(place.name),
                subtitle: Text(place.location),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddJournalScreen(place: place),
                    ),
                  ).then((_) => setState(reload));
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          appText(LanguageController.current.value.code, 'myJournal'),
        ),
        actions: [
          IconButton(
            onPressed: openAddManual,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<JournalEntry>>(
        future: entriesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data!;

          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  appText(LanguageController.current.value.code, 'noJournal'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.4),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(18),
            children: entries.map((entry) {
              return JournalCard(
                entry: entry,
                onDelete: () => deleteEntry(entry.id),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class AddJournalScreen extends StatefulWidget {
  final HeritagePlace place;

  const AddJournalScreen({super.key, required this.place});

  @override
  State<AddJournalScreen> createState() => _AddJournalScreenState();
}

class _AddJournalScreenState extends State<AddJournalScreen> {
  final JournalService journalService = JournalService();
  final ImagePicker picker = ImagePicker();

  final TextEditingController letterController = TextEditingController();

  List<String> imagePaths = [];
  List<String> videoPaths = [];
  bool saving = false;

  Future<String> copyPickedFileToPermanentStorage(
    XFile pickedFile,
    String folderName,
  ) async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final mediaDirectory = Directory(
      '${appDirectory.path}/heritagebot_media/$folderName',
    );

    if (!await mediaDirectory.exists()) {
      await mediaDirectory.create(recursive: true);
    }

    final originalName = pickedFile.name.trim().isEmpty
        ? pickedFile.path.split('/').last
        : pickedFile.name.trim();

    final safeName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

    final newPath =
        '${mediaDirectory.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName';

    final savedFile = await File(pickedFile.path).copy(newPath);
    return savedFile.path;
  }

  Future<void> pickImage() async {
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);

    if (file == null) return;

    final savedPath = await copyPickedFileToPermanentStorage(file, 'images');

    if (!mounted) return;

    setState(() => imagePaths.add(savedPath));
  }

  Future<void> pickVideo() async {
    final XFile? file = await picker.pickVideo(source: ImageSource.gallery);

    if (file == null) return;

    final savedPath = await copyPickedFileToPermanentStorage(file, 'videos');

    if (!mounted) return;

    setState(() => videoPaths.add(savedPath));
  }

  Future<void> saveJournal() async {
    if (letterController.text.trim().isEmpty &&
        imagePaths.isEmpty &&
        videoPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a letter, photo, or video.')),
      );
      return;
    }

    setState(() => saving = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;

      if (userId == null || userId.trim().isEmpty) {
        throw FirebaseAuthException(
          code: 'not-logged-in',
          message: 'Please log in before saving a journal entry.',
        );
      }

      final now = DateTime.now();

      final entry = JournalEntry(
        id: now.microsecondsSinceEpoch.toString(),
        userId: userId,
        placeId: widget.place.id,
        placeName: widget.place.name,
        letter: letterController.text.trim(),
        imagePaths: List<String>.from(imagePaths),
        videoPaths: List<String>.from(videoPaths),
        createdAt: now.toIso8601String(),
        createdAtMillis: now.millisecondsSinceEpoch,
      );

      await journalService.addEntry(entry);
    } catch (e) {
      if (!mounted) return;

      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save journal to Firestore: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() => saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          appText(LanguageController.current.value.code, 'journalSaved'),
        ),
      ),
    );

    Navigator.pop(context);
  }

  @override
  void dispose() {
    letterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          appText(LanguageController.current.value.code, 'addMemory'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionTitle(
            title: widget.place.name,
            subtitle: appText(
              LanguageController.current.value.code,
              'addMemorySubtitle',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: letterController,
            maxLines: 8,
            decoration: inputDecoration(
              label: appText(
                LanguageController.current.value.code,
                'writeMemoryLetter',
              ),
              icon: Icons.edit_note_rounded,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickImage,
                  icon: const Icon(Icons.image_rounded),
                  label: const Text('Add Picture'),
                  style: socialButtonStyle(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickVideo,
                  icon: const Icon(Icons.video_library_rounded),
                  label: const Text('Add Video'),
                  style: socialButtonStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (imagePaths.isNotEmpty) ...[
            const Text(
              'Selected Pictures',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: imagePaths.map((path) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(path),
                    width: 95,
                    height: 95,
                    fit: BoxFit.cover,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
          ],
          if (videoPaths.isNotEmpty) ...[
            const Text(
              'Selected Videos',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...videoPaths.map(
              (path) => LocalJournalVideoPlayer(
                filePath: path,
                title: appText(
                  LanguageController.current.value.code,
                  'attachedVideo',
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          ElevatedButton.icon(
            onPressed: saving ? null : saveJournal,
            icon: const Icon(Icons.save_rounded),
            label: Text(
              saving
                  ? appText(LanguageController.current.value.code, 'saving')
                  : appText(
                      LanguageController.current.value.code,
                      'saveMemory',
                    ),
            ),
            style: mainButtonStyle(),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> logout(BuildContext context) async {
    await AuthService().logout();
  }

  void showProfileMessage(BuildContext context, String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget profileLanguageSelector(BuildContext context, String code) {
    return Card(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.gold.withOpacity(0.35),
                  child: const Icon(
                    Icons.language_rounded,
                    color: AppColors.brown,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    appText(code, 'languageSettings'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: AppColors.deepBrown,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: code,
              isExpanded: true,
              decoration: inputDecoration(
                label: appText(code, 'preferredLanguage'),
                icon: Icons.translate_rounded,
              ),
              items: supportedLanguages
                  .map(
                    (language) => DropdownMenuItem<String>(
                      value: language.code,
                      child: Text(language.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                await LanguageController.setLanguageCode(value);
                if (context.mounted)
                  showProfileMessage(context, appText(value, 'languageSaved'));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final bool isPasswordAccount =
        user != null && AuthService().isPasswordUser(user);
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageController.current,
      builder: (context, language, _) {
        final code = language.code;
        return Scaffold(
          appBar: AppBar(title: Text(appText(code, 'profile'))),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.gold,
                      backgroundImage: user?.photoURL == null
                          ? null
                          : NetworkImage(user!.photoURL!),
                      child: user?.photoURL == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 50,
                              color: AppColors.brown,
                            )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      user?.displayName ?? appText(code, 'profileUser'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepBrown,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? appText(code, 'noEmail'),
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    if (user != null)
                      FutureBuilder<UserProfile?>(
                        future: UserService().getUserProfile(user.uid),
                        builder: (context, snapshot) {
                          final role = snapshot.data?.role;

                          if (role == null || role.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Role: ${UserRoles.label(role)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.brown,
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isPasswordAccount
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ChangePasswordScreen(),
                                  ),
                                );
                              }
                            : () {
                                showProfileMessage(
                                  context,
                                  appText(code, 'changePasswordUnavailableMsg'),
                                );
                              },
                        icon: const Icon(Icons.lock_reset_rounded),
                        label: Text(
                          isPasswordAccount
                              ? appText(code, 'changePassword')
                              : appText(code, 'changePasswordUnavailable'),
                        ),
                        style: mainButtonStyle(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => logout(context),
                        icon: const Icon(Icons.logout_rounded),
                        label: Text(appText(code, 'logout')),
                        style: mainButtonStyle(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.bookmarks_rounded,
                    color: AppColors.brown,
                  ),
                  title: const Text(
                    'View Bookmarked Sites',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.deepBrown,
                    ),
                  ),
                  subtitle: const Text(
                    'View and manage the heritage sites saved to your account.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BookmarkedSitesScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              profileLanguageSelector(context, code),
              const SizedBox(height: 18),
              InfoCard(
                icon: Icons.info_rounded,
                title: appText(code, 'systemNote'),
                body: appText(code, 'systemNoteBody'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final AuthService _auth = AuthService();
  final TextEditingController currentPasswordController =
      TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool loading = false;
  bool hideCurrentPassword = true;
  bool hideNewPassword = true;
  bool hideConfirmPassword = true;

  void showMessage(String text) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);

    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> submitChangePassword() async {
    FocusScope.of(context).unfocus();

    final currentPassword = currentPasswordController.text;
    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      showMessage('Please complete all password fields.');
      return;
    }

    if (newPassword.length < 6) {
      showMessage('New password must be at least 6 characters.');
      return;
    }

    if (newPassword != confirmPassword) {
      showMessage('New password and confirm password do not match.');
      return;
    }

    if (mounted) {
      setState(() => loading = true);
    }

    try {
      await _auth.changeCurrentUserPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      if (!mounted) return;

      showMessage('Password changed successfully.');

      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();

      await Future.delayed(const Duration(milliseconds: 600));

      if (mounted) {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        showMessage('Current password is incorrect.');
      } else if (e.code == 'weak-password') {
        showMessage('New password is too weak.');
      } else if (e.code == 'requires-recent-login') {
        showMessage('Please log out, log in again, then change your password.');
      } else {
        showMessage(e.message ?? 'Failed to change password.');
      }
    } catch (_) {
      if (!mounted) return;
      showMessage('Failed to change password. Please try again.');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionTitle(
            title: 'Change Password',
            subtitle:
                'Enter your current password and create a new password for your HeritageBot account.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: currentPasswordController,
            obscureText: hideCurrentPassword,
            decoration: inputDecoration(
              label: 'Current Password',
              icon: Icons.lock_rounded,
              suffix: IconButton(
                icon: Icon(
                  hideCurrentPassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () {
                  setState(() {
                    hideCurrentPassword = !hideCurrentPassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: newPasswordController,
            obscureText: hideNewPassword,
            decoration: inputDecoration(
              label: 'New Password',
              icon: Icons.password_rounded,
              suffix: IconButton(
                icon: Icon(
                  hideNewPassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () {
                  setState(() {
                    hideNewPassword = !hideNewPassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: confirmPasswordController,
            obscureText: hideConfirmPassword,
            decoration: inputDecoration(
              label: 'Confirm New Password',
              icon: Icons.verified_user_rounded,
              suffix: IconButton(
                icon: Icon(
                  hideConfirmPassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () {
                  setState(() {
                    hideConfirmPassword = !hideConfirmPassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loading ? null : submitChangePassword,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                loading ? 'Changing Password...' : 'Save New Password',
              ),
              style: mainButtonStyle(),
            ),
          ),
          const SizedBox(height: 12),
          const InfoCard(
            icon: Icons.info_rounded,
            title: 'Password Account Only',
            body:
                'This feature works for accounts created using email and password. Google and Facebook users must change their password from their own account provider.',
          ),
        ],
      ),
    );
  }
}

class VideoPlaceCard extends StatelessWidget {
  final HeritagePlace place;
  final VoidCallback onTap;

  const VideoPlaceCard({super.key, required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          backgroundColor: AppColors.gold.withOpacity(0.35),
          child: const Icon(
            Icons.play_circle_fill_rounded,
            color: AppColors.brown,
          ),
        ),
        title: Text(
          place.name,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.deepBrown,
          ),
        ),
        subtitle: Text(
          place.isTesting
              ? '${place.videoTitle} • TEST SITE'
              : place.videoTitle,
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class LocalJournalImageThumb extends StatelessWidget {
  final String path;

  const LocalJournalImageThumb({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final file = File(path);

    if (!file.existsSync()) {
      return Container(
        width: 82,
        height: 82,
        alignment: Alignment.center,
        color: AppColors.gold.withOpacity(0.15),
        child: const Icon(
          Icons.image_not_supported_rounded,
          color: AppColors.brown,
        ),
      );
    }

    return Image.file(file, width: 82, height: 82, fit: BoxFit.cover);
  }
}

class JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback? onDelete;

  const JournalCard({super.key, required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.gold,
                  child: Icon(Icons.book_rounded, color: AppColors.brown),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.placeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: AppColors.deepBrown,
                    ),
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
            if (entry.letter.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(entry.letter, style: const TextStyle(height: 1.45)),
            ],
            if (entry.imagePaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entry.imagePaths.map((path) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: path.startsWith('http')
                        ? Image.network(
                            path,
                            width: 82,
                            height: 82,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox(
                                width: 82,
                                height: 82,
                                child: Icon(Icons.broken_image_rounded),
                              );
                            },
                          )
                        : LocalJournalImageThumb(path: path),
                  );
                }).toList(),
              ),
            ],
            if (entry.videoPaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...entry.videoPaths.map(
                (path) => LocalJournalVideoPlayer(
                  filePath: path,
                  title: appText(
                    LanguageController.current.value.code,
                    'attachedVideo',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LocalJournalVideoPlayer extends StatefulWidget {
  final String filePath;
  final String title;

  const LocalJournalVideoPlayer({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<LocalJournalVideoPlayer> createState() =>
      _LocalJournalVideoPlayerState();
}

class _LocalJournalVideoPlayerState extends State<LocalJournalVideoPlayer> {
  VideoPlayerController? controller;
  bool loading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    initializeVideo();
  }

  Future<void> initializeVideo() async {
    try {
      late final VideoPlayerController videoController;

      if (widget.filePath.startsWith('http')) {
        videoController = VideoPlayerController.networkUrl(
          Uri.parse(widget.filePath),
        );
      } else {
        final file = File(widget.filePath);

        if (!await file.exists()) {
          if (!mounted) return;
          setState(() {
            loading = false;
            hasError = true;
          });
          return;
        }

        videoController = VideoPlayerController.file(file);
      }

      await videoController.initialize();

      if (!mounted) {
        await videoController.dispose();
        return;
      }

      setState(() {
        controller = videoController;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        hasError = true;
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void togglePlay() {
    final videoController = controller;

    if (videoController == null || !videoController.value.isInitialized) {
      return;
    }

    setState(() {
      if (videoController.value.isPlaying) {
        videoController.pause();
      } else {
        videoController.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final videoController = controller;

    if (loading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.title)),
            ],
          ),
        ),
      );
    }

    if (hasError || videoController == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_rounded, color: Colors.redAccent),
          title: Text(widget.title),
          subtitle: const Text(
            'This saved video file cannot be found. Add the video again so HeritageBot can copy it into app storage.',
          ),
        ),
      );
    }

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.video_file_rounded, color: AppColors.brown),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: videoController.value.aspectRatio == 0
                    ? 16 / 9
                    : videoController.value.aspectRatio,
                child: VideoPlayer(videoController),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: togglePlay,
                icon: Icon(
                  videoController.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  videoController.value.isPlaying
                      ? 'Pause Video'
                      : 'Play Video',
                ),
                style: mainButtonStyle(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HeritageVideoPlayer extends StatefulWidget {
  final String title;
  final String assetPath;

  const HeritageVideoPlayer({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<HeritageVideoPlayer> createState() => _HeritageVideoPlayerState();
}

class _HeritageVideoPlayerState extends State<HeritageVideoPlayer> {
  late final VideoPlayerController controller;
  bool hasError = false;

  @override
  void initState() {
    super.initState();

    controller = VideoPlayerController.asset(widget.assetPath)
      ..initialize()
          .then((_) {
            if (mounted) {
              setState(() {});
            }
          })
          .catchError((error) {
            if (mounted) {
              setState(() {
                hasError = true;
              });
            }
          });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void togglePlay() {
    if (!controller.value.isInitialized) return;

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return const InfoCard(
        icon: Icons.error_rounded,
        title: 'Video Error',
        body:
            'The video cannot be loaded. Check the filename inside assets/videos/ and run flutter pub get again.',
      );
    }

    return Card(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.gold.withOpacity(0.35),
                  child: const Icon(
                    Icons.video_library_rounded,
                    color: AppColors.brown,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.deepBrown,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!controller.value.isInitialized)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: controller.value.isInitialized ? togglePlay : null,
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  controller.value.isPlaying ? 'Pause Video' : 'Play Video',
                ),
                style: mainButtonStyle(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const SectionTitle({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w900,
            color: AppColors.deepBrown,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.black54, height: 1.4),
        ),
      ],
    );
  }
}

class AiGeneratedImageCard extends StatelessWidget {
  final GeneratedHeritageImage image;
  final String languageCode;
  final HeritagePlace place;

  const AiGeneratedImageCard({
    super.key,
    required this.image,
    required this.languageCode,
    required this.place,
  });

  @override
  Widget build(BuildContext context) {
    final hasGeneratedImage =
        !image.isFallback && image.base64Data.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library_rounded, color: AppColors.brown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Heritage Area Photos - ${place.name}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBrown,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<String>>(
            future: PlaceImageService().getPlaceImageUrls(place, limit: 5),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  width: double.infinity,
                  height: 220,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.bg,
                  ),
                  child: const CircularProgressIndicator(
                    color: AppColors.brown,
                  ),
                );
              }

              final imageUrls = snapshot.data ?? <String>[];

              if (imageUrls.isNotEmpty) {
                return HeritagePhotoCarousel(
                  imageUrls: imageUrls,
                  placeName: place.name,
                );
              }

              if (hasGeneratedImage) {
                return GeneratedImagePreview(image: image, place: place);
              }

              return HeritagePhotoFallback(place: place);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Swipe left or right to view photos. Photos are retrieved from online open heritage image sources when available; otherwise, the app shows a safe preview.',
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class HeritagePhotoCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final String placeName;

  const HeritagePhotoCarousel({
    super.key,
    required this.imageUrls,
    required this.placeName,
  });

  @override
  State<HeritagePhotoCarousel> createState() => _HeritagePhotoCarouselState();
}

class _HeritagePhotoCarouselState extends State<HeritagePhotoCarousel> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: double.infinity,
        height: 220,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: total,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                return Image.network(
                  widget.imageUrls[index],
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: AppColors.bg,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        color: AppColors.brown,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return HeritagePhotoFallback(placeName: widget.placeName);
                  },
                );
              },
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentIndex + 1}/$total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (total > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(total, (index) {
                    final selected = index == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: selected ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white
                            : Colors.white.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GeneratedImagePreview extends StatelessWidget {
  final GeneratedHeritageImage image;
  final HeritagePlace place;

  const GeneratedImagePreview({
    super.key,
    required this.image,
    required this.place,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final imageBytes = base64Decode(image.base64Data);

      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          imageBytes,
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } catch (_) {
      return HeritagePhotoFallback(place: place);
    }
  }
}

class HeritagePhotoFallback extends StatelessWidget {
  final HeritagePlace? place;
  final String? placeName;

  const HeritagePhotoFallback({super.key, this.place, this.placeName});

  @override
  Widget build(BuildContext context) {
    final name = placeName ?? place?.name ?? 'Heritage Site';

    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.deepBrown, AppColors.brown, AppColors.clay],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.travel_explore_rounded,
            color: AppColors.gold,
            size: 70,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.gold.withOpacity(0.35),
              child: Icon(icon, color: AppColors.brown),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.deepBrown,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(body, style: const TextStyle(height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration inputDecoration({
  required String label,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.clay, width: 1.5),
    ),
  );
}

ButtonStyle mainButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: AppColors.brown,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900),
  );
}

ButtonStyle socialButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.brown,
    backgroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 14),
    side: const BorderSide(color: AppColors.gold),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900),
  );
}
