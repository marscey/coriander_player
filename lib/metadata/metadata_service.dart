import 'dart:convert';
import 'dart:typed_data';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_scraper.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/metadata/scraper_orchestrator.dart';
import 'package:coriander_player/utils.dart';
import 'package:crypto/crypto.dart';

// flutter_rust_bridge 生成的函数
// ignore: depend_on_referenced_packages
import 'package:coriander_player/src/rust/api/tag_reader.dart' as rust_api;

/// 元数据服务 - 统一接口
///
/// 提供音频元数据的读取、写入、缓存、刮削和匹配功能。
/// 核心设计：
/// - contentHash 作为稳定标识，文件移动后仍可匹配
/// - 云音频使用 cloud:md5(path) 作为 ID
/// - 所有写入操作通过 Rust lofty 实现
/// - 刮削通过 ScraperOrchestrator 调度
class MetadataService {
  static MetadataService get instance => _instance;
  static final MetadataService _instance = MetadataService._();
  MetadataService._();

  /// 计算音频文件的 contentHash
  /// 本地文件：SHA256(文件头64KB + 文件大小)
  /// 云音频：cloud:md5(path)
  Future<String?> computeAudioId(Audio audio) async {
    if (audio.isCloudAudio) {
      return _computeCloudAudioId(audio);
    }
    return rust_api.computeContentHash(path: audio.path);
  }

  /// 计算云音频 ID
  /// cloud:md5(webdavPath + fileSize + duration)
  String _computeCloudAudioId(Audio audio) {
    final components = [audio.path];
    if ((audio.bitrate ?? 0) > 0) components.add(audio.bitrate.toString());
    if (audio.duration > 0) components.add(audio.duration.toString());
    final input = components.join('|');
    final hash = md5.convert(utf8.encode(input));
    return 'cloud:$hash';
  }

  /// 写入标签到音频文件
  /// fields: 需要写入的字段，null 值的字段保持原值不变
  Future<void> writeTags({
    required String path,
    String? title,
    String? artist,
    String? album,
    int? track,
    int? year,
    String? genre,
    String? mbRecordingId,
    String? mbReleaseId,
    String? mbArtistId,
  }) async {
    final fields = <String, dynamic>{};
    if (title != null) fields['title'] = title;
    if (artist != null) fields['artist'] = artist;
    if (album != null) fields['album'] = album;
    if (track != null) fields['track'] = track;
    if (year != null) fields['year'] = year;
    if (genre != null) fields['genre'] = genre;
    if (mbRecordingId != null) fields['mb_recording_id'] = mbRecordingId;
    if (mbReleaseId != null) fields['mb_release_id'] = mbReleaseId;
    if (mbArtistId != null) fields['mb_artist_id'] = mbArtistId;

    if (fields.isEmpty) return;

    await rust_api.writeTagsToPath(path: path, fields: jsonEncode(fields));
    LOGGER.i("[MetadataService] Tags written to: $path");
  }

  /// 写入封面到音频文件
  Future<void> writeCover({
    required String path,
    required Uint8List coverData,
    String mimeType = 'image/jpeg',
  }) async {
    await rust_api.writeCoverToPath(
      path: path,
      coverData: coverData,
      mimeType: mimeType,
    );
    LOGGER.i("[MetadataService] Cover written to: $path, size=${coverData.length} bytes");
  }

  /// 写入歌词到音频文件
  /// isSynced: true 表示 LRC 格式同步歌词
  Future<void> writeLyric({
    required String path,
    required String lyricText,
    bool isSynced = true,
  }) async {
    await rust_api.writeLyricToPath(
      path: path,
      lyricText: lyricText,
      isSynced: isSynced,
    );
    LOGGER.i("[MetadataService] Lyric written to: $path, synced=$isSynced");
  }

  // ==================== 刮削相关 ====================

  /// 搜索元数据
  ///
  /// 返回所有刮削源的搜索结果，按匹配度排序
  Future<List<ScrapeResult>> searchMetadata(
    String query, {
    String? artist,
    String? album,
  }) async {
    return ScraperOrchestrator.instance.search(query, artist: artist, album: album);
  }

  /// 刮削并应用元数据
  ///
  /// 完整流程：搜索 → 获取歌词/封面 → 缓存 → 写入文件（可选）
  /// [audio] 音频对象
  /// [fetchLyric] 是否获取歌词
  /// [fetchCover] 是否获取封面
  /// [writeToFile] 是否将刮削结果写入音频文件
  Future<ScrapeOutput?> scrapeAndApply({
    required Audio audio,
    bool fetchLyric = true,
    bool fetchCover = true,
    bool writeToFile = false,
  }) async {
    final audioId = await computeAudioId(audio);
    if (audioId == null) {
      LOGGER.e("[MetadataService] Cannot compute audioId for: ${audio.path}");
      return null;
    }

    final output = await ScraperOrchestrator.instance.scrape(
      audioId: audioId,
      query: audio.title,
      artist: audio.artist,
      album: audio.album,
      fetchLyric: fetchLyric,
      fetchCover: fetchCover,
    );

    if (output == null) return null;

    // 可选：写入到音频文件
    if (writeToFile && !audio.isCloudAudio) {
      final path = audio.path;
      try {
        // 写入标签
        await writeTags(
          path: path,
          title: output.bestMatch.title,
          artist: output.bestMatch.artist,
          album: output.bestMatch.album,
          mbRecordingId: output.bestMatch.mbRecordingId,
          mbReleaseId: output.bestMatch.mbReleaseId,
          mbArtistId: output.bestMatch.mbArtistId,
        );

        // 写入歌词
        if (output.lyricText != null) {
          await writeLyric(path: path, lyricText: output.lyricText!);
        }

        // 写入封面
        if (output.coverData != null) {
          await writeCover(
            path: path,
            coverData: output.coverData!,
            mimeType: output.coverMimeType ?? 'image/jpeg',
          );
        }

        LOGGER.i("[MetadataService] Scraped data written to file: $path");
      } catch (e) {
        LOGGER.e("[MetadataService] Failed to write scraped data to file: $e");
      }
    }

    return output;
  }

  /// 获取缓存的元数据（优先从缓存读取，未命中则刮削）
  ///
  /// [audio] 音频对象
  /// [autoScrape] 缓存未命中时是否自动刮削
  Future<MetadataRecord?> getOrScrapeMetadata(
    Audio audio, {
    bool autoScrape = true,
  }) async {
    final audioId = await computeAudioId(audio);
    if (audioId == null) return null;

    // 先查缓存
    final cached = await MetadataStore.instance.getMetadata(audioId);
    if (cached != null) return cached;

    // 缓存未命中，自动刮削
    if (autoScrape) {
      await scrapeAndApply(audio: audio, writeToFile: false);
      return MetadataStore.instance.getMetadata(audioId);
    }

    return null;
  }

  /// 获取缓存的歌词（优先从缓存读取，未命中则刮削）
  Future<String?> getOrScrapeLyric(Audio audio, {bool autoScrape = true}) async {
    final audioId = await computeAudioId(audio);
    if (audioId == null) return null;

    // 先查缓存
    final cached = await MediaCache.instance.getLyric(audioId);
    if (cached != null) return cached.$1;

    // 缓存未命中，自动刮削
    if (autoScrape) {
      await scrapeAndApply(audio: audio, fetchCover: false, writeToFile: false);
      final lyric = await MediaCache.instance.getLyric(audioId);
      return lyric?.$1;
    }

    return null;
  }

  /// 获取缓存的封面（优先从缓存读取，未命中则刮削）
  Future<Uint8List?> getOrScrapeCover(Audio audio, {bool autoScrape = true}) async {
    final audioId = await computeAudioId(audio);
    if (audioId == null) return null;

    // 先查缓存
    final cached = await MediaCache.instance.getCover(audioId);
    if (cached != null) return cached.$1;

    // 缓存未命中，自动刮削
    if (autoScrape) {
      await scrapeAndApply(audio: audio, fetchLyric: false, writeToFile: false);
      final cover = await MediaCache.instance.getCover(audioId);
      return cover?.$1;
    }

    return null;
  }

  /// 检测图片 MIME 类型
  static String detectImageMimeType(Uint8List data) {
    if (data.length >= 3 && data[0] == 0xFF && data[1] == 0xD8) {
      return 'image/jpeg';
    }
    if (data.length >= 8 &&
        data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70) {
      return 'image/jpeg'; // JP2
    }
    if (data.length >= 4 &&
        data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) {
      return 'image/png';
    }
    if (data.length >= 4 &&
        data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) {
      return 'image/gif';
    }
    return 'image/jpeg'; // 默认
  }

  // ==================== 自动刮削相关 ====================

  /// 检查刮削结果是否与音频元数据完全匹配
  /// 完全匹配标准：标题、艺术家、专辑都相同（不区分大小写，忽略首尾空格）
  bool isExactMatch(Audio audio, ScrapeResult result) {
    final audioTitle = audio.title.trim().toLowerCase();
    final audioArtist = audio.artist.trim().toLowerCase();
    final audioAlbum = audio.album.trim().toLowerCase();

    final resultTitle = (result.title ?? '').trim().toLowerCase();
    final resultArtist = (result.artist ?? '').trim().toLowerCase();
    final resultAlbum = (result.album ?? '').trim().toLowerCase();

    // 标题必须匹配
    if (audioTitle != resultTitle) return false;

    // 艺术家匹配（允许刮削结果包含更多艺术家，但主要艺术家必须匹配）
    if (!resultArtist.contains(audioArtist) && !audioArtist.contains(resultArtist)) {
      return false;
    }

    // 专辑匹配（如果音频有专辑信息）
    if (audioAlbum.isNotEmpty && resultAlbum.isNotEmpty) {
      if (!resultAlbum.contains(audioAlbum) && !audioAlbum.contains(resultAlbum)) {
        return false;
      }
    }

    return true;
  }

  /// 自动刮削元数据（播放时后台调用）
  /// 只有当刮削结果与音频元数据完全匹配时，才会自动保存
  /// [audio] 音频对象
  /// [onScraped] 刮削完成回调，返回是否完全匹配和刮削结果
  Future<void> autoScrape(Audio audio, {
    Function(bool isExactMatch, ScrapeOutput? output)? onScraped,
  }) async {
    try {
      LOGGER.i("[MetadataService] Auto-scraping for: ${audio.title}");

      final audioId = await computeAudioId(audio);
      if (audioId == null) {
        LOGGER.w("[MetadataService] Cannot compute audioId for: ${audio.path}");
        onScraped?.call(false, null);
        return;
      }

      // 检查是否已有缓存
      final cached = await MetadataStore.instance.getMetadata(audioId);
      if (cached?.scrapedAt != null) {
        // 已经刮削过，不再重复刮削
        LOGGER.i("[MetadataService] Already scraped for: ${audio.title}");
        onScraped?.call(true, null);
        return;
      }

      // 执行刮削
      final output = await ScraperOrchestrator.instance.scrape(
        audioId: audioId,
        query: audio.title,
        artist: audio.artist,
        album: audio.album,
        fetchLyric: true,
        fetchCover: true,
      );

      if (output == null) {
        LOGGER.i("[MetadataService] No scrape results for: ${audio.title}");
        onScraped?.call(false, null);
        return;
      }

      // 检查是否完全匹配
      final exactMatch = isExactMatch(audio, output.bestMatch);

      if (exactMatch) {
        LOGGER.i("[MetadataService] Exact match found for: ${audio.title}, auto-saving");
        // 完全匹配，自动保存到缓存
        await MetadataStore.instance.upsertMetadata(MetadataRecord(
          audioId: audioId,
          filePath: audio.path,
          title: output.bestMatch.title,
          artist: output.bestMatch.artist,
          album: output.bestMatch.album,
          mbRecordingId: output.bestMatch.mbRecordingId,
          mbReleaseId: output.bestMatch.mbReleaseId,
          mbArtistId: output.bestMatch.mbArtistId,
          scraperSource: output.bestMatch.source,
          scrapedAt: DateTime.now(),
        ));
      } else {
        LOGGER.i("[MetadataService] No exact match for: ${audio.title}, "
            "audio=(${audio.title}, ${audio.artist}, ${audio.album}), "
            "result=(${output.bestMatch.title}, ${output.bestMatch.artist}, ${output.bestMatch.album})");
      }

      onScraped?.call(exactMatch, output);
    } catch (e) {
      LOGGER.e("[MetadataService] Auto-scrape failed: $e");
      onScraped?.call(false, null);
    }
  }
}
