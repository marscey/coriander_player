import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

/// 云音频封面预加载服务
///
/// 列表滚动时，对可见的云音频项异步发 Range 请求拉取头部字节，
/// 调用 Rust [getPictureFromBytes] 解析内嵌封面，无需下载完整文件。
///
/// 特性：
/// - 单例
/// - 并发控制（默认最多 3 个并发 Range 请求）
/// - 去重（同一 audio path 仅请求一次）
/// - 失败缓存（避免重复请求失败的 audio，应用重启后清除）
/// - 异步 fire-and-forget，不堵塞 UI
///
/// 调用时机：列表项 build 时，若 audio 是云音频且无封面，调用 [prefetch]。
/// 内部会去重和限流，可安全地在 build 中调用。
class CloudCoverPrefetcher {
  CloudCoverPrefetcher._();
  static final CloudCoverPrefetcher instance = CloudCoverPrefetcher._();

  /// 并发请求数上限
  static const int _maxConcurrent = 3;

  /// Range 请求拉取的头部字节大小（256KB，覆盖大多数内嵌封面）
  static const int _headSize = 256 * 1024;

  /// Range 请求拉取的尾部字节大小（M4A/MP4 用，覆盖 moov atom）
  static const int _tailSize = 256 * 1024;

  /// 目标封面尺寸（与列表项 [AudioTile] 48x48 一致，避免重复解码）
  static const int _coverWidth = 48;
  static const int _coverHeight = 48;

  int _running = 0;

  /// 等待获取并发槽位的请求队列
  final Queue<Completer<void>> _slotQueue = Queue();

  /// 进行中的请求（audio path → Future），用于去重
  final Map<String, Future<void>> _pending = {};

  /// 已成功的请求（audio path），避免重复处理
  final Set<String> _succeeded = {};

  /// 已失败的请求（audio path），避免重复请求（应用重启后清除）
  final Set<String> _failed = {};

  /// 预加载云音频封面（fire-and-forget）
  ///
  /// 调用方在列表项 build 时调用，无需 await。内部会去重和限流。
  /// 成功后自动调用 [Audio.setCover] + [Audio.setCoverSource]('embedded')
  /// + 写入 [MediaCache] + [AudioLibrary.notifyUpdated] 触发 UI 刷新。
  void prefetch(Audio audio) {
    // 仅云音频
    if (!audio.isCloudAudio) return;

    // 已有封面，跳过
    if (audio.coverImage != null) return;

    // 无 connectionId，跳过
    if (audio.connectionId == null) return;

    final path = audio.path;

    // 已成功或已失败，跳过
    if (_succeeded.contains(path)) return;
    if (_failed.contains(path)) return;

    // 已在队列中，跳过
    if (_pending.containsKey(path)) return;

    _pending[path] = _execute(audio);
  }

  Future<void> _execute(Audio audio) async {
    await _acquireSlot();
    try {
      await _doPrefetch(audio);
    } finally {
      _releaseSlot();
      _pending.remove(audio.path);
    }
  }

  Future<void> _acquireSlot() async {
    if (_running < _maxConcurrent) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _slotQueue.add(completer);
    await completer.future;
    _running++;
  }

  void _releaseSlot() {
    _running--;
    if (_slotQueue.isNotEmpty) {
      _slotQueue.removeFirst().complete();
    }
  }

  Future<void> _doPrefetch(Audio audio) async {
    final path = audio.path;
    try {
      final service =
          CloudServiceManager.instance.getService(audio.connectionId!);
      if (service == null) {
        _failed.add(path);
        return;
      }

      final audioId = await MetadataService.instance.computeAudioId(audio);

      // 0. 检查 cover_source：'none' 表示用户主动清除，不预加载
      // 'scraped'/'custom' 表示已有刮削/自定义封面，不预加载
      if (audioId != null) {
        final coverSource =
            await MetadataStore.instance.getCoverSource(audioId);
        if (coverSource == 'none' ||
            coverSource == 'scraped' ||
            coverSource == 'custom') {
          _failed.add(path);
          return;
        }
      }

      // 1. 优先检查 MediaCache（可能其他流程已存入）
      if (audioId != null) {
        final cached = await MediaCache.instance.getCover(audioId);
        if (cached != null) {
          _applyCover(audio, cached.$1);
          _succeeded.add(path);
          return;
        }
      }

      // 2. 检查 CloudCacheManager 是否有完整缓存（有则直接读内嵌）
      final cachedPath = CloudCacheManager.instance.getCachedFilePath(path);
      if (cachedPath != null) {
        final pic = await getPictureFromPath(
          path: cachedPath,
          width: _coverWidth,
          height: _coverHeight,
        );
        if (pic != null) {
          _applyCover(audio, pic);
          if (audioId != null) {
            await MediaCache.instance
                .saveCover(audioId, pic, mimeType: 'image/png');
          }
          _succeeded.add(path);
          return;
        }
      }

      // 3. Range 请求拉取头部字节
      int? fileSize = audio.fileSize;
      if (fileSize == null || fileSize < 128) {
        fileSize = await service.getFileSize(path);
        if (fileSize == null || fileSize < 128) {
          LOGGER.w(
              '[CloudCoverPrefetcher] cannot get file size, skip: $path');
          _failed.add(path);
          return;
        }
      }

      final fileName = p.basename(path);
      final isMp4 = fileName.toLowerCase().endsWith('.m4a') ||
          fileName.toLowerCase().endsWith('.mp4');

      // M4A/MP4 封面在 moov atom（通常在文件尾部），需要 head + tail
      // 其他格式（MP3/FLAC）封面在头部，仅需 head
      Uint8List? headBytes;
      Uint8List? tailBytes;

      if (isMp4) {
        // M4A: 并发拉取 head 256KB + tail 256KB
        final headEnd = (_headSize - 1).clamp(0, fileSize - 1);
        final tailSize = _tailSize.clamp(0, fileSize);
        final tailStart = (fileSize - tailSize).clamp(0, fileSize - 1);

        final results = await Future.wait([
          service.downloadRange(path, 0, headEnd),
          service.downloadRange(path, tailStart, fileSize - 1),
        ]);
        headBytes = results[0];
        tailBytes = results[1];

        if (headBytes == null ||
            headBytes.isEmpty ||
            tailBytes == null ||
            tailBytes.isEmpty) {
          LOGGER.w(
              '[CloudCoverPrefetcher] M4A Range request failed, skip: $path');
          _failed.add(path);
          return;
        }
      } else {
        // 其他格式: 仅 head
        final headEnd = (_headSize - 1).clamp(0, fileSize - 1);
        headBytes = await service.downloadRange(path, 0, headEnd);
        if (headBytes == null || headBytes.isEmpty) {
          LOGGER.w(
              '[CloudCoverPrefetcher] Range request failed, skip: $path');
          _failed.add(path);
          return;
        }
      }

      // 4. 调用 Rust 解析封面
      final picBytes = await getPictureFromBytes(
        headBytes: headBytes,
        tailBytes: tailBytes ?? Uint8List(0),
        fileSize: fileSize,
        fileName: fileName,
        width: _coverWidth,
        height: _coverHeight,
      );

      if (picBytes == null || picBytes.isEmpty) {
        LOGGER.i(
            '[CloudCoverPrefetcher] no embedded cover: $path');
        _failed.add(path);
        return;
      }

      // 5. 成功：设置封面 + 存 MediaCache + 标记 source + 通知 UI
      _applyCover(audio, picBytes);
      if (audioId != null) {
        await MediaCache.instance
            .saveCover(audioId, picBytes, mimeType: 'image/png');
      }
      await audio.setCoverSource('embedded');
      _succeeded.add(path);

      LOGGER.i('[CloudCoverPrefetcher] prefetched cover: $path');
    } catch (e) {
      LOGGER.e('[CloudCoverPrefetcher] prefetch failed for $path: $e');
      _failed.add(path);
    }
  }

  /// 应用封面到 Audio 并通知 UI 刷新
  void _applyCover(Audio audio, Uint8List picBytes) {
    final coverImg = MemoryImage(picBytes);
    audio.setCover(coverImg);

    for (final libAudio in AudioLibrary.instance.audioCollection) {
      if (libAudio.path == audio.path && !identical(libAudio, audio)) {
        libAudio.setCover(coverImg);
      }
    }

    final playbackService = PlayService.instance.playbackService;
    if (playbackService.nowPlaying?.path == audio.path) {
      playbackService.refreshNowPlaying();
    }
    AudioLibrary.instance.notifyUpdated();
  }

  /// 重置指定 audio 的预加载状态
  ///
  /// 用于用户手动重新刮削、清除封面、或音频文件被替换后，
  /// 允许重新触发预加载。
  void reset(String audioPath) {
    _succeeded.remove(audioPath);
    _failed.remove(audioPath);
  }

  /// 清除所有状态（应用重启时调用）
  void clearAll() {
    _pending.clear();
    _slotQueue.clear();
    _failed.clear();
    _succeeded.clear();
    _running = 0;
  }
}
