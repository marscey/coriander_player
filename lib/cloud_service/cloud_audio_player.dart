import 'dart:io';
import 'dart:convert';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;
import 'package:coriander_player/cloud_service/webdav_service.dart' as webdav;
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/cloud_service/cloud_connection.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/utils.dart';

class ResolvedStreaming {
  final String url;
  final Map<String, String>? headers;
  ResolvedStreaming({required this.url, this.headers});
}

class CloudAudioPlayer {
  static bool get _supportsStreaming {
    final engineType = AppSettings.instance.playerEngineType ??
        PlayerEngineType.defaultForPlatform;
    return engineType == PlayerEngineType.mediaKit;
  }

  static final Map<String, webdav.WebDavService> _pathToService = {};

  static void registerPath(String webdavPath, webdav.WebDavService service) {
    _pathToService[webdavPath] = service;
  }

  static Future<webdav.WebDavService?> _findServiceForPath(
      String webdavPath) async {
    var service = _pathToService[webdavPath];
    if (service != null) return service;

    try {
      final manager = CloudServiceManager.instance;
      await manager.ready;

      final audio = AudioLibrary.instance.audioCollection
          .where((a) => a.path == webdavPath)
          .firstOrNull;
      if (audio?.connectionId != null) {
        service = manager.getService(audio!.connectionId!);
        if (service != null) {
          _pathToService[webdavPath] = service;
          return service;
        }
      }

      for (final conn in manager.connections) {
        if (conn.type == CloudServiceType.webdav) {
          final svc = manager.getService(conn.id);
          if (svc != null) {
            _pathToService[webdavPath] = svc;
            return svc;
          }
        }
      }
    } catch (e) {
      LOGGER.w('[CloudAudioPlayer] CloudServiceManager not available: $e');
    }

    return null;
  }

  static Future<ResolvedStreaming> resolveStreamingUrl(
      String webdavPath) async {
    final service = await _findServiceForPath(webdavPath);
    if (service == null) {
      throw Exception(
          '[CloudAudioPlayer] no service registered for path: $webdavPath');
    }
    final streamingUrl = await service.getStreamingUrl(webdavPath);
    final isCdnUrl = streamingUrl.startsWith('https://') ||
        streamingUrl.startsWith('http://');
    final authHeaders = isCdnUrl &&
            (streamingUrl.contains('X-Amz-Signature') ||
                streamingUrl.contains('x-amz'))
        ? null
        : service.getAuthHeaders();
    LOGGER.i(
        '[CloudAudioPlayer] resolved: $webdavPath -> CDN=$isCdnUrl, hasHeaders=${authHeaders != null}');
    return ResolvedStreaming(url: streamingUrl, headers: authHeaders);
  }

  /// 从文件名解析标题和艺术家。
  /// 支持格式："艺术家 - 标题.ext"、"标题.ext"
  static ({String title, String artist}) _parseFileName(String fileName) {
    final ext = path.extension(fileName);
    final nameWithoutExt = fileName.replaceAll(ext, '');

    // 尝试按 "艺术家 - 标题" 格式解析
    // 支持的分隔符: " - ", " — ", " – "
    final separators = [' - ', ' — ', ' – '];
    for (final sep in separators) {
      final idx = nameWithoutExt.indexOf(sep);
      if (idx > 0 && idx < nameWithoutExt.length - sep.length) {
        final artist = nameWithoutExt.substring(0, idx).trim();
        final title = nameWithoutExt.substring(idx + sep.length).trim();
        if (artist.isNotEmpty && title.isNotEmpty) {
          return (title: title, artist: artist);
        }
      }
    }

    return (title: nameWithoutExt, artist: '');
  }

  static Audio _createStreamingAudio(
      webdav.WebDavFile file, webdav.WebDavService service,
      {String? connectionId}) {
    registerPath(file.path, service);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final parsed = _parseFileName(file.name);
    return Audio(
      parsed.title,
      parsed.artist,
      '',
      0,
      0,
      null,
      null,
      file.path,
      now,
      now,
      'Cloud',
      connectionId: connectionId,
      fileSize: file.size > 0 ? file.size : null,
    );
  }

  static Future<void> _updateMetadataAsync(
    webdav.WebDavService service,
    webdav.WebDavFile file,
  ) async {
    try {
      final webdavPath = file.path;
      final library = AudioLibrary.instance;
      final existingInLib = library.audioCollection
          .where((a) => a.path == webdavPath && a.artist.isNotEmpty)
          .toList();
      if (existingInLib.isNotEmpty) {
        LOGGER.i(
            '[CloudAudioPlayer] metadata already cached in library: $webdavPath');
        final libAudio = existingInLib.first;
        final playbackService = PlayService.instance.playbackService;
        if (playbackService.nowPlaying?.path == webdavPath) {
          final np = playbackService.nowPlaying!;
          np.title = libAudio.title;
          np.artist = libAudio.artist;
          np.splitedArtists = libAudio.splitedArtists;
          np.album = libAudio.album;
          np.track = libAudio.track;
          np.duration = libAudio.duration;
          np.bitrate = libAudio.bitrate;
          np.sampleRate = libAudio.sampleRate;
          if (libAudio.coverImage != null) {
            np.setCover(libAudio.coverImage!);
          }
          playbackService.refreshNowPlaying();
          try {
            ThemeProvider.instance.applyThemeFromAudio(np);
          } catch (_) {}
        }
        return;
      }

      // 优先通过 Range 请求快速获取元数据
      final rangeOk = await _updateMetadataViaRange(service, file);
      if (rangeOk) return;

      // 回退：等待缓存完成后读取元数据
      await _updateMetadataViaFullDownload(service, file);
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] 异步更新元数据失败: $e');
    }
  }

  /// 通过 HTTP Range 请求快速获取云音频元数据（仅下载头尾约 192KB）。
  /// 返回 true 表示成功获取并更新了元数据。
  static Future<bool> _updateMetadataViaRange(
    webdav.WebDavService service,
    webdav.WebDavFile file,
  ) async {
    try {
      final webdavPath = file.path;
      final fileSize = await service.getFileSize(webdavPath);
      if (fileSize == null || fileSize < 128) {
        LOGGER.w(
            '[CloudAudioPlayer] cannot get file size for Range request: $webdavPath');
        return false;
      }

      final headSize = (64 * 1024).clamp(0, fileSize);
      final tailSize = (128 * 1024).clamp(0, fileSize);
      final tailStart = (fileSize - tailSize).clamp(0, fileSize - 1);

      // 并行下载头尾
      final results = await Future.wait([
        service.downloadRange(webdavPath, 0, headSize - 1),
        service.downloadRange(webdavPath, tailStart, fileSize - 1),
      ]);

      final headBytes = results[0];
      final tailBytes = results[1];

      if (headBytes == null || tailBytes == null) {
        LOGGER.w('[CloudAudioPlayer] Range request failed for: $webdavPath');
        return false;
      }

      final jsonStr = await readMetadataFromBytes(
        headBytes: headBytes,
        tailBytes: tailBytes,
        fileSize: fileSize,
        fileName: file.name,
      );

      if (jsonStr == null) {
        LOGGER.w(
            '[CloudAudioPlayer] readMetadataFromBytes returned null for: $webdavPath');
        return false;
      }

      final Map<String, dynamic> meta = json.decode(jsonStr);
      LOGGER.i(
          '[CloudAudioPlayer] Range metadata: title=${meta['title']}, artist=${meta['artist']}, album=${meta['album']}, duration=${meta['duration']}');

      final playbackService = PlayService.instance.playbackService;
      if (playbackService.nowPlaying?.path == webdavPath) {
        final np = playbackService.nowPlaying!;
        if (meta['title'] != null && (meta['title'] as String).isNotEmpty) {
          np.title = meta['title'] as String;
        }
        if (meta['artist'] != null && (meta['artist'] as String).isNotEmpty) {
          np.artist = meta['artist'] as String;
          np.splitedArtists =
              np.artist.split(RegExp(AppSettings.instance.artistSplitPattern));
        }
        if (meta['album'] != null && (meta['album'] as String).isNotEmpty) {
          np.album = meta['album'] as String;
        }
        if (meta['track'] != null) {
          np.track = meta['track'] as int;
        }
        if (meta['duration'] != null && (meta['duration'] as num) > 0) {
          np.duration = (meta['duration'] as num).toInt();
        }
        if (meta['bitrate'] != null) {
          np.bitrate = meta['bitrate'] as int?;
        }
        if (meta['sample_rate'] != null) {
          np.sampleRate = meta['sample_rate'] as int?;
        }
        np.fileSize = fileSize;

        // 尝试从缓存文件获取封面
        try {
          final cachedPath =
              CloudCacheManager.instance.getCachedFilePath(webdavPath);
          if (cachedPath != null) {
            final pic = await getPictureFromPath(
                path: cachedPath, width: 400, height: 400);
            if (pic != null) {
              np.setCover(MemoryImage(pic));
            }
          }
        } catch (_) {}

        playbackService.refreshNowPlaying();
        try {
          ThemeProvider.instance.applyThemeFromAudio(np);
        } catch (_) {}

        _updateLibraryAudioMetadata(np);
      }

      return true;
    } catch (e) {
      LOGGER.w('[CloudAudioPlayer] Range metadata failed, will fallback: $e');
      return false;
    }
  }

  /// 回退方案：等待缓存完成后从完整文件读取元数据。
  static Future<void> _updateMetadataViaFullDownload(
    webdav.WebDavService service,
    webdav.WebDavFile file,
  ) async {
    final webdavPath = file.path;

    String? localFilePath;

    final cachedPath = CloudCacheManager.instance.getCachedFilePath(webdavPath);
    if (cachedPath != null) {
      localFilePath = cachedPath;
      LOGGER.i('[CloudAudioPlayer] metadata from cache: $cachedPath');
    } else {
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final cached = CloudCacheManager.instance.getCachedFilePath(webdavPath);
        if (cached != null) {
          localFilePath = cached;
          LOGGER.i(
              '[CloudAudioPlayer] metadata from cache after ${i + 1}x2s: $cached');
          break;
        }
      }
    }

    final metaDir = Directory(path.join(
      Directory.systemTemp.path,
      'coriander_meta_${DateTime.now().millisecondsSinceEpoch}',
    ));
    await metaDir.create(recursive: true);

    if (localFilePath != null) {
      final originalName = webdavPath.split('/').last;
      final tempCopyPath = path.join(metaDir.path, originalName);
      await File(localFilePath).copy(tempCopyPath);
      localFilePath = tempCopyPath;
    } else {
      LOGGER.w(
          '[CloudAudioPlayer] cache not ready, downloading file for metadata: $webdavPath');
      final originalName = webdavPath.split('/').last;
      final tempFilePath = path.join(metaDir.path, originalName);
      final bytes = await service.downloadFile(webdavPath);
      await File(tempFilePath).writeAsBytes(bytes);
      localFilePath = tempFilePath;
    }

    final localFile = File(localFilePath);
    if (!await localFile.exists()) {
      LOGGER.w(
          '[CloudAudioPlayer] local file not found for metadata: $localFilePath');
      await metaDir.delete(recursive: true);
      return;
    }

    final metaIndexDir = Directory(path.join(
      Directory.systemTemp.path,
      'coriander_metaidx_${DateTime.now().millisecondsSinceEpoch}',
    ));
    await metaIndexDir.create(recursive: true);

    await buildIndexFromFoldersRecursively(
      folders: [metaDir.path],
      indexPath: metaIndexDir.path,
    ).drain();

    final indexFile = File(path.join(metaIndexDir.path, 'index.json'));
    if (await indexFile.exists()) {
      final indexStr = await indexFile.readAsString();
      final Map indexJson = json.decode(indexStr);
      final List foldersJson = indexJson["folders"];
      if (foldersJson.isNotEmpty) {
        final List audiosJson = foldersJson[0]["audios"];
        if (audiosJson.isNotEmpty) {
          final updatedAudio = Audio.fromMap(audiosJson[0]);
          final playbackService = PlayService.instance.playbackService;
          if (playbackService.nowPlaying?.path == webdavPath) {
            final np = playbackService.nowPlaying!;
            np.title = updatedAudio.title;
            np.artist = updatedAudio.artist;
            np.splitedArtists = updatedAudio.splitedArtists;
            np.album = updatedAudio.album;
            np.track = updatedAudio.track;
            np.duration = updatedAudio.duration;
            np.bitrate = updatedAudio.bitrate;
            np.sampleRate = updatedAudio.sampleRate;
            LOGGER.i(
                '[CloudAudioPlayer] metadata updated: title=${updatedAudio.title}, artist=${updatedAudio.artist}, album=${updatedAudio.album}, duration=${updatedAudio.duration}');

            try {
              final pic = await getPictureFromPath(
                path: updatedAudio.path,
                width: 400,
                height: 400,
              );
              LOGGER.i(
                  '[CloudAudioPlayer] getPictureFromPath result: ${pic != null ? "${pic.length} bytes" : "null"}, path=${updatedAudio.path}');
              if (pic != null) {
                np.setCover(MemoryImage(pic));
                LOGGER.i(
                    '[CloudAudioPlayer] cover set on nowPlaying, _cover=${np.coverImage != null}');
              }
            } catch (_) {}

            playbackService.refreshNowPlaying();
            try {
              ThemeProvider.instance.applyThemeFromAudio(np);
            } catch (_) {}

            _updateLibraryAudioMetadata(np);
          }
        }
      }
    }

    await metaDir.delete(recursive: true);
    await metaIndexDir.delete(recursive: true);
  }

  static Future<void> updateMetadataFromCache(Audio audio) async {
    try {
      final library = AudioLibrary.instance;
      final existingInLib = library.audioCollection
          .where((a) => a.path == audio.path && a.artist.isNotEmpty)
          .firstOrNull;
      if (existingInLib != null) {
        LOGGER
            .i('[CloudAudioPlayer] metadata from library cache: ${audio.path}');
        audio.title = existingInLib.title;
        audio.artist = existingInLib.artist;
        audio.splitedArtists = existingInLib.splitedArtists;
        audio.album = existingInLib.album;
        audio.track = existingInLib.track;
        audio.duration = existingInLib.duration;
        audio.bitrate = existingInLib.bitrate;
        audio.sampleRate = existingInLib.sampleRate;
        if (existingInLib.coverImage != null) {
          audio.setCover(existingInLib.coverImage!);
        }
        PlayService.instance.playbackService.refreshNowPlaying();
        return;
      }

      final cachedPath =
          CloudCacheManager.instance.getCachedFilePath(audio.path);
      if (cachedPath == null) {
        LOGGER
            .w('[CloudAudioPlayer] no cache file for metadata: ${audio.path}');
        return;
      }

      final metaDir = Directory(path.join(
        Directory.systemTemp.path,
        'coriander_meta_${DateTime.now().millisecondsSinceEpoch}',
      ));
      await metaDir.create(recursive: true);

      final originalName = audio.path.split('/').last;
      final tempCopyPath = path.join(metaDir.path, originalName);
      await File(cachedPath).copy(tempCopyPath);

      final metaIndexDir = Directory(path.join(
        Directory.systemTemp.path,
        'coriander_metaidx_${DateTime.now().millisecondsSinceEpoch}',
      ));
      await metaIndexDir.create(recursive: true);

      await buildIndexFromFoldersRecursively(
        folders: [metaDir.path],
        indexPath: metaIndexDir.path,
      ).drain();

      final indexFile = File(path.join(metaIndexDir.path, 'index.json'));
      if (await indexFile.exists()) {
        final indexStr = await indexFile.readAsString();
        final Map indexJson = json.decode(indexStr);
        final List foldersJson = indexJson["folders"];
        if (foldersJson.isNotEmpty) {
          final List audiosJson = foldersJson[0]["audios"];
          if (audiosJson.isNotEmpty) {
            final updatedAudio = Audio.fromMap(audiosJson[0]);
            final playbackService = PlayService.instance.playbackService;
            if (playbackService.nowPlaying?.path == audio.path) {
              final np = playbackService.nowPlaying!;
              np.title = updatedAudio.title;
              np.artist = updatedAudio.artist;
              np.splitedArtists = updatedAudio.splitedArtists;
              np.album = updatedAudio.album;
              np.track = updatedAudio.track;
              np.duration = updatedAudio.duration;
              np.bitrate = updatedAudio.bitrate;
              np.sampleRate = updatedAudio.sampleRate;

              try {
                final pic = await getPictureFromPath(
                  path: updatedAudio.path,
                  width: 400,
                  height: 400,
                );
                LOGGER.i(
                    '[CloudAudioPlayer] getPictureFromPath: ${pic != null ? "${pic.length} bytes" : "null"}');
                if (pic != null) {
                  np.setCover(MemoryImage(pic));
                }
              } catch (_) {}

              playbackService.refreshNowPlaying();
              try {
                ThemeProvider.instance.applyThemeFromAudio(np);
              } catch (_) {}

              _updateLibraryAudioMetadata(np);
            }
          }
        }
      }

      await metaDir.delete(recursive: true);
      await metaIndexDir.delete(recursive: true);
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] updateMetadataFromCache failed: $e');
    }
  }

  static void _updateLibraryAudioMetadata(Audio updatedAudio) {
    try {
      final library = AudioLibrary.instance;
      final existing = library.audioCollection
          .where((a) => a.path == updatedAudio.path)
          .toList();
      for (final audio in existing) {
        audio.title = updatedAudio.title;
        audio.artist = updatedAudio.artist;
        audio.splitedArtists = updatedAudio.splitedArtists;
        audio.album = updatedAudio.album;
        audio.track = updatedAudio.track;
        audio.duration = updatedAudio.duration;
        audio.bitrate = updatedAudio.bitrate;
        audio.sampleRate = updatedAudio.sampleRate;
        if (updatedAudio.coverImage != null) {
          audio.setCover(updatedAudio.coverImage!);
        }
      }
      if (existing.isNotEmpty) {
        library.rebuildCollections();
        library.saveCloudAudios();
        library.notifyUpdated();
        PlayService.instance.playbackService.refreshNowPlaying();
      }
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] 更新音乐库元数据失败: $e');
    }
  }

  /// 通过 HTTP Range 请求快速获取云音频元数据并创建 Audio 对象（仅下载头尾约 192KB）。
  /// 失败时回退到文件名解析。
  static Future<Audio> _createAudioViaRange(
    webdav.WebDavService service,
    webdav.WebDavFile file, {
    String? connectionId,
  }) async {
    final webdavPath = file.path;
    final parsed = _parseFileName(file.name);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final knownFileSize = file.size > 0 ? file.size : null;
    LOGGER.i(
        '[DEBUG] _createAudioViaRange: path=$webdavPath, fileName=${file.name}, file.size=${file.size}, knownFileSize=$knownFileSize');

    final fallbackAudio = Audio(
      parsed.title,
      parsed.artist,
      '',
      0,
      0,
      null,
      null,
      webdavPath,
      now,
      now,
      'Cloud',
      connectionId: connectionId,
      fileSize: knownFileSize,
    );

    try {
      final fileSize = knownFileSize ?? await service.getFileSize(webdavPath);
      LOGGER.i(
          '[DEBUG] _createAudioViaRange: fileSize=$fileSize (from ${knownFileSize != null ? "PROPFIND" : "HEAD"})');
      if (fileSize == null || fileSize < 128) {
        LOGGER.w(
            '[CloudAudioPlayer] cannot get file size for Range request: $webdavPath');
        return fallbackAudio;
      }

      final headSize = (64 * 1024).clamp(0, fileSize);
      final tailSize = (128 * 1024).clamp(0, fileSize);
      final tailStart = (fileSize - tailSize).clamp(0, fileSize - 1);
      LOGGER.i(
          '[DEBUG] _createAudioViaRange: headSize=$headSize, tailSize=$tailSize, tailStart=$tailStart, fileSize=$fileSize');

      final results = await Future.wait([
        service.downloadRange(webdavPath, 0, headSize - 1),
        service.downloadRange(webdavPath, tailStart, fileSize - 1),
      ]);

      final headBytes = results[0];
      final tailBytes = results[1];
      LOGGER.i(
          '[DEBUG] _createAudioViaRange: headBytes=${headBytes != null ? headBytes.length : "null"}, tailBytes=${tailBytes != null ? tailBytes.length : "null"}');

      if (headBytes == null || tailBytes == null) {
        LOGGER.w('[CloudAudioPlayer] Range request failed for: $webdavPath');
        return fallbackAudio;
      }

      LOGGER.i(
          '[DEBUG] _createAudioViaRange: calling readMetadataFromBytes(headBytes=${headBytes.length}, tailBytes=${tailBytes.length}, fileSize=$fileSize, fileName=${file.name})');
      final jsonStr = await readMetadataFromBytes(
        headBytes: headBytes,
        tailBytes: tailBytes,
        fileSize: fileSize,
        fileName: file.name,
      );

      LOGGER.i(
          '[DEBUG] _createAudioViaRange: readMetadataFromBytes result=${jsonStr != null ? jsonStr : "NULL"}');
      if (jsonStr == null) {
        LOGGER.w(
            '[CloudAudioPlayer] readMetadataFromBytes returned null for: $webdavPath');
        return fallbackAudio;
      }

      final Map<String, dynamic> meta = json.decode(jsonStr);
      final metaTitle = meta['title'] as String?;
      final metaArtist = meta['artist'] as String?;
      final metaAlbum = meta['album'] as String?;
      final metaTrack = meta['track'] as int?;
      final metaDuration = meta['duration'] as int?;
      final metaBitrate = meta['bitrate'] as int?;
      final metaSampleRate = meta['sample_rate'] as int?;

      LOGGER.i(
          '[DEBUG] _createAudioViaRange: parsed meta => title=$metaTitle, artist=$metaArtist, album=$metaAlbum, track=$metaTrack, duration=$metaDuration, bitrate=$metaBitrate, sampleRate=$metaSampleRate');

      int duration = metaDuration ?? 0;
      int? bitrate = metaBitrate;
      int? sampleRate = metaSampleRate;

      // duration=0 时用 fileSize/bitrate 估算
      if (duration == 0 && bitrate != null && bitrate > 0) {
        duration = ((fileSize * 8) / (bitrate * 1000)).round();
        LOGGER.i(
            '[DEBUG] _createAudioViaRange: estimated duration from fileSize/bitrate: ${duration}s');
      }

      // bitrate=0 时用 fileSize/duration 估算（FLAC 虚拟文件无音频帧，lofty 返回 bitrate=0）
      if ((bitrate == null || bitrate == 0) && duration > 0) {
        bitrate = ((fileSize * 8) / (duration * 1000)).round();
        LOGGER.i(
            '[DEBUG] _createAudioViaRange: estimated bitrate from fileSize/duration: ${bitrate}kbps');
      }

      LOGGER.i(
          '[DEBUG] _createAudioViaRange: final Audio => duration=$duration, bitrate=$bitrate, sampleRate=$sampleRate, fileSize=$fileSize');

      return Audio(
        (metaTitle != null && metaTitle.isNotEmpty) ? metaTitle : parsed.title,
        (metaArtist != null && metaArtist.isNotEmpty)
            ? metaArtist
            : parsed.artist,
        (metaAlbum != null && metaAlbum.isNotEmpty) ? metaAlbum : '',
        metaTrack ?? 0,
        duration,
        bitrate,
        sampleRate,
        webdavPath,
        now,
        now,
        'Cloud',
        connectionId: connectionId,
        fileSize: fileSize,
      );
    } catch (e, stackTrace) {
      LOGGER
          .w('[DEBUG] _createAudioViaRange: exception caught: $e\n$stackTrace');
      return fallbackAudio;
    }
  }

  static Future<Audio> _createAudioWithMetadata(File downloadedFile) async {
    try {
      final metaIndexDir = Directory(path.join(
        Directory.systemTemp.path,
        'coriander_meta_${DateTime.now().millisecondsSinceEpoch}',
      ));
      await metaIndexDir.create(recursive: true);

      await buildIndexFromFoldersRecursively(
        folders: [downloadedFile.parent.path],
        indexPath: metaIndexDir.path,
      ).drain();

      final indexFile = File(path.join(metaIndexDir.path, 'index.json'));
      if (await indexFile.exists()) {
        final indexStr = await indexFile.readAsString();
        final Map indexJson = json.decode(indexStr);
        final List foldersJson = indexJson["folders"];
        if (foldersJson.isNotEmpty) {
          final List audiosJson = foldersJson[0]["audios"];
          if (audiosJson.isNotEmpty) {
            final audio = Audio.fromMap(audiosJson[0]);
            await metaIndexDir.delete(recursive: true);
            return audio;
          }
        }
      }
      await metaIndexDir.delete(recursive: true);
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] 读取云音频元数据失败: $e');
    }

    final parsed = _parseFileName(path.basename(downloadedFile.path));
    return Audio(
      parsed.title,
      parsed.artist,
      '',
      0,
      0,
      null,
      null,
      downloadedFile.path,
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Cloud',
    );
  }

  static Future<File> _downloadToTempDir(
    webdav.WebDavService service,
    String filePath,
    String fileName,
  ) async {
    final cloudDir = Directory(path.join(
      Directory.systemTemp.path,
      'coriander_cloud_${DateTime.now().millisecondsSinceEpoch}',
    ));
    await cloudDir.create(recursive: true);

    final tempFilePath =
        path.join(cloudDir.path, fileName.replaceAll('/', '_'));
    final bytes = await service.downloadFile(filePath);
    final downloadedFile = File(tempFilePath);
    await downloadedFile.writeAsBytes(bytes);

    if (!await downloadedFile.exists()) {
      throw Exception('文件下载失败');
    }

    return downloadedFile;
  }

  static Future<void> playCloudFile({
    required webdav.WebDavService service,
    required String filePath,
    required String fileName,
    required List<webdav.WebDavFile> folderFiles,
    String? connectionId,
    void Function()? onPlayStarted,
  }) async {
    try {
      LOGGER.i(
          '[CloudAudioPlayer] playCloudFile: filePath=$filePath, folderFiles=${folderFiles.length}, _supportsStreaming=$_supportsStreaming');

      final audioFiles = folderFiles.where((f) => f.isAudioFile).toList();
      if (audioFiles.isEmpty) {
        LOGGER.w('[CloudAudioPlayer] no audio files in folder');
        return;
      }

      final startIndex = audioFiles.indexWhere((f) => f.path == filePath);
      final playIndex = startIndex >= 0 ? startIndex : 0;

      if (_supportsStreaming) {
        final playbackService = PlayService.instance.playbackService;
        final audioList = <Audio>[];
        int adjustedPlayIndex = -1;

        for (int i = 0; i < audioFiles.length; i++) {
          final audio = _createStreamingAudio(audioFiles[i], service,
              connectionId: connectionId);
          if (i == playIndex) {
            adjustedPlayIndex = audioList.length;
            audioList.add(audio);
          } else if (!playbackService.isInPlaylist(audio.path)) {
            audioList.add(audio);
          }
        }

        if (adjustedPlayIndex < 0) adjustedPlayIndex = 0;

        PlayService.instance.playbackService.play(
          adjustedPlayIndex,
          audioList,
        );
        LOGGER.i(
            '[CloudAudioPlayer] play() called with ${audioList.length} cloud audios (skipped duplicates), starting at index $adjustedPlayIndex');

        _updateMetadataAsync(service, audioFiles[playIndex]);
      } else {
        final firstFile = audioFiles[playIndex];
        final downloadedFile =
            await _downloadToTempDir(service, firstFile.path, firstFile.name);
        final firstAudio = await _createAudioWithMetadata(downloadedFile);
        LOGGER.i(
            '[CloudAudioPlayer] Downloaded first audio: title=${firstAudio.title}');

        PlayService.instance.playbackService.play(0, [firstAudio]);

        Future.delayed(const Duration(minutes: 5), () {
          downloadedFile.parent
              .delete(recursive: true)
              .catchError((_) => downloadedFile.parent);
        });

        for (int i = 0; i < audioFiles.length; i++) {
          if (i == playIndex) continue;
          try {
            final dlFile = await _downloadToTempDir(
                service, audioFiles[i].path, audioFiles[i].name);
            final audio = await _createAudioWithMetadata(dlFile);
            PlayService.instance.playbackService.addToNext(audio);

            Future.delayed(const Duration(minutes: 30), () {
              dlFile.parent
                  .delete(recursive: true)
                  .catchError((_) => dlFile.parent);
            });
          } catch (e) {
            LOGGER.e('[CloudAudioPlayer] 添加文件失败: ${audioFiles[i].path} - $e');
          }
        }
      }

      onPlayStarted?.call();
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] 播放云文件失败: $e');
      rethrow;
    }
  }

  static Future<void> addCloudFolderToPlaylist({
    required webdav.WebDavService service,
    required String folderPath,
    String? connectionId,
    void Function(int addedCount)? onProgress,
  }) async {
    try {
      final audioFiles = await service.scanAudioFiles(folderPath);

      int addedCount = 0;
      for (final file in audioFiles) {
        try {
          if (_supportsStreaming) {
            final audio = _createStreamingAudio(file, service,
                connectionId: connectionId);
            PlayService.instance.playbackService.addToNext(audio);
          } else {
            final downloadedFile =
                await _downloadToTempDir(service, file.path, file.name);
            final audio = await _createAudioWithMetadata(downloadedFile);
            PlayService.instance.playbackService.addToNext(audio);

            Future.delayed(const Duration(minutes: 30), () {
              downloadedFile.parent
                  .delete(recursive: true)
                  .catchError((_) => downloadedFile.parent);
            });
          }
          addedCount++;
          onProgress?.call(addedCount);
        } catch (e) {
          LOGGER.e('[CloudAudioPlayer] 添加文件失败: ${file.path} - $e');
          continue;
        }
      }

      onProgress?.call(addedCount);
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] 添加云文件夹到播放列表失败: $e');
      rethrow;
    }
  }

  static Future<void> addCloudFilesToPlaylist({
    required webdav.WebDavService service,
    required List<webdav.WebDavFile> files,
    String? connectionId,
    void Function(int addedCount)? onProgress,
  }) async {
    int addedCount = 0;

    for (final file in files) {
      try {
        if (!file.isAudioFile) continue;

        if (_supportsStreaming) {
          final audio =
              _createStreamingAudio(file, service, connectionId: connectionId);
          PlayService.instance.playbackService.addToNext(audio);
        } else {
          final downloadedFile =
              await _downloadToTempDir(service, file.path, file.name);
          final audio = await _createAudioWithMetadata(downloadedFile);
          PlayService.instance.playbackService.addToNext(audio);

          Future.delayed(const Duration(minutes: 30), () {
            downloadedFile.parent
                .delete(recursive: true)
                .catchError((_) => downloadedFile.parent);
          });
        }
        addedCount++;
        onProgress?.call(addedCount);
      } catch (e) {
        LOGGER.e('[CloudAudioPlayer] 添加文件失败: ${file.path} - $e');
        continue;
      }
    }

    onProgress?.call(addedCount);
  }

  static Future<void> addCloudFolderToLibrary({
    required webdav.WebDavService service,
    required String folderPath,
    String? connectionId,
    void Function(int addedCount)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    try {
      onStatus?.call('正在扫描音频文件...');

      final audioFiles = await service.scanAudioFiles(folderPath);
      onStatus?.call('找到 ${audioFiles.length} 个音频文件，正在读取元数据...');

      final library = AudioLibrary.instance;
      final cloudAudios = <Audio>[];

      for (int i = 0; i < audioFiles.length; i++) {
        final file = audioFiles[i];
        try {
          if (library.audioCollection.any((a) => a.path == file.path)) continue;

          registerPath(file.path, service);
          onStatus?.call('正在处理 (${i + 1}/${audioFiles.length}): ${file.name}');

          final audio = await _createAudioViaRange(service, file,
              connectionId: connectionId);

          cloudAudios.add(audio);
          onProgress?.call(cloudAudios.length);
        } catch (e) {
          LOGGER.e('[CloudAudioPlayer] 处理文件失败: ${file.path} - $e');
          final parsed = _parseFileName(file.name);
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          cloudAudios.add(Audio(
            parsed.title,
            parsed.artist,
            '',
            0,
            0,
            null,
            null,
            file.path,
            now,
            now,
            'Cloud',
            connectionId: connectionId,
            fileSize: file.size > 0 ? file.size : null,
          ));
          onProgress?.call(cloudAudios.length);
        }
      }

      if (cloudAudios.isNotEmpty) {
        await library.addCloudAudios(cloudAudios);
        library.rebuildCollections();
        await library.saveCloudAudios();
        library.notifyUpdated();
        onStatus?.call('完成！已添加 ${cloudAudios.length} 首音频到音乐库');
      } else {
        onStatus?.call('未找到新的音频文件');
      }
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] 扫描云文件夹到库失败: $e');
      onStatus?.call('扫描失败: $e');
      rethrow;
    }
  }

  /// 将指定的云音频文件添加到音乐库（非递归扫描文件夹）。
  static Future<void> addCloudFilesToLibrary({
    required webdav.WebDavService service,
    required List<webdav.WebDavFile> files,
    String? connectionId,
    void Function(int addedCount)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    try {
      final audioFiles = files.where((f) => f.isAudioFile).toList();
      if (audioFiles.isEmpty) {
        onStatus?.call('未找到音频文件');
        return;
      }

      onStatus?.call('正在处理 ${audioFiles.length} 个音频文件...');

      final library = AudioLibrary.instance;
      final cloudAudios = <Audio>[];

      for (int i = 0; i < audioFiles.length; i++) {
        final file = audioFiles[i];
        try {
          if (library.audioCollection.any((a) => a.path == file.path)) continue;

          registerPath(file.path, service);
          onStatus?.call('正在处理 (${i + 1}/${audioFiles.length}): ${file.name}');

          final audio = await _createAudioViaRange(service, file,
              connectionId: connectionId);

          cloudAudios.add(audio);
          onProgress?.call(cloudAudios.length);
        } catch (e) {
          LOGGER.e('[CloudAudioPlayer] 处理文件失败: ${file.path} - $e');
          final parsed = _parseFileName(file.name);
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          cloudAudios.add(Audio(
            parsed.title,
            parsed.artist,
            '',
            0,
            0,
            null,
            null,
            file.path,
            now,
            now,
            'Cloud',
            connectionId: connectionId,
            fileSize: file.size > 0 ? file.size : null,
          ));
          onProgress?.call(cloudAudios.length);
        }
      }

      if (cloudAudios.isNotEmpty) {
        await library.addCloudAudios(cloudAudios);
        library.rebuildCollections();
        await library.saveCloudAudios();
        library.notifyUpdated();
        onStatus?.call('完成！已添加 ${cloudAudios.length} 首音频到音乐库');
      } else {
        onStatus?.call('所有文件已在音乐库中');
      }
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] 添加音频文件到库失败: $e');
      onStatus?.call('添加失败: $e');
      rethrow;
    }
  }
}
