import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

/// from index.json
class AudioLibrary extends ChangeNotifier {
  List<AudioFolder> folders;

  AudioLibrary._(this.folders);

  List<Audio> audioCollection = [];

  Map<String, Artist> artistCollection = {};

  Map<String, Album> albumCollection = {};

  Map<String, Genre> genreCollection = {};

  static AudioLibrary get instance {
    _instance ??= AudioLibrary._([]);
    return _instance!;
  }

  static AudioLibrary? _instance;

  /// 目前 index 结构：
  /// ```json
  /// {
  ///     "folders": [
  ///         {
  ///             "audios": [
  ///                 {...},
  ///                 ...
  ///             ],
  ///             ...
  ///         },
  ///         ...
  ///     ],
  ///     "version": 110
  /// }
  /// ```
  static Future<void> initFromIndex() async {
    try {
      final supportPath = (await getAppDataDir()).path;
      // 使用path包构建跨平台兼容的路径
      final indexPath = '$supportPath${PlatformHelper.pathSeparator}index.json';

      final indexStr = File(indexPath).readAsStringSync();
      final Map indexJson = json.decode(indexStr);
      final List foldersJson = indexJson["folders"];
      final List<AudioFolder> folders = [];

      for (Map folderMap in foldersJson) {
        final List audiosJson = folderMap["audios"];
        final List<Audio> audios = [];
        for (Map audioMap in audiosJson) {
          audios.add(Audio.fromMap(audioMap));
        }
        folders.add(AudioFolder.fromMap(folderMap, audios));
      }

      _instance = AudioLibrary._(folders);

      instance.artistCollection.clear();
      instance.albumCollection.clear();
      instance.genreCollection.clear();
      instance._buildCollections();
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      // index.json 加载失败时，确保 AudioLibrary 实例存在
      _instance ??= AudioLibrary._([]);
    }

    // 无论 index.json 是否加载成功，都尝试加载云音频
    await instance._loadCloudAudios();

    // 音频库加载完成后，恢复上次播放状态
    await PlayService.instance.playbackService.restorePlaybackState();
  }

  static Future<String> _getCloudAudiosFilePath() async {
    final supportPath = (await getAppDataDir()).path;
    return p.join(supportPath, 'cloud_audios.json');
  }

  Future<void> _loadCloudAudios() async {
    try {
      final filePath = await _getCloudAudiosFilePath();
      final file = File(filePath);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      final cloudAudios = jsonList.map((m) => Audio.fromMap(m as Map)).toList();

      if (cloudAudios.isNotEmpty) {
        final existingPaths = audioCollection.map((a) => a.path).toSet();
        final newAudios =
            cloudAudios.where((a) => !existingPaths.contains(a.path)).toList();
        if (newAudios.isNotEmpty) {
          audioCollection.addAll(newAudios);
          for (Audio audio in newAudios) {
            for (String artistName in audio.splitedArtists) {
              artistCollection
                  .putIfAbsent(artistName, () => Artist(name: artistName))
                  .works
                  .add(audio);
            }
            albumCollection
                .putIfAbsent(audio.album, () => Album(name: audio.album))
                .works
                .add(audio);
            if (audio.genre.isNotEmpty) {
              genreCollection
                  .putIfAbsent(audio.genre, () => Genre(name: audio.genre))
                  .works
                  .add(audio);
            }
          }
          for (Artist artist in artistCollection.values) {
            for (Audio audio in artist.works) {
              artist.albumsMap.putIfAbsent(
                audio.album,
                () => albumCollection[audio.album]!,
              );
            }
          }
          for (Album album in albumCollection.values) {
            for (Audio audio in album.works) {
              for (String artistName in audio.splitedArtists) {
                album.artistsMap.putIfAbsent(
                  artistName,
                  () => artistCollection[artistName]!,
                );
              }
            }
          }
          LOGGER.i(
              '[AudioLibrary] loaded ${newAudios.length} cloud audios from persistence');
        }
      }
    } catch (e) {
      LOGGER.e('[AudioLibrary] failed to load cloud audios: $e');
    }
  }

  Future<void> saveCloudAudios() async {
    try {
      final cloudAudios = audioCollection.where((a) => a.isCloudAudio).toList();
      final filePath = await _getCloudAudiosFilePath();
      final jsonList = cloudAudios.map((a) => a.toMap()).toList();
      await File(filePath).writeAsString(jsonEncode(jsonList));
      LOGGER.i(
          '[AudioLibrary] saved ${cloudAudios.length} cloud audios to persistence');
    } catch (e) {
      LOGGER.e('[AudioLibrary] failed to save cloud audios: $e');
    }
  }

  void _buildCollections() {
    for (var f in folders) {
      audioCollection.addAll(f.audios);
    }

    for (Audio audio in audioCollection) {
      for (String artistName in audio.splitedArtists) {
        artistCollection
            .putIfAbsent(artistName, () => Artist(name: artistName))
            .works
            .add(audio);
      }

      albumCollection
          .putIfAbsent(audio.album, () => Album(name: audio.album))
          .works
          .add(audio);

      // 构建流派集合
      if (audio.genre.isNotEmpty) {
        genreCollection
            .putIfAbsent(audio.genre, () => Genre(name: audio.genre))
            .works
            .add(audio);
      }
    }

    for (Artist artist in artistCollection.values) {
      for (Audio audio in artist.works) {
        artist.albumsMap.putIfAbsent(
          audio.album,
          () => albumCollection[audio.album]!,
        );
      }
    }

    for (Album album in albumCollection.values) {
      for (Audio audio in album.works) {
        for (String artistName in audio.splitedArtists) {
          album.artistsMap.putIfAbsent(
            artistName,
            () => artistCollection[artistName]!,
          );
        }
      }
    }
  }

  Future<void> addCloudAudios(List<Audio> cloudAudios) async {
    final existingPaths = audioCollection.map((a) => a.path).toSet();
    final newAudios =
        cloudAudios.where((a) => !existingPaths.contains(a.path)).toList();
    if (newAudios.isEmpty) return;

    audioCollection.addAll(newAudios);

    for (Audio audio in newAudios) {
      for (String artistName in audio.splitedArtists) {
        artistCollection
            .putIfAbsent(artistName, () => Artist(name: artistName))
            .works
            .add(audio);
      }

      albumCollection
          .putIfAbsent(audio.album, () => Album(name: audio.album))
          .works
          .add(audio);

      // 构建流派集合
      if (audio.genre.isNotEmpty) {
        genreCollection
            .putIfAbsent(audio.genre, () => Genre(name: audio.genre))
            .works
            .add(audio);
      }
    }

    for (Artist artist in artistCollection.values) {
      for (Audio audio in artist.works) {
        artist.albumsMap.putIfAbsent(
          audio.album,
          () => albumCollection[audio.album]!,
        );
      }
    }

    for (Album album in albumCollection.values) {
      for (Audio audio in album.works) {
        for (String artistName in audio.splitedArtists) {
          album.artistsMap.putIfAbsent(
            artistName,
            () => artistCollection[artistName]!,
          );
        }
      }
    }

    await saveCloudAudios();
    notifyListeners();
  }

  Future<void> removeAudio(Audio audio) async {
    audioCollection.remove(audio);

    // 从 folders 中移除本地音频
    if (!audio.isCloudAudio) {
      for (final folder in folders) {
        folder.audios.remove(audio);
      }
    }

    for (String artistName in audio.splitedArtists) {
      final artist = artistCollection[artistName];
      if (artist != null) {
        artist.works.remove(audio);
        if (artist.works.isEmpty) {
          artistCollection.remove(artistName);
        } else {
          artist.albumsMap.remove(audio.album);
        }
      }
    }

    final album = albumCollection[audio.album];
    if (album != null) {
      album.works.remove(audio);
      if (album.works.isEmpty) {
        albumCollection.remove(audio.album);
      } else {
        for (String artistName in audio.splitedArtists) {
          final stillHasArtist = album.works.any(
            (a) => a.splitedArtists.contains(artistName),
          );
          if (!stillHasArtist) {
            album.artistsMap.remove(artistName);
          }
        }
      }
    }

    if (audio.isCloudAudio) {
      await saveCloudAudios();
    }
    notifyListeners();
  }

  void notifyUpdated() {
    notifyListeners();
  }

  void rebuildCollections() {
    artistCollection.clear();
    albumCollection.clear();
    genreCollection.clear();
    for (Audio audio in audioCollection) {
      for (String artistName in audio.splitedArtists) {
        artistCollection
            .putIfAbsent(artistName, () => Artist(name: artistName))
            .works
            .add(audio);
      }

      albumCollection
          .putIfAbsent(audio.album, () => Album(name: audio.album))
          .works
          .add(audio);

      // 重建流派集合
      if (audio.genre.isNotEmpty) {
        genreCollection
            .putIfAbsent(audio.genre, () => Genre(name: audio.genre))
            .works
            .add(audio);
      }
    }

    for (Artist artist in artistCollection.values) {
      for (Audio audio in artist.works) {
        artist.albumsMap.putIfAbsent(
          audio.album,
          () => albumCollection[audio.album]!,
        );
      }
    }

    for (Album album in albumCollection.values) {
      for (Audio audio in album.works) {
        for (String artistName in audio.splitedArtists) {
          album.artistsMap.putIfAbsent(
            artistName,
            () => artistCollection[artistName]!,
          );
        }
      }
    }
  }

  @override
  String toString() {
    return folders.toString();
  }
}

class AudioFolder {
  List<Audio> audios;

  /// absolute path
  String path;

  /// secs since UNIX EPOCH
  int modified;

  /// secs since UNIX EPOCH
  int latest;

  AudioFolder(this.audios, this.path, this.modified, this.latest);

  factory AudioFolder.fromMap(Map map, List<Audio> audios) =>
      AudioFolder(audios, map["path"], map["modified"], map["latest"]);

  @override
  String toString() {
    return {
      "audios": audios.toString(),
      "path": path,
      "modified":
          DateTime.fromMillisecondsSinceEpoch(modified * 1000).toString(),
    }.toString();
  }
}

class Audio {
  String title;

  /// 从音乐标签中读取的艺术家字符串，可能包含多个艺术家，以"、"，"/"等分隔。
  String artist;

  /// 分割[artist]得到的结果
  List<String> splitedArtists;

  String album;

  /// 音乐流派/类型（从音频标签的 genre 字段提取）
  String genre;

  /// 发行年份（从音频标签的 year 字段提取）
  int? year;

  /// 发行日期（完整格式，如 "2022-07-15"，从 DATE/RecordingDate 标签提取）
  String date;

  /// 0: 没有track
  int track;

  /// audio's duration in secs
  int duration;

  /// kbps
  int? bitrate;

  int? sampleRate;

  /// 文件大小（字节），云音频从 WebDAV 获取，本地音频从文件读取
  int? fileSize;

  /// absolute path
  String path;

  /// secs since UNIX EPOCH
  int modified;

  /// secs since UNIX EPOCH
  int created;

  /// 标签来源（Lofty、Windows、null）
  String? by;

  String? connectionId;

  ImageProvider? _cover;
  int _coverGeneration = 0;

  ImageProvider? get coverImage => _cover;

  Future<ImageProvider?>? _coverFuture;

  /// 封面来源标记的内存缓存，避免每次访问 cover 都查 DB。
  /// 取值: null(未查询) | 'embedded' | 'scraped' | 'custom' | 'none'
  String? _coverSourceCache;
  bool _coverSourceQueried = false;

  Future<ImageProvider?>? _largeCoverFuture;

  Audio(
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.year,
    this.date,
    this.track,
    this.duration,
    this.bitrate,
    this.sampleRate,
    this.path,
    this.modified,
    this.created,
    this.by, {
    this.connectionId,
    this.fileSize,
  }) : splitedArtists = artist.split(
          RegExp(AppSettings.instance.artistSplitPattern),
        );

  factory Audio.fromMap(Map map) => Audio(
        map["title"]?.toString() ?? '',
        map["artist"]?.toString() ?? '',
        map["album"]?.toString() ?? '',
        map["genre"]?.toString() ?? '',
        map["year"] is int
            ? map["year"]
            : map["year"] is double
                ? (map["year"] as double).toInt()
                : null,
        map["date"]?.toString() ?? '',
        map["track"] is int
            ? map["track"]
            : map["track"] is double
                ? (map["track"] as double).toInt()
                : 0,
        map["duration"] is int
            ? map["duration"]
            : map["duration"] is double
                ? (map["duration"] as double).toInt()
                : 0,
        map["bitrate"] is int
            ? map["bitrate"]
            : map["bitrate"] is double
                ? (map["bitrate"] as double).toInt()
                : null,
        map["sample_rate"] is int
            ? map["sample_rate"]
            : map["sample_rate"] is double
                ? (map["sample_rate"] as double).toInt()
                : null,
        map["path"]?.toString() ?? '',
        map["modified"] is int
            ? map["modified"]
            : map["modified"] is double
                ? (map["modified"] as double).toInt()
                : 0,
        map["created"] is int
            ? map["created"]
            : map["created"] is double
                ? (map["created"] as double).toInt()
                : 0,
        map["by"]?.toString(),
        connectionId: map["connection_id"]?.toString(),
        fileSize: map["file_size"] is int
            ? map["file_size"]
            : map["file_size"] is double
                ? (map["file_size"] as double).toInt()
                : null,
      );

  Map toMap() => {
        "title": title,
        "artist": artist,
        "album": album,
        "genre": genre,
        "year": year,
        "date": date,
        "track": track,
        "duration": duration,
        "bitrate": bitrate,
        "sample_rate": sampleRate,
        "file_size": fileSize,
        "path": path,
        "modified": modified,
        "created": created,
        "by": by,
        "connection_id": connectionId,
      };

  /// 读取音乐文件的图片，自动适应缩放
  ///
  /// 封面来源优先级（基于 MetadataStore.cover_source）:
  /// 1. 'custom' → 读 MediaCache（用户自定义，最高优先级）
  /// 2. 'scraped' → 读 MediaCache（用户主动刮削）
  /// 3. 'none' → 返回 null（用户主动清除，显示占位图）
  /// 4. 'embedded' 或 null:
  ///    a. 云音频: 优先从本地缓存文件读内嵌 → 失败回退 MediaCache
  ///    b. 本地音频: 直接读文件内嵌 → 失败回退 MediaCache
  Future<ImageProvider?> _getResizedPic({
    required int width,
    required int height,
  }) async {
    if (_cover != null && width <= 48 && height <= 48) return _cover;

    final gen = _coverGeneration;
    final ratio = PlatformDispatcher.instance.views.first.devicePixelRatio;
    final targetWidth = (width * ratio).round();
    final targetHeight = (height * ratio).round();

    final coverSource = await _getCoverSource();

    // generation 变化说明 clearCoverCache/setCover 被调用过
    if (gen != _coverGeneration) return _cover;
    if (_cover != null && width <= 48 && height <= 48) return _cover;

    if (coverSource == 'custom' || coverSource == 'scraped') {
      try {
        final audioId = await MetadataService.instance.computeAudioId(this);
        if (audioId != null) {
          final cached = await MediaCache.instance.getCover(audioId);
          if (cached != null) {
            if (gen == _coverGeneration && _cover == null) {
              _cover = MemoryImage(cached.$1);
            }
            return _cover;
          }
          if (gen == _coverGeneration) await _setCoverSource('embedded');
        }
      } catch (e) {
        LOGGER.e("[Audio] Failed to get ${coverSource}Cover: $e");
      }
    }

    if (coverSource == 'none') {
      return null;
    }

    if (isCloudAudio) {
      final cachedPath = CloudCacheManager.instance.getCachedFilePath(path);
      if (cachedPath != null) {
        final pic = await getPictureFromPath(
          path: cachedPath,
          width: targetWidth,
          height: targetHeight,
        );
        if (pic != null) {
          if (gen == _coverGeneration && _cover == null) {
            _cover = MemoryImage(pic);
            if (coverSource == null) await _setCoverSource('embedded');
          }
          return _cover;
        }
      }
    } else {
      final pic = await getPictureFromPath(
        path: path,
        width: targetWidth,
        height: targetHeight,
      );
      if (pic != null) {
        if (gen == _coverGeneration && _cover == null) {
          _cover = MemoryImage(pic);
          if (coverSource == null) await _setCoverSource('embedded');
        }
        return _cover;
      }
    }

    try {
      final audioId = await MetadataService.instance.computeAudioId(this);
      if (audioId != null) {
        final cached = await MediaCache.instance.getCover(audioId);
        if (cached != null) {
          if (gen == _coverGeneration && _cover == null) {
            _cover = MemoryImage(cached.$1);
          }
          return _cover;
        }
      }
    } catch (e) {
      LOGGER.e("[Audio] Failed to get cover from MediaCache: $e");
    }
    return null;
  }

  /// 获取封面来源标记（内存缓存优先）
  Future<String?> _getCoverSource() async {
    if (_coverSourceQueried) return _coverSourceCache;
    _coverSourceQueried = true;
    try {
      final audioId = await MetadataService.instance.computeAudioId(this);
      if (audioId != null) {
        _coverSourceCache = await MetadataStore.instance.getCoverSource(audioId);
      }
    } catch (e) {
      LOGGER.e("[Audio] Failed to query cover_source: $e");
    }
    return _coverSourceCache;
  }

  /// 设置封面来源标记（同步更新内存缓存与 DB）
  Future<void> _setCoverSource(String source) async {
    _coverSourceCache = source;
    _coverSourceQueried = true;
    try {
      final audioId = await MetadataService.instance.computeAudioId(this);
      if (audioId != null) {
        await MetadataStore.instance.updateCoverSource(audioId, source);
      }
    } catch (e) {
      LOGGER.e("[Audio] Failed to update cover_source: $e");
    }
  }

  /// 外部调用：设置封面来源标记（用于 EditTagDialog 等场景）
  Future<void> setCoverSource(String source) async {
    await _setCoverSource(source);
  }

  Future<ImageProvider?> get cover {
    if (_cover != null) {
      return Future.value(_cover);
    }
    if (_coverFuture != null) {
      return _coverFuture!;
    }
    final gen = _coverGeneration;
    _coverFuture = _getResizedPic(width: 48, height: 48).then((value) {
      // 只在 generation 未变化时操作（未被 setCover/clearCoverCache 打断）
      if (gen == _coverGeneration) {
        _coverFuture = null;
        if (_cover != null) {
          AudioLibrary.instance.notifyUpdated();
        }
      }
      return _cover;
    });
    return _coverFuture!;
  }

  void setCover(ImageProvider cover) {
    final changed = !identical(_cover, cover);
    _cover = cover;
    _coverGeneration++;
    _coverFuture = Future.value(cover);
    if (changed) {
      AudioLibrary.instance.notifyUpdated();
    }
  }

  /// 清除封面缓存，下次访问时重新加载
  /// 注意：不重置 _coverSourceCache，保留来源标记以便下次按优先级加载
  void clearCoverCache() {
    final hadCover = _cover != null;
    _cover = null;
    _coverGeneration++;
    _coverFuture = null;
    _largeCoverFuture = null;
    if (hadCover) {
      AudioLibrary.instance.notifyUpdated();
    }
  }

  /// 强制重置封面来源查询状态（用于音频文件被替换、元数据被覆盖等场景）
  void resetCoverSourceQuery() {
    _coverSourceCache = null;
    _coverSourceQueried = false;
    clearCoverCache();
  }

  bool get isCloudAudio => by == 'Cloud';

  String get subtitleText {
    final parts = <String>[
      if (artist.isNotEmpty) artist,
      if (album.isNotEmpty) album,
    ];
    return parts.join(' - ');
  }

  /// audio detail page 不需要频繁调用，所以不缓存图片
  /// 200 * 200
  Future<ImageProvider?> get mediumCover =>
      _getResizedPic(width: 200, height: 200);

  /// now playing 封面，缓存 Future 避免播放/暂停时重复加载
  /// size: 400 * devicePixelRatio（屏幕缩放大小）
  Future<ImageProvider?> get largeCover {
    return _largeCoverFuture ??= _getResizedPic(width: 400, height: 400);
  }

  @override
  String toString() {
    return {
      "title": title,
      "artist": artist,
      "album": album,
      "path": path,
      "modified":
          DateTime.fromMillisecondsSinceEpoch(modified * 1000).toString(),
      "created": DateTime.fromMillisecondsSinceEpoch(created * 1000).toString(),
    }.toString();
  }
}

class Artist {
  String name;

  /// 所有专辑
  Map<String, Album> albumsMap = {};

  /// 作品
  List<Audio> works = [];

  /// 只能用在artist detail page
  /// 200*200
  Future<ImageProvider?> get picture =>
      works.first._getResizedPic(width: 200, height: 200);

  Artist({required this.name});
}

class Album {
  String name;

  /// 参与的艺术家
  Map<String, Artist> artistsMap = {};

  /// 作品
  List<Audio> works = [];

  /// 只能用在album detail page
  /// 200*200
  Future<ImageProvider?> get cover =>
      works.first._getResizedPic(width: 200, height: 200);

  Album({required this.name});
}

class Genre {
  String name;

  /// 作品
  List<Audio> works = [];

  Genre({required this.name});
}
