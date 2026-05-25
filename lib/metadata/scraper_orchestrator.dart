import 'dart:typed_data';

import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_scraper.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/metadata/chinese_scrapers.dart';
import 'package:coriander_player/metadata/musicbrainz_scraper.dart';
import 'package:coriander_player/utils.dart';

/// 刮削结果（包含完整数据）
class ScrapeOutput {
  final ScrapeResult bestMatch;
  final String? lyricText;
  final Uint8List? coverData;
  final String? coverMimeType;

  const ScrapeOutput({
    required this.bestMatch,
    this.lyricText,
    this.coverData,
    this.coverMimeType,
  });
}

/// 刮削调度器
///
/// 统一管理所有刮削源，按优先级调度搜索、歌词获取、封面获取。
/// 支持降级策略：高优先级源失败后自动尝试下一个源。
class ScraperOrchestrator {
  static ScraperOrchestrator? _instance;
  final Map<String, MetadataScraper> _scrapers = {};

  ScraperOrchestrator._();

  static ScraperOrchestrator get instance {
    _instance ??= ScraperOrchestrator._();
    return _instance!;
  }

  /// 注册刮削源
  void registerScraper(MetadataScraper scraper) {
    _scrapers[scraper.id] = scraper;
    LOGGER.i("[ScraperOrchestrator] Registered scraper: ${scraper.id} (${scraper.name})");
  }

  /// 获取已注册的刮削源
  MetadataScraper? getScraper(String id) => _scrapers[id];

  /// 初始化默认刮削源
  Future<void> initDefaults() async {
    LOGGER.i("[ScraperOrchestrator] initDefaults START");

    // 从数据库读取配置
    final configs = await MetadataStore.instance.getScraperConfigs();
    LOGGER.i("[ScraperOrchestrator] Loaded ${configs.length} scraper configs from DB");

    // 如果没有配置，插入默认配置
    if (configs.isEmpty) {
      LOGGER.i("[ScraperOrchestrator] No configs found, using hardcoded defaults");
      // 直接注册所有默认刮削源
      registerScraper(NeteaseScraper());
      registerScraper(QQScraper());
      registerScraper(KuGouScraper());
      registerScraper(MusicBrainzScraper());
    } else {
      // 注册国内刮削源
      if (configs.any((c) => c.type == 'netease' && c.enabled)) {
        registerScraper(NeteaseScraper());
      }
      if (configs.any((c) => c.type == 'qq' && c.enabled)) {
        registerScraper(QQScraper());
      }
      if (configs.any((c) => c.type == 'kugou' && c.enabled)) {
        registerScraper(KuGouScraper());
      }
      if (configs.any((c) => c.type == 'musicbrainz' && c.enabled)) {
        final mbConfig = configs.firstWhere((c) => c.type == 'musicbrainz');
        registerScraper(MusicBrainzScraper(
          apiBase: mbConfig.apiBase ?? 'https://musicbrainz.org/ws/2',
        ));
      }
    }

    LOGGER.i("[ScraperOrchestrator] Initialized with ${_scrapers.length} scrapers: ${_scrapers.keys.toList()}");
  }

  /// 搜索元数据
  ///
  /// 按优先级依次搜索所有已启用的刮削源，合并结果并按匹配度排序。
  /// [query] 搜索关键词
  /// [artist] 可选艺术家名
  /// [album] 可选专辑名
  Future<List<ScrapeResult>> search(
    String query, {
    String? artist,
    String? album,
  }) async {
    final configs = await MetadataStore.instance.getEnabledScraperConfigs();
    final allResults = <ScrapeResult>[];

    // 按优先级依次搜索
    for (final config in configs) {
      final scraper = _scrapers[config.type];
      if (scraper == null) continue;

      try {
        final results = await scraper.search(query, artist: artist, album: album);
        allResults.addAll(results);
      } catch (e) {
        LOGGER.e("[ScraperOrchestrator] ${config.type} search failed: $e");
      }
    }

    // 按匹配度排序
    allResults.sort((a, b) => b.score.compareTo(a.score));
    return allResults;
  }

  /// 完整刮削流程：搜索 → 获取歌词 → 获取封面 → 缓存结果
  ///
  /// [audioId] 音频ID（contentHash）
  /// [query] 搜索关键词
  /// [artist] 可选艺术家名
  /// [album] 可选专辑名
  /// [fetchLyric] 是否获取歌词
  /// [fetchCover] 是否获取封面
  Future<ScrapeOutput?> scrape({
    required String audioId,
    required String query,
    String? artist,
    String? album,
    bool fetchLyric = true,
    bool fetchCover = true,
  }) async {
    // 1. 搜索
    final results = await search(query, artist: artist, album: album);
    if (results.isEmpty) {
      LOGGER.i("[ScraperOrchestrator] No results found for: $query");
      return null;
    }

    final bestMatch = results.first;
    LOGGER.i("[ScraperOrchestrator] Best match: ${bestMatch.title} by ${bestMatch.artist} "
        "(score: ${bestMatch.score.toStringAsFixed(3)}, source: ${bestMatch.source})");

    // 2. 获取歌词
    String? lyricText;
    if (fetchLyric) {
      lyricText = await _fetchLyricWithFallback(bestMatch, results);
      if (lyricText != null) {
        // 缓存歌词
        await MediaCache.instance.saveLyric(audioId, lyricText, synced: true);
        await MetadataStore.instance.updateLyric(audioId, lyricText, synced: true);
        LOGGER.i("[ScraperOrchestrator] Lyric cached for: $audioId");
      }
    }

    // 3. 获取封面
    Uint8List? coverData;
    String? coverMimeType;
    if (fetchCover) {
      final coverResult = await _fetchCoverWithFallback(bestMatch, results);
      if (coverResult != null) {
        coverData = coverResult.$1;
        coverMimeType = coverResult.$2;
        // 缓存封面
        final coverPath = await MediaCache.instance.saveCover(
          audioId, coverData, mimeType: coverMimeType,
        );
        await MetadataStore.instance.updateCoverCache(audioId, coverPath, coverMimeType);
        LOGGER.i("[ScraperOrchestrator] Cover cached for: $audioId (${coverData.length} bytes)");
      }
    }

    // 4. 更新元数据记录
    await MetadataStore.instance.upsertMetadata(MetadataRecord(
      audioId: audioId,
      title: bestMatch.title,
      artist: bestMatch.artist,
      album: bestMatch.album,
      mbRecordingId: bestMatch.mbRecordingId,
      mbReleaseId: bestMatch.mbReleaseId,
      mbArtistId: bestMatch.mbArtistId,
      scraperSource: bestMatch.source,
      scrapedAt: DateTime.now(),
    ));

    return ScrapeOutput(
      bestMatch: bestMatch,
      lyricText: lyricText,
      coverData: coverData,
      coverMimeType: coverMimeType,
    );
  }

  /// 获取歌词（带降级策略）
  Future<String?> _fetchLyricWithFallback(
    ScrapeResult bestMatch,
    List<ScrapeResult> allResults,
  ) async {
    // 先尝试最佳匹配的源
    final scraper = _scrapers[bestMatch.source];
    if (scraper != null) {
      final lyric = await scraper.fetchLyric(bestMatch);
      if (lyric != null) return lyric;
    }

    // 降级：尝试其他源的结果
    for (final result in allResults) {
      if (result.source == bestMatch.source) continue;
      final fallbackScraper = _scrapers[result.source];
      if (fallbackScraper == null) continue;

      final lyric = await fallbackScraper.fetchLyric(result);
      if (lyric != null) return lyric;
    }

    return null;
  }

  /// 获取封面（带降级策略）
  Future<(Uint8List, String)?> _fetchCoverWithFallback(
    ScrapeResult bestMatch,
    List<ScrapeResult> allResults,
  ) async {
    // 先尝试最佳匹配的源
    final scraper = _scrapers[bestMatch.source];
    if (scraper != null) {
      final cover = await scraper.fetchCover(bestMatch);
      if (cover != null) {
        final mimeType = MetadataService.detectImageMimeType(cover);
        return (cover, mimeType);
      }
    }

    // 降级：尝试其他源的结果
    for (final result in allResults) {
      if (result.source == bestMatch.source) continue;
      final fallbackScraper = _scrapers[result.source];
      if (fallbackScraper == null) continue;

      final cover = await fallbackScraper.fetchCover(result);
      if (cover != null) {
        final mimeType = MetadataService.detectImageMimeType(cover);
        return (cover, mimeType);
      }
    }

    return null;
  }
}
