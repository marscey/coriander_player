import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:coriander_player/utils.dart';

class CloudCacheManager {
  static final CloudCacheManager _instance = CloudCacheManager._();
  static CloudCacheManager get instance => _instance;

  CloudCacheManager._();

  static String _defaultCacheDir = '';
  static String _customCacheDir = '';

  static Future<void> init() async {
    final appData = await _getAppDataDir();
    _defaultCacheDir = path.join(appData, 'cloud_cache');
    await _loadCustomDirConfig();
    final dir = Directory(_instance.cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _instance._loadIndex();
  }

  static Future<String> _getAppDataDir() async {
    final dir = Directory(path.join(
      Platform.environment['USERPROFILE'] ?? 'C:\\Users',
      'Documents',
      'coriander_player',
    ));
    if (await dir.exists()) return dir.path;
    return Directory.systemTemp.path;
  }

  static File _getConfigFile() {
    final appData = Platform.environment['USERPROFILE'] ?? 'C:\\Users';
    return File(path.join(appData, 'Documents', 'coriander_player', 'cloud_cache_config.json'));
  }

  static Future<void> _loadCustomDirConfig() async {
    final configFile = _getConfigFile();
    if (await configFile.exists()) {
      try {
        final content = await configFile.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        final customDir = json['cacheDir'] as String?;
        if (customDir != null && customDir.isNotEmpty && await Directory(customDir).exists()) {
          _customCacheDir = customDir;
        }
      } catch (e) {
        LOGGER.e('[CloudCache] failed to load config: $e');
      }
    }
  }

  static Future<void> _saveCustomDirConfig() async {
    final configFile = _getConfigFile();
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(jsonEncode({'cacheDir': _customCacheDir}));
  }

  String _cacheDir = '';
  String get cacheDir {
    if (_cacheDir.isNotEmpty) return _cacheDir;
    if (_customCacheDir.isNotEmpty) return _customCacheDir;
    return _defaultCacheDir;
  }

  set cacheDir(String value) {
    _cacheDir = value;
  }

  Future<void> setCacheDirAndPersist(String newDir) async {
    final oldDir = cacheDir;
    _cacheDir = newDir;
    _customCacheDir = newDir;
    await _saveCustomDirConfig();

    final newDirectory = Directory(newDir);
    if (!await newDirectory.exists()) {
      await newDirectory.create(recursive: true);
    }

    if (oldDir != newDir) {
      await _migrateCache(oldDir, newDir);
    }
  }

  Future<void> _migrateCache(String oldDir, String newDir) async {
    final oldDirectory = Directory(oldDir);
    if (!await oldDirectory.exists()) return;

    await for (final entity in oldDirectory.list()) {
      if (entity is File) {
        final fileName = path.basename(entity.path);
        try {
          final newPath = path.join(newDir, fileName);
          await entity.rename(newPath);
        } catch (e) {
          try {
            final newPath = path.join(newDir, path.basename(entity.path));
            await entity.copy(newPath);
            await entity.delete();
          } catch (e2) {
            LOGGER.e('[CloudCache] migration failed for ${entity.path}: $e2');
          }
        }
      }
    }

    _cacheIndex.clear();
    await _loadIndex();
    LOGGER.i('[CloudCache] migrated cache from $oldDir to $newDir');
  }

  final Map<String, String> _cacheIndex = {};

  Map<String, String> get cacheIndex => Map.unmodifiable(_cacheIndex);

  File _getIndexFile() => File(path.join(cacheDir, 'cache_index.json'));

  Future<void> _loadIndex() async {
    final indexFile = _getIndexFile();
    if (await indexFile.exists()) {
      try {
        final content = await indexFile.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        _cacheIndex.clear();
        json.forEach((key, value) {
          _cacheIndex[key] = value as String;
        });
        LOGGER.i('[CloudCache] loaded ${_cacheIndex.length} cache entries');
      } catch (e) {
        LOGGER.e('[CloudCache] failed to load index: $e');
      }
    }
  }

  Future<void> _saveIndex() async {
    final indexFile = _getIndexFile();
    await indexFile.writeAsString(jsonEncode(_cacheIndex));
  }

  String _cacheKey(String webdavPath) {
    return md5.convert(utf8.encode(webdavPath)).toString();
  }

  String? getCachedFilePath(String webdavPath) {
    final key = _cacheKey(webdavPath);
    final cachedPath = _cacheIndex[key];
    if (cachedPath == null) return null;

    final file = File(cachedPath);
    if (!file.existsSync()) {
      _cacheIndex.remove(key);
      return null;
    }
    return cachedPath;
  }

  bool isCached(String webdavPath) {
    return getCachedFilePath(webdavPath) != null;
  }

  Future<String> saveToCache(String webdavPath, List<int> bytes, {String? originalName}) async {
    final key = _cacheKey(webdavPath);
    final ext = originalName != null ? path.extension(originalName) : '.audio';
    final cacheFileName = '$key$ext';
    final cacheFilePath = path.join(cacheDir, cacheFileName);

    final cacheFile = File(cacheFilePath);
    await cacheFile.writeAsBytes(bytes);

    _cacheIndex[key] = cacheFilePath;
    await _saveIndex();

    LOGGER.i('[CloudCache] cached: $webdavPath -> $cacheFilePath (${bytes.length} bytes)');
    return cacheFilePath;
  }

  Future<String> saveStreamToCache(String webdavPath, Stream<List<int>> stream, {String? originalName}) async {
    final key = _cacheKey(webdavPath);
    final ext = originalName != null ? path.extension(originalName) : '.audio';
    final cacheFileName = '$key$ext';
    final cacheFilePath = path.join(cacheDir, cacheFileName);

    final cacheFile = File(cacheFilePath);
    final sink = cacheFile.openWrite();
    int totalBytes = 0;
    await for (final chunk in stream) {
      sink.add(chunk);
      totalBytes += chunk.length;
    }
    await sink.close();

    _cacheIndex[key] = cacheFilePath;
    await _saveIndex();

    LOGGER.i('[CloudCache] stream cached: $webdavPath -> $cacheFilePath ($totalBytes bytes)');
    return cacheFilePath;
  }

  Future<int> getCacheSize() async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return 0;

    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        try {
          totalSize += await entity.length();
        } catch (_) {}
      }
    }
    return totalSize;
  }

  Future<int> getCacheFileCount() async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return 0;

    int count = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if ({'.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.opus', '.ape', '.wma'}.contains(ext)) {
          count++;
        }
      }
    }
    return count;
  }

  Future<void> clearCache() async {
    final dir = Directory(cacheDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && path.basename(entity.path) != 'cache_index.json') {
          await entity.delete();
        }
      }
    }
    _cacheIndex.clear();
    await _saveIndex();
    LOGGER.i('[CloudCache] cache cleared');
  }

  Future<void> removeCache(String webdavPath) async {
    final key = _cacheKey(webdavPath);
    final cachedPath = _cacheIndex.remove(key);
    if (cachedPath != null) {
      final file = File(cachedPath);
      if (await file.exists()) {
        await file.delete();
      }
      await _saveIndex();
    }
  }

  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
