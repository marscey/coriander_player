import 'dart:io';

import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// 音频元数据缓存记录
class MetadataRecord {
  final String audioId; // contentHash 或 cloud:md5
  final String? filePath; // 当前文件路径（可能变化）
  final String? title;
  final String? artist;
  final String? album;
  final int? track;
  final int? year;
  final String? genre;
  final String? mbRecordingId;
  final String? mbReleaseId;
  final String? mbArtistId;
  final String? lyricText;
  final bool? lyricSynced;
  final String? coverCachePath; // 本地缓存封面路径
  final String? coverMimeType;
  final String? scraperSource; // 刮削来源标识
  final DateTime? scrapedAt; // 刮削时间
  final DateTime? updatedAt; // 最后更新时间

  const MetadataRecord({
    required this.audioId,
    this.filePath,
    this.title,
    this.artist,
    this.album,
    this.track,
    this.year,
    this.genre,
    this.mbRecordingId,
    this.mbReleaseId,
    this.mbArtistId,
    this.lyricText,
    this.lyricSynced,
    this.coverCachePath,
    this.coverMimeType,
    this.scraperSource,
    this.scrapedAt,
    this.updatedAt,
  });

  factory MetadataRecord.fromMap(Map<String, dynamic> map) {
    return MetadataRecord(
      audioId: map['audio_id'] as String,
      filePath: map['file_path'] as String?,
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      track: map['track'] as int?,
      year: map['year'] as int?,
      genre: map['genre'] as String?,
      mbRecordingId: map['mb_recording_id'] as String?,
      mbReleaseId: map['mb_release_id'] as String?,
      mbArtistId: map['mb_artist_id'] as String?,
      lyricText: map['lyric_text'] as String?,
      lyricSynced: map['lyric_synced'] == 1,
      coverCachePath: map['cover_cache_path'] as String?,
      coverMimeType: map['cover_mime_type'] as String?,
      scraperSource: map['scraper_source'] as String?,
      scrapedAt: map['scraped_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['scraped_at'] as int)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'audio_id': audioId,
      'file_path': filePath,
      'title': title,
      'artist': artist,
      'album': album,
      'track': track,
      'year': year,
      'genre': genre,
      'mb_recording_id': mbRecordingId,
      'mb_release_id': mbReleaseId,
      'mb_artist_id': mbArtistId,
      'lyric_text': lyricText,
      'lyric_synced': lyricSynced == true ? 1 : 0,
      'cover_cache_path': coverCachePath,
      'cover_mime_type': coverMimeType,
      'scraper_source': scraperSource,
      'scraped_at': scrapedAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// 合并两个记录，非空字段覆盖
  MetadataRecord merge(MetadataRecord other) {
    return MetadataRecord(
      audioId: audioId,
      filePath: other.filePath ?? filePath,
      title: other.title ?? title,
      artist: other.artist ?? artist,
      album: other.album ?? album,
      track: other.track ?? track,
      year: other.year ?? year,
      genre: other.genre ?? genre,
      mbRecordingId: other.mbRecordingId ?? mbRecordingId,
      mbReleaseId: other.mbReleaseId ?? mbReleaseId,
      mbArtistId: other.mbArtistId ?? mbArtistId,
      lyricText: other.lyricText ?? lyricText,
      lyricSynced: other.lyricSynced ?? lyricSynced,
      coverCachePath: other.coverCachePath ?? coverCachePath,
      coverMimeType: other.coverMimeType ?? coverMimeType,
      scraperSource: other.scraperSource ?? scraperSource,
      scrapedAt: other.scrapedAt ?? scrapedAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// 刮削源配置记录
class ScraperConfig {
  final String id; // 唯一标识
  final String name; // 显示名称
  final String type; // 类型：netease, qq, kugou, musicbrainz
  final bool enabled; // 是否启用
  final int priority; // 优先级（数字越小越优先）
  final String? apiBase; // API 基础地址（可替换）
  final String? apiKey; // API Key
  final String? extraConfig; // 额外配置（JSON 字符串）

  const ScraperConfig({
    required this.id,
    required this.name,
    required this.type,
    this.enabled = true,
    this.priority = 0,
    this.apiBase,
    this.apiKey,
    this.extraConfig,
  });

  factory ScraperConfig.fromMap(Map<String, dynamic> map) {
    return ScraperConfig(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      enabled: map['enabled'] == 1,
      priority: map['priority'] as int,
      apiBase: map['api_base'] as String?,
      apiKey: map['api_key'] as String?,
      extraConfig: map['extra_config'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'enabled': enabled ? 1 : 0,
      'priority': priority,
      'api_base': apiBase,
      'api_key': apiKey,
      'extra_config': extraConfig,
    };
  }
}

/// SQLite 元数据缓存数据库
/// 核心设计：以 audioId（contentHash/cloud:md5）为主键
/// 文件移动/重命名后，只要内容不变，audioId 不变，可直接匹配元数据
class MetadataStore {
  static const _dbName = 'coriander_metadata.db';
  static const _dbVersion = 1;

  static const metadataTable = 'metadata';
  static const scraperConfigTable = 'scraper_config';

  static MetadataStore? _instance;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Database? _db;

  MetadataStore._();

  static MetadataStore get instance {
    _instance ??= MetadataStore._();
    return _instance!;
  }

  /// 获取数据库实例
  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    _log.i('[MetadataStore] Opening database at: $path');

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    _log.i('[MetadataStore] Creating database tables (version $version)');

    // 元数据表
    await db.execute('''
      CREATE TABLE $metadataTable (
        audio_id TEXT PRIMARY KEY,
        file_path TEXT,
        title TEXT,
        artist TEXT,
        album TEXT,
        track INTEGER,
        year INTEGER,
        genre TEXT,
        mb_recording_id TEXT,
        mb_release_id TEXT,
        mb_artist_id TEXT,
        lyric_text TEXT,
        lyric_synced INTEGER DEFAULT 0,
        cover_cache_path TEXT,
        cover_mime_type TEXT,
        scraper_source TEXT,
        scraped_at INTEGER,
        updated_at INTEGER
      )
    ''');

    // 文件路径索引（用于按路径快速查找）
    await db.execute('''
      CREATE INDEX idx_metadata_file_path ON $metadataTable (file_path)
    ''');

    // 刮削源配置表
    await db.execute('''
      CREATE TABLE $scraperConfigTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        enabled INTEGER DEFAULT 1,
        priority INTEGER DEFAULT 0,
        api_base TEXT,
        api_key TEXT,
        extra_config TEXT
      )
    ''');

    // 插入默认刮削源配置
    await _insertDefaultScraperConfigs(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _log.i(
        '[MetadataStore] Upgrading database from $oldVersion to $newVersion');
    // 后续版本升级时在此添加迁移逻辑
  }

  Future<void> _insertDefaultScraperConfigs(Database db) async {
    final defaults = [
      ScraperConfig(
        id: 'netease',
        name: '网易云音乐',
        type: 'netease',
        enabled: true,
        priority: 1,
      ),
      ScraperConfig(
        id: 'qq',
        name: 'QQ音乐',
        type: 'qq',
        enabled: true,
        priority: 2,
      ),
      ScraperConfig(
        id: 'kugou',
        name: '酷狗音乐',
        type: 'kugou',
        enabled: true,
        priority: 3,
      ),
      ScraperConfig(
        id: 'musicbrainz',
        name: 'MusicBrainz',
        type: 'musicbrainz',
        enabled: true,
        priority: 10,
        apiBase: 'https://musicbrainz.org/ws/2',
      ),
    ];

    for (final config in defaults) {
      await db.insert(scraperConfigTable, config.toMap());
    }
  }

  // ==================== 元数据 CRUD ====================

  /// 插入或更新元数据记录
  Future<void> upsertMetadata(MetadataRecord record) async {
    final db = await database;
    final existing = await getMetadata(record.audioId);

    if (existing != null) {
      // 合并：新记录的非空字段覆盖旧记录
      final merged = existing.merge(record);
      await db.update(
        metadataTable,
        merged.toMap(),
        where: 'audio_id = ?',
        whereArgs: [record.audioId],
      );
      _log.i('[MetadataStore] Updated metadata for: ${record.audioId}');
    } else {
      await db.insert(metadataTable, {
        ...record.toMap(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      _log.i('[MetadataStore] Inserted metadata for: ${record.audioId}');
    }
  }

  /// 根据 audioId 获取元数据
  Future<MetadataRecord?> getMetadata(String audioId) async {
    final db = await database;
    final results = await db.query(
      metadataTable,
      where: 'audio_id = ?',
      whereArgs: [audioId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return MetadataRecord.fromMap(results.first);
  }

  /// 根据文件路径获取元数据
  Future<MetadataRecord?> getMetadataByPath(String filePath) async {
    final db = await database;
    final results = await db.query(
      metadataTable,
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return MetadataRecord.fromMap(results.first);
  }

  /// 更新文件路径（文件移动/重命名时）
  /// 传入 null 表示清除文件路径（文件从库中移除但保留元数据）
  Future<void> updateFilePath(String audioId, String? newFilePath) async {
    final db = await database;
    await db.update(
      metadataTable,
      {
        'file_path': newFilePath,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'audio_id = ?',
      whereArgs: [audioId],
    );
    _log.i(
        '[MetadataStore] Updated file path for $audioId -> $newFilePath');
  }

  /// 更新歌词缓存
  Future<void> updateLyric(String audioId, String lyricText,
      {bool synced = false}) async {
    final db = await database;
    await db.update(
      metadataTable,
      {
        'lyric_text': lyricText,
        'lyric_synced': synced ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'audio_id = ?',
      whereArgs: [audioId],
    );
    _log.i('[MetadataStore] Updated lyric for: $audioId');
  }

  /// 更新封面缓存路径
  Future<void> updateCoverCache(
      String audioId, String coverCachePath, String mimeType) async {
    final db = await database;
    await db.update(
      metadataTable,
      {
        'cover_cache_path': coverCachePath,
        'cover_mime_type': mimeType,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'audio_id = ?',
      whereArgs: [audioId],
    );
    _log.i('[MetadataStore] Updated cover cache for: $audioId');
  }

  /// 删除元数据记录
  Future<void> deleteMetadata(String audioId) async {
    final db = await database;
    await db.delete(
      metadataTable,
      where: 'audio_id = ?',
      whereArgs: [audioId],
    );
    _log.i('[MetadataStore] Deleted metadata for: $audioId');
  }

  /// 获取所有元数据记录数量
  Future<int> getMetadataCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM $metadataTable');
    return result.first['count'] as int;
  }

  // ==================== 刮削源配置 CRUD ====================

  /// 获取所有刮削源配置（按优先级排序）
  Future<List<ScraperConfig>> getScraperConfigs() async {
    final db = await database;
    final results = await db.query(
      scraperConfigTable,
      orderBy: 'priority ASC',
    );
    return results.map((map) => ScraperConfig.fromMap(map)).toList();
  }

  /// 获取已启用的刮削源配置
  Future<List<ScraperConfig>> getEnabledScraperConfigs() async {
    final db = await database;
    final results = await db.query(
      scraperConfigTable,
      where: 'enabled = 1',
      orderBy: 'priority ASC',
    );
    return results.map((map) => ScraperConfig.fromMap(map)).toList();
  }

  /// 更新刮削源配置
  Future<void> updateScraperConfig(ScraperConfig config) async {
    final db = await database;
    await db.update(
      scraperConfigTable,
      config.toMap(),
      where: 'id = ?',
      whereArgs: [config.id],
    );
    _log.i('[MetadataStore] Updated scraper config: ${config.id}');
  }

  /// 更新刮削源 API 地址（可替换）
  Future<void> updateScraperApiBase(String id, String? apiBase) async {
    final db = await database;
    await db.update(
      scraperConfigTable,
      {'api_base': apiBase},
      where: 'id = ?',
      whereArgs: [id],
    );
    _log.i('[MetadataStore] Updated API base for $id: $apiBase');
  }

  /// 启用/禁用刮削源
  Future<void> toggleScraper(String id, bool enabled) async {
    final db = await database;
    await db.update(
      scraperConfigTable,
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _log.i('[MetadataStore] Toggled scraper $id: enabled=$enabled');
  }

  // ==================== 工具方法 ====================

  /// 清理无效的文件路径引用
  /// 返回被清理的记录数
  Future<int> cleanupInvalidPaths() async {
    final db = await database;
    final results = await db.query(metadataTable, columns: ['audio_id', 'file_path']);

    int cleaned = 0;
    for (final row in results) {
      final filePath = row['file_path'] as String?;
      if (filePath != null && !await _fileExists(filePath)) {
        await db.update(
          metadataTable,
          {'file_path': null},
          where: 'audio_id = ?',
          whereArgs: [row['audio_id']],
        );
        cleaned++;
      }
    }

    if (cleaned > 0) {
      _log.i('[MetadataStore] Cleaned up $cleaned invalid file paths');
    }
    return cleaned;
  }

  Future<bool> _fileExists(String path) async {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
