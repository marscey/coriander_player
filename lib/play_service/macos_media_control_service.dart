import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../library/audio_library.dart';
import 'playback_service.dart';
import '../platform_helper.dart';
import '../utils.dart';

/// macOS 和 iOS 系统媒体控制服务
///
/// macOS: 通过 audio_service 接入系统通知栏控件
/// iOS: 通过 audio_service 接入 MPRemoteCommandCenter（锁屏/蓝牙控制）
///
/// 蓝牙歌词方案：将歌词文本动态更新到 title（歌曲名称）字段，
/// 通过 MPNowPlayingInfoCenter 传输给锁屏/蓝牙设备显示。
/// 这与 QQ音乐、网易云音乐等主流播放器的方案一致。
class MacosMediaControlService extends BaseAudioHandler
    with WidgetsBindingObserver {
  static MacosMediaControlService? _instance;
  Audio? _currentAudio;

  String? _lastCoverAudioPath;
  String? _cachedCoverPath;
  Uint8List? _cachedCoverBytes;

  String? _lastLyricText;

  bool _bluetoothLyricEnabled = true;

  Function()? onPlay;
  Function()? onPause;
  Function()? onStop;
  Function()? onNext;
  Function()? onPrevious;
  Function(Duration)? onSeek;

  MacosMediaControlService._() {
    if (PlatformHelper.isIOS || PlatformHelper.isMacOS) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  static MacosMediaControlService get instance => _instance!;

  bool get bluetoothLyricEnabled => _bluetoothLyricEnabled;

  set bluetoothLyricEnabled(bool value) {
    _bluetoothLyricEnabled = value;
    if (!value && _currentAudio != null) {
      _lastLyricText = null;
      _updateMediaItem();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!PlatformHelper.isIOS && !PlatformHelper.isMacOS) return;
    if (state == AppLifecycleState.resumed) {
      _ensureNowPlayingInfo();
    }
  }

  void _ensureNowPlayingInfo() {
    if (_currentAudio == null) return;
    ensureAudioSessionActive();
    _updateMediaItem(lyricText: _lastLyricText);
  }

  static Future<MacosMediaControlService> init() async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) {
      _instance = MacosMediaControlService._();
      return _instance!;
    }

    LOGGER
        .i("[MediaControl] init: START, platform=${Platform.operatingSystem}");

    await _configureAudioSession();

    LOGGER.i(
        "[MediaControl] init: AudioSession configured, calling AudioService.init...");

    _instance = await AudioService.init(
      builder: () {
        LOGGER.i("[MediaControl] init: builder callback called");
        return MacosMediaControlService._();
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.coriander.player.channel.audio',
        androidNotificationChannelName: 'AudioService',
        androidNotificationOngoing: true,
        androidNotificationClickStartsActivity: true,
        androidShowNotificationBadge: true,
      ),
    );

    LOGGER.i("[MediaControl] init: AudioService.init completed");

    if (PlatformHelper.isIOS) {
      await _verifyAudioSessionState("after AudioService.init");
    }

    return _instance!;
  }

  static Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      LOGGER.i("[MediaControl] AudioSession configured as music/playback");

      try {
        await session.setActive(true);
        LOGGER.i("[MediaControl] AudioSession setActive(true) SUCCESS");
      } catch (e) {
        LOGGER.e("[MediaControl] AudioSession setActive(true) FAILED: $e");
      }

      if (PlatformHelper.isIOS) {
        await _verifyAudioSessionState("after configure");
      }
    } catch (e) {
      LOGGER.e("[MediaControl] Failed to configure AudioSession: $e");
    }
  }

  static Future<void> _verifyAudioSessionState(String context) async {
    try {
      final session = await AudioSession.instance;
      LOGGER.i(
          "[MediaControl] AudioSession state ($context): isConfigured=${session.isConfigured}");
    } catch (e) {
      LOGGER.e(
          "[MediaControl] Failed to verify AudioSession state ($context): $e");
    }
  }

  void setPlaybackService(PlaybackService playbackService) {}

  void setCallbacks({
    Function()? onPlay,
    Function()? onPause,
    Function()? onStop,
    Function()? onNext,
    Function()? onPrevious,
    Function(Duration)? onSeek,
  }) {
    this.onPlay = onPlay;
    this.onPause = onPause;
    this.onStop = onStop;
    this.onNext = onNext;
    this.onPrevious = onPrevious;
    this.onSeek = onSeek;
  }

  void updateCurrentMediaItem(Audio audio) {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;

    _currentAudio = audio;
    _lastLyricText = null;

    final artUri = _getCachedCoverUri(audio);
    LOGGER.i("[MediaControl] updateCurrentMediaItem: title='${audio.title}', "
        "artist='${audio.artist}', album='${audio.album}', "
        "duration=${audio.duration}s, artUri=$artUri");

    _updateMediaItem();

    _loadAndUpdateCover(audio);
  }

  /// 更新歌词到锁屏/媒体中心
  /// 有歌词时：title=歌词，artist=歌曲名 - 艺术家
  /// 歌词只取第一行，过滤音译/翻译等第二行内容
  void updateLyricOnCover(String lyricText, {String? translation}) {
    if (!PlatformHelper.isIOS && !PlatformHelper.isMacOS) return;
    if (!_bluetoothLyricEnabled) return;
    if (_currentAudio == null) return;

    // 只取歌词第一行，过滤音译/翻译等第二行
    final firstLine = lyricText.split('\n').first.trim();
    if (firstLine.isEmpty) return;

    if (firstLine == _lastLyricText) return;

    _lastLyricText = firstLine;
    _updateMediaItem(lyricText: firstLine);
  }

  /// 清除歌词（暂停/停止时调用）
  void clearLyricFromCover() {
    if (!PlatformHelper.isIOS && !PlatformHelper.isMacOS) return;
    if (!_bluetoothLyricEnabled) return;
    _lastLyricText = null;
    _updateMediaItem();
  }

  /// 更新 MediaItem
  /// 无歌词时：title=歌曲名，artist=艺术家 - 专辑
  /// 有歌词时：title=歌词，artist=歌曲名 - 艺术家
  void _updateMediaItem({String? lyricText}) {
    if (_currentAudio == null) return;

    final artUri = _getCachedCoverUri(_currentAudio!);
    final String title;
    final String artist;

    if (lyricText != null) {
      title = lyricText;
      artist = '${_currentAudio!.title} - ${_currentAudio!.artist}';
    } else {
      title = _currentAudio!.title;
      final parts = <String>[
        if (_currentAudio!.artist.isNotEmpty) _currentAudio!.artist,
        if (_currentAudio!.album.isNotEmpty) _currentAudio!.album,
      ];
      artist = parts.join(' - ');
    }

    mediaItem.add(
      MediaItem(
        id: _currentAudio!.path,
        album: _currentAudio!.album,
        title: title,
        artist: artist,
        duration:
            Duration(milliseconds: (_currentAudio!.duration * 1000).toInt()),
        artUri: artUri,
      ),
    );
  }

  Uri? _getCachedCoverUri(Audio audio) {
    if (_lastCoverAudioPath == audio.path && _cachedCoverPath != null) {
      final file = File(_cachedCoverPath!);
      if (file.existsSync()) {
        return Uri.file(_cachedCoverPath!);
      } else {
        LOGGER
            .w("[MediaControl] Cached cover file not found: $_cachedCoverPath");
        _lastCoverAudioPath = null;
        _cachedCoverPath = null;
        _cachedCoverBytes = null;
      }
    }
    return null;
  }

  Future<void> _loadAndUpdateCover(Audio audio) async {
    try {
      if (_lastCoverAudioPath == audio.path && _cachedCoverPath != null) {
        return;
      }

      final coverProvider = await audio.largeCover;
      if (coverProvider == null) {
        final smallCover = await audio.cover;
        if (smallCover == null) {
          LOGGER.i("[MediaControl] No cover available for: ${audio.title}");
          _cachedCoverBytes = null;
          return;
        }
        final coverBytes = await _extractBytesFromImageProvider(smallCover);
        if (coverBytes != null) {
          _cachedCoverBytes = coverBytes;
        } else {
          _cachedCoverBytes = null;
        }
        return;
      }

      final coverBytes = await _extractBytesFromImageProvider(coverProvider);
      if (coverBytes == null) {
        LOGGER.w(
            "[MediaControl] Failed to extract cover bytes for: ${audio.title}");
        _cachedCoverBytes = null;
        return;
      }

      _cachedCoverBytes = coverBytes;

      final tempDir = await getTemporaryDirectory();
      final coverPath = p.join(tempDir.path, 'now_playing_cover.jpg');
      final coverFile = File(coverPath);
      await coverFile.writeAsBytes(coverBytes);

      _lastCoverAudioPath = audio.path;
      _cachedCoverPath = coverPath;

      if (_currentAudio == audio) {
        _updateMediaItem(lyricText: _lastLyricText);
        LOGGER.i(
            "[MediaControl] MediaItem cover updated, artUri=${Uri.file(coverPath)}");
      }
    } catch (e) {
      LOGGER.e("[MediaControl] Failed to load cover: $e");
    }
  }

  Future<Uint8List?> _extractBytesFromImageProvider(
      ImageProvider provider) async {
    try {
      if (provider is MemoryImage) {
        return provider.bytes;
      }
      if (provider is FileImage) {
        return await File(provider.file.path).readAsBytes();
      }
      return null;
    } catch (e) {
      LOGGER.e("[MediaControl] Failed to extract bytes: $e");
      return null;
    }
  }

  void updatePlaybackState({
    required bool playing,
    Duration? position,
    AudioProcessingState? processingState,
  }) {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;

    final controls = [
      MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
    ];

    final state = PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState ?? AudioProcessingState.ready,
      playing: playing,
      updatePosition: position ?? Duration.zero,
      speed: 1.0,
    );

    playbackState.add(state);
  }

  static Future<void> ensureAudioSessionActive() async {
    if (!PlatformHelper.isIOS && !PlatformHelper.isMacOS) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
      LOGGER.i("[MediaControl] AudioSession ensured active");
    } catch (e) {
      LOGGER.e("[MediaControl] Failed to ensure AudioSession active: $e");
    }
  }

  @override
  Future<void> play() async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;
    LOGGER.i("[MediaControl] System requested play");
    onPlay?.call();
  }

  @override
  Future<void> pause() async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;
    LOGGER.i("[MediaControl] System requested pause");
    onPause?.call();
  }

  @override
  Future<void> stop() async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;
    LOGGER.i("[MediaControl] System requested stop");
    onStop?.call();
  }

  @override
  Future<void> skipToNext() async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;
    LOGGER.i("[MediaControl] System requested skipToNext");
    onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;
    LOGGER.i("[MediaControl] System requested skipToPrevious");
    onPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;
    LOGGER.i("[MediaControl] System requested seek to ${position.inSeconds}s");
    onSeek?.call(position);
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;
    await stop();
    await super.onTaskRemoved();
  }

  void dispose() {
    if (PlatformHelper.isMacOS || PlatformHelper.isIOS) {
      WidgetsBinding.instance.removeObserver(this);
      super.stop();
    }
  }
}
