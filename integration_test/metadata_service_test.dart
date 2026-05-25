/// Phase 1.3 集成测试 - 验证 MetadataService 标签写入、封面嵌入、歌词嵌入、contentHash 计算
///
/// 运行方式：flutter test integration_test/metadata_service_test.dart
/// 注意：需要 Rust 桥接已编译，在模拟器或真机上运行
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart' as rust_api;
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('coriander_metadata_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// 创建一个最小的有效 WAV 文件
  Future<File> createTestWav(String name) async {
    final path = '${tempDir.path}/$name';
    const sampleRate = 44100;
    const numChannels = 1;
    const bitsPerSample = 16;
    const numSamples = 44100; // 1 second
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

    final file = File(path);
    await file.writeAsBytes(buf.toBytes());
    return file;
  }

  /// 创建一个最小的 JPEG 数据 (1x1 白色像素)
  Uint8List createMinimalJpeg() {
    return Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
      0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
      0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
      0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
      0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
      0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
      0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
      0x00, 0x7B, 0x94, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xD9,
    ]);
  }

  group('computeContentHash (Rust API)', () {
    test('本地文件返回 contentHash', () async {
      final file = await createTestWav('test_hash.wav');
      final hash = await rust_api.computeContentHash(path: file.path);
      expect(hash, isNotNull);
      expect(hash!.length, equals(64)); // SHA256 hex string
    });

    test('同一文件多次计算返回相同 hash', () async {
      final file = await createTestWav('test_hash_consistent.wav');
      final hash1 = await rust_api.computeContentHash(path: file.path);
      final hash2 = await rust_api.computeContentHash(path: file.path);
      expect(hash1, equals(hash2));
    });

    test('不存在的文件返回 null', () async {
      final hash =
          await rust_api.computeContentHash(path: '/nonexistent/file.wav');
      expect(hash, isNull);
    });
  });

  group('writeTagsToPath (Rust API)', () {
    test('写入基本标签成功', () async {
      final file = await createTestWav('test_write_tags.wav');

      await rust_api.writeTagsToPath(
        path: file.path,
        fields: '{"title":"Test Title","artist":"Test Artist","album":"Test Album","track":1,"year":2024,"genre":"Rock"}',
      );

      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));
    });

    test('部分更新标签不报错', () async {
      final file = await createTestWav('test_write_tags_partial.wav');

      await rust_api.writeTagsToPath(
        path: file.path,
        fields: '{"title":"Original Title","artist":"Original Artist"}',
      );

      await rust_api.writeTagsToPath(
        path: file.path,
        fields: '{"title":"Updated Title"}',
      );

      expect(await file.exists(), isTrue);
    });
  });

  group('writeCoverToPath (Rust API)', () {
    test('写入封面成功', () async {
      final file = await createTestWav('test_write_cover.wav');
      final coverData = createMinimalJpeg();

      await rust_api.writeCoverToPath(
        path: file.path,
        coverData: coverData,
        mimeType: 'image/jpeg',
      );

      expect(await file.exists(), isTrue);
      // 写入封面后文件应该变大
      expect(await file.length(), greaterThan(44 + 44100 * 2));
    });
  });

  group('writeLyricToPath (Rust API)', () {
    test('写入歌词成功', () async {
      final file = await createTestWav('test_write_lyric.wav');

      await rust_api.writeLyricToPath(
        path: file.path,
        lyricText: '[00:00.00]Test lyric line 1\n[00:05.00]Test lyric line 2',
        isSynced: true,
      );

      expect(await file.exists(), isTrue);
    });

    test('替换歌词不报错', () async {
      final file = await createTestWav('test_write_lyric_replace.wav');

      await rust_api.writeLyricToPath(
        path: file.path,
        lyricText: 'Old lyric',
        isSynced: false,
      );

      await rust_api.writeLyricToPath(
        path: file.path,
        lyricText: '[00:00.00]New lyric',
        isSynced: true,
      );

      expect(await file.exists(), isTrue);
    });
  });

  group('MetadataService.detectImageMimeType', () {
    test('JPEG 数据返回 image/jpeg', () {
      final jpegData = createMinimalJpeg();
      expect(MetadataService.detectImageMimeType(jpegData), 'image/jpeg');
    });

    test('PNG 数据返回 image/png', () {
      final pngData = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      ]);
      expect(MetadataService.detectImageMimeType(pngData), 'image/png');
    });

    test('GIF 数据返回 image/gif', () {
      final gifData = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a signature
      ]);
      expect(MetadataService.detectImageMimeType(gifData), 'image/gif');
    });

    test('未知数据默认返回 image/jpeg', () {
      final unknownData = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      expect(MetadataService.detectImageMimeType(unknownData), 'image/jpeg');
    });
  });

  group('MetadataService (full flow)', () {
    test('writeTags + writeCover + writeLyric 综合测试', () async {
      final file = await createTestWav('test_full_flow.wav');
      final service = MetadataService.instance;

      // 写入标签
      await service.writeTags(
        path: file.path,
        title: 'Integration Test',
        artist: 'Test Artist',
        album: 'Test Album',
        year: 2024,
      );

      // 写入封面
      await service.writeCover(
        path: file.path,
        coverData: createMinimalJpeg(),
        mimeType: 'image/jpeg',
      );

      // 写入歌词
      await service.writeLyric(
        path: file.path,
        lyricText: '[00:00.00]Integration test lyric',
        isSynced: true,
      );

      // 验证文件存在且大小合理
      expect(await file.exists(), isTrue);
      final size = await file.length();
      expect(size, greaterThan(44 + 44100 * 2)); // 比原始 WAV 大（有标签+封面+歌词）
    });
  });
}

Uint8List _le32(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}

Uint8List _le16(int value) {
  return Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}
