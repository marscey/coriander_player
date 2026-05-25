/// Phase 2.3 集成测试 - 验证数据库CRUD、缓存读写、文件移动后重新匹配
///
/// 运行方式：flutter test integration_test/metadata_store_test.dart
/// 注意：需要 Rust 桥接已编译，在模拟器或真机上运行
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart' as rust_api;
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MetadataStore store;
  late MediaCache cache;

  setUpAll(() async {
    await RustLib.init();
    // iOS模拟器使用sqflite原生实现，无需FFI初始化
  });

  setUp(() async {
    store = MetadataStore.instance;
    cache = MediaCache.instance;
    // 每个测试前清理缓存
    await cache.clearAll();
  });

  // ==================== MetadataStore CRUD 测试 ====================

  group('MetadataStore CRUD', () {
    test('插入和查询元数据', () async {
      final record = MetadataRecord(
        audioId: 'test_hash_001',
        filePath: '/music/test.mp3',
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        track: 1,
        year: 2024,
        genre: 'Rock',
      );

      await store.upsertMetadata(record);

      final retrieved = await store.getMetadata('test_hash_001');
      expect(retrieved, isNotNull);
      expect(retrieved!.audioId, equals('test_hash_001'));
      expect(retrieved.title, equals('Test Song'));
      expect(retrieved.artist, equals('Test Artist'));
      expect(retrieved.album, equals('Test Album'));
      expect(retrieved.track, equals(1));
      expect(retrieved.year, equals(2024));
      expect(retrieved.genre, equals('Rock'));
    });

    test('更新元数据（合并）', () async {
      // 先插入
      await store.upsertMetadata(MetadataRecord(
        audioId: 'test_hash_002',
        filePath: '/music/test2.mp3',
        title: 'Original Title',
        artist: 'Original Artist',
      ));

      // 更新部分字段
      await store.upsertMetadata(MetadataRecord(
        audioId: 'test_hash_002',
        title: 'Updated Title',
      ));

      final retrieved = await store.getMetadata('test_hash_002');
      expect(retrieved, isNotNull);
      expect(retrieved!.title, equals('Updated Title'));
      // 原有字段应保留
      expect(retrieved.artist, equals('Original Artist'));
      expect(retrieved.filePath, equals('/music/test2.mp3'));
    });

    test('按文件路径查询', () async {
      await store.upsertMetadata(MetadataRecord(
        audioId: 'test_hash_003',
        filePath: '/music/by_path.mp3',
        title: 'Path Test',
      ));

      final retrieved =
          await store.getMetadataByPath('/music/by_path.mp3');
      expect(retrieved, isNotNull);
      expect(retrieved!.audioId, equals('test_hash_003'));
    });

    test('更新文件路径（模拟文件移动）', () async {
      await store.upsertMetadata(MetadataRecord(
        audioId: 'test_hash_004',
        filePath: '/music/old_path.mp3',
        title: 'Move Test',
      ));

      // 模拟文件移动
      await store.updateFilePath('test_hash_004', '/music/new_path.mp3');

      // 旧路径查不到
      final oldPathResult =
          await store.getMetadataByPath('/music/old_path.mp3');
      expect(oldPathResult, isNull);

      // 新路径能查到
      final newPathResult =
          await store.getMetadataByPath('/music/new_path.mp3');
      expect(newPathResult, isNotNull);
      expect(newPathResult!.title, equals('Move Test'));

      // audioId 查询仍然有效
      final byId = await store.getMetadata('test_hash_004');
      expect(byId, isNotNull);
      expect(byId!.filePath, equals('/music/new_path.mp3'));
    });

    test('更新歌词', () async {
      await store.upsertMetadata(MetadataRecord(
        audioId: 'test_hash_005',
        title: 'Lyric Test',
      ));

      await store.updateLyric('test_hash_005', '[00:00.00]Hello',
          synced: true);

      final retrieved = await store.getMetadata('test_hash_005');
      expect(retrieved, isNotNull);
      expect(retrieved!.lyricText, equals('[00:00.00]Hello'));
      expect(retrieved.lyricSynced, isTrue);
    });

    test('更新封面缓存路径', () async {
      await store.upsertMetadata(MetadataRecord(
        audioId: 'test_hash_006',
        title: 'Cover Test',
      ));

      await store.updateCoverCache(
          'test_hash_006', '/cache/covers/test.jpg', 'image/jpeg');

      final retrieved = await store.getMetadata('test_hash_006');
      expect(retrieved, isNotNull);
      expect(retrieved!.coverCachePath, equals('/cache/covers/test.jpg'));
      expect(retrieved.coverMimeType, equals('image/jpeg'));
    });

    test('删除元数据', () async {
      await store.upsertMetadata(MetadataRecord(
        audioId: 'test_hash_007',
        title: 'Delete Test',
      ));

      await store.deleteMetadata('test_hash_007');

      final retrieved = await store.getMetadata('test_hash_007');
      expect(retrieved, isNull);
    });

    test('查询不存在的记录返回 null', () async {
      final result = await store.getMetadata('nonexistent_hash');
      expect(result, isNull);
    });
  });

  // ==================== 刮削源配置测试 ====================

  group('ScraperConfig', () {
    test('默认刮削源配置存在', () async {
      final configs = await store.getScraperConfigs();
      expect(configs, isNotEmpty);
      expect(configs.any((c) => c.type == 'netease'), isTrue);
      expect(configs.any((c) => c.type == 'qq'), isTrue);
      expect(configs.any((c) => c.type == 'kugou'), isTrue);
      expect(configs.any((c) => c.type == 'musicbrainz'), isTrue);
    });

    test('按优先级排序', () async {
      final configs = await store.getScraperConfigs();
      for (int i = 1; i < configs.length; i++) {
        expect(configs[i].priority, greaterThanOrEqualTo(configs[i - 1].priority));
      }
    });

    test('启用/禁用刮削源', () async {
      await store.toggleScraper('netease', false);

      final enabled = await store.getEnabledScraperConfigs();
      expect(enabled.every((c) => c.type != 'netease'), isTrue);

      await store.toggleScraper('netease', true);

      final enabledAgain = await store.getEnabledScraperConfigs();
      expect(enabledAgain.any((c) => c.type == 'netease'), isTrue);
    });

    test('更新 API 地址', () async {
      await store.updateScraperApiBase(
          'musicbrainz', 'https://custom-mb.example.com/ws/2');

      final configs = await store.getScraperConfigs();
      final mb = configs.firstWhere((c) => c.type == 'musicbrainz');
      expect(mb.apiBase, equals('https://custom-mb.example.com/ws/2'));
    });
  });

  // ==================== MediaCache 测试 ====================

  group('MediaCache - 封面', () {
    test('保存和读取封面', () async {
      final coverData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG header
      final path = await cache.saveCover('test_cover_001', coverData);

      expect(File(path).existsSync(), isTrue);

      final result = await cache.getCover('test_cover_001');
      expect(result, isNotNull);
      expect(result!.$1.length, equals(4));
      expect(result.$2, equals('image/jpeg'));
    });

    test('封面缓存存在性检查', () async {
      expect(await cache.hasCover('test_cover_002'), isFalse);

      await cache.saveCover(
          'test_cover_002', Uint8List.fromList([1, 2, 3]));

      expect(await cache.hasCover('test_cover_002'), isTrue);
    });

    test('删除封面缓存', () async {
      await cache.saveCover(
          'test_cover_003', Uint8List.fromList([1, 2, 3]));
      expect(await cache.hasCover('test_cover_003'), isTrue);

      await cache.deleteCover('test_cover_003');
      expect(await cache.hasCover('test_cover_003'), isFalse);
    });

    test('PNG 格式封面', () async {
      final pngData = Uint8List.fromList(
          [0x89, 0x50, 0x4E, 0x47]); // PNG header
      final path = await cache.saveCover(
          'test_cover_png', pngData,
          mimeType: 'image/png');

      expect(path.endsWith('.png'), isTrue);

      final result = await cache.getCover('test_cover_png');
      expect(result, isNotNull);
      expect(result!.$2, equals('image/png'));
    });
  });

  group('MediaCache - 歌词', () {
    test('保存和读取 LRC 歌词', () async {
      const lyric = '[00:00.00]First line\n[00:05.00]Second line';
      final path = await cache.saveLyric('test_lyric_001', lyric, synced: true);

      expect(path.endsWith('.lrc'), isTrue);
      expect(File(path).existsSync(), isTrue);

      final result = await cache.getLyric('test_lyric_001');
      expect(result, isNotNull);
      expect(result!.$1, equals(lyric));
      expect(result.$2, isTrue); // synced
    });

    test('保存和读取纯文本歌词', () async {
      const lyric = 'Plain text lyric without timestamps';
      final path =
          await cache.saveLyric('test_lyric_002', lyric, synced: false);

      expect(path.endsWith('.txt'), isTrue);

      final result = await cache.getLyric('test_lyric_002');
      expect(result, isNotNull);
      expect(result!.$1, equals(lyric));
      expect(result.$2, isFalse); // not synced
    });

    test('删除歌词缓存', () async {
      await cache.saveLyric('test_lyric_003', 'test', synced: true);
      expect(await cache.hasLyric('test_lyric_003'), isTrue);

      await cache.deleteLyric('test_lyric_003');
      expect(await cache.hasLyric('test_lyric_003'), isFalse);
    });
  });

  // ==================== 综合测试：文件移动后重新匹配 ====================

  group('文件移动后重新匹配', () {
    test('contentHash 不变，可重新匹配元数据', () async {
      // 1. 创建测试 WAV 文件
      final tempDir =
          await Directory.systemTemp.createTemp('coriander_move_test_');
      final wavPath1 = '${tempDir.path}/original.wav';
      await _createTestWav(wavPath1);

      // 2. 计算 contentHash
      final audioId = await rust_api.computeContentHash(path: wavPath1);
      expect(audioId, isNotNull);

      // 3. 保存元数据和缓存
      await store.upsertMetadata(MetadataRecord(
        audioId: audioId!,
        filePath: wavPath1,
        title: 'Move Test Song',
        artist: 'Move Test Artist',
      ));
      await cache.saveCover(audioId, Uint8List.fromList([0xFF, 0xD8, 0xFF]),
          mimeType: 'image/jpeg');
      await cache.saveLyric(audioId, '[00:00.00]Move test lyric',
          synced: true);

      // 4. 模拟文件移动（重命名）
      final wavPath2 = '${tempDir.path}/moved.wav';
      await File(wavPath1).rename(wavPath2);

      // 5. 更新文件路径
      await store.updateFilePath(audioId, wavPath2);

      // 6. 验证通过新路径可以找到元数据
      final byPath = await store.getMetadataByPath(wavPath2);
      expect(byPath, isNotNull);
      expect(byPath!.title, equals('Move Test Song'));

      // 7. 验证通过 audioId 仍然可以找到元数据
      final byId = await store.getMetadata(audioId);
      expect(byId, isNotNull);
      expect(byId!.filePath, equals(wavPath2));

      // 8. 验证封面和歌词缓存仍然有效
      final cover = await cache.getCover(audioId);
      expect(cover, isNotNull);

      final lyric = await cache.getLyric(audioId);
      expect(lyric, isNotNull);
      expect(lyric!.$1, equals('[00:00.00]Move test lyric'));

      // 清理
      await tempDir.delete(recursive: true);
      await store.deleteMetadata(audioId);
      await cache.clearForAudio(audioId);
    });

    test('文件移除后重新添加，通过 contentHash 匹配', () async {
      // 1. 创建测试 WAV 文件
      final tempDir =
          await Directory.systemTemp.createTemp('coriander_readd_test_');
      final wavPath = '${tempDir.path}/readd.wav';
      await _createTestWav(wavPath);

      // 2. 计算 contentHash 并保存元数据
      final audioId = await rust_api.computeContentHash(path: wavPath);
      expect(audioId, isNotNull);

      await store.upsertMetadata(MetadataRecord(
        audioId: audioId!,
        filePath: wavPath,
        title: 'Re-add Test',
        artist: 'Re-add Artist',
        lyricText: '[00:00.00]Cached lyric',
        lyricSynced: true,
      ));

      // 3. 模拟文件从音乐库移除（删除文件，但元数据保留）
      await File(wavPath).delete();
      await store.updateFilePath(audioId, null);

      // 4. 模拟文件重新添加（重新创建相同内容的文件）
      final wavPath2 = '${tempDir.path}/readd_new_location.wav';
      await _createTestWav(wavPath2);

      // 5. 重新计算 contentHash（内容相同，hash 应相同）
      final newAudioId =
          await rust_api.computeContentHash(path: wavPath2);
      expect(newAudioId, equals(audioId));

      // 6. 通过 audioId 找到之前缓存的元数据
      final cached = await store.getMetadata(audioId!);
      expect(cached, isNotNull);
      expect(cached!.title, equals('Re-add Test'));
      expect(cached.lyricText, equals('[00:00.00]Cached lyric'));

      // 7. 更新文件路径
      await store.updateFilePath(audioId, wavPath2);

      // 清理
      await tempDir.delete(recursive: true);
      await store.deleteMetadata(audioId);
    });
  });

  group('缓存管理', () {
    test('清理指定音频的缓存', () async {
      await cache.saveCover('clean_test', Uint8List.fromList([1, 2, 3]));
      await cache.saveLyric('clean_test', 'test lyric', synced: true);

      expect(await cache.hasCover('clean_test'), isTrue);
      expect(await cache.hasLyric('clean_test'), isTrue);

      await cache.clearForAudio('clean_test');

      expect(await cache.hasCover('clean_test'), isFalse);
      expect(await cache.hasLyric('clean_test'), isFalse);
    });

    test('缓存大小统计', () async {
      final sizeBefore = await cache.getCacheSize();

      await cache.saveCover(
          'size_test', Uint8List.fromList(List.filled(1024, 0)));
      await cache.saveLyric('size_test', 'x' * 512, synced: true);

      final sizeAfter = await cache.getCacheSize();
      expect(sizeAfter, greaterThan(sizeBefore));

      // 清理
      await cache.clearForAudio('size_test');
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
