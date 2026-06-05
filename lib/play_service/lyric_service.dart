import 'dart:async';
import 'dart:math';

import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/music_matcher.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

/// 只通知 lyric 变更
class LyricService extends ChangeNotifier {
  final PlayService playService;

  late StreamSubscription _positionStreamSubscription;
  LyricService(this.playService) {
    _positionStreamSubscription =
        playService.playbackService.positionMsStream.listen((posInMs) {
      currLyricFuture.then((value) {
        if (value == null) return;
        if (_nextLyricLine >= value.lines.length) return;

        final adjustedPos = posInMs + _lyricOffsetMs;
        if (adjustedPos > value.lines[_nextLyricLine].start.inMilliseconds) {
          _nextLyricLine += 1;

          final currLineIndex = _nextLyricLine - 1;
          _lyricLineStreamController.add(currLineIndex);

          playService.desktopLyricService.canSendMessage.then((canSend) {
            if (!canSend) return;

            final currLine = value.lines[currLineIndex];
            playService.desktopLyricService.sendLyricLineMessage(currLine);
          });

          // macOS/iOS: 更新蓝牙歌词（封面图+歌词合成）
          if (PlatformHelper.isIOS || PlatformHelper.isMacOS) {
            final currLine = value.lines[currLineIndex];
            final lyricText = currLine is SyncLyricLine
                ? currLine.content
                : (currLine is UnsyncLyricLine ? currLine.content : '');
            final translation =
                currLine is SyncLyricLine ? currLine.translation : null;
            if (lyricText.isNotEmpty) {
              playService.playbackService
                  .updateBluetoothLyric(lyricText, translation: translation);
            }
          }
        }
      });
    });
  }

  Audio? _getNowPlaying() => playService.playbackService.nowPlaying;

  /// 当前音频的歌词时间偏移（毫秒），正值=歌词提前，负值=歌词延后
  int _lyricOffsetMs = 0;
  int get lyricOffsetMs => _lyricOffsetMs;

  void setLyricOffset(int offsetMs) {
    _lyricOffsetMs = offsetMs;
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

    final source = LYRIC_SOURCES[nowPlaying.path];
    if (source != null) {
      source.offsetMs = offsetMs;
    } else {
      LYRIC_SOURCES[nowPlaying.path] =
          LyricSource(LyricSourceType.local, offsetMs: offsetMs);
    }
    saveLyricSources();
    findCurrLyricLine();
    notifyListeners();
  }

  void resetLyricOffset() {
    setLyricOffset(0);
  }

  /// 供 widget 使用
  Future<Lyric?> currLyricFuture = Future.value(null);

  /// 下一行歌词
  int _nextLyricLine = 0;

  late final StreamController<int> _lyricLineStreamController =
      StreamController.broadcast(onListen: () {
    _lyricLineStreamController.add(_nextLyricLine);
  });

  Stream<int> get lyricLineStream => _lyricLineStreamController.stream;

  /// 重新计算歌词进行到第几行
  void findCurrLyricLine() {
    currLyricFuture.then((value) {
      if (value == null) return;

      final posMs =
          playService.playbackService.position * 1000 + _lyricOffsetMs;
      final next = value.lines.indexWhere(
        (element) => element.start.inMilliseconds > posMs,
      );
      _nextLyricLine = next == -1 ? value.lines.length : next;
      _lyricLineStreamController.add(max(_nextLyricLine - 1, 0));
    });
  }

  Future<Lyric?> _getLyricDefault(bool localFirst) async {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return Future.value(null);

    // 内嵌歌词始终最优先（主流播放器标准：文件内嵌数据 > 在线缓存）
    // 云音频：有本地缓存文件时从缓存文件读内嵌，无缓存文件跳过
    if (!nowPlaying.isCloudAudio) {
      final embeddedLyric = await Lrc.fromAudioPath(nowPlaying);
      if (embeddedLyric != null) return embeddedLyric;
    } else {
      final cachedPath =
          CloudCacheManager.instance.getCachedFilePath(nowPlaying.path);
      if (cachedPath != null) {
        final lyricText = await getLyricFromPath(path: cachedPath);
        if (lyricText != null) {
          final lyric = Lrc.fromLrcText(lyricText, LrcSource.local);
          if (lyric != null) return lyric;
        }
      }
    }

    // 内嵌歌词不存在时，从缓存获取
    final cachedLyric = await _getLyricFromCache(nowPlaying);
    if (cachedLyric != null) return cachedLyric;

    // 缓存也没有时，在线获取
    return (await getMostMatchedLyric(nowPlaying));
  }

  /// 从 MetadataService 缓存获取歌词
  Future<Lyric?> _getLyricFromCache(Audio audio) async {
    try {
      final audioId = await MetadataService.instance.computeAudioId(audio);
      if (audioId == null) return null;

      // 从本地缓存文件获取歌词
      final cached = await MediaCache.instance.getLyric(audioId);
      if (cached != null) {
        final lyricText = cached.$1;
        // 解析歌词文本为 Lyric 对象
        final lyric = Lrc.fromLrcText(lyricText, LrcSource.local);
        if (lyric != null) {
          LOGGER
              .i("[LyricService] Loaded lyric from cache for: ${audio.title}");
          return lyric;
        }
      }

      // 从数据库获取歌词文本
      final metadata = await MetadataStore.instance.getMetadata(audioId);
      if (metadata?.lyricText != null) {
        final lyric = Lrc.fromLrcText(metadata!.lyricText!, LrcSource.local);
        if (lyric != null) {
          // 同步缓存到文件
          await MediaCache.instance.saveLyric(
            audioId,
            metadata.lyricText!,
            synced: metadata.lyricSynced ?? false,
          );
          LOGGER.i("[LyricService] Loaded lyric from DB for: ${audio.title}");
          return lyric;
        }
      }
    } catch (e) {
      LOGGER.e("[LyricService] Failed to get lyric from cache: $e");
    }
    return null;
  }

  /// 根据默认歌词来源获取歌词：
  /// 1. 如果没有指定来源，按照现在的方式寻找歌词（本地优先或在线优先）
  /// 2. 如果指定来源，按照指定的来源获取
  void updateLyric() {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

    currLyricFuture.ignore();

    final lyricSource = LYRIC_SOURCES[nowPlaying.path];
    _lyricOffsetMs = lyricSource?.offsetMs ?? 0;

    if (lyricSource == null) {
      currLyricFuture = _getLyricDefault(true);
    } else if (lyricSource.source == LyricSourceType.local) {
      currLyricFuture = _getLyricDefault(true);
    } else {
      currLyricFuture = getOnlineLyric(
        qqSongId: lyricSource.qqSongId,
        kugouSongHash: lyricSource.kugouSongHash,
        neteaseSongId: lyricSource.neteaseSongId,
      ).then((lyric) async {
        if (lyric != null) return lyric;
        return _getLyricDefault(true);
      });
    }

    currLyricFuture.then((value) {
      _nextLyricLine = 0;
      // 自动缓存歌词到 MetadataService
      if (value != null) {
        _cacheLyricInBackground(nowPlaying, value);
      }
    });

    notifyListeners();
  }

  /// 后台缓存歌词（不阻塞播放流程）
  Future<void> _cacheLyricInBackground(Audio audio, Lyric lyric) async {
    try {
      final audioId = await MetadataService.instance.computeAudioId(audio);
      if (audioId == null) return;

      // 检查是否已有缓存
      final existing = await MediaCache.instance.getLyric(audioId);
      if (existing != null) return;

      // 将歌词导出为文本并缓存
      final lyricText = _lyricToText(lyric);
      if (lyricText.isNotEmpty) {
        await MediaCache.instance.saveLyric(audioId, lyricText, synced: true);
        await MetadataStore.instance
            .updateLyric(audioId, lyricText, synced: true);
        LOGGER.i("[LyricService] Auto-cached lyric for: ${audio.title}");
      }
    } catch (e) {
      LOGGER.e("[LyricService] Failed to cache lyric: $e");
    }
  }

  /// 将 Lyric 对象转换为 LRC 文本
  String _lyricToText(Lyric lyric) {
    final buf = StringBuffer();
    for (final line in lyric.lines) {
      if (line is LrcLine) {
        final startMs = line.start.inMilliseconds;
        final min = (startMs ~/ 60000).toString().padLeft(2, '0');
        final sec = ((startMs % 60000) ~/ 1000).toString().padLeft(2, '0');
        final ms = (startMs % 1000).toString().padLeft(3, '0');
        buf.writeln('[$min:$sec.$ms]${line.content}');
      }
    }
    return buf.toString();
  }

  void useLocalLyric() {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

    currLyricFuture.ignore();

    currLyricFuture = Lrc.fromAudioPath(nowPlaying);
    currLyricFuture.then((value) {
      findCurrLyricLine();
    });

    notifyListeners();
  }

  void useOnlineLyric() {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

    currLyricFuture.ignore();

    currLyricFuture = getMostMatchedLyric(nowPlaying);
    currLyricFuture.then((value) {
      findCurrLyricLine();
    });

    notifyListeners();
  }

  void useSpecificLyric(Lyric lyric) {
    currLyricFuture.ignore();

    currLyricFuture = Future.value(lyric);
    currLyricFuture.then((value) {
      findCurrLyricLine();
    });

    notifyListeners();
  }

  @override
  void dispose() {
    _lyricLineStreamController.close();
    _positionStreamSubscription.cancel();
    super.dispose();
  }
}
