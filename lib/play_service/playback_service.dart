import 'dart:async';
import 'dart:io';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
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
import 'package:coriander_player/play_service/now_playing_widget.dart';
import 'package:flutter/foundation.dart';

import 'package:coriander_player/cloud_service/cloud_audio_player.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/play_service/recent_play_service.dart';

enum PlayMode {
  forward,
  loop,
  singleLoop;

  static PlayMode? fromString(String playMode) {
    for (var value in PlayMode.values) {
      if (value.name == playMode) return value;
    }
    return null;
  }
}

class PlaybackService extends ChangeNotifier {
  final PlayService playService;

  late StreamSubscription _playerStateStreamSub;
  StreamSubscription? _smtcEventStreamSub;
  StreamSubscription? _positionStreamSub;

  MacosMediaControlService? _macosMediaControlService;
  StreamSubscription? _positionStreamForMacosMediaControl;

  late PlayerEngine _player;

  PlaybackService(this.playService) {
    _player = PlayerEngineFactory.getDefaultEngine();
    _player.initialize();

    _playerStateStreamSub = playerStateStream.listen((event) {
      if (event == PlayerState.completed) {
        _autoNextAudio();
      }
    });

    if (PlatformHelper.isDesktop) {
      _smtc = SMTCFlutter();
      _smtcEventStreamSub = _smtc!.subscribeToControlEvents().listen((event) {
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

      _positionStreamSub = positionStream.listen((progress) {
        _smtc!.updateTimeProperties(progress: (progress * 1000).floor());
      });
    }
  }

  /// 异步初始化（必须在 main() 中显式 await）
  /// iOS/macOS 上需要等待 AudioService.init() 完成
  Future<void> initialize() async {
    LOGGER.i("[DEBUG] PlaybackService-initialize: START");

    // 先配置平台特定初始化（AudioSession 等）
    await PlatformSpecificInitialization.initializeForPlatform();
    LOGGER.i(
        "[DEBUG] PlaybackService-initialize: PlatformSpecificInitialization done");

    // macOS 和 iOS 初始化系统媒体控制
    if (PlatformHelper.isMacOS || PlatformHelper.isIOS) {
      await _initMediaControlService();
    }

    LOGGER.i("[DEBUG] PlaybackService-initialize: DONE");
  }

  Future<void> _initMediaControlService() async {
    try {
      LOGGER.i("[DEBUG] PlaybackService-_initMediaControlService: START");
      _macosMediaControlService = await MacosMediaControlService.init();
      _macosMediaControlService!.setPlaybackService(this);

      // 同步蓝牙歌词设置
      if (PlatformHelper.isIOS) {
        _macosMediaControlService!.bluetoothLyricEnabled =
            AppSettings.instance.bluetoothLyric;
      }

      LOGGER.i(
          "[DEBUG] PlaybackService-_initMediaControlService: setting callbacks...");
      _macosMediaControlService!.setCallbacks(
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

      LOGGER.i(
          "[DEBUG] PlaybackService-_initMediaControlService: listening position stream...");
      // 降低位置更新频率：只在位置变化超过1秒时才更新
      // 避免每100ms触发一次原生调用导致性能问题
      _positionStreamForMacosMediaControl = positionStream
          .distinct((a, b) => (a - b).abs() < 1.0)
          .listen((progress) {
        if (nowPlaying != null) {
          _macosMediaControlService?.updatePlaybackState(
            playing: playerState == PlayerState.playing,
            position: Duration(milliseconds: (progress * 1000).toInt()),
          );
        }
      });
      LOGGER.i("[DEBUG] PlaybackService-_initMediaControlService: DONE");
    } catch (e) {
      LOGGER.e("[DEBUG] PlaybackService-_initMediaControlService: FAILED: $e");
    }
  }

  SMTCFlutter? _smtc;
  final _pref = AppPreference.instance.playbackPref;

  late final _wasapiExclusive = ValueNotifier(false);
  ValueNotifier<bool> get wasapiExclusive => _wasapiExclusive;

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

  double get buffer => _player.buffer.inSeconds.toDouble();

  PlayerState get playerState => _player.state;

  double get volumeDsp => AppPreference.instance.playbackPref.volumeDsp;

  void setVolumeDsp(double volume) {
    try {
      _player.setVolume(volume);
      _pref.volumeDsp = volume;
    } catch (e) {
      LOGGER.e("Failed to set volume DSP: $e");
    }
  }

  Stream<double> get positionStream =>
      _player.positionStream.map((duration) => duration.inSeconds.toDouble());

  Stream<double> get bufferStream =>
      _player.bufferStream.map((duration) => duration.inSeconds.toDouble());

  Stream<double> get durationStream =>
      _player.durationStream.map((duration) => duration.inSeconds.toDouble());

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> _loadAndPlay(int audioIndex, List<Audio> playlist,
      {Map<String, String>? httpHeaders}) async {
    try {
      _playlistIndex = audioIndex;
      nowPlaying = playlist[audioIndex];

      final isCloud = nowPlaying!.isCloudAudio;

      LOGGER.i(
          "[_loadAndPlay] title=${nowPlaying!.title}, path=${nowPlaying!.path}, isCloud=$isCloud");

      if (isCloud && _supportsStreamingForCloud()) {
        final cachedPath =
            CloudCacheManager.instance.getCachedFilePath(nowPlaying!.path);
        if (cachedPath != null) {
          LOGGER.i("[_loadAndPlay] using cached file: $cachedPath");
          await _player.setSource(cachedPath, isNetwork: false);
        } else {
          try {
            final resolved =
                await CloudAudioPlayer.resolveStreamingUrl(nowPlaying!.path);
            await _player.setSource(
              resolved.url,
              isNetwork: true,
              httpHeaders: resolved.headers,
            );
            _cacheStreamInBackground(
                nowPlaying!.path, resolved.url, resolved.headers);
          } catch (e) {
            LOGGER.e("[_loadAndPlay] resolve streaming URL failed: $e");
            showTextOnSnackBar('云音频播放失败: $e');
            return;
          }
        }
      } else if (isCloud) {
        showTextOnSnackBar('当前引擎不支持云音频流式播放，请切换到 MediaKit 引擎');
        return;
      } else {
        await _player.setSource(
          nowPlaying!.path,
          isNetwork: false,
          httpHeaders: httpHeaders,
        );
      }

      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);

      playService.lyricService.updateLyric();

      await _player.play();
      LOGGER.i("[_loadAndPlay] play() completed, playerState=$playerState");
      notifyListeners();
      ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);

      // 记录到最近播放
      RecentPlayService.instance.recordPlay(nowPlaying!);

      if (isCloud && nowPlaying!.artist.isEmpty) {
        CloudAudioPlayer.updateMetadataFromCache(nowPlaying!);
      }

      if (PlatformHelper.isDesktop) {
        _smtc?.updateState(state: SMTCState.playing);

        if (!isCloud) {
          _smtc?.updateDisplay(
            title: nowPlaying!.title,
            artist: nowPlaying!.artist,
            album: nowPlaying!.album,
            duration: (length * 1000).floor(),
            path: nowPlaying!.path,
          );
        }
      }

      if ((PlatformHelper.isMacOS || PlatformHelper.isIOS) &&
          nowPlaying != null) {
        // 确保 AudioSession 处于激活状态
        // media_kit 可能在初始化时覆盖了 AVAudioSession 配置
        await MacosMediaControlService.ensureAudioSessionActive();

        _macosMediaControlService?.updateCurrentMediaItem(nowPlaying!);
        _macosMediaControlService?.updatePlaybackState(
          playing: true,
          position: Duration.zero,
        );
        if (PlatformHelper.isIOS) {
          NowPlayingWidget.update();
        }
        LOGGER.i("[_loadAndPlay] MediaControl updated for iOS/macOS");
      }

      if (PlatformHelper.isDesktop) {
        playService.desktopLyricService.canSendMessage.then((canSend) {
          if (!canSend) return;

          playService.desktopLyricService
              .sendPlayerStateMessage(playerState == PlayerState.playing);
          playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
        });
      }

      // 后台自动刮削元数据（不阻塞播放流程）
      _autoScrapeMetadata(nowPlaying!);
    } catch (err) {
      LOGGER.e("[_loadAndPlay] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 后台自动刮削元数据
  /// 只有当刮削结果与音频元数据完全匹配时，才会自动保存
  void _autoScrapeMetadata(Audio audio) {
    // 在后台执行，不阻塞播放流程
    MetadataService.instance.autoScrape(audio, onScraped: (isExactMatch, output) {
      if (isExactMatch && output != null) {
        // 完全匹配，刷新歌词和封面
        LOGGER.i("[_loadAndPlay] Auto-scrape exact match, refreshing lyric and cover");
        playService.lyricService.updateLyric();
        audio.clearCoverCache();
        notifyListeners();
      }
    });
  }

  bool _supportsStreamingForCloud() {
    final engineType = AppSettings.instance.playerEngineType ??
        PlayerEngineType.defaultForPlatform;
    return engineType == PlayerEngineType.mediaKit;
  }

  void _cacheStreamInBackground(
      String webdavPath, String streamingUrl, Map<String, String>? headers) {
    () async {
      final client = HttpClient();
      client.autoUncompress = false;
      try {
        LOGGER.i('[CloudCache] background caching: $webdavPath');
        final request = await client.getUrl(Uri.parse(streamingUrl));
        if (headers != null) {
          headers.forEach((key, value) {
            request.headers.set(key, value);
          });
        }
        final response = await request.close();
        if (response.statusCode == 200) {
          final originalName = webdavPath.split('/').last;
          await CloudCacheManager.instance.saveStreamToCache(
            webdavPath,
            response,
            originalName: originalName,
          );
        } else {
          LOGGER.w(
              '[CloudCache] background cache failed: HTTP ${response.statusCode}');
          await response.drain<void>();
        }
      } catch (e) {
        LOGGER.e('[CloudCache] background cache error: $e');
      } finally {
        client.close();
      }
    }();
  }

  void playIndexOfPlaylist(int audioIndex) {
    _loadAndPlay(audioIndex, playlist.value);
  }

  void play(int audioIndex, List<Audio> playlist,
      {Map<String, String>? httpHeaders}) {
    if (shuffle.value) {
      this.playlist.value = List.from(playlist);
      final willPlay = this.playlist.value.removeAt(audioIndex);
      this.playlist.value.shuffle();
      this.playlist.value.insert(0, willPlay);
      _playlistBackup = List.from(playlist);
      _loadAndPlay(0, this.playlist.value, httpHeaders: httpHeaders);
    } else {
      _loadAndPlay(audioIndex, playlist, httpHeaders: httpHeaders);
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

  void addToNext(Audio audio) {
    if (_playlistIndex != null) {
      final exists = playlist.value.any((a) => a.path == audio.path);
      if (exists) return;
      playlist.value.insert(_playlistIndex! + 1, audio);
      _playlistBackup = List.from(playlist.value);
    }
  }

  bool isInPlaylist(String audioPath) {
    return playlist.value.any((a) => a.path == audioPath);
  }

  void refreshNowPlaying() {
    notifyListeners();
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

  void nextAudio() => _nextAudio_loop();

  void lastAudio() {
    if (_playlistIndex == null) return;

    int newIndex = _playlistIndex! - 1;
    if (newIndex < 0) {
      newIndex = playlist.value.length - 1;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  void pause() {
    try {
      _player.pause();

      if (PlatformHelper.isDesktop) {
        _smtc?.updateState(state: SMTCState.paused);
      }

      if ((PlatformHelper.isMacOS || PlatformHelper.isIOS) &&
          nowPlaying != null) {
        _macosMediaControlService?.updatePlaybackState(
          playing: false,
          position: _player.position,
        );
        // 暂停时清除封面歌词
        if (PlatformHelper.isIOS) {
          _macosMediaControlService?.clearLyricFromCover();
          NowPlayingWidget.update();
        }
      }

      if (PlatformHelper.isDesktop) {
        playService.desktopLyricService.canSendMessage.then((canSend) {
          if (!canSend) return;

          playService.desktopLyricService.sendPlayerStateMessage(false);
        });
      }

      notifyListeners();
    } catch (err) {
      LOGGER.e("[pause] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  void start() {
    try {
      _player.play();

      if (PlatformHelper.isDesktop) {
        _smtc?.updateState(state: SMTCState.playing);
      }

      if ((PlatformHelper.isMacOS || PlatformHelper.isIOS) &&
          nowPlaying != null) {
        // 确保 AudioSession 激活（防止被 media_kit 覆盖）
        MacosMediaControlService.ensureAudioSessionActive();
        _macosMediaControlService?.updatePlaybackState(
          playing: true,
          position: _player.position,
        );
        if (PlatformHelper.isIOS) {
          NowPlayingWidget.update();
        }
      }

      if (PlatformHelper.isDesktop) {
        playService.desktopLyricService.canSendMessage.then((canSend) {
          if (!canSend) return;

          playService.desktopLyricService.sendPlayerStateMessage(true);
        });
      }

      notifyListeners();
    } catch (err) {
      LOGGER.e("[start]: $err");
      showTextOnSnackBar(err.toString());
    }
  }

  void playAgain() => _nextAudio_singleLoop();

  /// 更新蓝牙歌词（iOS 封面图+歌词合成）
  /// 由 LyricService 在歌词行变化时调用
  void updateBluetoothLyric(String lyricText, {String? translation}) {
    if (!PlatformHelper.isIOS) return;
    _macosMediaControlService?.updateLyricOnCover(lyricText,
        translation: translation);
  }

  /// 设置蓝牙歌词开关
  void setBluetoothLyricEnabled(bool enabled) {
    if (!PlatformHelper.isIOS) return;
    _macosMediaControlService?.bluetoothLyricEnabled = enabled;
  }

  void seek(double position) {
    _player.seek(Duration(seconds: position.floor()));
    playService.lyricService.findCurrLyricLine();

    if ((PlatformHelper.isMacOS || PlatformHelper.isIOS) &&
        nowPlaying != null) {
      _macosMediaControlService?.updatePlaybackState(
        playing: playerState == PlayerState.playing,
        position: _player.position,
      );
    }
  }

  void close() {
    _playerStateStreamSub.cancel();
    _positionStreamSub?.cancel();
    _smtcEventStreamSub?.cancel();

    if (PlatformHelper.isMacOS || PlatformHelper.isIOS) {
      _positionStreamForMacosMediaControl?.cancel();
      _macosMediaControlService?.dispose();
    }

    try {
      _player.dispose();
    } catch (e) {
      LOGGER.e("Failed to free player engine: $e");
    }

    if (PlatformHelper.isDesktop) {
      _smtc?.close();
    }
  }

  Future<void> switchEngine(PlayerEngineType type) async {
    LOGGER.i("[switchEngine] START: switching to $type");
    try {
      final currentPosition = _player.position;
      final currentAudio = nowPlaying;
      final isPlaying = playerState == PlayerState.playing;
      LOGGER.i(
          "[switchEngine] Saved state: position=${currentPosition.inSeconds}s, audio=${currentAudio?.title}, isPlaying=$isPlaying");

      LOGGER.i("[switchEngine] Canceling stream subscriptions...");
      _playerStateStreamSub.cancel();
      _positionStreamSub?.cancel();

      LOGGER.i("[switchEngine] Disposing old engine...");
      try {
        await _player.dispose().timeout(const Duration(seconds: 5));
        LOGGER.i("[switchEngine] Old engine disposed successfully");
      } catch (e) {
        LOGGER.e("[switchEngine] Failed to dispose old player engine: $e");
      }

      LOGGER.i("[switchEngine] Creating new engine: $type");
      _player = PlayerEngineFactory.createEngine(type);
      LOGGER.i("[switchEngine] Initializing new engine...");
      await _player.initialize().timeout(const Duration(seconds: 10));
      LOGGER.i("[switchEngine] New engine initialized successfully");

      LOGGER.i("[switchEngine] Re-subscribing to streams...");
      _playerStateStreamSub = playerStateStream.listen((event) {
        if (event == PlayerState.completed) {
          _autoNextAudio();
        }
      });

      _positionStreamSub = positionStream.listen((progress) {
        _smtc?.updateTimeProperties(progress: (progress * 1000).floor());
      });

      if (currentAudio != null) {
        final isCloud = currentAudio.isCloudAudio;
        LOGGER.i(
            "[switchEngine] Restoring playback: path=${currentAudio.path}, isCloud=$isCloud");
        if (isCloud && type != PlayerEngineType.mediaKit) {
          LOGGER.i(
              "[switchEngine] Cloud audio not supported by BASS engine, skipping restore");
        } else {
          try {
            LOGGER.i("[switchEngine] Calling setSource...");
            if (isCloud) {
              final cachedPath = CloudCacheManager.instance
                  .getCachedFilePath(currentAudio.path);
              if (cachedPath != null) {
                await _player
                    .setSource(cachedPath, isNetwork: false)
                    .timeout(const Duration(seconds: 10));
              } else {
                final resolved = await CloudAudioPlayer.resolveStreamingUrl(
                    currentAudio.path);
                await _player
                    .setSource(resolved.url,
                        isNetwork: true, httpHeaders: resolved.headers)
                    .timeout(const Duration(seconds: 10));
              }
            } else {
              await _player
                  .setSource(currentAudio.path, isNetwork: false)
                  .timeout(const Duration(seconds: 10));
            }
            LOGGER.i(
                "[switchEngine] setSource done, seeking to ${currentPosition.inSeconds}s...");
            await _player
                .seek(currentPosition)
                .timeout(const Duration(seconds: 5));
            LOGGER.i("[switchEngine] seek done, isPlaying=$isPlaying");
            if (isPlaying) {
              LOGGER.i("[switchEngine] Calling play...");
              await _player.play().timeout(const Duration(seconds: 5));
              LOGGER.i("[switchEngine] play done");
            }
          } catch (e) {
            LOGGER.e(
                "[switchEngine] Failed to restore playback after engine switch: $e");
          }
        }
      }

      LOGGER.i("[switchEngine] Saving settings...");
      AppSettings.instance.playerEngineType = type;
      await AppSettings.instance.saveSettings();
      LOGGER.i("[switchEngine] DONE: successfully switched to $type");
    } catch (e) {
      LOGGER.e("[switchEngine] FAILED: $e");
      rethrow;
    }
  }
}
