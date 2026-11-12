// HERITAGEBOT - TEST SUPPORT: shared harness for CASE-007..CASE-030.
//
// Installs the platform-level fakes (Firebase Auth, Cloud Firestore,
// Google Sign-In, Geolocator, Facebook SDK channel, text-to-speech channel)
// BEFORE any HeritageBot code runs, and gives every test a clean backend so
// tests never share authentication or database state.
//
// Nothing here renders a HeritageBot screen of its own or produces a result:
// tests pump the REAL widgets from package:heritagebot/main.dart.

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/models/user_profile.dart';
import 'package:heritagebot/services/language_service.dart';

import 'fake_firebase_platform.dart';
import 'fake_plugin_platforms.dart';

export 'fake_firebase_platform.dart';
export 'fake_plugin_platforms.dart';

/// All fake back-ends for one test file.
class HeritageBotTestBackend {
  HeritageBotTestBackend._({
    required this.auth,
    required this.firestore,
    required this.google,
    required this.geolocator,
    required this.channels,
  });

  final FakeFirebaseAuthPlatform auth;
  final FakeFirebaseFirestorePlatform firestore;
  final FakeGoogleSignInPlatform google;
  final FakeGeolocatorPlatform geolocator;
  final FakeChannelPlugins channels;

  /// Call from setUpAll(). [accounts] are the Firebase Auth accounts that
  /// exist before the test starts.
  static Future<HeritageBotTestBackend> install({
    List<FakeAuthAccount> accounts = const [],
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();

    final backend = HeritageBotTestBackend._(
      auth: FakeFirebaseAuthPlatform(accounts: accounts),
      firestore: FakeFirebaseFirestorePlatform(),
      google: FakeGoogleSignInPlatform(),
      geolocator: FakeGeolocatorPlatform(),
      channels: FakeChannelPlugins(),
    );

    FirebaseAuthPlatform.instance = backend.auth;
    FirebaseFirestorePlatform.instance = backend.firestore;
    GoogleSignInPlatform.instance = backend.google;
    GeolocatorPlatform.instance = backend.geolocator;
    backend.channels.install();

    await Firebase.initializeApp();
    await _loadDeviceFonts();
    return backend;
  }

  static bool _fontsLoaded = false;

  /// flutter_test normally draws every glyph as a 1em square ("Ahem"-style
  /// test font), which makes text far wider than on a phone and produces
  /// layout overflows that never happen on a device. Load the real Roboto
  /// family (Material's Android font) and Material Icons that ship with the
  /// Flutter SDK so layouts are measured with real device font metrics.
  static Future<void> _loadDeviceFonts() async {
    if (_fontsLoaded) return;
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null) return;
    final dir = Directory(
      '$flutterRoot/bin/cache/artifacts/material_fonts',
    );
    if (!dir.existsSync()) return;

    final roboto = FontLoader('Roboto');
    final icons = FontLoader('MaterialIcons');
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last.toLowerCase();
      if (name.startsWith('roboto') && name.endsWith('.ttf')) {
        roboto.addFont(_fontBytes(file));
      } else if (name.startsWith('materialicons') && name.endsWith('.otf')) {
        icons.addFont(_fontBytes(file));
      }
    }
    await roboto.load();
    await icons.load();
    _fontsLoaded = true;
  }

  static Future<ByteData> _fontBytes(File file) async =>
      ByteData.sublistView(Uint8List.fromList(await file.readAsBytes()));

  /// Call from setUp(): logged out, empty database, default site list,
  /// English UI, no recorded calls.
  Future<void> reset() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await FirebaseAuth.instance.signOut();
    auth.clearCallLogs();
    firestore.documents.clear();
    channels.clear();
    heritagePlaces
      ..clear()
      ..addAll(defaultHeritagePlaces);
    LanguageController.current.value = languageByCode('en');
  }

  /// Seeds users/{uid} with the same fields UserService.savePublicProfile
  /// writes.
  void seedProfile({
    required String uid,
    required String email,
    required String fullName,
    required String role,
    String accountStatus = 'active',
  }) {
    firestore.seedDocument('users/$uid', <String, dynamic>{
      'uid': uid,
      'fullName': fullName,
      'email': email,
      'role': role,
      'preferredLanguage': 'en',
      'accountStatus': accountStatus,
      'photoUrl': '',
      'createdAtMillis': 0,
      'updatedAtMillis': 0,
    });
  }

  /// Convenience for an already-registered, verified tourist.
  void seedTourist(FakeAuthAccount account) => seedProfile(
        uid: account.uid,
        email: account.email,
        fullName: account.displayName ?? 'Test Tourist',
        role: UserRoles.tourist,
      );
}

/// English UI string exactly as the app renders it.
String en(String key) => appText('en', key);

/// Phone-sized surface so real layouts render as on a device:
/// 1080 x 2400 px at 2.625 dpr = 411 x 914 logical px (common Android phone).
/// (flutter_test renders text with a square-glyph test font that is wider
/// than real fonts, so a narrower surface can cause sub-pixel overflows that
/// do not occur on the device.)
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

/// Pumps frames (letting real async work complete) until [finder] matches.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Widget did not appear after $maxPumps pumps: $finder');
}

/// Pumps frames until [finder] no longer matches (e.g. a route was popped).
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Widget still present after $maxPumps pumps: $finder');
}

/// Pumps a fixed amount of time in small steps (for real async work that
/// must be allowed to finish before asserting something did NOT happen).
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final steps = duration.inMilliseconds ~/ 50;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls [finder] into view and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget, reason: 'Expected exactly one $finder');
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Text fields inside the real LoginSignupScreen, in on-screen order.
Finder fieldsOf(Type screen) => find.descendant(
      of: find.byType(screen),
      matching: find.byType(TextField),
    );

/// Finds a SnackBar showing exactly [message].
Finder snackBarWithText(String message) => find.descendant(
      of: find.byType(SnackBar),
      matching: find.text(message),
    );

/// Precondition helper: [account] is already signed in on the device
/// (as after an earlier successful login) before the app is opened.
Future<void> signInBeforeLaunch(FakeAuthAccount account) async {
  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: account.email,
    password: account.password,
  );
}

/// Opens the real app entry point (AuthGate) and waits for [screen].
Future<void> launchAuthGate(WidgetTester tester, {required Type until}) async {
  await tester.pumpWidget(const MaterialApp(home: app.AuthGate()));
  await pumpUntilFound(tester, find.byType(until));
}

/// Taps a destination of the real bottom NavigationBar by its label.
Future<void> tapNavDestination(WidgetTester tester, String label) async {
  final destination = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  expect(destination, findsOneWidget,
      reason: 'Navigation destination "$label" must exist.');
  await tester.tap(destination);
  await tester.pump();
}

/// Scrolls the first scrollable inside [screen] until [finder] is built.
Future<void> scrollUntilBuilt(
  WidgetTester tester,
  Finder finder, {
  required Type screen,
  double delta = 250, // positive scrolls down, negative scrolls up
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(of: find.byType(screen), matching: find.byType(Scrollable))
        .first,
  );
}

/// The real InfoCard widgets currently built whose title is [title].
List<app.InfoCard> infoCardsTitled(WidgetTester tester, String title) => tester
    .widgetList<app.InfoCard>(find.byType(app.InfoCard, skipOffstage: false))
    .where((card) => card.title == title)
    .toList();

/// Unmounts the app so pending timers/futures settle cleanly.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}
