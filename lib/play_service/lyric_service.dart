import 'dart:async';
import 'dart:math';

import 'package:coriander_player/app_settings.dart';
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
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

/// 只通知 lyric 变更
class LyricService extends ChangeNotifier {
  final PlayService playService;

  late StreamSubscription _positionStreamSubscription;
  LyricService(this.playService) {
    _positionStreamSubscription =
        playService.playbackService.positionStream.listen((pos) {
      currLyricFuture.then((value) {
        if (value == null) return;
        if (_nextLyricLine >= value.lines.length) return;

        if ((pos * 1000) > value.lines[_nextLyricLine].start.inMilliseconds) {
          _nextLyricLine += 1;

          final currLineIndex = _nextLyricLine - 1;
          _lyricLineStreamController.add(currLineIndex);

          playService.desktopLyricService.canSendMessage.then((canSend) {
            if (!canSend) return;

            final currLine = value.lines[currLineIndex];
            playService.desktopLyricService.sendLyricLineMessage(currLine);
          });

          // iOS: 更新蓝牙歌词（封面图+歌词合成）
          if (PlatformHelper.isIOS) {
            final currLine = value.lines[currLineIndex];
            final lyricText = currLine is SyncLyricLine
                ? currLine.content
                : (currLine is UnsyncLyricLine ? currLine.content : '');
            final translation = currLine is SyncLyricLine
                ? currLine.translation
                : null;
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

      final next = value.lines.indexWhere(
        (element) =>
            element.start.inMilliseconds / 1000 >
            playService.playbackService.position,
      );
      _nextLyricLine = next == -1 ? value.lines.length : next;
      _lyricLineStreamController.add(max(_nextLyricLine - 1, 0));
    });
  }

  Future<Lyric?> _getLyricDefault(bool localFirst) async {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return Future.value(null);

    // 优先从 MetadataService 缓存获取歌词
    final cachedLyric = await _getLyricFromCache(nowPlaying);
    if (cachedLyric != null) return cachedLyric;

    if (localFirst) {
      return (await Lrc.fromAudioPath(nowPlaying)) ??
          (await getMostMatchedLyric(nowPlaying));
    }
    return (await getMostMatchedLyric(nowPlaying)) ??
        (await Lrc.fromAudioPath(nowPlaying));
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
          LOGGER.i("[LyricService] Loaded lyric from cache for: ${audio.title}");
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
            audioId, metadata.lyricText!, synced: metadata.lyricSynced ?? false,
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
    if (lyricSource == null) {
      currLyricFuture = _getLyricDefault(AppSettings.instance.localLyricFirst);
    } else {
      if (lyricSource.source == LyricSourceType.local) {
        currLyricFuture = Lrc.fromAudioPath(nowPlaying);
      } else {
        currLyricFuture = getOnlineLyric(
          qqSongId: lyricSource.qqSongId,
          kugouSongHash: lyricSource.kugouSongHash,
          neteaseSongId: lyricSource.neteaseSongId,
        );
      }
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
        await MetadataStore.instance.updateLyric(audioId, lyricText, synced: true);
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
