import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';

class _CacheEntry {
  String filePath;
  int fileSize;
  DateTime lastAccessed;

  _CacheEntry({
    required this.filePath,
    required this.fileSize,
    required this.lastAccessed,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'fileSize': fileSize,
        'lastAccessed': lastAccessed.toIso8601String(),
      };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
        filePath: json['filePath'] as String,
        fileSize: json['fileSize'] as int? ?? 0,
        lastAccessed: json['lastAccessed'] != null
            ? DateTime.parse(json['lastAccessed'] as String)
            : DateTime.now(),
      );
}

class CloudCacheManager {
  static final CloudCacheManager _instance = CloudCacheManager._();
  static CloudCacheManager get instance => _instance;

  CloudCacheManager._();

  static String _defaultCacheDir = '';
  static String _customCacheDir = '';

  int _maxCacheSizeBytes = 2 * 1024 * 1024 * 1024;
  int get maxCacheSizeBytes => _maxCacheSizeBytes;

  static const int noLimit = -1;

  void setMaxCacheSizeMB(int sizeMB) {
    if (sizeMB == noLimit) {
      _maxCacheSizeBytes = noLimit;
    } else {
      _maxCacheSizeBytes = sizeMB * 1024 * 1024;
    }
  }

  int get maxCacheSizeMB {
    if (_maxCacheSizeBytes == noLimit) return noLimit;
    return (_maxCacheSizeBytes / (1024 * 1024)).round();
  }

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
    if (PlatformHelper.isWindows) {
      final dir = Directory(path.join(
        Platform.environment['USERPROFILE'] ?? 'C:\\Users',
        'Documents',
        'coriander_player',
      ));
      if (await dir.exists()) return dir.path;
    }

    final appDir = await getApplicationSupportDirectory();
    return appDir.path;
  }

  static Future<File> _getConfigFile() async {
    final appDir = await getApplicationSupportDirectory();
    return File(path.join(appDir.path, 'cloud_cache_config.json'));
  }

  static Future<void> _loadCustomDirConfig() async {
    final configFile = await _getConfigFile();
    if (await configFile.exists()) {
      try {
        final content = await configFile.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        final customDir = json['cacheDir'] as String?;
        if (customDir != null &&
            customDir.isNotEmpty &&
            await Directory(customDir).exists()) {
          _customCacheDir = customDir;
        }
      } catch (e) {
        LOGGER.e('[CloudCache] failed to load config: $e');
      }
    }
  }

  static Future<void> _saveCustomDirConfig() async {
    final configFile = await _getConfigFile();
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

    _cacheEntries.clear();
    await _loadIndex();
    LOGGER.i('[CloudCache] migrated cache from $oldDir to $newDir');
  }

  final Map<String, _CacheEntry> _cacheEntries = {};

  Map<String, String> get cacheIndex =>
      Map.unmodifiable(_cacheEntries.map((k, v) => MapEntry(k, v.filePath)));

  File _getIndexFile() => File(path.join(cacheDir, 'cache_index.json'));

  Future<void> _loadIndex() async {
    final indexFile = _getIndexFile();
    if (!await indexFile.exists()) {
      await _migrateFromOldIndex();
      return;
    }

    try {
      final content = await indexFile.readAsString();
      final Map<String, dynamic> json = jsonDecode(content);

      if (json.isEmpty) {
        await _migrateFromOldIndex();
        return;
      }

      final firstValue = json.values.first;
      if (firstValue is String) {
        await _migrateFromOldIndex();
        return;
      }

      _cacheEntries.clear();
      json.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          _cacheEntries[key] = _CacheEntry.fromJson(value);
        }
      });
      LOGGER.i('[CloudCache] loaded ${_cacheEntries.length} cache entries');
    } catch (e) {
      LOGGER.e('[CloudCache] failed to load index: $e');
      await _migrateFromOldIndex();
    }
  }

  Future<void> _migrateFromOldIndex() async {
    final indexFile = _getIndexFile();
    if (!await indexFile.exists()) return;

    try {
      final content = await indexFile.readAsString();
      final Map<String, dynamic> json = jsonDecode(content);
      _cacheEntries.clear();

      for (final entry in json.entries) {
        if (entry.value is String) {
          final filePath = entry.value as String;
          final file = File(filePath);
          int fileSize = 0;
          if (await file.exists()) {
            try {
              fileSize = await file.length();
            } catch (_) {}
          }
          _cacheEntries[entry.key] = _CacheEntry(
            filePath: filePath,
            fileSize: fileSize,
            lastAccessed: await _getFileLastModified(file),
          );
        }
      }

      await _saveIndex();
      LOGGER.i(
          '[CloudCache] migrated ${_cacheEntries.length} entries from old index format');
    } catch (e) {
      LOGGER.e('[CloudCache] failed to migrate old index: $e');
    }
  }

  Future<DateTime> _getFileLastModified(File file) async {
    try {
      if (await file.exists()) {
        return await file.lastModified();
      }
    } catch (_) {}
    return DateTime.now();
  }

  Future<void> _saveIndex() async {
    final indexFile = _getIndexFile();
    final json = _cacheEntries.map((k, v) => MapEntry(k, v.toJson()));
    await indexFile.writeAsString(jsonEncode(json));
  }

  String _cacheKey(String webdavPath) {
    return md5.convert(utf8.encode(webdavPath)).toString();
  }

  String? getCachedFilePath(String webdavPath) {
    final key = _cacheKey(webdavPath);
    final entry = _cacheEntries[key];
    if (entry == null) return null;

    final file = File(entry.filePath);
    if (!file.existsSync()) {
      _cacheEntries.remove(key);
      return null;
    }

    entry.lastAccessed = DateTime.now();
    return entry.filePath;
  }

  bool isCached(String webdavPath) {
    return getCachedFilePath(webdavPath) != null;
  }

  Future<String> saveToCache(String webdavPath, List<int> bytes,
      {String? originalName}) async {
    final key = _cacheKey(webdavPath);

    final existing = _cacheEntries[key];
    if (existing != null) {
      final oldFile = File(existing.filePath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
      _cacheEntries.remove(key);
    }

    final ext = originalName != null ? path.extension(originalName) : '.audio';
    final cacheFileName = '$key$ext';
    final cacheFilePath = path.join(cacheDir, cacheFileName);

    final cacheFile = File(cacheFilePath);
    await cacheFile.writeAsBytes(bytes);

    _cacheEntries[key] = _CacheEntry(
      filePath: cacheFilePath,
      fileSize: bytes.length,
      lastAccessed: DateTime.now(),
    );
    await _saveIndex();

    LOGGER.i(
        '[CloudCache] cached: $webdavPath -> $cacheFilePath (${bytes.length} bytes)');

    await _evictIfNeeded();
    return cacheFilePath;
  }

  Future<String> saveStreamToCache(String webdavPath, Stream<List<int>> stream,
      {String? originalName}) async {
    final key = _cacheKey(webdavPath);

    final existing = _cacheEntries[key];
    if (existing != null) {
      final oldFile = File(existing.filePath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
      _cacheEntries.remove(key);
    }

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

    _cacheEntries[key] = _CacheEntry(
      filePath: cacheFilePath,
      fileSize: totalBytes,
      lastAccessed: DateTime.now(),
    );
    await _saveIndex();

    LOGGER.i(
        '[CloudCache] stream cached: $webdavPath -> $cacheFilePath ($totalBytes bytes)');

    await _evictIfNeeded();
    return cacheFilePath;
  }

  Future<void> _evictIfNeeded() async {
    if (_maxCacheSizeBytes == noLimit) return;

    final totalSize = _cacheEntries.values.fold<int>(0, (sum, e) => sum + e.fileSize);
    if (totalSize <= _maxCacheSizeBytes) return;

    final sorted = _cacheEntries.entries.toList()
      ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));

    int currentSize = totalSize;
    final targetSize = (_maxCacheSizeBytes * 0.8).round();

    for (final entry in sorted) {
      if (currentSize <= targetSize) break;

      final file = File(entry.value.filePath);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        LOGGER.w('[CloudCache] failed to delete evicted file: ${entry.value.filePath}: $e');
      }

      currentSize -= entry.value.fileSize;
      _cacheEntries.remove(entry.key);
      LOGGER.i('[CloudCache] evicted: ${entry.key} (${formatSize(entry.value.fileSize)})');
    }

    await _saveIndex();
    LOGGER.i('[CloudCache] eviction complete, cache size: ${formatSize(currentSize)}');
  }

  Future<void> evictIfNeeded() async => await _evictIfNeeded();

  Future<int> getCacheSize() async {
    int totalSize = 0;
    for (final entry in _cacheEntries.values) {
      final file = File(entry.filePath);
      if (await file.exists()) {
        try {
          final actualSize = await file.length();
          entry.fileSize = actualSize;
          totalSize += actualSize;
        } catch (_) {
          totalSize += entry.fileSize;
        }
      }
    }
    return totalSize;
  }

  int get cachedEntryCount => _cacheEntries.length;

  Future<int> getCacheFileCount() async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return 0;

    int count = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if ({
          '.mp3',
          '.flac',
          '.wav',
          '.aac',
          '.m4a',
          '.ogg',
          '.opus',
          '.ape',
          '.wma'
        }.contains(ext)) {
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
    _cacheEntries.clear();
    await _saveIndex();
    LOGGER.i('[CloudCache] cache cleared');
  }

  Future<void> removeCache(String webdavPath) async {
    final key = _cacheKey(webdavPath);
    final entry = _cacheEntries.remove(key);
    if (entry != null) {
      final file = File(entry.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      await _saveIndex();
    }
  }

  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
