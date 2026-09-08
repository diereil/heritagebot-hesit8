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

import 'services/ai_image_service.dart';
import 'services/auth_service.dart';
import 'services/community_submission_service.dart';
import 'services/community_media_service.dart';
import 'services/journal_service.dart';
import 'services/language_service.dart';
import 'services/user_service.dart';

const double nearbyRadiusMeters = 10000.0;
const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const String geminiModel = 'gemini-2.0-flash';
const String geminiImageModel = 'gemini-3.1-flash-image';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await GoogleSignIn.instance.initialize();
  await LanguageController.load();

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
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey',
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

    final prompt =
        '''
You are HeritageBot, an AI-based historical narrative generator for Cebu heritage tourism.

Generate a context-aware story for the user.

Place: ${place.name}
Location: ${place.location}
Distance from user: ${(distanceMeters / 1000).toStringAsFixed(2)} km
User movement context: $speedText

Verified historical/context facts:
${place.historicalFacts}

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
- Do not invent fake dates or unsupported historical claims.
- If the user has saved memories, connect them gently to the place.
- Keep it around 2 to 4 short paragraphs.
''';

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
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
        return text.trim();
      }

      return _fallbackStory(
        place,
        distanceMeters,
        speedMetersPerSecond,
        memories,
        preferredLanguage,
      );
    } catch (_) {
      return _fallbackStory(
        place,
        distanceMeters,
        speedMetersPerSecond,
        memories,
        preferredLanguage,
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

  late final TextEditingController titleController;
  late final TextEditingController storyController;

  String? selectedPlaceId;
  bool saving = false;

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
      await _submissionService.updatePendingSubmission(
        submission: widget.submission,
        heritagePlaceId: place.id,
        heritagePlaceName: place.name,
        title: title,
        story: story,
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
                'You can change the heritage place, title, and story while the submission is still Pending.',
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
          if (submission.imageUrls.isNotEmpty ||
              submission.videoUrls.isNotEmpty) ...[
            const SizedBox(height: 18),
            InfoCard(
              icon: Icons.perm_media_rounded,
              title: 'Existing Media',
              body:
                  '${submission.imageUrls.length} photo${submission.imageUrls.length == 1 ? '' : 's'} and '
                  '${submission.videoUrls.length} video${submission.videoUrls.length == 1 ? '' : 's'} remain attached to this submission.',
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

  late Future<List<CommunitySubmission>> _submissionsFuture;

  String selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  void _loadSubmissions() {
    _submissionsFuture = _submissionService.getAllSubmissions();
  }

  Future<void> _refresh() async {
    setState(_loadSubmissions);
    await _submissionsFuture;
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
                const InfoCard(
                  icon: Icons.people_alt_rounded,
                  title: 'Manage Users',
                  body:
                      'User management will be connected in the next administrator development stage.',
                ),
                const InfoCard(
                  icon: Icons.location_city_rounded,
                  title: 'Manage Heritage Sites',
                  body:
                      'Heritage site creation, editing, deletion, and media management will be connected in a later stage.',
                ),
              ],
            );
          },
        ),
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

    if (distance <= nearbyRadiusMeters) {
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
            'Nearest place: ${place.name}. Distance: ${(distance / 1000).toStringAsFixed(2)} km.',
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
                FutureBuilder<String>(
                  future: storyFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return InfoCard(
                        icon: Icons.auto_awesome_rounded,
                        title: appText(
                          preferredLanguage.code,
                          'generatingStory',
                        ),
                        body: appText(
                          preferredLanguage.code,
                          'generatingStoryBody',
                        ),
                      );
                    }

                    return InfoCard(
                      icon: Icons.auto_awesome_rounded,
                      title: appText(
                        preferredLanguage.code,
                        'contextStoryTitle',
                      ),
                      body: snapshot.data!,
                    );
                  },
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
                        width: 45,
                        height: 45,
                        child: Icon(
                          place.id == 'uclm'
                              ? Icons.school_rounded
                              : place.hasVideo
                              ? Icons.video_library_rounded
                              : Icons.location_on_rounded,
                          color: place.id == 'uclm'
                              ? Colors.deepPurple
                              : place.hasVideo
                              ? Colors.orange
                              : Colors.red,
                          size: 38,
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
                  place.id == 'uclm'
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
        subtitle: Text(place.videoTitle),
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
