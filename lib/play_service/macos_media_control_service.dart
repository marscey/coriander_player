import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/painting.dart';
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
/// iOS 蓝牙歌词方案：将歌词文本绘制到封面图底部，
/// 通过 AVRCP 封面图传输给蓝牙设备显示。
/// 这是目前 iOS 上唯一可行的蓝牙歌词显示方案。
class MacosMediaControlService extends BaseAudioHandler {
  static MacosMediaControlService? _instance;
  Audio? _currentAudio;

  // 封面缓存
  String? _lastCoverAudioPath;
  String? _cachedCoverPath;
  Uint8List? _cachedCoverBytes; // 缓存原始封面字节，用于歌词叠加

  // 歌词封面
  String? _lyricCoverPath; // 带歌词的封面路径
  String? _lastLyricText; // 上次绘制的歌词文本，避免重复绘制
  DateTime? _lastLyricUpdateTime; // 上次更新时间，用于节流

  // 蓝牙歌词开关
  bool _bluetoothLyricEnabled = true;

  // 回调函数
  Function()? onPlay;
  Function()? onPause;
  Function()? onStop;
  Function()? onNext;
  Function()? onPrevious;
  Function(Duration)? onSeek;

  MacosMediaControlService._();

  static MacosMediaControlService get instance => _instance!;

  /// 是否启用蓝牙歌词（封面图+歌词合成）
  bool get bluetoothLyricEnabled => _bluetoothLyricEnabled;

  set bluetoothLyricEnabled(bool value) {
    _bluetoothLyricEnabled = value;
    if (!value) {
      // 关闭时恢复原始封面
      _restoreOriginalCover();
    }
  }

  /// 初始化 AudioService
  static Future<MacosMediaControlService> init() async {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) {
      _instance = MacosMediaControlService._();
      return _instance!;
    }

    LOGGER.i("[MediaControl] init: START, platform=${Platform.operatingSystem}");

    await _configureAudioSession();

    LOGGER.i("[MediaControl] init: AudioSession configured, calling AudioService.init...");

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

  /// 配置音频会话
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

  /// 验证 AudioSession 当前状态
  static Future<void> _verifyAudioSessionState(String context) async {
    try {
      final session = await AudioSession.instance;
      LOGGER.i("[MediaControl] AudioSession state ($context): isConfigured=${session.isConfigured}");
    } catch (e) {
      LOGGER.e("[MediaControl] Failed to verify AudioSession state ($context): $e");
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

  // 更新媒体项
  void updateCurrentMediaItem(Audio audio) {
    if (!PlatformHelper.isMacOS && !PlatformHelper.isIOS) return;

    _currentAudio = audio;
    // 切歌时重置歌词状态
    _lastLyricText = null;
    _lastLyricUpdateTime = null;

    final artUri = _getCachedCoverUri(audio);
    LOGGER.i("[MediaControl] updateCurrentMediaItem: title='${audio.title}', "
        "artist='${audio.artist}', album='${audio.album}', "
        "duration=${audio.duration}s, artUri=$artUri");

    mediaItem.add(
      MediaItem(
        id: audio.path,
        album: audio.album,
        title: audio.title,
        artist: audio.artist,
        duration: Duration(milliseconds: (audio.duration * 1000).toInt()),
        artUri: artUri,
      ),
    );

    // 异步加载封面并更新
    _loadAndUpdateCover(audio);
  }

  /// 更新歌词到封面图（iOS 蓝牙歌词方案）
  /// 当歌词行变化时调用，将歌词文本绘制到封面图底部
  /// 使用节流策略：每 2 秒最多更新一次
  void updateLyricOnCover(String lyricText, {String? translation}) {
    if (!PlatformHelper.isIOS) return;
    if (!_bluetoothLyricEnabled) return;
    if (_currentAudio == null) return;

    // 节流：2秒内不重复更新
    final now = DateTime.now();
    if (_lastLyricUpdateTime != null &&
        now.difference(_lastLyricUpdateTime!).inSeconds < 2) {
      return;
    }

    // 文本相同则不更新
    final fullText = translation != null && translation.isNotEmpty
        ? '$lyricText\n$translation'
        : lyricText;
    if (fullText == _lastLyricText) return;

    _lastLyricText = fullText;
    _lastLyricUpdateTime = now;

    _renderLyricCover(lyricText, translation: translation);
  }

  /// 清除封面上的歌词（暂停/停止时调用）
  void clearLyricFromCover() {
    if (!PlatformHelper.isIOS) return;
    if (!_bluetoothLyricEnabled) return;
    _lastLyricText = null;
    _restoreOriginalCover();
  }

  /// 渲染歌词到封面图
  Future<void> _renderLyricCover(String lyricText, {String? translation}) async {
    try {
      // 需要有原始封面字节
      if (_cachedCoverBytes == null) {
        LOGGER.i("[MediaControl] No cover bytes cached, skip lyric render");
        return;
      }

      final compositeBytes = await _renderLyricOnImage(
        _cachedCoverBytes!,
        lyricText,
        translation: translation,
      );

      if (compositeBytes == null) {
        LOGGER.w("[MediaControl] Failed to render lyric on cover");
        return;
      }

      // 保存带歌词的封面
      final tempDir = await getTemporaryDirectory();
      _lyricCoverPath = p.join(tempDir.path, 'now_playing_cover_lyric.png');
      final coverFile = File(_lyricCoverPath!);
      await coverFile.writeAsBytes(compositeBytes);

      // 更新 MediaItem
      if (_currentAudio != null) {
        final artUri = Uri.file(_lyricCoverPath!);
        mediaItem.add(
          MediaItem(
            id: _currentAudio!.path,
            album: _currentAudio!.album,
            title: _currentAudio!.title,
            artist: _currentAudio!.artist,
            duration: Duration(milliseconds: (_currentAudio!.duration * 1000).toInt()),
            artUri: artUri,
          ),
        );
        LOGGER.i("[MediaControl] Lyric cover updated: '$lyricText'");
      }
    } catch (e) {
      LOGGER.e("[MediaControl] Failed to render lyric cover: $e");
    }
  }

  /// 将歌词文本绘制到封面图上
  /// 使用 dart:ui 进行图片合成
  Future<Uint8List?> _renderLyricOnImage(
    Uint8List coverBytes,
    String lyricText, {
    String? translation,
  }) async {
    try {
      // 1. 解码原始封面
      final codec = await ui.instantiateImageCodec(coverBytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;

      final width = originalImage.width;
      final height = originalImage.height;

      // 2. 创建画布
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = Size(width.toDouble(), height.toDouble());

      // 3. 绘制原始封面
      canvas.drawImage(originalImage, Offset.zero, Paint());

      // 4. 绘制底部半透明遮罩
      final maskHeight = size.height * 0.35;
      final maskRect = Rect.fromLTWH(0, size.height - maskHeight, size.width, maskHeight);
      canvas.drawRect(maskRect, Paint()..color = const Color.fromRGBO(0, 0, 0, 0.65));

      // 5. 绘制歌词文本
      final fontSize = (width * 0.065).clamp(14.0, 28.0);
      final padding = width * 0.05;

      // 主歌词
      final lyricSpan = TextSpan(
        text: lyricText,
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 2),
          ],
        ),
      );
      final lyricPainter = TextPainter(
        text: lyricSpan,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '...',
      );
      lyricPainter.layout(maxWidth: size.width - padding * 2);

      // 翻译歌词
      TextPainter? transPainter;
      if (translation != null && translation.isNotEmpty) {
        final transFontSize = fontSize * 0.8;
        final transSpan = TextSpan(
          text: translation,
          style: TextStyle(
            color: const Color(0xFFCCCCCC),
            fontSize: transFontSize,
            shadows: const [
              Shadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 2),
            ],
          ),
        );
        transPainter = TextPainter(
          text: transSpan,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '...',
        );
        transPainter.layout(maxWidth: size.width - padding * 2);
      }

      // 计算垂直居中位置
      final totalTextHeight = lyricPainter.height + (transPainter != null ? transPainter.height + 4 : 0);
      final startY = size.height - maskHeight + (maskHeight - totalTextHeight) / 2;

      lyricPainter.paint(canvas, Offset(padding, startY));

      if (transPainter != null) {
        transPainter.paint(canvas, Offset(padding, startY + lyricPainter.height + 4));
      }

      // 6. 转换为图片
      final picture = recorder.endRecording();
      final compositeImage = await picture.toImage(width, height);
      final byteData = await compositeImage.toByteData(format: ui.ImageByteFormat.png);

      // 释放资源
      originalImage.dispose();
      compositeImage.dispose();

      return byteData?.buffer.asUint8List();
    } catch (e) {
      LOGGER.e("[MediaControl] Failed to render lyric on image: $e");
      return null;
    }
  }

  /// 恢复原始封面（不带歌词）
  void _restoreOriginalCover() {
    if (_currentAudio == null) return;
    if (_cachedCoverPath == null) return;

    final artUri = _getCachedCoverUri(_currentAudio!);
    if (artUri != null) {
      mediaItem.add(
        MediaItem(
          id: _currentAudio!.path,
          album: _currentAudio!.album,
          title: _currentAudio!.title,
          artist: _currentAudio!.artist,
          duration: Duration(milliseconds: (_currentAudio!.duration * 1000).toInt()),
          artUri: artUri,
        ),
      );
      LOGGER.i("[MediaControl] Restored original cover (no lyric)");
    }
  }

  /// 获取缓存的封面 URI
  Uri? _getCachedCoverUri(Audio audio) {
    if (_lastCoverAudioPath == audio.path && _cachedCoverPath != null) {
      final file = File(_cachedCoverPath!);
      if (file.existsSync()) {
        return Uri.file(_cachedCoverPath!);
      } else {
        LOGGER.w("[MediaControl] Cached cover file not found: $_cachedCoverPath");
        _lastCoverAudioPath = null;
        _cachedCoverPath = null;
        _cachedCoverBytes = null;
      }
    }
    return null;
  }

  /// 异步加载封面图片并更新 MediaItem
  Future<void> _loadAndUpdateCover(Audio audio) async {
    try {
      if (_lastCoverAudioPath == audio.path && _cachedCoverPath != null) {
        return;
      }

      final coverProvider = await audio.cover;
      if (coverProvider == null) {
        LOGGER.i("[MediaControl] No cover available for: ${audio.title}");
        _cachedCoverBytes = null;
        return;
      }

      final coverBytes = await _extractBytesFromImageProvider(coverProvider);
      if (coverBytes == null) {
        LOGGER.w("[MediaControl] Failed to extract cover bytes for: ${audio.title}");
        _cachedCoverBytes = null;
        return;
      }

      // 缓存原始封面字节（用于歌词叠加）
      _cachedCoverBytes = coverBytes;

      final tempDir = await getTemporaryDirectory();
      final coverPath = p.join(tempDir.path, 'now_playing_cover.jpg');
      final coverFile = File(coverPath);
      await coverFile.writeAsBytes(coverBytes);

      final exists = await coverFile.exists();
      final size = exists ? await coverFile.length() : 0;
      LOGGER.i("[MediaControl] Cover file written: path=$coverPath, exists=$exists, size=$size bytes");

      _lastCoverAudioPath = audio.path;
      _cachedCoverPath = coverPath;

      if (_currentAudio == audio) {
        final artUri = Uri.file(coverPath);
        mediaItem.add(
          MediaItem(
            id: audio.path,
            album: audio.album,
            title: audio.title,
            artist: audio.artist,
            duration: Duration(milliseconds: (audio.duration * 1000).toInt()),
            artUri: artUri,
          ),
        );
        LOGGER.i("[MediaControl] MediaItem cover updated, artUri=$artUri");
      }
    } catch (e) {
      LOGGER.e("[MediaControl] Failed to load cover: $e");
    }
  }

  /// 从 ImageProvider 提取字节数据
  Future<Uint8List?> _extractBytesFromImageProvider(ImageProvider provider) async {
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

  // 更新播放状态
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

  /// 确保 AudioSession 处于激活状态
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

  // BaseAudioHandler 覆盖方法
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
      super.stop();
    }
  }
}
