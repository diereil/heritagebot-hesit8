// HERITAGEBOT - TEST SUPPORT: Fakes for native plugin platform layers.
//
// Like fake_firebase_platform.dart, these replace ONLY the native platform
// implementation that each plugin exposes for testing. All HeritageBot code
// above them (AuthService, LocationService, GeolocationScreen,
// NarrativeAudioService ...) runs unmodified from lib/.
//
//   * FakeGoogleSignInPlatform  -> GoogleSignInPlatform.instance
//                                 (account picker: choose account / cancel)
//   * FakeGeolocatorPlatform    -> GeolocatorPlatform.instance
//                                 (GPS on/off, permission dialog, fixes)
//   * Facebook + flutter_tts    -> mocked MethodChannels that record calls
//
// The fakes never decide a test outcome; they provide device/provider
// behaviour and record what the app asked for.

// Transitive dependencies of google_sign_in / geolocator (already in
// pubspec.lock); pubspec.yaml is not modified.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

// ---------------------------------------------------------------------------
// GOOGLE SIGN-IN
// ---------------------------------------------------------------------------

/// What the (fake) Google account picker does when the app opens it.
enum FakeGooglePickerOutcome { chooseAccount, cancel }

class FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  FakeGoogleSignInPlatform();

  FakeGooglePickerOutcome outcome = FakeGooglePickerOutcome.cancel;

  /// Google identity returned when the user chooses an account.
  GoogleSignInUserData? account;
  String? idToken;

  int authenticateCalls = 0;
  int signOutCalls = 0;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async =>
      null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    authenticateCalls++;

    if (outcome == FakeGooglePickerOutcome.cancel || account == null) {
      // Exactly what the Android/iOS implementations throw when the user
      // dismisses the Google account picker.
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
        description: 'The user canceled the sign-in flow.',
      );
    }

    return AuthenticationResults(
      user: account!,
      authenticationTokens: AuthenticationTokenData(idToken: idToken),
    );
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async {
    signOutCalls++;
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

// ---------------------------------------------------------------------------
// GEOLOCATOR (device GPS + OS permission dialog)
// ---------------------------------------------------------------------------

class FakeGeolocatorPlatform extends GeolocatorPlatform {
  FakeGeolocatorPlatform();

  /// Device location service (GPS switch).
  bool serviceEnabled = true;

  /// Current OS permission state.
  LocationPermission permission = LocationPermission.denied;

  /// What the user taps in the OS permission dialog.
  LocationPermission userResponseToPermissionDialog =
      LocationPermission.whileInUse;

  /// Fix returned by getCurrentPosition.
  Position? currentFix;

  final StreamController<Position> liveFixes =
      StreamController<Position>.broadcast();

  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int getCurrentPositionCalls = 0;

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls++;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    permission = userResponseToPermissionDialog;
    return permission;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async =>
      null;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    getCurrentPositionCalls++;

    // Mirrors the native implementations' error behaviour.
    if (!serviceEnabled) throw const LocationServiceDisabledException();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException('Location permission denied');
    }
    final fix = currentFix;
    if (fix == null) {
      throw TimeoutException('No GPS fix available');
    }
    return fix;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      liveFixes.stream;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// Builds a GPS fix. [accuracy] is the horizontal accuracy radius in metres
/// as reported by the device (Position.accuracy).
Position fakeGpsFix({
  required double latitude,
  required double longitude,
  double accuracy = 5,
  double speed = 0,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

// ---------------------------------------------------------------------------
// METHOD-CHANNEL PLUGINS (Facebook SDK, text-to-speech)
// ---------------------------------------------------------------------------

class FakeChannelPlugins {
  final List<MethodCall> facebookCalls = <MethodCall>[];
  final List<MethodCall> ttsCalls = <MethodCall>[];

  /// Text passed to FlutterTts.speak().
  List<String> get spokenTexts => ttsCalls
      .where((call) => call.method == 'speak')
      .map((call) => call.arguments.toString())
      .toList();

  void clear() {
    facebookCalls.clear();
    ttsCalls.clear();
  }

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel('app.meedu/flutter_facebook_auth'),
      (call) async {
        facebookCalls.add(call);
        return null;
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async {
        ttsCalls.add(call);
        // 1 == success for speak/stop/set* on Android & iOS.
        if (call.method == 'isLanguageAvailable') return true;
        return 1;
      },
    );
  }
}
