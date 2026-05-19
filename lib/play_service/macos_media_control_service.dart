import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../library/audio_library.dart';
import 'playback_service.dart';
import '../platform_helper.dart';
import '../utils.dart';

class MacosMediaControlService extends BaseAudioHandler {
  static final MacosMediaControlService _instance =
      MacosMediaControlService._internal();
  final AudioPlayer _player = AudioPlayer();
  late PlaybackService _playbackService;
  Audio? _currentAudio;

  // 回调函数
  Function()? onPlay;
  Function()? onPause;
  Function()? onStop;
  Function()? onNext;
  Function()? onPrevious;
  Function(Duration)? onSeek;

  factory MacosMediaControlService() => _instance;
  MacosMediaControlService._internal() {
    // 只在macOS平台初始化监听
    if (PlatformHelper.isMacOS) {
      // 监听播放状态变化，更新AudioService状态
      _player.playbackEventStream.listen((event) {
        final playing = event.processingState != ProcessingState.idle &&
            event.processingState != ProcessingState.completed &&
            _player.playing;

        updatePlaybackState(
            playing: playing,
            position: event.updatePosition,
            processingState: _mapProcessingState(event.processingState));
      });
    }
  }

  // 初始化 AudioService
  static Future<MacosMediaControlService> init() async {
    // 只在macOS平台初始化
    if (PlatformHelper.isMacOS) {
      await AudioService.init(
        builder: () => MacosMediaControlService(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.coriander.player.channel.audio',
          androidNotificationChannelName: 'Audio Service',
          androidNotificationOngoing: true,
          androidNotificationClickStartsActivity: true,
          androidShowNotificationBadge: true,
        ),
      );
    }
    return _instance;
  }

  // 设置PlaybackService引用
  void setPlaybackService(PlaybackService playbackService) {
    _playbackService = playbackService;
  }

  // 将just_audio的ProcessingState映射到AudioService的AudioProcessingState
  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
      default:
        return AudioProcessingState.ready;
    }
  }

  // 设置回调函数
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
    if (!PlatformHelper.isMacOS) return;

    _currentAudio = audio;
    // 尝试获取专辑封面路径
    String? albumArtPath;
    try {
      // Audio类没有直接的albumArtPath属性，我们尝试通过cover属性获取
      final cover = audio.cover;
      // 由于cover是Future<ImageProvider?>，这里我们无法直接获取路径
      // 但我们可以设置专辑封面为null，让系统使用默认封面
    } catch (e) {
      LOGGER.e("Failed to get album art path: $e");
    }

    mediaItem.add(
      MediaItem(
        id: audio.path, // 使用文件路径作为唯一标识符
        album: audio.album, // Audio类的album属性不是可空的
        title: audio.title,
        artist: audio.artist, // Audio类的artist属性不是可空的
        duration: Duration(milliseconds: (audio.duration * 1000).toInt()),
        artUri: albumArtPath != null ? Uri.file(albumArtPath) : null,
      ),
    );
  }

  // 更新播放状态
  void updatePlaybackState({
    required bool playing,
    Duration? position,
    AudioProcessingState? processingState,
  }) {
    if (!PlatformHelper.isMacOS) return;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState ?? AudioProcessingState.ready,
        playing: playing,
        updatePosition: position ?? Duration.zero,
      ),
    );
  }

  // BaseAudioHandler 覆盖方法 - 这些会被系统通知栏调用
  @override
  Future<void> play() async {
    if (!PlatformHelper.isMacOS) return;
    onPlay?.call();
  }

  @override
  Future<void> pause() async {
    if (!PlatformHelper.isMacOS) return;
    onPause?.call();
  }

  @override
  Future<void> stop() async {
    if (!PlatformHelper.isMacOS) return;
    onStop?.call();
  }

  @override
  Future<void> skipToNext() async {
    if (!PlatformHelper.isMacOS) return;
    onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    if (!PlatformHelper.isMacOS) return;
    onPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!PlatformHelper.isMacOS) return;
    onSeek?.call(position);
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!PlatformHelper.isMacOS) return;
    await stop();
    await super.onTaskRemoved();
  }

  void dispose() {
    if (PlatformHelper.isMacOS) {
      _player.dispose();
      super.stop();
    }
  }
}
