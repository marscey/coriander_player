import 'dart:io';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 封面和歌词本地缓存管理
/// 缓存目录结构：
///   cache_dir/
///     covers/
///       {audioId}.jpg / {audioId}.png
///     lyrics/
///       {audioId}.lrc
///       {audioId}.txt
class MediaCache {
  static MediaCache? _instance;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Directory? _cacheDir;

  MediaCache._();

  static MediaCache get instance {
    _instance ??= MediaCache._();
    return _instance!;
  }

  /// 获取缓存根目录
  Future<Directory> get cacheDir async {
    if (_cacheDir != null) return _cacheDir!;

    final appDir = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(appDir.path, 'media_cache'));

    if (!_cacheDir!.existsSync()) {
      _cacheDir!.createSync(recursive: true);
      _log.i('[MediaCache] Created cache directory: ${_cacheDir!.path}');
    }

    return _cacheDir!;
  }

  /// 获取封面缓存目录
  Future<Directory> get coversDir async {
    final dir = Directory(p.join((await cacheDir).path, 'covers'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 获取歌词缓存目录
  Future<Directory> get lyricsDir async {
    final dir = Directory(p.join((await cacheDir).path, 'lyrics'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  // ==================== 封面缓存 ====================

  /// 保存封面到缓存
  /// 返回缓存文件路径
  Future<String> saveCover(String audioId, Uint8List data,
      {String mimeType = 'image/jpeg'}) async {
    final dir = await coversDir;
    final ext = _mimeTypeToExtension(mimeType);
    final file = File(p.join(dir.path, '$audioId$ext'));

    await file.writeAsBytes(data);
    _log.i('[MediaCache] Cover saved: ${file.path} (${data.length} bytes)');

    // 如果存在其他格式的旧缓存，删除
    await _cleanupOldCoverCache(audioId, ext);

    return file.path;
  }

  /// 获取缓存的封面
  /// 返回 (Uint8List, mimeType) 或 null
  Future<(Uint8List, String)?> getCover(String audioId) async {
    final dir = await coversDir;

    // 尝试各种图片格式
    for (final ext in ['.jpg', '.png', '.webp', '.bmp']) {
      final file = File(p.join(dir.path, '$audioId$ext'));
      if (file.existsSync()) {
        final data = await file.readAsBytes();
        final mimeType = _extensionToMimeType(ext);
        return (Uint8List.fromList(data), mimeType);
      }
    }

    return null;
  }

  /// 获取缓存的封面文件路径
  Future<String?> getCoverPath(String audioId) async {
    final dir = await coversDir;

    for (final ext in ['.jpg', '.png', '.webp', '.bmp']) {
      final file = File(p.join(dir.path, '$audioId$ext'));
      if (file.existsSync()) {
        return file.path;
      }
    }

    return null;
  }

  /// 删除封面缓存
  Future<bool> deleteCover(String audioId) async {
    final dir = await coversDir;
    bool deleted = false;

    for (final ext in ['.jpg', '.png', '.webp', '.bmp']) {
      final file = File(p.join(dir.path, '$audioId$ext'));
      if (file.existsSync()) {
        await file.delete();
        deleted = true;
      }
    }

    if (deleted) {
      _log.i('[MediaCache] Cover deleted for: $audioId');
    }
    return deleted;
  }

  /// 检查封面缓存是否存在
  Future<bool> hasCover(String audioId) async {
    final path = await getCoverPath(audioId);
    return path != null;
  }

  // ==================== 歌词缓存 ====================

  /// 保存歌词到缓存
  /// synced=true 保存为 .lrc，synced=false 保存为 .txt
  /// 返回缓存文件路径
  Future<String> saveLyric(String audioId, String lyricText,
      {bool synced = true}) async {
    final dir = await lyricsDir;
    final ext = synced ? '.lrc' : '.txt';
    final file = File(p.join(dir.path, '$audioId$ext'));

    await file.writeAsString(lyricText);
    _log.i('[MediaCache] Lyric saved: ${file.path}');

    // 如果存在其他格式的旧缓存，删除
    await _cleanupOldLyricCache(audioId, ext);

    return file.path;
  }

  /// 获取缓存的歌词
  /// 返回 (lyricText, isSynced) 或 null
  Future<(String, bool)?> getLyric(String audioId) async {
    final dir = await lyricsDir;

    // 优先返回 .lrc 格式
    final lrcFile = File(p.join(dir.path, '$audioId.lrc'));
    if (lrcFile.existsSync()) {
      final text = await lrcFile.readAsString();
      return (text, true);
    }

    final txtFile = File(p.join(dir.path, '$audioId.txt'));
    if (txtFile.existsSync()) {
      final text = await txtFile.readAsString();
      return (text, false);
    }

    return null;
  }

  /// 获取缓存的歌词文件路径
  Future<String?> getLyricPath(String audioId) async {
    final dir = await lyricsDir;

    final lrcFile = File(p.join(dir.path, '$audioId.lrc'));
    if (lrcFile.existsSync()) return lrcFile.path;

    final txtFile = File(p.join(dir.path, '$audioId.txt'));
    if (txtFile.existsSync()) return txtFile.path;

    return null;
  }

  /// 删除歌词缓存
  Future<bool> deleteLyric(String audioId) async {
    final dir = await lyricsDir;
    bool deleted = false;

    for (final ext in ['.lrc', '.txt']) {
      final file = File(p.join(dir.path, '$audioId$ext'));
      if (file.existsSync()) {
        await file.delete();
        deleted = true;
      }
    }

    if (deleted) {
      _log.i('[MediaCache] Lyric deleted for: $audioId');
    }
    return deleted;
  }

  /// 检查歌词缓存是否存在
  Future<bool> hasLyric(String audioId) async {
    final path = await getLyricPath(audioId);
    return path != null;
  }

  // ==================== 缓存管理 ====================

  /// 获取缓存总大小（字节）
  Future<int> getCacheSize() async {
    final dir = await cacheDir;
    if (!dir.existsSync()) return 0;

    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// 清理所有缓存
  Future<void> clearAll() async {
    final dir = await cacheDir;
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      dir.createSync(recursive: true);
      _log.i('[MediaCache] All cache cleared');
    }
  }

  /// 清理指定 audioId 的所有缓存
  Future<void> clearForAudio(String audioId) async {
    await deleteCover(audioId);
    await deleteLyric(audioId);
  }

  // ==================== 私有方法 ====================

  /// 清理旧格式的封面缓存
  Future<void> _cleanupOldCoverCache(String audioId, String currentExt) async {
    final dir = await coversDir;
    for (final ext in ['.jpg', '.png', '.webp', '.bmp']) {
      if (ext == currentExt) continue;
      final file = File(p.join(dir.path, '$audioId$ext'));
      if (file.existsSync()) {
        await file.delete();
        _log.d('[MediaCache] Removed old cover cache: ${file.path}');
      }
    }
  }

  /// 清理旧格式的歌词缓存
  Future<void> _cleanupOldLyricCache(String audioId, String currentExt) async {
    final dir = await lyricsDir;
    for (final ext in ['.lrc', '.txt']) {
      if (ext == currentExt) continue;
      final file = File(p.join(dir.path, '$audioId$ext'));
      if (file.existsSync()) {
        await file.delete();
        _log.d('[MediaCache] Removed old lyric cache: ${file.path}');
      }
    }
  }

  String _mimeTypeToExtension(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/bmp':
        return '.bmp';
      case 'image/gif':
        return '.gif';
      case 'image/jpeg':
      case 'image/jpg':
      default:
        return '.jpg';
    }
  }

  String _extensionToMimeType(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.gif':
        return 'image/gif';
      case '.jpg':
      default:
        return 'image/jpeg';
    }
  }
}
