import 'dart:async';
import 'dart:io';

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

import 'package:coriander_player/cloud_service/cloud_audio_player.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';

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
  late StreamSubscription _smtcEventStreamSub;
  late StreamSubscription _positionStreamSub;

  late final MacosMediaControlService _macosMediaControlService;
  late StreamSubscription? _positionStreamForMacosMediaControl;

  late PlayerEngine _player;

  PlaybackService(this.playService) {
    _player = PlayerEngineFactory.getDefaultEngine();
    _player.initialize();

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

    _positionStreamSub = positionStream.listen((progress) {
      _smtc.updateTimeProperties(progress: (progress * 1000).floor());
    });

    if (PlatformHelper.isMacOS) {
      _initMacosMediaControlService();
    }
  }

  void _asyncInit() async {
    await PlatformSpecificInitialization.initializeForPlatform();
  }

  Future<void> _initMacosMediaControlService() async {
    try {
      _macosMediaControlService = await MacosMediaControlService.init();
      _macosMediaControlService.setPlaybackService(this);

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

      LOGGER.i("[_loadAndPlay] title=${nowPlaying!.title}, path=${nowPlaying!.path}, isCloud=$isCloud");

      if (isCloud && _supportsStreamingForCloud()) {
        final cachedPath = CloudCacheManager.instance.getCachedFilePath(nowPlaying!.path);
        if (cachedPath != null) {
          LOGGER.i("[_loadAndPlay] using cached file: $cachedPath");
          await _player.setSource(cachedPath, isNetwork: false);
        } else {
          try {
            final resolved = await CloudAudioPlayer.resolveStreamingUrl(nowPlaying!.path);
            await _player.setSource(
              resolved.url,
              isNetwork: true,
              httpHeaders: resolved.headers,
            );
            _cacheStreamInBackground(nowPlaying!.path, resolved.url, resolved.headers);
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

      _smtc.updateState(state: SMTCState.playing);

      if (!isCloud) {
        _smtc.updateDisplay(
          title: nowPlaying!.title,
          artist: nowPlaying!.artist,
          album: nowPlaying!.album,
          duration: (length * 1000).floor(),
          path: nowPlaying!.path,
        );
      }

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
      LOGGER.e("[_loadAndPlay] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  bool _supportsStreamingForCloud() {
    final engineType = AppSettings.instance.playerEngineType;
    return engineType == PlayerEngineType.mediaKit;
  }

  void _cacheStreamInBackground(String webdavPath, String streamingUrl, Map<String, String>? headers) {
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
          LOGGER.w('[CloudCache] background cache failed: HTTP ${response.statusCode}');
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
      _smtc.updateState(state: SMTCState.paused);

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

  void start() {
    try {
      _player.play();
      _smtc.updateState(state: SMTCState.playing);

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

  void playAgain() => _nextAudio_singleLoop();

  void seek(double position) {
    _player.seek(Duration(seconds: position.floor()));
    playService.lyricService.findCurrLyricLine();

    if (PlatformHelper.isMacOS && nowPlaying != null) {
      _macosMediaControlService.updatePlaybackState(
        playing: playerState == PlayerState.playing,
        position: _player.position,
      );
    }
  }

  void close() {
    _playerStateStreamSub.cancel();
    _positionStreamSub.cancel();
    _smtcEventStreamSub.cancel();

    if (PlatformHelper.isMacOS) {
      _positionStreamForMacosMediaControl?.cancel();
      _macosMediaControlService.dispose();
    }

    try {
      _player.dispose();
    } catch (e) {
      LOGGER.e("Failed to free player engine: $e");
    }

    _smtc.close();
  }

  Future<void> switchEngine(PlayerEngineType type) async {
    LOGGER.i("[switchEngine] START: switching to $type");
    try {
      final currentPosition = _player.position;
      final currentAudio = nowPlaying;
      final isPlaying = playerState == PlayerState.playing;
      LOGGER.i("[switchEngine] Saved state: position=${currentPosition.inSeconds}s, audio=${currentAudio?.title}, isPlaying=$isPlaying");

      LOGGER.i("[switchEngine] Canceling stream subscriptions...");
      _playerStateStreamSub.cancel();
      _positionStreamSub.cancel();

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
        _smtc.updateTimeProperties(progress: (progress * 1000).floor());
      });

      if (currentAudio != null) {
        final isCloud = currentAudio.isCloudAudio;
        LOGGER.i("[switchEngine] Restoring playback: path=${currentAudio.path}, isCloud=$isCloud");
        if (isCloud && type != PlayerEngineType.mediaKit) {
          LOGGER.i("[switchEngine] Cloud audio not supported by BASS engine, skipping restore");
        } else {
          try {
            LOGGER.i("[switchEngine] Calling setSource...");
            if (isCloud) {
              final cachedPath = CloudCacheManager.instance.getCachedFilePath(currentAudio.path);
              if (cachedPath != null) {
                await _player
                    .setSource(cachedPath, isNetwork: false)
                    .timeout(const Duration(seconds: 10));
              } else {
                final resolved = await CloudAudioPlayer.resolveStreamingUrl(currentAudio.path);
                await _player
                    .setSource(resolved.url, isNetwork: true, httpHeaders: resolved.headers)
                    .timeout(const Duration(seconds: 10));
              }
            } else {
              await _player
                  .setSource(currentAudio.path, isNetwork: false)
                  .timeout(const Duration(seconds: 10));
            }
            LOGGER.i("[switchEngine] setSource done, seeking to ${currentPosition.inSeconds}s...");
            await _player.seek(currentPosition).timeout(const Duration(seconds: 5));
            LOGGER.i("[switchEngine] seek done, isPlaying=$isPlaying");
            if (isPlaying) {
              LOGGER.i("[switchEngine] Calling play...");
              await _player.play().timeout(const Duration(seconds: 5));
              LOGGER.i("[switchEngine] play done");
            }
          } catch (e) {
            LOGGER.e("[switchEngine] Failed to restore playback after engine switch: $e");
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
