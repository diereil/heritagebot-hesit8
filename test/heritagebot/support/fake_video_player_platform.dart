// HERITAGEBOT - TEST SUPPORT: fake native layer for the video_player plugin.
//
// Added for CASE-035 / CASE-037 (and any test that opens a screen containing
// HeritageBot's real HeritageVideoPlayer). Like the other fakes in this
// folder it replaces ONLY the plugin's native platform implementation
// (VideoPlayerPlatform.instance). HeritageBot's widgets and the real
// video_player package (VideoPlayerController / VideoPlayer) run unmodified.
//
// Behaviour mirrors the Android/iOS implementations:
//   * an asset video that IS packaged in the app's asset bundle opens and
//     reports `initialized` (duration + size);
//   * an asset video that is NOT in the bundle fails to open: the player
//     emits a PlatformException on its event stream, exactly as ExoPlayer /
//     AVPlayer do for a missing source;
//   * play()/pause() are recorded and acknowledged with isPlaying events.
//
// Whether an asset exists is read from the REAL AssetManifest that
// `flutter test` builds from pubspec.yaml - the fake never decides it.
//
// video_player_platform_interface is a transitive dependency of video_player
// (already in pubspec.lock); pubspec.yaml is not modified.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform._();

  /// Installs the fake and reads the real asset manifest. Call from
  /// setUpAll() (outside the widget-test fake-async zone).
  static Future<FakeVideoPlayerPlatform> install() async {
    final fake = FakeVideoPlayerPlatform._();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    fake.bundledAssets = manifest.listAssets().toSet();
    VideoPlayerPlatform.instance = fake;
    return fake;
  }

  /// Every asset path packaged with the app (from AssetManifest.bin).
  Set<String> bundledAssets = <String>{};

  /// Data sources the app asked the native player to open, in order.
  final List<DataSource> openedSources = <DataSource>[];

  /// Player ids that were successfully initialised / asked to play / pause.
  final List<int> initializedPlayers = <int>[];
  final List<int> playCalls = <int>[];
  final List<int> pauseCalls = <int>[];

  final Map<int, StreamController<VideoEvent>> _events =
      <int, StreamController<VideoEvent>>{};
  int _nextPlayerId = 1;

  void clear() {
    openedSources.clear();
    initializedPlayers.clear();
    playCalls.clear();
    pauseCalls.clear();
  }

  bool _sourceExists(DataSource source) {
    switch (source.sourceType) {
      case DataSourceType.asset:
        return source.asset != null && bundledAssets.contains(source.asset);
      case DataSourceType.file:
        final uri = source.uri;
        return uri != null && File(Uri.parse(uri).toFilePath()).existsSync();
      case DataSourceType.network:
      case DataSourceType.contentUri:
        // No network / content resolver in the host test VM.
        return false;
    }
  }

  int _open(DataSource source) {
    final playerId = _nextPlayerId++;
    openedSources.add(source);

    // Single-subscription controller buffers events until the
    // VideoPlayerController starts listening (like the native event channel).
    final events = StreamController<VideoEvent>();
    _events[playerId] = events;

    if (_sourceExists(source)) {
      initializedPlayers.add(playerId);
      events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 2),
        size: const Size(1280, 720),
        rotationCorrection: 0,
      ));
    } else {
      events.addError(PlatformException(
        code: 'VideoError',
        message: 'Video player had error: source not found '
            '(${source.asset ?? source.uri})',
      ));
    }
    return playerId;
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => _open(dataSource);

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      _open(options.dataSource);

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {
    playCalls.add(playerId);
    _events[playerId]?.add(VideoEvent(
      eventType: VideoEventType.isPlayingStateUpdate,
      isPlaying: true,
    ));
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls.add(playerId);
    _events[playerId]?.add(VideoEvent(
      eventType: VideoEventType.isPlayingStateUpdate,
      isPlaying: false,
    ));
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => Texture(textureId: playerId);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      Texture(textureId: options.playerId);
}
