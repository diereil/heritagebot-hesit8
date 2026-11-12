// HERITAGEBOT - TEST SUPPORT: offline stand-in for Cloudinary's media
// delivery CDN (res.cloudinary.com) for CASE-096 (Community Contribution
// Review / View Attached Media).
//
// A community submission stores the secure_url of each photo / video that
// CommunityMediaService uploaded. The real AdminReviewSubmissionScreen
// (lib/, unmodified) shows those URLs with Image.network and
// LocalJournalVideoPlayer (VideoPlayerController.networkUrl). The host test
// VM has no internet, so this fake plays the CDN:
//
//   * FakeMediaCdn.photos  -> bytes served for a photo URL (HTTP 200);
//                             any other URL -> HTTP 404.
//                             Installed through Flutter's own debug hook
//                             debugNetworkImageHttpClientProvider (used by
//                             NetworkImage only).
//   * FakeMediaCdn.videos  -> video URLs the CDN can stream. The fake
//                             video_player native layer (VideoPlayerPlatform)
//                             reports `initialized` for these URLs and a
//                             source error for any other URL, like
//                             ExoPlayer / AVPlayer.
//
// It never decides which media HeritageBot shows - it only answers the
// requests HeritageBot makes, and records them.
//
// video_player_platform_interface is a transitive dependency of
// video_player (already in pubspec.lock); pubspec.yaml is not modified.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeMediaCdn {
  /// Photo URL -> image bytes.
  final Map<String, Uint8List> photos = <String, Uint8List>{};

  /// Video URLs that can be streamed.
  final Set<String> videos = <String>{};

  /// Every URL HeritageBot requested (photos via HTTP, videos via player).
  final List<String> requestedPhotoUrls = <String>[];
  final List<String> openedVideoUrls = <String>[];

  late final FakeCdnVideoPlayerPlatform videoPlayer =
      FakeCdnVideoPlayerPlatform._(this);

  /// Installs the fake video layer and the NetworkImage HTTP client.
  /// Call [uninstall] before the test ends (Flutter checks that debug
  /// hooks are reset).
  void install() {
    VideoPlayerPlatform.instance = videoPlayer;
    debugNetworkImageHttpClientProvider = () => _FakeCdnHttpClient(this);
  }

  void uninstall() {
    debugNetworkImageHttpClientProvider = null;
  }
}

// ---------------------------------------------------------------------------
// PHOTOS (NetworkImage -> HttpClient)
// ---------------------------------------------------------------------------

class _FakeCdnHttpClient implements HttpClient {
  _FakeCdnHttpClient(this._cdn);

  final FakeMediaCdn _cdn;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeCdnRequest(_cdn, url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCdnHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCdnRequest implements HttpClientRequest {
  _FakeCdnRequest(this._cdn, this._url);

  final FakeMediaCdn _cdn;
  final Uri _url;

  @override
  final HttpHeaders headers = _FakeCdnHeaders();

  @override
  Future<HttpClientResponse> close() async {
    final key = _url.toString();
    _cdn.requestedPhotoUrls.add(key);
    final bytes = _cdn.photos[key];
    return _FakeCdnResponse(bytes == null ? 404 : 200, bytes ?? Uint8List(0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCdnResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeCdnResponse(this.statusCode, this._bytes);

  @override
  final int statusCode;
  final Uint8List _bytes;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable(<List<int>>[
        if (_bytes.isNotEmpty) _bytes,
      ]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// VIDEOS (VideoPlayerController.networkUrl -> VideoPlayerPlatform)
// ---------------------------------------------------------------------------

class FakeCdnVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeCdnVideoPlayerPlatform._(this._cdn);

  final FakeMediaCdn _cdn;
  final Map<int, StreamController<VideoEvent>> _events =
      <int, StreamController<VideoEvent>>{};
  int _nextPlayerId = 1;

  /// Player ids that reached `initialized`.
  final List<int> initializedPlayers = <int>[];

  int _open(DataSource source) {
    final playerId = _nextPlayerId++;
    final url = source.uri ?? source.asset ?? '';
    _cdn.openedVideoUrls.add(url);
    final events = StreamController<VideoEvent>();
    _events[playerId] = events;

    if (source.sourceType == DataSourceType.network &&
        _cdn.videos.contains(url)) {
      initializedPlayers.add(playerId);
      events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 45),
        size: const Size(1280, 720),
        rotationCorrection: 0,
      ));
    } else {
      events.addError(PlatformException(
        code: 'VideoError',
        message: 'Video player had error: source not found ($url)',
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
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

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
