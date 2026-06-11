import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
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

      await instance._loadCloudAudios();
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
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

  ImageProvider? get coverImage => _cover;

  Future<ImageProvider?>? _largeCoverFuture;

  Audio(
    this.title,
    this.artist,
    this.album,
    this.genre,
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
        map["track"] ?? 0,
        map["duration"] ?? 0,
        map["bitrate"],
        map["sample_rate"],
        map["path"]?.toString() ?? '',
        map["modified"] ?? 0,
        map["created"] ?? 0,
        map["by"]?.toString(),
        connectionId: map["connection_id"]?.toString(),
        fileSize: map["file_size"],
      );

  Map toMap() => {
        "title": title,
        "artist": artist,
        "album": album,
        "genre": genre,
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
  Future<ImageProvider?> _getResizedPic({
    required int width,
    required int height,
  }) async {
    // 只有当请求尺寸不超过已缓存的封面尺寸（48x48）时才复用缓存
    if (_cover != null && width <= 48 && height <= 48) return _cover;

    if (isCloudAudio) {
      final cachedPath = CloudCacheManager.instance.getCachedFilePath(path);
      if (cachedPath != null) {
        final ratio = PlatformDispatcher.instance.views.first.devicePixelRatio;
        return getPictureFromPath(
          path: cachedPath,
          width: (width * ratio).round(),
          height: (height * ratio).round(),
        ).then((pic) async {
          if (pic != null) {
            _cover = MemoryImage(pic);
            return _cover;
          }

          // 缓存文件无内嵌封面，尝试从 MediaCache 获取刮削的封面
          try {
            final audioId = await MetadataService.instance.computeAudioId(this);
            if (audioId != null) {
              final cached = await MediaCache.instance.getCover(audioId);
              if (cached != null) {
                _cover = MemoryImage(cached.$1);
                return _cover;
              }
            }
          } catch (e) {
            LOGGER.e("[Audio] Failed to get cover from MediaCache: $e");
          }
          return null;
        });
      }

      // 无本地缓存文件，直接从 MediaCache 获取刮削的封面
      try {
        final audioId = await MetadataService.instance.computeAudioId(this);
        if (audioId != null) {
          final cached = await MediaCache.instance.getCover(audioId);
          if (cached != null) {
            _cover = MemoryImage(cached.$1);
            return _cover;
          }
        }
      } catch (e) {
        LOGGER.e("[Audio] Failed to get cover from MediaCache: $e");
      }
      return null;
    }
    final ratio = PlatformDispatcher.instance.views.first.devicePixelRatio;
    return getPictureFromPath(
      path: path,
      width: (width * ratio).round(),
      height: (height * ratio).round(),
    ).then((pic) async {
      if (pic != null) return MemoryImage(pic);

      // 文件内嵌封面不存在，尝试从 MediaCache 获取刮削的封面
      try {
        final audioId = await MetadataService.instance.computeAudioId(this);
        if (audioId != null) {
          final cached = await MediaCache.instance.getCover(audioId);
          if (cached != null) {
            final coverBytes = cached.$1;
            return MemoryImage(coverBytes);
          }
        }
      } catch (e) {
        LOGGER.e("[Audio] Failed to get cover from cache: $e");
      }
      return null;
    });
  }

  /// 缓存ImageProvider而不是Uint8List（bytes）
  /// 缓存bytes时，每次加载图片都要重新解码，内存占用很大。快速滚动时能到700mb
  /// 缓存ImageProvider不用重新解码。快速滚动时最多250mb
  /// 48*48
  Future<ImageProvider?> get cover {
    if (_cover == null) {
      return _getResizedPic(width: 48, height: 48).then((value) {
        if (value == null) return null;

        _cover = value;
        return _cover;
      });
    }
    return Future.value(_cover);
  }

  void setCover(ImageProvider cover) {
    _cover = cover;
  }

  /// 清除封面缓存，下次访问时重新加载
  void clearCoverCache() {
    _cover = null;
    _largeCoverFuture = null;
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
