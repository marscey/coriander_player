import 'dart:async';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/src/rust/api/smtc_flutter.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/play_service/macos_media_control_service.dart';
import 'package:coriander_player/play_service/engine/player_engine.dart';
import 'package:coriander_player/play_service/engine/player_engine_factory.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:coriander_player/play_service/engine/platform_specific_initialization.dart';
import 'package:coriander_player/play_service/engine/bass_player_engine.dart';
import 'package:flutter/foundation.dart';

enum PlayMode {
  /// 顺序播放到播放列表结尾
  forward,

  /// 循环整个播放列表
  loop,

  /// 循环播放单曲
  singleLoop;

  static PlayMode? fromString(String playMode) {
    for (var value in PlayMode.values) {
      if (value.name == playMode) return value;
    }
    return null;
  }
}

/// 只通知 now playing 变更
class PlaybackService extends ChangeNotifier {
  final PlayService playService;

  late StreamSubscription _playerStateStreamSub;
  late StreamSubscription _smtcEventStreamSub;

  late final MacosMediaControlService _macosMediaControlService;
  late StreamSubscription? _positionStreamForMacosMediaControl;

  late PlayerEngine _player;

  PlaybackService(this.playService) {
    // 立即初始化播放器引擎（同步）
    _player = PlayerEngineFactory.getDefaultEngine();
    _player.initialize();
    
    // 在构造函数完成后异步执行其他初始化
    _asyncInit();
    
    _playerStateStreamSub = playerStateStream.listen((event) {
      if (event == PlayerState.completed) {
        _autoNextAudio();
      }
    });

    _smtcEventStreamSub = _smtc.subscribeToControlEvents().listen((event) {
      switch (event) {
        case SMTCControlEvent.play:
          start();
          break;
        case SMTCControlEvent.pause:
          pause();
          break;
        case SMTCControlEvent.previous:
          lastAudio();
          break;
        case SMTCControlEvent.next:
          nextAudio();
          break;
        case SMTCControlEvent.unknown:
      }
    });

    positionStream.listen((progress) {
      _smtc.updateTimeProperties(progress: (progress * 1000).floor());
    });

    // 初始化macOS平台特定的媒体控制服务
    if (PlatformHelper.isMacOS) {
      _initMacosMediaControlService();
    }
  }

  void _asyncInit() async {
    // 执行平台特定初始化
    await PlatformSpecificInitialization.initializeForPlatform();
  }

  Future<void> _initMacosMediaControlService() async {
    try {
      _macosMediaControlService = await MacosMediaControlService.init();
      _macosMediaControlService.setPlaybackService(this);
      
      // 设置回调函数
      _macosMediaControlService.setCallbacks(
        onPlay: start,
        onPause: pause,
        onStop: () {
          pause();
        },
        onNext: nextAudio,
        onPrevious: lastAudio,
        onSeek: (duration) {
          seek(duration.inMilliseconds / 1000);
        },
      );
      
      // 监听播放位置变化，更新系统通知栏
      _positionStreamForMacosMediaControl = positionStream.listen((progress) {
        if (nowPlaying != null) {
          _macosMediaControlService.updatePlaybackState(
            playing: playerState == PlayerState.playing,
            position: Duration(milliseconds: (progress * 1000).toInt()),
          );
        }
      });
    } catch (e) {
      LOGGER.e("Failed to initialize macOS media control service: $e");
    }
  }

  final _smtc = SmtcFlutter();
  final _pref = AppPreference.instance.playbackPref;

  // 独占模式，仅对BASS引擎有效
  late final _wasapiExclusive = ValueNotifier(false);
  ValueNotifier<bool> get wasapiExclusive => _wasapiExclusive;

  /// 独占模式
  void useExclusiveMode(bool exclusive) {
    _wasapiExclusive.value = exclusive;
  }

  Audio? nowPlaying;

  int? _playlistIndex;
  int get playlistIndex => _playlistIndex ?? 0;

  final ValueNotifier<List<Audio>> playlist = ValueNotifier([]);
  List<Audio> _playlistBackup = [];

  late final _playMode = ValueNotifier(_pref.playMode);
  ValueNotifier<PlayMode> get playMode => _playMode;

  void setPlayMode(PlayMode playMode) {
    this.playMode.value = playMode;
    _pref.playMode = playMode;
  }

  late final _shuffle = ValueNotifier(false);
  ValueNotifier<bool> get shuffle => _shuffle;

  double get length => _player.duration.inSeconds.toDouble();

  double get position => _player.position.inSeconds.toDouble();

  PlayerState get playerState => _player.state;

  // 兼容旧代码的volumeDsp属性
  double get volumeDsp => AppPreference.instance.playbackPref.volumeDsp;

  /// 修改解码时的音量（不影响 Windows 系统音量）
  void setVolumeDsp(double volume) {
    try {
      _player.setVolume(volume);
      _pref.volumeDsp = volume;
    } catch (e) {
      LOGGER.e("Failed to set volume DSP: $e");
    }
  }

  // 适配Stream<Duration>到Stream<double>
  Stream<double> get positionStream => 
      _player.positionStream.map((duration) => duration.inSeconds.toDouble());

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 1. 更新 [_playlistIndex] 为 [audioIndex]
  /// 2. 更新 [nowPlaying] 为 playlist[_nowPlayingIndex]
  /// 3. _bassPlayer.setSource
  /// 4. 设置解码音量
  /// 4. 获取歌词 **将 [_nextLyricLine] 置为0**
  /// 5. 播放
  /// 6. 通知并更新主题色
  void _loadAndPlay(int audioIndex, List<Audio> playlist) {
    try {
      _playlistIndex = audioIndex;
      nowPlaying = playlist[audioIndex];
      
      // 根据当前配置的播放器引擎类型，确保使用正确的引擎
      final engineType = AppSettings.instance.playerEngineType;
      if (engineType != null &&
          !(_player is BassPlayerEngine && engineType == PlayerEngineType.bass)) {
        // 如果当前引擎与配置的引擎不同，释放当前引擎并创建新引擎
        _player.dispose();
        _player = PlayerEngineFactory.createEngine(engineType);
        _player.initialize();
        
        // 重新设置播放状态监听
        _playerStateStreamSub.cancel();
        _playerStateStreamSub = playerStateStream.listen((event) {
          if (event == PlayerState.completed) {
            _autoNextAudio();
          }
        });
        
        // 重新设置播放位置监听
        positionStream.listen((progress) {
          _smtc.updateTimeProperties(progress: (progress * 1000).floor());
        });
      }
      
      _player.setSource(nowPlaying!.path);
      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);

      playService.lyricService.updateLyric();

      _player.play();
      notifyListeners();
      ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);

      _smtc.updateState(state: SMTCState.playing);
      _smtc.updateDisplay(
        title: nowPlaying!.title,
        artist: nowPlaying!.artist,
        album: nowPlaying!.album,
        duration: (length * 1000).floor(),
        path: nowPlaying!.path,
      );

      // 在macOS平台上更新系统通知栏媒体控件
      if (PlatformHelper.isMacOS && nowPlaying != null) {
        _macosMediaControlService.updateCurrentMediaItem(nowPlaying!);
        _macosMediaControlService.updatePlaybackState(
          playing: true,
          position: Duration.zero,
        );
      }

      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService
            .sendPlayerStateMessage(playerState == PlayerState.playing);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });
    } catch (err) {
      LOGGER.e("[load and play] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 播放当前播放列表的第几项，只能用在播放列表界面
  void playIndexOfPlaylist(int audioIndex) {
    _loadAndPlay(audioIndex, playlist.value);
  }

  /// 播放playlist[audioIndex]并设置播放列表为playlist
  void play(int audioIndex, List<Audio> playlist) {
    if (shuffle.value) {
      this.playlist.value = List.from(playlist);
      final willPlay = this.playlist.value.removeAt(audioIndex);
      this.playlist.value.shuffle();
      this.playlist.value.insert(0, willPlay);
      _playlistBackup = List.from(playlist);
      _loadAndPlay(0, this.playlist.value);
    } else {
      _loadAndPlay(audioIndex, playlist);
      this.playlist.value = List.from(playlist);
      _playlistBackup = List.from(playlist);
    }
  }

  void shuffleAndPlay(List<Audio> audios) {
    playlist.value = List.from(audios);
    playlist.value.shuffle();
    _playlistBackup = List.from(audios);

    shuffle.value = true;

    _loadAndPlay(0, playlist.value);
  }

  /// 下一首播放
  void addToNext(Audio audio) {
    if (_playlistIndex != null) {
      playlist.value.insert(_playlistIndex! + 1, audio);
      _playlistBackup = List.from(playlist.value);
    }
  }

  void useShuffle(bool flag) {
    if (nowPlaying == null) return;
    if (flag == shuffle.value) return;

    if (flag) {
      playlist.value.shuffle();
      playlist.value.remove(nowPlaying!);
      playlist.value.insert(0, nowPlaying!);
      _playlistIndex = 0;
      shuffle.value = true;
    } else {
      playlist.value = List.from(_playlistBackup);
      _playlistIndex = playlist.value.indexOf(nowPlaying!);
      shuffle.value = false;
    }
  }

  void _nextAudio_forward() {
    if (_playlistIndex == null) return;

    if (_playlistIndex! < playlist.value.length - 1) {
      _loadAndPlay(_playlistIndex! + 1, playlist.value);
    }
  }

  void _nextAudio_loop() {
    if (_playlistIndex == null) return;

    int newIndex = _playlistIndex! + 1;
    if (newIndex >= playlist.value.length) {
      newIndex = 0;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  void _nextAudio_singleLoop() {
    if (_playlistIndex == null) return;

    _loadAndPlay(_playlistIndex!, playlist.value);
  }

  void _autoNextAudio() {
    switch (playMode.value) {
      case PlayMode.forward:
        _nextAudio_forward();
        break;
      case PlayMode.loop:
        _nextAudio_loop();
        break;
      case PlayMode.singleLoop:
        _nextAudio_singleLoop();
        break;
    }
  }

  /// 手动下一曲时默认循环播放列表
  void nextAudio() => _nextAudio_loop();

  /// 手动上一曲时默认循环播放列表
  void lastAudio() {
    if (_playlistIndex == null) return;

    int newIndex = _playlistIndex! - 1;
    if (newIndex < 0) {
      newIndex = playlist.value.length - 1;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  /// 暂停
  void pause() {
    try {
      _player.pause();
      _smtc.updateState(state: SMTCState.paused);
      
      // 在macOS平台上更新系统通知栏媒体控件
      if (PlatformHelper.isMacOS && nowPlaying != null) {
        _macosMediaControlService.updatePlaybackState(
          playing: false,
          position: _player.position,
        );
      }
      
      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService.sendPlayerStateMessage(false);
      });
    } catch (err) {
      LOGGER.e("[pause] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 恢复播放
  void start() {
    try {
      _player.play();
      _smtc.updateState(state: SMTCState.playing);
      
      // 在macOS平台上更新系统通知栏媒体控件
      if (PlatformHelper.isMacOS && nowPlaying != null) {
        _macosMediaControlService.updatePlaybackState(
          playing: true,
          position: _player.position,
        );
      }
      
      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService.sendPlayerStateMessage(true);
      });
    } catch (err) {
      LOGGER.e("[start]: $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 再次播放。在顺序播放完最后一曲时再次按播放时使用。
  /// 与 [start] 的差别在于它会通知重绘组件
  void playAgain() => _nextAudio_singleLoop();

  void seek(double position) {
    _player.seek(Duration(seconds: position.floor()));
    playService.lyricService.findCurrLyricLine();
    
    // 在macOS平台上更新系统通知栏媒体控件的播放进度
    if (PlatformHelper.isMacOS && nowPlaying != null) {
      _macosMediaControlService.updatePlaybackState(
        playing: playerState == PlayerState.playing,
        position: _player.position,
      );
    }
  }

  void close() {
    _playerStateStreamSub.cancel();
    _smtcEventStreamSub.cancel();
    
    // 释放macOS平台特定的媒体控制服务资源
    if (PlatformHelper.isMacOS) {
      _positionStreamForMacosMediaControl?.cancel();
      _macosMediaControlService.dispose();
    }
    
    // 释放播放器引擎资源
    try {
      _player.dispose();
    } catch (e) {
      LOGGER.e("Failed to free player engine: $e");
    }
    
    _smtc.close();
  }
  
  /// 切换播放器引擎
  Future<void> switchEngine(PlayerEngineType type) async {
    try {
      // 保存当前播放状态
      final currentPosition = _player.position;
      final currentAudio = nowPlaying;
      final isPlaying = playerState == PlayerState.playing;
      
      // 释放旧引擎资源
      try {
        await _player.dispose();
        _playerStateStreamSub.cancel();
      } catch (e) {
        LOGGER.e("Failed to dispose old player engine: $e");
      }
      
      // 创建新引擎
      _player = PlayerEngineFactory.createEngine(type);
      await _player.initialize();
      
      // 重新设置播放状态监听
      _playerStateStreamSub = playerStateStream.listen((event) {
        if (event == PlayerState.completed) {
          _autoNextAudio();
        }
      });
      
      // 重新设置播放位置监听
      positionStream.listen((progress) {
        _smtc.updateTimeProperties(progress: (progress * 1000).floor());
      });
      
      // 恢复播放状态
      if (currentAudio != null) {
        await _player.setSource(currentAudio.path);
        await _player.seek(currentPosition);
        if (isPlaying) {
          await _player.play();
        }
      }
      
      // 更新配置
      AppSettings.instance.playerEngineType = type;
      await AppSettings.instance.saveSettings();
      
    } catch (e) {
      LOGGER.e("Failed to switch player engine: $e");
      rethrow;
    }
  }
}
