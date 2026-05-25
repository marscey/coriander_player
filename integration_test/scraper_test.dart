/// Phase 3.2 集成测试 - 验证刮削源接口、API调用、结果缓存
///
/// 运行方式：flutter test integration_test/scraper_test.dart
/// 注意：需要 Rust 桥接已编译，在模拟器或真机上运行
/// MusicBrainz 测试需要网络连接
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_scraper.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/metadata/musicbrainz_scraper.dart';
import 'package:coriander_player/metadata/scraper_orchestrator.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart' as rust_api;
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MetadataStore store;
  late MediaCache cache;
  late ScraperOrchestrator orchestrator;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() async {
    store = MetadataStore.instance;
    cache = MediaCache.instance;
    orchestrator = ScraperOrchestrator.instance;
  });

  // ==================== ScrapeResult 数据结构测试 ====================

  group('ScrapeResult', () {
    test('创建和字段访问', () {
      final result = ScrapeResult(
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        score: 0.85,
        source: 'netease',
        platformIds: {'neteaseSongId': '12345'},
      );

      expect(result.title, equals('Test Song'));
      expect(result.artist, equals('Test Artist'));
      expect(result.album, equals('Test Album'));
      expect(result.score, equals(0.85));
      expect(result.source, equals('netease'));
      expect(result.platformIds['neteaseSongId'], equals('12345'));
    });

    test('copyWith 正确覆盖字段', () {
      final result = ScrapeResult(
        title: 'Original',
        artist: 'Artist1',
        score: 0.5,
        source: 'qq',
      );

      final copied = result.copyWith(
        title: 'Updated',
        score: 0.9,
      );

      expect(copied.title, equals('Updated'));
      expect(copied.artist, equals('Artist1')); // 保留原值
      expect(copied.score, equals(0.9));
      expect(copied.source, equals('qq')); // 保留原值
    });

    test('toString 包含关键信息', () {
      final result = ScrapeResult(
        title: 'Song',
        artist: 'Art',
        album: 'Alb',
        score: 0.75,
        source: 'kugou',
      );

      final str = result.toString();
      expect(str, contains('kugou'));
      expect(str, contains('Song'));
      expect(str, contains('0.750'));
    });
  });

  // ==================== MetadataScraper 接口合规性测试 ====================

  group('MetadataScraper 接口', () {
    test('MusicBrainzScraper 属性正确', () {
      final scraper = MusicBrainzScraper();

      expect(scraper.id, equals('musicbrainz'));
      expect(scraper.name, equals('MusicBrainz'));
    });

    test('MusicBrainzScraper 自定义 apiBase', () {
      final scraper = MusicBrainzScraper(
        apiBase: 'https://custom-mb.example.com/ws/2',
      );

      expect(scraper.apiBase, equals('https://custom-mb.example.com/ws/2'));
    });

    test('MusicBrainzScraper fetchLyric 返回 null（不支持歌词）', () async {
      final scraper = MusicBrainzScraper();
      final result = ScrapeResult(
        source: 'musicbrainz',
        platformIds: {'mbRecordingId': 'test-id'},
      );

      final lyric = await scraper.fetchLyric(result);
      expect(lyric, isNull);
    });
  });

  // ==================== ScraperOrchestrator 调度逻辑测试 ====================

  group('ScraperOrchestrator', () {
    test('注册和获取刮削源', () {
      final scraper = MusicBrainzScraper();
      orchestrator.registerScraper(scraper);

      final retrieved = orchestrator.getScraper('musicbrainz');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('musicbrainz'));
    });

    test('获取未注册的刮削源返回 null', () {
      final retrieved = orchestrator.getScraper('nonexistent');
      expect(retrieved, isNull);
    });

    test('initDefaults 注册所有刮削源', () async {
      await orchestrator.initDefaults();

      // 验证默认启用的刮削源已注册
      expect(orchestrator.getScraper('netease'), isNotNull);
      expect(orchestrator.getScraper('qq'), isNotNull);
      expect(orchestrator.getScraper('kugou'), isNotNull);
      expect(orchestrator.getScraper('musicbrainz'), isNotNull);
    });
  });

  // ==================== MusicBrainz API 测试（需要网络） ====================

  group('MusicBrainz API', () {
    late MusicBrainzScraper scraper;

    setUp(() {
      scraper = MusicBrainzScraper();
    });

    test('搜索知名歌曲', () async {
      // 使用一首非常知名的歌曲进行测试
      final results = await scraper.search('Yesterday', artist: 'Beatles');

      // 应该有搜索结果
      expect(results, isNotEmpty);

      // 第一个结果应该包含基本信息
      final first = results.first;
      expect(first.title, isNotNull);
      expect(first.title!.isNotEmpty, isTrue);
      expect(first.source, equals('musicbrainz'));
      expect(first.mbRecordingId, isNotNull);
      expect(first.score, greaterThan(0.0));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('搜索结果包含 MusicBrainz ID', () async {
      final results = await scraper.search('Bohemian Rhapsody', artist: 'Queen');

      if (results.isNotEmpty) {
        final first = results.first;
        // 至少应有 mbRecordingId
        expect(
          first.mbRecordingId != null || first.platformIds['mbRecordingId'] != null,
          isTrue,
        );
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('搜索中文歌曲', () async {
      final results = await scraper.search('晴天', artist: '周杰伦');

      // MusicBrainz 可能没有中文歌曲，但不应抛出异常
      // 结果可以为空
      expect(results, isA<List<ScrapeResult>>());
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('搜索无结果的关键词', () async {
      final results = await scraper.search('xyznonexistentsong12345');

      // 可能返回空列表
      expect(results, isA<List<ScrapeResult>>());
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  // ==================== 刮削结果缓存测试 ====================

  group('刮削结果缓存', () {
    test('搜索结果可存入 MetadataStore', () async {
      final result = ScrapeResult(
        title: 'Cached Song',
        artist: 'Cached Artist',
        album: 'Cached Album',
        score: 0.9,
        source: 'netease',
        mbRecordingId: 'mb-rec-123',
        mbReleaseId: 'mb-rel-456',
        platformIds: {'neteaseSongId': '789'},
      );

      // 存入数据库
      await store.upsertMetadata(MetadataRecord(
        audioId: 'scrape_cache_test_001',
        filePath: '/test/cached.mp3',
        title: result.title,
        artist: result.artist,
        album: result.album,
        mbRecordingId: result.mbRecordingId,
        mbReleaseId: result.mbReleaseId,
        scraperSource: result.source,
        scrapedAt: DateTime.now(),
      ));

      // 读取验证
      final cached = await store.getMetadata('scrape_cache_test_001');
      expect(cached, isNotNull);
      expect(cached!.title, equals('Cached Song'));
      expect(cached.artist, equals('Cached Artist'));
      expect(cached.mbRecordingId, equals('mb-rec-123'));
      expect(cached.scraperSource, equals('netease'));

      // 清理
      await store.deleteMetadata('scrape_cache_test_001');
    });

    test('封面缓存与刮削结果关联', () async {
      const audioId = 'scrape_cover_test_001';

      // 模拟刮削获取的封面数据
      final coverData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final coverPath = await cache.saveCover(audioId, coverData);

      // 更新数据库记录
      await store.upsertMetadata(MetadataRecord(
        audioId: audioId,
        title: 'Cover Test Song',
        scraperSource: 'qq',
      ));
      await store.updateCoverCache(audioId, coverPath, 'image/jpeg');

      // 验证关联
      final cached = await store.getMetadata(audioId);
      expect(cached, isNotNull);
      expect(cached!.coverCachePath, isNotNull);

      final cover = await cache.getCover(audioId);
      expect(cover, isNotNull);
      expect(cover!.$1.length, equals(6));

      // 清理
      await store.deleteMetadata(audioId);
      await cache.clearForAudio(audioId);
    });

    test('歌词缓存与刮削结果关联', () async {
      const audioId = 'scrape_lyric_test_001';

      // 模拟刮削获取的歌词
      const lyricText = '[00:00.00]First line\n[00:05.00]Second line';
      await cache.saveLyric(audioId, lyricText, synced: true);

      // 更新数据库记录
      await store.upsertMetadata(MetadataRecord(
        audioId: audioId,
        title: 'Lyric Test Song',
        scraperSource: 'kugou',
      ));
      await store.updateLyric(audioId, lyricText, synced: true);

      // 验证关联
      final cached = await store.getMetadata(audioId);
      expect(cached, isNotNull);
      expect(cached!.lyricText, equals(lyricText));
      expect(cached.lyricSynced, isTrue);

      final lyric = await cache.getLyric(audioId);
      expect(lyric, isNotNull);
      expect(lyric!.$1, equals(lyricText));
      expect(lyric.$2, isTrue);

      // 清理
      await store.deleteMetadata(audioId);
      await cache.clearForAudio(audioId);
    });
  });

  // ==================== 刮削源配置测试 ====================

  group('刮削源配置与调度', () {
    test('禁用刮削源后不参与搜索', () async {
      // 禁用所有国内源
      await store.toggleScraper('netease', false);
      await store.toggleScraper('qq', false);
      await store.toggleScraper('kugou', false);

      final enabled = await store.getEnabledScraperConfigs();
      expect(enabled.every((c) => c.type != 'netease'), isTrue);
      expect(enabled.every((c) => c.type != 'qq'), isTrue);
      expect(enabled.every((c) => c.type != 'kugou'), isTrue);

      // 恢复
      await store.toggleScraper('netease', true);
      await store.toggleScraper('qq', true);
      await store.toggleScraper('kugou', true);
    });

    test('更新 MusicBrainz API 地址', () async {
      await store.updateScraperApiBase(
        'musicbrainz', 'https://custom-mb.example.com/ws/2');

      final configs = await store.getScraperConfigs();
      final mb = configs.firstWhere((c) => c.type == 'musicbrainz');
      expect(mb.apiBase, equals('https://custom-mb.example.com/ws/2'));

      // 恢复默认
      await store.updateScraperApiBase('musicbrainz', 'https://musicbrainz.org/ws/2');
    });

    test('优先级排序正确', () async {
      final configs = await store.getEnabledScraperConfigs();

      // 验证按优先级排序
      for (int i = 1; i < configs.length; i++) {
        expect(
          configs[i].priority,
          greaterThanOrEqualTo(configs[i - 1].priority),
        );
      }

      // 网易云应优先于 QQ，QQ 优先于酷狗
      if (configs.length >= 3) {
        final neteaseIdx = configs.indexWhere((c) => c.type == 'netease');
        final qqIdx = configs.indexWhere((c) => c.type == 'qq');
        final kugouIdx = configs.indexWhere((c) => c.type == 'kugou');

        if (neteaseIdx >= 0 && qqIdx >= 0) {
          expect(neteaseIdx, lessThan(qqIdx));
        }
        if (qqIdx >= 0 && kugouIdx >= 0) {
          expect(qqIdx, lessThan(kugouIdx));
        }
      }
    });
  });

  // ==================== contentHash 与刮削集成测试 ====================

  group('contentHash 与刮削集成', () {
    test('contentHash 可作为 audioId 关联刮削结果', () async {
      // 创建测试 WAV 文件
      final tempDir =
          await Directory.systemTemp.createTemp('coriander_scrape_test_');
      final wavPath = '${tempDir.path}/test.wav';
      await _createTestWav(wavPath);

      // 计算 contentHash
      final audioId = await rust_api.computeContentHash(path: wavPath);
      expect(audioId, isNotNull);

      // 模拟刮削结果存入数据库
      await store.upsertMetadata(MetadataRecord(
        audioId: audioId!,
        filePath: wavPath,
        title: 'Scraped Title',
        artist: 'Scraped Artist',
        album: 'Scraped Album',
        scraperSource: 'netease',
        scrapedAt: DateTime.now(),
      ));

      // 通过 contentHash 查询刮削结果
      final cached = await store.getMetadata(audioId);
      expect(cached, isNotNull);
      expect(cached!.title, equals('Scraped Title'));
      expect(cached.scraperSource, equals('netease'));

      // 清理
      await tempDir.delete(recursive: true);
      await store.deleteMetadata(audioId);
    });
  });
}

/// 创建测试 WAV 文件
Future<void> _createTestWav(String path) async {
  const sampleRate = 44100;
  const numChannels = 1;
  const bitsPerSample = 16;
  const numSamples = 44100;
  const dataSize = numSamples * numChannels * (bitsPerSample ~/ 2);

  final buf = BytesBuilder();
  buf.add([0x52, 0x49, 0x46, 0x46]); // "RIFF"
  buf.add(_le32(36 + dataSize));
  buf.add([0x57, 0x41, 0x56, 0x45]); // "WAVE"
  buf.add([0x66, 0x6D, 0x74, 0x20]); // "fmt "
  buf.add(_le32(16));
  buf.add(_le16(1)); // PCM
  buf.add(_le16(numChannels));
  buf.add(_le32(sampleRate));
  buf.add(_le32(sampleRate * numChannels * bitsPerSample ~/ 8));
  buf.add(_le16(numChannels * bitsPerSample ~/ 8));
  buf.add(_le16(bitsPerSample));
  buf.add([0x64, 0x61, 0x74, 0x61]); // "data"
  buf.add(_le32(dataSize));
  buf.add(List.filled(dataSize, 0));

  await File(path).writeAsBytes(buf.toBytes());
}

Uint8List _le32(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}

Uint8List _le16(int value) {
  return Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}
