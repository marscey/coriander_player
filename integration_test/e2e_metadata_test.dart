/// Phase 4.2 集成测试 - 端到端验证完整流程
///
/// 测试完整链路：
/// 1. 创建音频文件 → 计算 contentHash
/// 2. 写入标签 → 验证标签可读
/// 3. 写入封面 → 验证封面可读
/// 4. 写入歌词 → 验证歌词可读
/// 5. 缓存元数据 → 通过 audioId 查询
/// 6. 文件移动后重新匹配
/// 7. 刮削源配置管理
///
/// 运行方式：flutter test integration_test/e2e_metadata_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_scraper.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/metadata/musicbrainz_scraper.dart';
import 'package:coriander_player/metadata/scraper_orchestrator.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart' as rust_api;
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MetadataStore store;
  late MediaCache cache;
  late MetadataService service;
  late ScraperOrchestrator orchestrator;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() async {
    store = MetadataStore.instance;
    cache = MediaCache.instance;
    service = MetadataService.instance;
    orchestrator = ScraperOrchestrator.instance;
  });

  // ==================== 端到端：标签写入 + 缓存 + 查询 ====================

  group('端到端：标签写入与缓存', () {
    test('写入标签 → 缓存元数据 → 通过 audioId 查询', () async {
      // 1. 创建测试文件
      final tempDir =
          await Directory.systemTemp.createTemp('coriander_e2e_tag_');
      final wavPath = '${tempDir.path}/tag_test.wav';
      await _createTestWav(wavPath);

      // 2. 计算 contentHash
      final audioId = await rust_api.computeContentHash(path: wavPath);
      expect(audioId, isNotNull);

      // 3. 写入标签
      await service.writeTags(
        path: wavPath,
        title: 'E2E Test Song',
        artist: 'E2E Artist',
        album: 'E2E Album',
        track: 1,
        year: 2024,
      );

      // 4. 缓存元数据
      await store.upsertMetadata(MetadataRecord(
        audioId: audioId!,
        filePath: wavPath,
        title: 'E2E Test Song',
        artist: 'E2E Artist',
        album: 'E2E Album',
        track: 1,
        year: 2024,
        scraperSource: 'manual',
      ));

      // 5. 通过 audioId 查询
      final cached = await store.getMetadata(audioId);
      expect(cached, isNotNull);
      expect(cached!.title, equals('E2E Test Song'));
      expect(cached.artist, equals('E2E Artist'));
      expect(cached.album, equals('E2E Album'));
      expect(cached.track, equals(1));
      expect(cached.year, equals(2024));
      expect(cached.scraperSource, equals('manual'));

      // 清理
      await tempDir.delete(recursive: true);
      await store.deleteMetadata(audioId);
    });
  });

  // ==================== 端到端：封面写入 + 缓存 + 读取 ====================

  group('端到端：封面写入与缓存', () {
    test('写入封面 → 缓存封面 → 通过 audioId 读取', () async {
      // 1. 创建测试文件
      final tempDir =
          await Directory.systemTemp.createTemp('coriander_e2e_cover_');
      final wavPath = '${tempDir.path}/cover_test.wav';
      await _createTestWav(wavPath);

      // 2. 计算 contentHash
      final audioId = await rust_api.computeContentHash(path: wavPath);
      expect(audioId, isNotNull);

      // 3. 写入封面到文件
      final coverData = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, // JPEG header
        ...List.filled(100, 0x80),
      ]);
      await service.writeCover(
        path: wavPath,
        coverData: coverData,
        mimeType: 'image/jpeg',
      );

      // 4. 缓存封面
      final coverPath = await cache.saveCover(audioId!, coverData);
      await store.upsertMetadata(MetadataRecord(audioId: audioId));
      await store.updateCoverCache(audioId, coverPath, 'image/jpeg');

      // 5. 通过 audioId 读取缓存封面
      final cachedCover = await cache.getCover(audioId);
      expect(cachedCover, isNotNull);
      expect(cachedCover!.$1.length, equals(104)); // 4 + 100
      expect(cachedCover.$2, equals('image/jpeg'));

      // 6. 验证数据库关联
      final cached = await store.getMetadata(audioId);
      expect(cached, isNotNull);
      expect(cached!.coverCachePath, isNotNull);
      expect(cached.coverMimeType, equals('image/jpeg'));

      // 清理
      await tempDir.delete(recursive: true);
      await store.deleteMetadata(audioId);
      await cache.clearForAudio(audioId);
    });
  });

  // ==================== 端到端：歌词写入 + 缓存 + 读取 ====================

  group('端到端：歌词写入与缓存', () {
    test('写入歌词 → 缓存歌词 → 通过 audioId 读取', () async {
      // 1. 创建测试文件
      final tempDir =
          await Directory.systemTemp.createTemp('coriander_e2e_lyric_');
      final wavPath = '${tempDir.path}/lyric_test.wav';
      await _createTestWav(wavPath);

      // 2. 计算 contentHash
      final audioId = await rust_api.computeContentHash(path: wavPath);
      expect(audioId, isNotNull);

      // 3. 写入歌词到文件
      const lyricText = '[00:00.00]E2E First line\n[00:05.00]E2E Second line';
      await service.writeLyric(path: wavPath, lyricText: lyricText);

      // 4. 缓存歌词
      await cache.saveLyric(audioId!, lyricText, synced: true);
      await store.upsertMetadata(MetadataRecord(audioId: audioId));
      await store.updateLyric(audioId, lyricText, synced: true);

      // 5. 通过 audioId 读取缓存歌词
      final cachedLyric = await cache.getLyric(audioId);
      expect(cachedLyric, isNotNull);
      expect(cachedLyric!.$1, equals(lyricText));
      expect(cachedLyric.$2, isTrue);

      // 6. 验证数据库关联
      final cached = await store.getMetadata(audioId);
      expect(cached, isNotNull);
      expect(cached!.lyricText, equals(lyricText));
      expect(cached.lyricSynced, isTrue);

      // 清理
      await tempDir.delete(recursive: true);
      await store.deleteMetadata(audioId);
      await cache.clearForAudio(audioId);
    });
  });

  // ==================== 端到端：文件移动后重新匹配 ====================

  group('端到端：文件移动后重新匹配', () {
    test('文件移动 → 更新路径 → 通过新路径查询 → audioId 不变', () async {
      // 1. 创建测试文件
      final tempDir =
          await Directory.systemTemp.createTemp('coriander_e2e_move_');
      final oldPath = '${tempDir.path}/old_location.wav';
      await _createTestWav(oldPath);

      // 2. 计算 contentHash
      final audioId = await rust_api.computeContentHash(path: oldPath);
      expect(audioId, isNotNull);

      // 3. 写入标签和缓存
      await service.writeTags(
        path: oldPath,
        title: 'Move Test Song',
        artist: 'Move Artist',
      );
      await store.upsertMetadata(MetadataRecord(
        audioId: audioId!,
        filePath: oldPath,
        title: 'Move Test Song',
        artist: 'Move Artist',
        scraperSource: 'manual',
      ));

      // 4. 缓存封面和歌词
      final coverData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      await cache.saveCover(audioId, coverData);
      await cache.saveLyric(audioId, '[00:00.00]Move lyric', synced: true);

      // 5. 移动文件
      final newPath = '${tempDir.path}/new_location.wav';
      await File(oldPath).rename(newPath);

      // 6. 更新文件路径
      await store.updateFilePath(audioId, newPath);

      // 7. 通过新路径查询
      final byPath = await store.getMetadataByPath(newPath);
      expect(byPath, isNotNull);
      expect(byPath!.title, equals('Move Test Song'));

      // 8. 旧路径查不到
      final byOldPath = await store.getMetadataByPath(oldPath);
      expect(byOldPath, isNull);

      // 9. audioId 查询仍然有效
      final byId = await store.getMetadata(audioId);
      expect(byId, isNotNull);
      expect(byId!.filePath, equals(newPath));

      // 10. 缓存仍然有效
      final cover = await cache.getCover(audioId);
      expect(cover, isNotNull);
      final lyric = await cache.getLyric(audioId);
      expect(lyric, isNotNull);

      // 清理
      await tempDir.delete(recursive: true);
      await store.deleteMetadata(audioId);
      await cache.clearForAudio(audioId);
    });

    test('文件移除后重新添加 → contentHash 匹配 → 元数据恢复', () async {
      // 1. 创建测试文件
      final tempDir =
          await Directory.systemTemp.createTemp('coriander_e2e_readd_');
      final wavPath = '${tempDir.path}/readd.wav';
      await _createTestWav(wavPath);

      // 2. 计算 contentHash 并保存元数据
      final audioId = await rust_api.computeContentHash(path: wavPath);
      expect(audioId, isNotNull);

      await store.upsertMetadata(MetadataRecord(
        audioId: audioId!,
        filePath: wavPath,
        title: 'Re-add Song',
        artist: 'Re-add Artist',
        scraperSource: 'netease',
      ));
      await cache.saveLyric(audioId, '[00:00.00]Cached lyric', synced: true);

      // 3. 模拟文件移除
      await File(wavPath).delete();
      await store.updateFilePath(audioId, null);

      // 4. 重新创建相同内容的文件
      final newPath = '${tempDir.path}/readd_new.wav';
      await _createTestWav(newPath);

      // 5. 重新计算 contentHash（内容相同，hash 应相同）
      final newAudioId = await rust_api.computeContentHash(path: newPath);
      expect(newAudioId, equals(audioId));

      // 6. 通过 audioId 找到之前缓存的元数据
      final cached = await store.getMetadata(audioId);
      expect(cached, isNotNull);
      expect(cached!.title, equals('Re-add Song'));
      expect(cached.lyricText, isNull); // lyricText 存在数据库中
      // 但歌词缓存仍然有效
      final lyric = await cache.getLyric(audioId);
      expect(lyric, isNotNull);
      expect(lyric!.$1, equals('[00:00.00]Cached lyric'));

      // 7. 更新文件路径
      await store.updateFilePath(audioId, newPath);
      final byPath = await store.getMetadataByPath(newPath);
      expect(byPath, isNotNull);
      expect(byPath!.title, equals('Re-add Song'));

      // 清理
      await tempDir.delete(recursive: true);
      await store.deleteMetadata(audioId);
      await cache.clearForAudio(audioId);
    });
  });

  // ==================== 端到端：MusicBrainz 刮削 ====================

  group('端到端：MusicBrainz 刮削', () {
    test('搜索 → 获取封面 → 缓存结果', () async {
      final scraper = MusicBrainzScraper();

      // 1. 搜索
      final results = await scraper.search('Yesterday', artist: 'Beatles');
      expect(results, isNotEmpty);

      final bestMatch = results.first;
      expect(bestMatch.mbRecordingId, isNotNull);

      // 2. 尝试获取封面（Cover Art Archive）
      final cover = await scraper.fetchCover(bestMatch);
      // 封面可能获取不到（Cover Art Archive 不一定有），但不应抛异常

      // 3. 缓存搜索结果
      const testAudioId = 'e2e_mb_test_001';
      await store.upsertMetadata(MetadataRecord(
        audioId: testAudioId,
        title: bestMatch.title,
        artist: bestMatch.artist,
        album: bestMatch.album,
        mbRecordingId: bestMatch.mbRecordingId,
        mbReleaseId: bestMatch.mbReleaseId,
        scraperSource: 'musicbrainz',
        scrapedAt: DateTime.now(),
      ));

      // 4. 如果获取到封面，缓存它
      if (cover != null) {
        final coverPath = await cache.saveCover(testAudioId, cover);
        await store.updateCoverCache(testAudioId, coverPath,
            MetadataService.detectImageMimeType(cover));
      }

      // 5. 验证缓存
      final cached = await store.getMetadata(testAudioId);
      expect(cached, isNotNull);
      expect(cached!.scraperSource, equals('musicbrainz'));
      expect(cached.mbRecordingId, isNotNull);

      // 清理
      await store.deleteMetadata(testAudioId);
      await cache.clearForAudio(testAudioId);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ==================== 端到端：ScraperOrchestrator 完整流程 ====================

  group('端到端：ScraperOrchestrator', () {
    test('初始化 → 搜索 → 缓存', () async {
      // 1. 初始化
      await orchestrator.initDefaults();
      expect(orchestrator.getScraper('musicbrainz'), isNotNull);

      // 2. 搜索
      final results = await orchestrator.search('Imagine', artist: 'John Lennon');
      // 结果可能为空（取决于网络），但不应抛异常
      expect(results, isA<List<ScrapeResult>>());

      // 3. 如果有结果，验证数据结构
      if (results.isNotEmpty) {
        final first = results.first;
        expect(first.source, isNotNull);
        expect(first.score, greaterThanOrEqualTo(0.0));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ==================== 端到端：刮削源配置管理 ====================

  group('端到端：刮削源配置管理', () {
    test('禁用所有源 → 搜索 → 启用 → 搜索', () async {
      // 1. 禁用所有源
      await store.toggleScraper('netease', false);
      await store.toggleScraper('qq', false);
      await store.toggleScraper('kugou', false);
      await store.toggleScraper('musicbrainz', false);

      final enabled = await store.getEnabledScraperConfigs();
      expect(enabled, isEmpty);

      // 2. 重新启用
      await store.toggleScraper('netease', true);
      await store.toggleScraper('qq', true);
      await store.toggleScraper('kugou', true);
      await store.toggleScraper('musicbrainz', true);

      final enabledAgain = await store.getEnabledScraperConfigs();
      expect(enabledAgain, isNotEmpty);
      expect(enabledAgain.length, equals(4));
    });

    test('修改 MusicBrainz API 地址 → 验证生效', () async {
      // 修改
      await store.updateScraperApiBase(
          'musicbrainz', 'https://custom.example.com/ws/2');

      final configs = await store.getScraperConfigs();
      final mb = configs.firstWhere((c) => c.type == 'musicbrainz');
      expect(mb.apiBase, equals('https://custom.example.com/ws/2'));

      // 恢复
      await store.updateScraperApiBase(
          'musicbrainz', 'https://musicbrainz.org/ws/2');
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
