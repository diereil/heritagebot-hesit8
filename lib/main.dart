import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'firebase_options.dart';
import 'services/ai_image_service.dart';
import 'services/language_service.dart';

const double nearbyRadiusMeters = 10000.0;
const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const String geminiModel = 'gemini-2.0-flash';
const String geminiImageModel = 'gemini-3.1-flash-image';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

class AppColors {
  static const bg = Color(0xFFF8F2E9);
  static const brown = Color(0xFF4A2C1A);
  static const deepBrown = Color(0xFF2C160B);
  static const clay = Color(0xFF9B5C2E);
  static const gold = Color(0xFFE0AD62);
  static const card = Colors.white;
}

class HeritagePlace {
  final String id;
  final String name;
  final String location;
  final double lat;
  final double lng;
  final String historicalFacts;
  final String videoTitle;
  final String? videoAsset;
  final String wikipediaTitle;

  const HeritagePlace({
    required this.id,
    required this.name,
    required this.location,
    required this.lat,
    required this.lng,
    required this.historicalFacts,
    required this.videoTitle,
    this.videoAsset,
    required this.wikipediaTitle,
  });

  bool get hasVideo => videoAsset != null && videoAsset!.isNotEmpty;
}

const List<HeritagePlace> heritagePlaces = [
  HeritagePlace(
    id: 'uclm',
    name: 'University of Cebu Lapu-Lapu and Mandaue',
    location: 'A.C. Cortes Avenue, Mandaue City, Cebu',
    lat: 10.32639,
    lng: 123.95451,
    videoTitle: 'UCLM School Heritage Video',
    videoAsset: 'assets/videos/uclm.mp4',
    wikipediaTitle: 'University of Cebu',
    historicalFacts:
        'The University of Cebu Lapu-Lapu and Mandaue, also known as UCLM, is an educational institution located along A.C. Cortes Avenue in Mandaue City. It is a meaningful place for students, alumni, families, and visitors because it connects education, personal growth, friendships, and school memories.',
  ),
  HeritagePlace(
    id: 'magellans_cross',
    name: 'Magellan’s Cross',
    location: 'Cebu City',
    lat: 10.2930,
    lng: 123.9020,
    videoTitle: 'Magellan’s Cross Heritage Video',
    videoAsset: 'assets/videos/magellans_cross.mp4',
    wikipediaTitle: "Magellan's Cross",
    historicalFacts:
        'Magellan’s Cross is one of Cebu’s most recognized landmarks. It is traditionally associated with the arrival of Christianity in the Philippines and is an important symbol of Cebuano history, faith, and tourism.',
  ),
  HeritagePlace(
    id: 'fort_san_pedro',
    name: 'Fort San Pedro',
    location: 'Cebu City',
    lat: 10.2923,
    lng: 123.9058,
    videoTitle: 'Fort San Pedro Historical Video',
    videoAsset: 'assets/videos/fort_san_pedro.mp4',
    wikipediaTitle: 'Fort San Pedro',
    historicalFacts:
        'Fort San Pedro is a Spanish colonial military defense structure in Cebu City. It served as a fortification during the colonial period and is now preserved as a heritage and tourism site.',
  ),
  HeritagePlace(
    id: 'basilica_santo_nino',
    name: 'Basilica Minore del Santo Niño',
    location: 'Cebu City',
    lat: 10.2939,
    lng: 123.9013,
    videoTitle: 'Santo Niño Heritage Video',
    videoAsset: 'assets/videos/basilica_santo_nino.mp4',
    wikipediaTitle: 'Basilica Minore del Santo Niño',
    historicalFacts:
        'The Basilica Minore del Santo Niño is one of the oldest Roman Catholic churches in the Philippines. It is closely connected to Cebuano devotion, the Santo Niño, and the Sinulog celebration.',
  ),
  HeritagePlace(
    id: 'casa_gorordo',
    name: 'Casa Gorordo Museum',
    location: 'Cebu City',
    lat: 10.3006,
    lng: 123.8996,
    videoTitle: 'Casa Gorordo Museum Video',
    videoAsset: 'assets/videos/casa_gorordo.mp4',
    wikipediaTitle: 'Casa Gorordo Museum',
    historicalFacts:
        'Casa Gorordo Museum presents the lifestyle of a Cebuano family during the Spanish colonial period. It preserves antique furniture, religious objects, religious images, household materials, and cultural items that show how old Cebuano families lived during the colonial era.',
  ),
];

class JournalEntry {
  final String id;
  final String userId;
  final String placeId;
  final String placeName;
  final String letter;
  final List<String> imagePaths;
  final List<String> videoPaths;
  final String createdAt;
  final int createdAtMillis;

  const JournalEntry({
    required this.id,
    required this.userId,
    required this.placeId,
    required this.placeName,
    required this.letter,
    required this.imagePaths,
    required this.videoPaths,
    required this.createdAt,
    required this.createdAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'placeId': placeId,
      'placeName': placeName,
      'letter': letter,
      'imagePaths': imagePaths,
      'videoPaths': videoPaths,
      'createdAt': createdAt,
      'createdAtMillis': createdAtMillis,
    };
  }

  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['createdAt'];
    final millisRaw = map['createdAtMillis'];

    int parsedMillis;

    if (millisRaw is int) {
      parsedMillis = millisRaw;
    } else if (millisRaw is num) {
      parsedMillis = millisRaw.toInt();
    } else {
      parsedMillis = DateTime.tryParse(createdAtRaw?.toString() ?? '')
              ?.millisecondsSinceEpoch ??
          0;
    }

    return JournalEntry(
      id: map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      placeId: map['placeId']?.toString() ?? '',
      placeName: map['placeName']?.toString() ?? '',
      letter: map['letter']?.toString() ?? '',
      imagePaths: _safeStringList(map['imagePaths']),
      videoPaths: _safeStringList(map['videoPaths']),
      createdAt: createdAtRaw?.toString() ?? '',
      createdAtMillis: parsedMillis,
    );
  }

  static List<String> _safeStringList(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return [];
  }
}

class JournalService {
  static const String _legacyLocalBaseKey = 'heritagebot_journal_entries';
  static const String _migrationFlagBaseKey = 'heritagebot_firestore_migrated';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'Please log in before using the journal.',
      );
    }

    return uid;
  }

  CollectionReference<Map<String, dynamic>> _journalCollection() {
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('journal_entries');
  }

  Future<List<JournalEntry>> getEntries() async {
    await _migrateLocalEntriesIfNeeded();

    final snapshot = await _journalCollection()
        .orderBy('createdAtMillis', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] ??= doc.id;
      return JournalEntry.fromMap(data);
    }).toList();
  }

  Future<List<JournalEntry>> getEntriesByPlace(String placeId) async {
    await _migrateLocalEntriesIfNeeded();

    final snapshot = await _journalCollection()
        .where('placeId', isEqualTo: placeId)
        .get();

    final entries = snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] ??= doc.id;
      return JournalEntry.fromMap(data);
    }).toList();

    entries.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return entries;
  }

  Future<void> _migrateLocalEntriesIfNeeded() async {
    final uid = _uid;
    final prefs = await SharedPreferences.getInstance();
    final migrationFlagKey = '${_migrationFlagBaseKey}_$uid';

    if (prefs.getBool(migrationFlagKey) == true) return;

    final legacyKey = '${_legacyLocalBaseKey}_$uid';
    final rawList = prefs.getStringList(legacyKey) ?? [];

    if (rawList.isEmpty) {
      await prefs.setBool(migrationFlagKey, true);
      return;
    }

    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;

        final oldEntry = JournalEntry.fromMap(
          Map<String, dynamic>.from(decoded),
        );

        final savedImagePaths = <String>[
          ...oldEntry.imagePaths.where((path) => path.trim().isNotEmpty),
        ];
        final savedVideoPaths = <String>[
          ...oldEntry.videoPaths.where((path) => path.trim().isNotEmpty),
        ];

        final nowMillis = oldEntry.createdAtMillis == 0
            ? DateTime.now().millisecondsSinceEpoch
            : oldEntry.createdAtMillis;

        final migratedEntry = JournalEntry(
          id: oldEntry.id.isEmpty
              ? DateTime.now().microsecondsSinceEpoch.toString()
              : oldEntry.id,
          userId: uid,
          placeId: oldEntry.placeId,
          placeName: oldEntry.placeName,
          letter: oldEntry.letter,
          imagePaths: savedImagePaths,
          videoPaths: savedVideoPaths,
          createdAt: oldEntry.createdAt.isEmpty
              ? DateTime.fromMillisecondsSinceEpoch(nowMillis).toIso8601String()
              : oldEntry.createdAt,
          createdAtMillis: nowMillis,
        );

        await _journalCollection().doc(migratedEntry.id).set(
              migratedEntry.toMap(),
              SetOptions(merge: true),
            );
      } catch (_) {
        // Skip broken local entries so the online database can still work.
      }
    }

    await prefs.setBool(migrationFlagKey, true);
  }

  Future<void> addEntry(JournalEntry entry) async {
    await _journalCollection().doc(entry.id).set(entry.toMap());
  }

  Future<void> updateEntry(JournalEntry entry) async {
    await _journalCollection().doc(entry.id).set(
          entry.toMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteEntry(String id) async {
    await _journalCollection().doc(id).delete();
  }
}

class PlaceImageService {
  static final Map<String, String?> _cache = {};

  Future<String?> getPlaceImageUrl(HeritagePlace place) async {
    final title = place.wikipediaTitle.trim();

    if (title.isEmpty) {
      return null;
    }

    if (_cache.containsKey(title)) {
      return _cache[title];
    }

    try {
      final uri = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
      );

      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'HeritageBot/1.0 (educational capstone app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _cache[title] = null;
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is Map) {
        final originalImage = decoded['originalimage'];
        final thumbnail = decoded['thumbnail'];

        final originalSource = originalImage is Map ? originalImage['source'] : null;
        final thumbnailSource = thumbnail is Map ? thumbnail['source'] : null;

        final source = originalSource ?? thumbnailSource;

        if (source is String && source.trim().isNotEmpty) {
          _cache[title] = source.trim();
          return source.trim();
        }
      }

      _cache[title] = null;
      return null;
    } catch (_) {
      _cache[title] = null;
      return null;
    }
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

    final prompt = '''
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

Target language:
Write the final answer in ${preferredLanguage.storyInstruction}.

Requirements:
- Use simple, friendly words for tourists and students.
- Make it immersive and meaningful.
- Do not invent fake dates or unsupported historical claims.
- If the user has saved memories, connect them gently to the place.
- Keep it around 2 to 4 short paragraphs.
- Title it "Context-Aware Heritage Story" if the language is English, or translate the title naturally if another language is selected.
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
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.7,
                'maxOutputTokens': 450,
              }
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
    final movement = speedMetersPerSecond < 1.2
        ? 'You seem to be walking or staying near this area.'
        : speedMetersPerSecond < 7
            ? 'You seem to be slowly moving near this place.'
            : 'You seem to be passing by this area while moving fast.';

    final memoryLine = memories.isEmpty
        ? 'You do not have saved memories for this place yet, but you can add a personal letter, picture, or video to make your next visit more meaningful.'
        : 'You have saved memories connected to this place, so HeritageBot can help you remember your previous visit while exploring it again.';

    if (preferredLanguage.code == 'ceb') {
      return '''Sugilanon sa Kabilin nga Nahiuyon sa Imong Lokasyon

Duol ka karon sa ${place.name}, nga nahimutang sa ${place.location}. Kini mga ${(distanceMeters / 1000).toStringAsFixed(2)} km gikan sa imong kasamtangang lokasyon. $movement

${place.historicalFacts}

$memoryLine''';
    }

    if (preferredLanguage.code == 'fil') {
      return '''Kuwento ng Pamana Batay sa Iyong Lokasyon

Malapit ka ngayon sa ${place.name}, na matatagpuan sa ${place.location}. Ito ay humigit-kumulang ${(distanceMeters / 1000).toStringAsFixed(2)} km mula sa iyong kasalukuyang lokasyon. $movement

${place.historicalFacts}

$memoryLine''';
    }

    return '''Context-Aware Heritage Story

You are near ${place.name}, located in ${place.location}. It is around ${(distanceMeters / 1000).toStringAsFixed(2)} km from your current position. $movement

${place.historicalFacts}

$memoryLine''';
  }
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> authChanges() => _auth.authStateChanges();

  bool isPasswordUser(User user) {
    return user.providerData.any((info) => info.providerId == 'password');
  }

  bool needsEmailVerification(User user) {
    return isPasswordUser(user) && !user.emailVerified;
  }

  Future<void> loginWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signupWithEmail(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await credential.user?.sendEmailVerification();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final trimmedEmail = email.trim();

    if (trimmedEmail.isEmpty) {
      throw FirebaseAuthException(
        code: 'empty-email',
        message: 'Please enter your email address first.',
      );
    }

    await _auth.sendPasswordResetEmail(email: trimmedEmail);
  }

  Future<void> changeCurrentUserPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No user is currently signed in.',
      );
    }

    if (!isPasswordUser(user)) {
      throw FirebaseAuthException(
        code: 'not-password-user',
        message: 'Password change is only available for email/password accounts. Google and Facebook accounts must change their password from their provider.',
      );
    }

    final email = user.email;

    if (email == null || email.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'This account has no email address.',
      );
    }

    if (currentPassword.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'empty-current-password',
        message: 'Please enter your current password.',
      );
    }

    if (newPassword.trim().length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'New password must be at least 6 characters.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: currentPassword,
    );

    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword.trim());
  }

  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No user is currently signed in.');
    }

    await user.sendEmailVerification();
  }

  Future<bool> reloadAndCheckVerified() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    await user.reload();

    final refreshedUser = _auth.currentUser;
    return refreshedUser?.emailVerified ?? false;
  }

  Future<void> signInWithGoogle() async {
    try {
      await GoogleSignIn.instance.signOut();

      final GoogleSignInAccount googleUser =
          await GoogleSignIn.instance.authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw Exception(
          'Google login failed because no ID token was returned. Please check SHA-1/SHA-256 and google-services.json.',
        );
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
    } catch (e) {
      throw Exception('Google login error: $e');
    }
  }

  Future<void> signInWithFacebook() async {
    final LoginResult result = await FacebookAuth.instance.login(
      permissions: ['email', 'public_profile'],
    );

    if (result.status != LoginStatus.success || result.accessToken == null) {
      throw Exception('Facebook login was cancelled or failed.');
    }

    final String token = result.accessToken!.tokenString;
    final OAuthCredential credential = FacebookAuthProvider.credential(token);

    await _auth.signInWithCredential(credential);
  }

  Future<void> logout() async {
    await GoogleSignIn.instance.signOut();
    await FacebookAuth.instance.logOut();
    await _auth.signOut();
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

    return Geolocator.getPositionStream(
      locationSettings: locationSettings,
    );
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
      (a, b) => distanceToPlace(position, a).compareTo(
        distanceToPlace(position, b),
      ),
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
            colors: [
              AppColors.deepBrown,
              AppColors.brown,
              AppColors.clay,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.travel_explore_rounded,
              size: 92,
              color: AppColors.gold,
            ),
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

        return const MainShell();
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
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
  final LanguageService _languageService = LanguageService();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool isSignup = false;
  bool loading = false;
  bool hidePassword = true;
  bool hideConfirmPassword = true;
  String selectedLanguageCode = LanguageController.current.value.code;

  String t(String key) => appText(selectedLanguageCode, key);

  @override
  void initState() {
    super.initState();
    selectedLanguageCode = LanguageController.current.value.code;
  }

  bool isValidGmailAddress(String email) {
    final trimmed = email.trim().toLowerCase();
    return RegExp(r'^[a-zA-Z0-9._%+\-]+@gmail\.com$').hasMatch(trimmed);
  }

  Future<void> submitEmail() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

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

    if (isSignup && !isValidGmailAddress(email)) {
      showMessage(
        'Please use a valid Gmail address ending in @gmail.com. You must verify the Gmail link before entering the system.',
      );
      return;
    }

    setState(() => loading = true);

    try {
      if (isSignup) {
        await _auth.signupWithEmail(email, password);
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
    } catch (e) {
      showMessage(e.toString());
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> facebookLogin() async {
    setState(() => loading = true);

    try {
      await _auth.signInWithFacebook();
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
            borderSide: const BorderSide(
              color: AppColors.gold,
              width: 1.7,
            ),
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
          side: const BorderSide(
            color: AppColors.gold,
            width: 1.4,
          ),
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
        value: selectedLanguageCode,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.language_rounded, color: AppColors.brown),
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
            borderSide: const BorderSide(
              color: AppColors.gold,
              width: 1.7,
            ),
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

  @override
  void dispose() {
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
              colors: [
                AppColors.deepBrown,
                AppColors.brown,
                AppColors.clay,
              ],
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
                        isSignup
                            ? t('alreadyHaveAccount')
                            : t('noAccount'),
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

  const EmailVerificationScreen({
    super.key,
    required this.email,
  });

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
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
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
              colors: [
                AppColors.deepBrown,
                AppColors.brown,
                AppColors.clay,
              ],
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
  const MainShell({super.key});

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
        final screens = const [HomeScreen(), GeolocationScreen(), MyJournalScreen(), ProfileScreen()];
        return Scaffold(
          body: screens[currentIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) => setState(() => currentIndex = index),
            destinations: [
              NavigationDestination(icon: const Icon(Icons.home_rounded), label: appText(code, 'home')),
              NavigationDestination(icon: const Icon(Icons.map_rounded), label: appText(code, 'geolocation')),
              NavigationDestination(icon: const Icon(Icons.book_rounded), label: appText(code, 'myJournal')),
              NavigationDestination(icon: const Icon(Icons.person_rounded), label: appText(code, 'profile')),
            ],
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
          content: Text(appText(LanguageController.current.value.code, 'noVideoBody')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HeritageVideoScreen(place: place),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoPlaces = heritagePlaces.where((place) => place.hasVideo).toList();
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
                  gradient: const LinearGradient(colors: [AppColors.brown, AppColors.clay], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.travel_explore_rounded, size: 58, color: AppColors.gold),
                  const SizedBox(height: 14),
                  Text(appText(code, 'welcomeHome'), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text(appText(code, 'homeIntro'), style: const TextStyle(color: Colors.white, fontSize: 15.5, height: 1.45, fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(height: 24),
              SectionTitle(title: appText(code, 'aboutSystem'), subtitle: appText(code, 'aboutSystemBody')),
              const SizedBox(height: 16),
              InfoCard(icon: Icons.auto_awesome_rounded, title: appText(code, 'aiStoryTitle'), body: appText(code, 'aiStoryBody')),
              InfoCard(icon: Icons.directions_walk_rounded, title: appText(code, 'liveMapTitle'), body: appText(code, 'liveMapBody')),
              InfoCard(icon: Icons.book_rounded, title: appText(code, 'memoryJournalTitle'), body: appText(code, 'memoryJournalBody')),
              const SizedBox(height: 8),
              SectionTitle(title: appText(code, 'heritageVideos'), subtitle: ''),
              const SizedBox(height: 8),
              ...videoPlaces.map((place) => VideoPlaceCard(place: place, onTap: () => openVideo(context, place))),
            ],
          ),
        );
      },
    );
  }
}


class HeritageVideoScreen extends StatelessWidget {
  final HeritagePlace place;

  const HeritageVideoScreen({
    super.key,
    required this.place,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageController.current,
      builder: (context, language, _) {
        final code = language.code;

        return Scaffold(
          appBar: AppBar(
            title: Text(place.name),
          ),
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
  final GeminiImageService geminiImageService = GeminiImageService(
    apiKey: geminiApiKey,
    model: geminiImageModel,
  );
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
      mapController.move(
        LatLng(position.latitude, position.longitude),
        17,
      );
    } catch (_) {}

    if (distance <= nearbyRadiusMeters) {
      final now = DateTime.now();
      final enoughTimePassed = lastPopupTime == null ||
          now.difference(lastPopupTime!).inSeconds >= 30;

      if (!popupIsOpen && (lastPopupPlaceId != place.id || enoughTimePassed)) {
        lastPopupPlaceId = place.id;
        lastPopupTime = now;

        final entries = await journalService.getEntriesByPlace(place.id);

        if (!mounted) return;

        await showPlacePopup(
          place,
          entries,
          distance,
          position.speed,
        );
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

    final imageFuture = storyFuture.then(
      (story) => geminiImageService.generateLocationImage(
        placeId: place.id,
        placeName: place.name,
        location: place.location,
        historicalFacts: place.historicalFacts,
        story: story,
        languageName: preferredLanguage.name,
      ),
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
                        title: appText(preferredLanguage.code, 'generatingStory'),
                        body: appText(preferredLanguage.code, 'generatingStoryBody'),
                      );
                    }

                    return InfoCard(
                      icon: Icons.auto_awesome_rounded,
                      title: appText(preferredLanguage.code, 'contextStoryTitle'),
                      body: snapshot.data!,
                    );
                  },
                ),
                const SizedBox(height: 12),
                FutureBuilder<GeneratedHeritageImage?>(
                  future: imageFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return InfoCard(
                        icon: Icons.image_rounded,
                        title: appText(preferredLanguage.code, 'generatingImage'),
                        body: appText(preferredLanguage.code, 'generatingImageBody'),
                      );
                    }

                    final generatedImage = snapshot.data;

                    if (generatedImage == null) {
                      return AiGeneratedImageCard(
                        image: const GeneratedHeritageImage(
                          base64Data: '',
                          mimeType: 'application/x-heritagebot-fallback',
                          promptSummary: '',
                          isFallback: true,
                        ),
                        languageCode: preferredLanguage.code,
                        place: place,
                      );
                    }

                    return AiGeneratedImageCard(
                      image: generatedImage,
                      languageCode: preferredLanguage.code,
                      place: place,
                    );
                  },
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
                  (entry) => JournalCard(
                    entry: entry,
                    onDelete: null,
                  ),
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
      appBar: AppBar(title: Text(appText(LanguageController.current.value.code, 'liveGeolocation'))),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
              ),
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
                    appText(LanguageController.current.value.code, 'startingLocation'),
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
                  appText(LanguageController.current.value.code, 'mapInstruction'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: loading ? null : forceRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(appText(LanguageController.current.value.code, 'refreshLocation')),
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

  HeritagePlace placeForEntry(JournalEntry entry) {
    return heritagePlaces.firstWhere(
      (place) => place.id == entry.placeId,
      orElse: () => HeritagePlace(
        id: entry.placeId,
        name: entry.placeName,
        location: 'Saved journal place',
        lat: 0,
        lng: 0,
        historicalFacts: '',
        videoTitle: '',
        wikipediaTitle: entry.placeName,
      ),
    );
  }

  Future<void> openEdit(JournalEntry entry) async {
    final place = placeForEntry(entry);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddJournalScreen(
          place: place,
          existingEntry: entry,
        ),
      ),
    );

    if (mounted) {
      setState(reload);
    }
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
              title: appText(LanguageController.current.value.code, 'chooseHeritagePlace'),
              subtitle: appText(LanguageController.current.value.code, 'chooseHeritagePlaceBody'),
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
        title: Text(appText(LanguageController.current.value.code, 'myJournal')),
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
            children: entries.map(
              (entry) {
                return JournalCard(
                  entry: entry,
                  onEdit: () => openEdit(entry),
                  onDelete: () => deleteEntry(entry.id),
                );
              },
            ).toList(),
          );
        },
      ),
    );
  }
}

class AddJournalScreen extends StatefulWidget {
  final HeritagePlace place;
  final JournalEntry? existingEntry;

  const AddJournalScreen({
    super.key,
    required this.place,
    this.existingEntry,
  });

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

  bool get isEditing => widget.existingEntry != null;

  @override
  void initState() {
    super.initState();

    final existingEntry = widget.existingEntry;

    if (existingEntry != null) {
      letterController.text = existingEntry.letter;
      imagePaths = List<String>.from(existingEntry.imagePaths);
      videoPaths = List<String>.from(existingEntry.videoPaths);
    }
  }

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

    final safeName = originalName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );

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
        const SnackBar(
          content: Text('Please add a letter, photo, or video.'),
        ),
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
      final existingEntry = widget.existingEntry;

      final entry = JournalEntry(
        id: existingEntry?.id ?? now.microsecondsSinceEpoch.toString(),
        userId: userId,
        placeId: widget.place.id,
        placeName: widget.place.name,
        letter: letterController.text.trim(),
        imagePaths: List<String>.from(imagePaths),
        videoPaths: List<String>.from(videoPaths),
        createdAt: existingEntry?.createdAt ?? now.toIso8601String(),
        createdAtMillis:
            existingEntry?.createdAtMillis ?? now.millisecondsSinceEpoch,
      );

      if (isEditing) {
        await journalService.updateEntry(entry);
      } else {
        await journalService.addEntry(entry);
      }
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
          isEditing
              ? 'Journal memory updated.'
              : appText(LanguageController.current.value.code, 'journalSaved'),
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
          isEditing
              ? 'Edit Memory'
              : appText(LanguageController.current.value.code, 'addMemory'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionTitle(
            title: widget.place.name,
            subtitle: appText(LanguageController.current.value.code, 'addMemorySubtitle'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: letterController,
            maxLines: 8,
            decoration: inputDecoration(
              label: appText(LanguageController.current.value.code, 'writeMemoryLetter'),
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
              children: imagePaths.asMap().entries.map((item) {
                final index = item.key;
                final path = item.value;

                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(path),
                        width: 95,
                        height: 95,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () {
                          setState(() => imagePaths.removeAt(index));
                        },
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
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
            ...videoPaths.asMap().entries.map(
              (item) {
                final index = item.key;
                final path = item.value;

                return Stack(
                  children: [
                    LocalJournalVideoPlayer(
                      filePath: path,
                      title: appText(
                        LanguageController.current.value.code,
                        'attachedVideo',
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InkWell(
                        onTap: () {
                          setState(() => videoPaths.removeAt(index));
                        },
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(5),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
          ],
          ElevatedButton.icon(
            onPressed: saving ? null : saveJournal,
            icon: const Icon(Icons.save_rounded),
            label: Text(
              saving
                  ? appText(LanguageController.current.value.code, 'saving')
                  : isEditing
                      ? 'Update Memory'
                      : appText(LanguageController.current.value.code, 'saveMemory'),
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
    messenger.showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)));
  }

  Widget profileLanguageSelector(BuildContext context, String code) {
    return Card(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: AppColors.gold.withOpacity(0.35), child: const Icon(Icons.language_rounded, color: AppColors.brown)),
            const SizedBox(width: 12),
            Expanded(child: Text(appText(code, 'languageSettings'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.deepBrown))),
          ]),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: code,
            isExpanded: true,
            decoration: inputDecoration(label: appText(code, 'preferredLanguage'), icon: Icons.translate_rounded),
            items: supportedLanguages.map((language) => DropdownMenuItem<String>(value: language.code, child: Text(language.name))).toList(),
            onChanged: (value) async {
              if (value == null) return;
              await LanguageController.setLanguageCode(value);
              if (context.mounted) showProfileMessage(context, appText(value, 'languageSaved'));
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final bool isPasswordAccount = user != null && AuthService().isPasswordUser(user);
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageController.current,
      builder: (context, language, _) {
        final code = language.code;
        return Scaffold(
          appBar: AppBar(title: Text(appText(code, 'profile'))),
          body: ListView(padding: const EdgeInsets.all(18), children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(28)),
              child: Column(children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: AppColors.gold,
                  backgroundImage: user?.photoURL == null ? null : NetworkImage(user!.photoURL!),
                  child: user?.photoURL == null ? const Icon(Icons.person_rounded, size: 50, color: AppColors.brown) : null,
                ),
                const SizedBox(height: 14),
                Text(user?.displayName ?? appText(code, 'profileUser'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.deepBrown)),
                const SizedBox(height: 4),
                Text(user?.email ?? appText(code, 'noEmail'), style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: isPasswordAccount ? () { Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen())); } : () { showProfileMessage(context, appText(code, 'changePasswordUnavailableMsg')); },
                  icon: const Icon(Icons.lock_reset_rounded),
                  label: Text(isPasswordAccount ? appText(code, 'changePassword') : appText(code, 'changePasswordUnavailable')),
                  style: mainButtonStyle(),
                )),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () => logout(context), icon: const Icon(Icons.logout_rounded), label: Text(appText(code, 'logout')), style: mainButtonStyle())),
              ]),
            ),
            const SizedBox(height: 18),
            profileLanguageSelector(context, code),
            const SizedBox(height: 18),
            InfoCard(icon: Icons.info_rounded, title: appText(code, 'systemNote'), body: appText(code, 'systemNoteBody')),
          ]),
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
              label: Text(loading ? 'Changing Password...' : 'Save New Password'),
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

  const VideoPlaceCard({
    super.key,
    required this.place,
    required this.onTap,
  });

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

  const LocalJournalImageThumb({
    super.key,
    required this.path,
  });

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

    return Image.file(
      file,
      width: 82,
      height: 82,
      fit: BoxFit.cover,
    );
  }
}

class JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const JournalCard({
    super.key,
    required this.entry,
    this.onEdit,
    required this.onDelete,
  });

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
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    tooltip: 'Edit',
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: AppColors.brown,
                    ),
                  ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    tooltip: 'Delete',
                    icon: const Icon(
                      Icons.delete_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
            if (entry.letter.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                entry.letter,
                style: const TextStyle(height: 1.45),
              ),
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
  State<LocalJournalVideoPlayer> createState() => _LocalJournalVideoPlayerState();
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
                  videoController.value.isPlaying ? 'Pause Video' : 'Play Video',
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
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
        }
      }).catchError((error) {
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
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

  const SectionTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });

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
          style: const TextStyle(
            color: Colors.black54,
            height: 1.4,
          ),
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
    Widget imageWidget;

    if (image.isFallback || image.base64Data.trim().isEmpty) {
      imageWidget = FutureBuilder<String?>(
        future: PlaceImageService().getPlaceImageUrl(place),
        builder: (context, snapshot) {
          final imageUrl = snapshot.data;

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              width: double.infinity,
              height: 220,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.bg,
              ),
              child: const CircularProgressIndicator(color: AppColors.brown),
            );
          }

          if (imageUrl == null || imageUrl.trim().isEmpty) {
            return Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [
                    AppColors.deepBrown,
                    AppColors.brown,
                    AppColors.clay,
                  ],
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
                      place.name,
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

          return Image.network(
            imageUrl,
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: double.infinity,
                height: 220,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: AppColors.bg,
                ),
                child: Text(
                  place.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.deepBrown,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      final imageBytes = base64Decode(image.base64Data);
      imageWidget = Image.memory(
        imageBytes,
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

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
              const Icon(Icons.image_rounded, color: AppColors.brown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  image.isFallback
                      ? '${appText(languageCode, 'aiImageFallbackTitle')} - ${place.name}'
                      : appText(languageCode, 'aiImageTitle'),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: imageWidget,
          ),
          const SizedBox(height: 8),
          Text(
            image.isFallback
                ? '${appText(languageCode, 'aiImageFallbackBody')} ${place.name}.'
                : image.promptSummary,
            style: const TextStyle(
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
                  Text(
                    body,
                    style: const TextStyle(height: 1.4),
                  ),
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
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    ),
    textStyle: const TextStyle(fontWeight: FontWeight.w900),
  );
}

ButtonStyle socialButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.brown,
    backgroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 14),
    side: const BorderSide(color: AppColors.gold),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    ),
    textStyle: const TextStyle(fontWeight: FontWeight.w900),
  );
}