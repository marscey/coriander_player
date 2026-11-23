import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_audio_player.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/cloud_service/cloud_cover_prefetcher.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_scraper.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/play_service/macos_media_control_service.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_state_service.dart';
import 'package:coriander_player/play_service/recent_play_service.dart';
import 'package:coriander_player/play_service/engine/bass_player_engine.dart';
import 'package:coriander_player/play_service/engine/player_engine.dart';
import 'package:coriander_player/play_service/engine/player_engine_factory.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:coriander_player/play_service/engine/platform_specific_initialization.dart';
import 'package:coriander_player/play_service/now_playing_widget.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/src/rust/api/smtc_flutter.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  StreamSubscription? _interruptionSub;
  StreamSubscription? _becomingNoisySub;
  bool _interrupted = false;

  late PlayerEngine _player;

  /// 加载代际标记，用于取消过期的 _loadAndPlay 调用。
  /// 每次调用 _loadAndPlay 时递增，旧的调用在检查点发现代龄不匹配时提前退出。
  int _loadPlayGeneration = 0;

  PlaybackService(this.playService) {
    _player = PlayerEngineFactory.getDefaultEngine();
    _player.initialize();

    // 启动30秒定时自动保存
    _startAutoSaveTimer();

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

    _listenAudioInterruption();

    LOGGER.i("[DEBUG] PlaybackService-initialize: DONE");
  }

  Future<void> _initMediaControlService() async {
    try {
      LOGGER.i("[DEBUG] PlaybackService-_initMediaControlService: START");
      _macosMediaControlService = await MacosMediaControlService.init();
      _macosMediaControlService!.setPlaybackService(this);

      // 同步蓝牙歌词设置
      if (PlatformHelper.isIOS || PlatformHelper.isMacOS) {
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

  void _listenAudioInterruption() {
    try {
      AudioSession.instance.then((session) {
        _interruptionSub = session.interruptionEventStream.listen((event) {
          if (event.begin) {
            if (playerState == PlayerState.playing) {
              _interrupted = true;
              pause();
            }
          } else {
            if (_interrupted) {
              _interrupted = false;
              start();
            }
          }
        });

        _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
          if (playerState == PlayerState.playing) {
            pause();
          }
        });
      });
    } catch (e) {
      LOGGER.e("[PlaybackService] Failed to listen audio interruption: $e");
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

  /// 是否正在缓冲加载（从 setSource 到 play 完成之间）
  bool _isBuffering = false;
  bool get isBuffering => _isBuffering;

  int? _playlistIndex;
  int get playlistIndex => _playlistIndex ?? 0;

  final ValueNotifier<List<Audio>> playlist = ValueNotifier([]);
  List<Audio> _playlistBackup = [];

  /// 不可用音频路径集合（播放失败时标记，重启后清空）
  final Set<String> unavailablePaths = {};

  /// 30秒定时保存播放状态
  Timer? _autoSaveTimer;

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

  /// 恢复状态下，用于 UI 显示的时长（秒）
  /// 播放器没加载音频时，优先用 Audio 对象的 duration，其次用保存的时长
  double get displayLength {
    if (_isRestoredState && nowPlaying != null) {
      if (nowPlaying!.duration > 0) {
        return nowPlaying!.duration.toDouble();
      }
      if (_restoredDurationSeconds != null && _restoredDurationSeconds! > 0) {
        return _restoredDurationSeconds!.toDouble();
      }
    }
    return length;
  }

  /// 恢复状态下，用于 UI 显示的播放位置（秒）
  double get displayPosition {
    if (_isRestoredState && _restoredPositionSeconds != null) {
      return _restoredPositionSeconds!.toDouble();
    }
    return position;
  }

  /// 恢复状态下，用于 UI 显示的缓冲进度（秒）
  /// 本地已缓存的音频直接显示满
  double get displayBuffer {
    if (_isRestoredState && nowPlaying != null) {
      if (nowPlaying!.duration > 0) {
        return nowPlaying!.duration.toDouble();
      }
      if (_restoredDurationSeconds != null && _restoredDurationSeconds! > 0) {
        return _restoredDurationSeconds!.toDouble();
      }
    }
    return buffer;
  }

  /// 是否处于恢复显示状态
  bool get isRestoredState => _isRestoredState;

  double get volumeDsp => AppPreference.instance.playbackPref.volumeDsp;

  void setVolumeDsp(double volume) {
    try {
      _player.setVolume(volume);
      _pref.volumeDsp = volume;
    } catch (e) {
      LOGGER.e("Failed to set volume DSP: $e");
    }
  }

  /// 秒级精度的播放位置流（用于进度条、时间显示、歌词行切换等）
  Stream<double> get positionStream =>
      _player.positionStream.map((duration) => duration.inSeconds.toDouble());

  /// 毫秒级精度的播放位置流（用于逐字歌词渲染等需要高精度的场景）
  Stream<double> get positionMsStream =>
      _player.positionStream.map((duration) => duration.inMilliseconds.toDouble());

  Stream<double> get bufferStream =>
      _player.bufferStream.map((duration) => duration.inSeconds.toDouble());

  Stream<double> get durationStream =>
      _player.durationStream.map((duration) => duration.inSeconds.toDouble());

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> _loadAndPlay(int audioIndex, List<Audio> playlist,
      {Map<String, String>? httpHeaders}) async {
    // 递增代龄，使之前正在执行的 _loadAndPlay 在检查点提前退出
    final gen = ++_loadPlayGeneration;

    try {
      _playlistIndex = audioIndex;
      nowPlaying = playlist[audioIndex];
      _isBuffering = true;
      notifyListeners(); // 立即通知：列表项显示选中状态 + 缓冲指示器

      final isCloud = nowPlaying!.isCloudAudio;

      LOGGER.i(
          "[_loadAndPlay] title=${nowPlaying!.title}, path=${nowPlaying!.path}, isCloud=$isCloud, _isRestoredPlayback=$_isRestoredPlayback, _restoredPositionSeconds=$_restoredPositionSeconds");

      if (isCloud && _supportsStreamingForCloud()) {
        final cachedPath =
            CloudCacheManager.instance.getCachedFilePath(nowPlaying!.path);
        debugLog("[DEBUG-CACHE] _loadAndPlay: path=${nowPlaying!.path}, isCloud=$isCloud, cachedPath=$cachedPath");
        if (cachedPath != null) {
          debugLog("[DEBUG-CACHE] cache HIT, using local file: $cachedPath");
          LOGGER.i("[_loadAndPlay] using cached file: $cachedPath");
          if (gen != _loadPlayGeneration) return;
          await _player.setSource(cachedPath, isNetwork: false);
        } else {
          debugLog("[DEBUG-CACHE] cache MISS, streaming + background caching");
          LOGGER.i("[_loadAndPlay] no cache found, streaming + background caching");
          try {
            final resolved =
                await CloudAudioPlayer.resolveStreamingUrl(nowPlaying!.path);
            // 网络请求后检查是否已被新调用取代
            if (gen != _loadPlayGeneration) return;
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
            _isBuffering = false;
            notifyListeners();
            _clearRestoredPlaybackState();
            return;
          }
        }
      } else if (isCloud) {
        showTextOnSnackBar('当前引擎不支持云音频流式播放，请切换到 MediaKit 引擎');
        _isBuffering = false;
        notifyListeners();
        _clearRestoredPlaybackState();
        return;
      } else {
        if (gen != _loadPlayGeneration) return;
        await _player.setSource(
          nowPlaying!.path,
          isNetwork: false,
          httpHeaders: httpHeaders,
        );
      }

      // 音频已加载，清除恢复显示状态
      _isRestoredState = false;

      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);

      playService.lyricService.updateLyric();

      // 如果是恢复播放，等待音频加载完成后 seek 到保存的位置，再播放
      if (_isRestoredPlayback && _restoredPositionSeconds != null) {
        LOGGER.i("[_loadAndPlay] Restored: waiting for duration then seek to ${_restoredPositionSeconds}s");

        // 等待 duration 变成非零（音频加载完成）
        int waitCount = 0;
        while (length <= 0 && waitCount < 50) {
          await Future.delayed(const Duration(milliseconds: 100));
          // 等待期间检查是否已被新调用取代
          if (gen != _loadPlayGeneration) return;
          waitCount++;
        }
        LOGGER.i("[_loadAndPlay] Restored: duration ready after ${waitCount * 100}ms, length=${length}s");

        if (gen != _loadPlayGeneration) return;
        if (length > 0) {
          await _player.seek(Duration(seconds: _restoredPositionSeconds!));
          LOGGER.i("[_loadAndPlay] Restored: seeked to ${_restoredPositionSeconds}s");
        } else {
          LOGGER.w("[_loadAndPlay] Restored: duration still 0 after 5s, skipping seek");
        }

        if (gen != _loadPlayGeneration) return;
        await _player.play();
        _restoredPositionSeconds = null;
        _restoredDurationSeconds = null;
        _isRestoredPlayback = false;
      } else {
        if (gen != _loadPlayGeneration) return;
        await _player.play();
        LOGGER.i("[_loadAndPlay] play() completed, playerState=$playerState");
      }

      _isBuffering = false;
      notifyListeners();
      ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);

      // 记录到最近播放
      RecentPlayService.instance.recordPlay(nowPlaying!);

      // 云音频元数据由 playCloudFile 中的 _updateMetadataAsync 统一处理（单链路）
      // 不再在此处调用 updateMetadataFromCache，避免并行修改 nowPlaying

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

      // 切歌时保存播放状态
      savePlaybackState();
    } catch (err) {
      LOGGER.e("[_loadAndPlay] $err");

      _isBuffering = false;
      notifyListeners();

      // 清理恢复播放状态，避免重试时卡在恢复流程
      _clearRestoredPlaybackState();

      // 标记不可用并提示用户
      if (nowPlaying != null) {
        final failedPath = nowPlaying!.path;
        markUnavailable(failedPath);
        _showUnavailableSnackBar(failedPath, nowPlaying!.title);
      } else {
        showTextOnSnackBar(err.toString());
      }
    }
  }

  /// 清理恢复播放进行中标志（防止 _loadAndPlay 提前返回或异常时状态残留）
  ///
  /// 注意：只清除 _isRestoredPlayback，保留 _restoredPositionSeconds 和 _isRestoredState。
  /// 这样当 _loadAndPlay 失败后，用户再次点击播放时仍能走恢复路径重试，
  /// 而不是走 _player.play() 正常路径（此时播放器无源，会静默失败）。
  /// _restoredPositionSeconds 和 _isRestoredState 在 _loadAndPlay 成功加载源后才会被清除。
  void _clearRestoredPlaybackState() {
    _isRestoredPlayback = false;
    notifyListeners();
  }

  /// 后台自动刮削元数据
  ///
  /// 两个独立维度：封面 和 元数据。
  /// - 有封面 → 不走封面相关逻辑
  /// - 没封面 → 抓封面（内嵌 → 刮削）
  /// - 有元数据 → 不抓元数据
  /// - 没元数据 → 抓元数据
  /// - 两者都缺 → 串行处理（先元数据回写，再封面）
  /// - 封面变动 → 触发主题颜色变化
  /// - 已有的不重复抓
  void _autoScrapeMetadata(Audio audio) {
    final metadataIncomplete = _isMetadataIncomplete(audio);
    final hasCover = audio.coverImage != null;

    // 前置短路：元数据完整 + 封面已有 → 无需任何操作
    if (!metadataIncomplete && hasCover) {
      return;
    }

    MetadataService.instance.autoScrape(
      audio,
      forceScrape: metadataIncomplete,
      onScraped: (isExactMatch, output) async {
        if (!isExactMatch) return;

        playService.lyricService.updateLyric();

        // 1. 元数据回写（仅在原字段缺失/UNKNOWN 时填充，不覆盖有效值）
        var metadataChanged = false;
        if (output?.bestMatch != null) {
          metadataChanged = _applyScrapedMetadata(audio, output!.bestMatch);
        }

        // 2. 封面处理：已有封面则跳过所有封面逻辑
        if (audio.coverImage != null) {
          // 封面已存在，不触碰
          if (metadataChanged) {
            notifyListeners();
            AudioLibrary.instance.notifyUpdated();
            if (nowPlaying?.path == audio.path) {
              ThemeProvider.instance.applyThemeFromAudio(audio);
            }
          }
          return;
        }

        // 3. 封面缺失：检查内嵌封面
        final hasEmbeddedCover = await _hasEmbeddedCover(audio);

        if (hasEmbeddedCover) {
          // 有内嵌封面但还没加载到内存，触发异步加载（cover getter 会自动加载并通知）
          // 不调用 clearCoverCache，不打断已有流程
          audio.cover; // 触发异步加载
          if (metadataChanged) {
            notifyListeners();
            AudioLibrary.instance.notifyUpdated();
          }
          if (nowPlaying?.path == audio.path) {
            ThemeProvider.instance.applyThemeFromAudio(audio);
          }
          return;
        }

        // 4. 无内嵌封面，尝试刮削封面
        Uint8List? coverBytes = output?.coverData;
        if (coverBytes == null) {
          coverBytes = await MetadataService.instance.getOrScrapeCover(
            audio,
            autoScrape: false,
          );
        }
        if (coverBytes == null) {
          coverBytes = await MetadataService.instance.getOrScrapeCover(
            audio,
            autoScrape: true,
          );
        }

        if (coverBytes != null) {
          audio.setCover(MemoryImage(coverBytes));
          await audio.setCoverSource('scraped');

          try {
            final audioId =
                await MetadataService.instance.computeAudioId(audio);
            if (audioId != null) {
              await MediaCache.instance.saveCover(audioId, coverBytes);
            }
          } catch (e) {
            LOGGER.e("[autoScrape] Failed to save cover to MediaCache: $e");
          }

          // 封面变动，通知 UI 和主题
          notifyListeners();
          AudioLibrary.instance.notifyUpdated();
          if (nowPlaying?.path == audio.path) {
            ThemeProvider.instance.applyThemeFromAudio(audio);
          }
        } else {
          // 没拿到封面，只在元数据有变化时才通知
          if (metadataChanged) {
            notifyListeners();
            AudioLibrary.instance.notifyUpdated();
          }
        }
      },
    );
  }

  /// 判断 audio 元数据是否缺失（需要刮削）
  /// 宽松判断：title/artist/album/genre 任一为空或 "UNKNOWN" 即认为缺失
  bool _isMetadataIncomplete(Audio audio) {
    bool isMissing(String? value) {
      if (value == null) return true;
      final trimmed = value.trim();
      return trimmed.isEmpty ||
          trimmed.toUpperCase() == 'UNKNOWN' ||
          trimmed == '未知';
    }

    // title 一般不会缺失（默认会用文件名），但仍检查
    // duration 为 0 也认为元数据缺失
    return isMissing(audio.title) ||
        isMissing(audio.artist) ||
        isMissing(audio.album) ||
        isMissing(audio.genre) ||
        audio.duration <= 0;
  }

  /// 将刮削结果回写到 audio 对象（仅在原字段缺失/UNKNOWN 时填充，不覆盖有效值）
  /// 返回 true 表示有字段被实际修改
  bool _applyScrapedMetadata(Audio audio, ScrapeResult result) {
    bool isMissing(String? value) {
      if (value == null) return true;
      final trimmed = value.trim();
      return trimmed.isEmpty ||
          trimmed.toUpperCase() == 'UNKNOWN' ||
          trimmed == '未知';
    }

    var changed = false;

    // 仅在原字段缺失时填充，不覆盖用户已有的有效值
    if (isMissing(audio.artist) && !isMissing(result.artist)) {
      audio.artist = result.artist!;
      changed = true;
    }
    if (isMissing(audio.album) && !isMissing(result.album)) {
      audio.album = result.album!;
      changed = true;
    }
    if (isMissing(audio.genre) && !isMissing(result.genre)) {
      audio.genre = result.genre!;
      changed = true;
    }
    // year 为 null 时填充
    if (audio.year == null && result.year != null) {
      audio.year = result.year;
      changed = true;
    }
    // title 一般不覆盖（用户的文件名可能就是想要的标题）
    // 只在 title 为 UNKNOWN/未知 时才覆盖
    if (isMissing(audio.title) && !isMissing(result.title)) {
      audio.title = result.title!;
      changed = true;
    }

    // 同步拆分艺术家列表
    if (audio.splitedArtists.isEmpty && audio.artist.isNotEmpty) {
      audio.splitedArtists = audio.artist.split(RegExp(r'[/、,，]'));
    }

    if (changed) {
      LOGGER.i("[autoScrape] Applied scraped metadata to ${audio.title}: "
          "artist=${audio.artist}, album=${audio.album}, genre=${audio.genre}, year=${audio.year}");
    }
    return changed;
  }

  /// 检查音频是否已有内嵌封面
  /// 云音频：检查本地缓存文件；本地音频：直接检查文件
  Future<bool> _hasEmbeddedCover(Audio audio) async {
    try {
      if (audio.isCloudAudio) {
        final cachedPath =
            CloudCacheManager.instance.getCachedFilePath(audio.path);
        if (cachedPath == null) return false;
        final pic = await getPictureFromPath(
          path: cachedPath,
          width: 48,
          height: 48,
        );
        return pic != null;
      } else {
        final pic = await getPictureFromPath(
          path: audio.path,
          width: 48,
          height: 48,
        );
        return pic != null;
      }
    } catch (_) {
      return false;
    }
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
          debugLog("[DEBUG-CACHE] background cache COMPLETED: $webdavPath");

          // 缓存下载完成后，如果当前播放的正是这首歌且还没有封面，
          // 尝试从缓存文件读取内嵌封面并通知 UI 刷新。
          await _tryLoadCoverFromCacheAfterDownload(webdavPath);
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

  /// 缓存文件下载完成后，尝试为当前播放歌曲加载封面。
  /// 仅当当前播放的正是这首歌且 audio 还没有封面时才执行。
  Future<void> _tryLoadCoverFromCacheAfterDownload(String webdavPath) async {
    try {
      final np = nowPlaying;
      if (np == null || np.path != webdavPath) return;
      if (np.coverImage != null) return;

      final cachedPath =
          CloudCacheManager.instance.getCachedFilePath(webdavPath);
      if (cachedPath == null) return;

      final pic = await getPictureFromPath(
        path: cachedPath,
        width: 400,
        height: 400,
      );

      if (pic != null && pic.isNotEmpty) {
        final coverImg = MemoryImage(pic);
        np.setCover(coverImg);
        for (final libAudio in AudioLibrary.instance.audioCollection) {
          if (libAudio.path == webdavPath && !identical(libAudio, np)) {
            libAudio.setCover(coverImg);
          }
        }
        try {
          final audioId = await MetadataService.instance.computeAudioId(np);
          if (audioId != null) {
            await MediaCache.instance.saveCover(audioId, pic, mimeType: 'image/png');
            await MetadataStore.instance.updateCoverSource(audioId, 'embedded');
          }
        } catch (_) {}
        await np.setCoverSource('embedded');
        CloudCoverPrefetcher.instance.reset(np.path);
        notifyListeners();
        AudioLibrary.instance.notifyUpdated();
        if (nowPlaying?.path == webdavPath) {
          ThemeProvider.instance.applyThemeFromAudio(np);
        }
      }
    } catch (e) {
      LOGGER.e("[CloudCache] _tryLoadCoverFromCacheAfterDownload error: $e");
    }
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
        // 暂停时清除歌词标题
        if (PlatformHelper.isIOS || PlatformHelper.isMacOS) {
          _macosMediaControlService?.clearLyricFromCover();
          if (PlatformHelper.isIOS) {
            NowPlayingWidget.update();
          }
        }
      }

      if (PlatformHelper.isDesktop) {
        playService.desktopLyricService.canSendMessage.then((canSend) {
          if (!canSend) return;

          playService.desktopLyricService.sendPlayerStateMessage(false);
        });
      }

      // 暂停时保存播放状态
      savePlaybackState();

      notifyListeners();
    } catch (err) {
      LOGGER.e("[pause] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 恢复的播放进度（秒），用户点击播放时 seek 到此位置后清空
  int? _restoredPositionSeconds;

  /// 恢复的播放总时长（秒），用于云音频等 Audio.duration 为 0 的情况
  int? _restoredDurationSeconds;

  /// 是否处于恢复显示状态（播放器未加载音频，用 Audio.duration 和保存的 position 显示）
  bool _isRestoredState = false;

  /// 是否是恢复播放（区别于正常切歌）
  bool _isRestoredPlayback = false;

  /// 重入保护：防止恢复播放时并发 _loadAndPlay
  bool _isStartingFromRestored = false;

  /// 暴露给 UI：恢复播放加载中（用于显示 loading 并禁用按钮）
  bool get isStartingFromRestored => _isStartingFromRestored;

  void start() {
    if (nowPlaying == null) return;
    try {
      // 如果有恢复的播放进度，需要先加载音频再播放
      if (_restoredPositionSeconds != null) {
        // 重入保护：异步加载期间忽略重复点击
        if (_isStartingFromRestored) {
          LOGGER.i("[start] Already starting from restored state, ignoring duplicate click");
          return;
        }
        _isStartingFromRestored = true;
        LOGGER.i("[start] Restored playback: loading audio at position ${_restoredPositionSeconds}s, _isRestoredPlayback=$_isRestoredPlayback");
        _isRestoredPlayback = true;
        final index = _playlistIndex ?? 0;
        // 必须 await，否则 seek 可能在加载完成前就检查了
        _loadAndPlay(index, playlist.value).then((_) {
          _isStartingFromRestored = false;
          notifyListeners();
          LOGGER.i("[start] _loadAndPlay completed");
        }).catchError((e) {
          _isStartingFromRestored = false;
          notifyListeners();
          LOGGER.e("[start] _loadAndPlay failed: $e");
        });
        // 立即通知 UI，让按钮显示 loading 态并禁用
        notifyListeners();
        return;
      }

      // 回退：播放器没有加载音频源时（如之前恢复加载失败），
      // 直接 _player.play() 会静默失败，需要走 _loadAndPlay 重新加载
      if (length <= 0) {
        LOGGER.i("[start] No source loaded (length=$length), reloading audio via _loadAndPlay");
        if (_isStartingFromRestored) {
          LOGGER.i("[start] Already starting, ignoring duplicate click");
          return;
        }
        _isStartingFromRestored = true;
        final index = _playlistIndex ?? 0;
        _loadAndPlay(index, playlist.value).then((_) {
          _isStartingFromRestored = false;
          notifyListeners();
          LOGGER.i("[start] _loadAndPlay (no-source fallback) completed");
        }).catchError((e) {
          _isStartingFromRestored = false;
          notifyListeners();
          LOGGER.e("[start] _loadAndPlay (no-source fallback) failed: $e");
        });
        notifyListeners();
        return;
      }

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

  /// 更新蓝牙歌词（macOS/iOS 封面图+歌词合成）
  /// 由 LyricService 在歌词行变化时调用
  void updateBluetoothLyric(String lyricText, {String? translation}) {
    if (!PlatformHelper.isIOS && !PlatformHelper.isMacOS) return;
    _macosMediaControlService?.updateLyricOnCover(lyricText,
        translation: translation);
  }

  /// 设置蓝牙歌词开关
  void setBluetoothLyricEnabled(bool enabled) {
    if (!PlatformHelper.isIOS && !PlatformHelper.isMacOS) return;
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

    // seek 时保存播放状态
    savePlaybackState();
  }

  // ─── 播放状态持久化 ──────────────────────────────────

  /// 保存当前播放状态到磁盘
  Future<void> savePlaybackState() async {
    if (nowPlaying == null || playlist.value.isEmpty) {
      LOGGER.w("[savePlaybackState] skipped: nowPlaying=$nowPlaying, playlist.length=${playlist.value.length}");
      return;
    }
    // 恢复状态下，播放器未加载音频，position 为 0
    // 此时使用 _restoredPositionSeconds 保存正确的进度，避免覆盖
    final pos = _isRestoredState && _restoredPositionSeconds != null
        ? _restoredPositionSeconds!
        : position.floor();
    // 时长：优先用播放器的真实时长，其次用 Audio 对象的 duration
    final dur = length > 0
        ? length.floor()
        : (nowPlaying!.duration > 0 ? nowPlaying!.duration : _restoredDurationSeconds ?? 0);
    await PlaybackStateService.instance.save(
      playlist: playlist.value
          .map((a) => PlaylistEntry(path: a.path, connectionId: a.connectionId))
          .toList(),
      currentIndex: playlistIndex,
      positionSeconds: pos,
      durationSeconds: dur,
    );
  }

  /// 启动10秒定时自动保存
  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // 仅在播放中保存，暂停/停止时不保存（避免无意义写入）
      if (playerState == PlayerState.playing) {
        savePlaybackState();
      }
    });
  }

  /// 从磁盘恢复播放状态
  ///
  /// 通过音频路径从 AudioLibrary 查找音频对象，填充播放列表。
  /// 不自动播放，只恢复显示状态。
  Future<void> restorePlaybackState() async {
    final state = await PlaybackStateService.instance.load();
    if (state == null) {
      LOGGER.i("[restorePlaybackState] No saved state found");
      return;
    }
    LOGGER.i("[restorePlaybackState] Loaded state: index=${state.currentIndex}, position=${state.positionSeconds}s, playlist.length=${state.playlist.length}");

    final allAudios = AudioLibrary.instance.audioCollection;
    final restoredPlaylist = <Audio>[];
    final pathToAudio = <String, Audio>{};
    for (final audio in allAudios) {
      pathToAudio[audio.path] = audio;
    }

    for (final entry in state.playlist) {
      // 优先从音乐库匹配（本地音频 + 已入库云音频）
      final audio = pathToAudio[entry.path];
      if (audio != null) {
        restoredPlaylist.add(audio);
        continue;
      }
      // 音乐库中找不到：如果有 connectionId，说明是未入库的云音频，重建 Audio 对象
      if (entry.connectionId != null && entry.connectionId!.isNotEmpty) {
        final rebuilt = await _rebuildCloudAudio(entry.path, entry.connectionId!);
        if (rebuilt != null) {
          restoredPlaylist.add(rebuilt);
        }
      }
    }

    if (restoredPlaylist.isEmpty) {
      LOGGER.w("[restorePlaybackState] No audios matched, skipping restore");
      return;
    }

    playlist.value = restoredPlaylist;
    _playlistBackup = List.from(restoredPlaylist);

    // 调整索引：如果保存的索引超出恢复后的列表范围，取最后一首
    final restoredIndex = state.currentIndex.clamp(0, restoredPlaylist.length - 1);
    _playlistIndex = restoredIndex;
    nowPlaying = restoredPlaylist[restoredIndex];

    // 恢复播放进度（但不播放，等用户点击播放时再 seek）
    _restoredPositionSeconds = state.positionSeconds;
    _restoredDurationSeconds = state.durationSeconds > 0 ? state.durationSeconds : null;
    _isRestoredState = true;

    notifyListeners();
  }

  /// 重建未入库的云音频 Audio 对象
  ///
  /// 从文件名解析标题/艺术家，注册 path → service 映射，
  /// 后续播放时通过 CloudAudioPlayer.resolveStreamingUrl 解析流地址。
  Future<Audio?> _rebuildCloudAudio(String webdavPath, String connectionId) async {
    try {
      final manager = CloudServiceManager.instance;
      // 等待 CloudServiceManager 加载完成（确保 getService 可用）
      await manager.ready;
      final service = manager.getService(connectionId);
      if (service == null) {
        LOGGER.w("[restorePlaybackState] service not found for connectionId=$connectionId, path=$webdavPath");
        return null;
      }
      // 注册 path → service 映射，播放时需要
      CloudAudioPlayer.registerPath(webdavPath, service);

      final fileName = webdavPath.split('/').last;
      final parsed = CloudAudioPlayer.parseFileName(fileName);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final audio = Audio(
        parsed.title,
        parsed.artist,
        '',
        '',
        null,
        '',
        0,
        0,
        null,
        null,
        webdavPath,
        now,
        now,
        'Cloud',
        connectionId: connectionId,
      );
      LOGGER.i("[restorePlaybackState] rebuilt cloud audio: ${parsed.title} ($webdavPath)");
      return audio;
    } catch (e) {
      LOGGER.w("[restorePlaybackState] failed to rebuild cloud audio: $webdavPath - $e");
      return null;
    }
  }

  /// 标记音频不可用并通知 UI
  void markUnavailable(String audioPath) {
    unavailablePaths.add(audioPath);
    playlist.notifyListeners();
  }

  /// 从播放列表移除不可用的音频
  void removeUnavailable(String audioPath) {
    unavailablePaths.remove(audioPath);
    final index = playlist.value.indexWhere((a) => a.path == audioPath);
    if (index == -1) return;

    playlist.value.removeAt(index);
    // 调整当前播放索引
    if (_playlistIndex != null) {
      if (index < _playlistIndex!) {
        _playlistIndex = _playlistIndex! - 1;
      } else if (index == _playlistIndex!) {
        // 当前播放的被移除了
        if (playlist.value.isEmpty) {
          _playlistIndex = null;
          nowPlaying = null;
        } else {
          _playlistIndex = _playlistIndex!.clamp(0, playlist.value.length - 1);
          nowPlaying = playlist.value[_playlistIndex!];
        }
      }
    }
    _playlistBackup = List.from(playlist.value);
    notifyListeners();
    savePlaybackState();
  }

  /// 显示不可用音频提示 SnackBar
  void _showUnavailableSnackBar(String audioPath, String audioTitle) {
    final context = ROUTER_KEY.currentContext;
    if (context == null) {
      showTextOnSnackBar("音频不可用：$audioTitle");
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("音频不可用：$audioTitle"),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: "移除",
          onPressed: () {
            removeUnavailable(audioPath);
            // 移除后尝试播放当前索引的音频
            if (nowPlaying != null && playlist.value.isNotEmpty) {
              _loadAndPlay(playlistIndex, playlist.value);
            }
          },
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // 自动跳到下一首
    nextAudio();
  }

  void close() {
    _autoSaveTimer?.cancel();
    // 关闭时同步保存播放状态
    savePlaybackState();
    _playerStateStreamSub.cancel();
    _positionStreamSub?.cancel();
    _smtcEventStreamSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();

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
