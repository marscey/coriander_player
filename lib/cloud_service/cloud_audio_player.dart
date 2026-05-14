import 'dart:io';
import 'dart:convert';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;
import 'package:coriander_player/cloud_service/webdav_service.dart' as webdav;
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/utils.dart';

class CloudAudioPlayer {
  static bool get _supportsStreaming {
    final engineType = AppSettings.instance.playerEngineType;
    return engineType == PlayerEngineType.mediaKit;
  }

  static String _titleFromFileName(String fileName) {
    final ext = path.extension(fileName);
    return fileName.replaceAll(ext, '');
  }

  static Audio _createStreamingAudio(webdav.WebDavFile file, String streamingUrl) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Audio(
      _titleFromFileName(file.name),
      'Cloud Audio',
      'Cloud',
      0,
      0,
      null,
      null,
      streamingUrl,
      now,
      now,
      'Cloud',
    );
  }

  static Future<void> _updateMetadataAsync(
    webdav.WebDavService service,
    webdav.WebDavFile file,
  ) async {
    try {
      final cloudDir = Directory(path.join(
        Directory.systemTemp.path,
        'coriander_meta_${DateTime.now().millisecondsSinceEpoch}',
      ));
      await cloudDir.create(recursive: true);

      final tempFilePath = path.join(cloudDir.path, file.name.replaceAll('/', '_'));
      final bytes = await service.downloadFile(file.path);
      final downloadedFile = File(tempFilePath);
      await downloadedFile.writeAsBytes(bytes);

      final metaIndexDir = Directory(path.join(
        Directory.systemTemp.path,
        'coriander_metaidx_${DateTime.now().millisecondsSinceEpoch}',
      ));
      await metaIndexDir.create(recursive: true);

      await buildIndexFromFoldersRecursively(
        folders: [cloudDir.path],
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
            if (playbackService.nowPlaying?.path.startsWith('http') == true) {
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
                if (pic != null) {
                  np.setCover(MemoryImage(pic));
                }
              } catch (_) {}

              playbackService.refreshNowPlaying();
              try {
                ThemeProvider.instance.applyThemeFromAudio(np);
              } catch (_) {}
            }
          }
        }
      }

      await cloudDir.delete(recursive: true);
      await metaIndexDir.delete(recursive: true);
    } catch (e) {
      LOGGER.e('[CloudAudioPlayer] 异步更新元数据失败: $e');
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

    return Audio(
      path.basename(downloadedFile.path),
      'Unknown Artist',
      'Unknown Album',
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

    final tempFilePath = path.join(cloudDir.path, fileName.replaceAll('/', '_'));
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
    void Function()? onPlayStarted,
  }) async {
    try {
      LOGGER.i('[CloudAudioPlayer] playCloudFile: filePath=$filePath, _supportsStreaming=$_supportsStreaming');
      if (_supportsStreaming) {
        final streamingUrl = await service.getStreamingUrl(filePath);
        final isCdnUrl = streamingUrl.startsWith('https://') ||
            streamingUrl.startsWith('http://');
        final authHeaders = isCdnUrl &&
                (streamingUrl.contains('X-Amz-Signature') ||
                    streamingUrl.contains('x-amz'))
            ? null
            : service.getAuthHeaders();
        LOGGER.i('[CloudAudioPlayer] streamingUrl=$streamingUrl');
        LOGGER.i('[CloudAudioPlayer] authHeaders=$authHeaders');
        final file = webdav.WebDavFile(
          path: filePath,
          name: fileName,
          isDirectory: false,
          size: 0,
          lastModified: DateTime.now(),
        );
        final audio = _createStreamingAudio(file, streamingUrl);
        LOGGER.i('[CloudAudioPlayer] created streaming audio: title=${audio.title}, path=${audio.path}');

        PlayService.instance.playbackService.play(
          0,
          [audio],
          httpHeaders: authHeaders,
        );
        LOGGER.i('[CloudAudioPlayer] play() called with streaming audio');

        _updateMetadataAsync(service, file);
      } else {
        LOGGER.i('[CloudAudioPlayer] Downloading file to temp dir...');
        final downloadedFile = await _downloadToTempDir(service, filePath, fileName);
        final audio = await _createAudioWithMetadata(downloadedFile);
        LOGGER.i('[CloudAudioPlayer] Downloaded audio: title=${audio.title}, path=${audio.path}');

        PlayService.instance.playbackService.play(0, [audio]);

        Future.delayed(const Duration(minutes: 5), () {
          downloadedFile.parent.delete(recursive: true).catchError((_) => downloadedFile.parent);
        });
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
    void Function(int addedCount)? onProgress,
  }) async {
    try {
      final audioFiles = await service.scanAudioFiles(folderPath);

      int addedCount = 0;
      for (final file in audioFiles) {
        try {
          if (_supportsStreaming) {
            final streamingUrl = await service.getStreamingUrl(file.path);
            final audio = _createStreamingAudio(file, streamingUrl);
            PlayService.instance.playbackService.addToNext(audio);
          } else {
            final downloadedFile = await _downloadToTempDir(service, file.path, file.name);
            final audio = await _createAudioWithMetadata(downloadedFile);
            PlayService.instance.playbackService.addToNext(audio);

            Future.delayed(const Duration(minutes: 30), () {
              downloadedFile.parent.delete(recursive: true).catchError((_) => downloadedFile.parent);
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
    void Function(int addedCount)? onProgress,
  }) async {
    int addedCount = 0;

    for (final file in files) {
      try {
        if (!file.isAudioFile) continue;

        if (_supportsStreaming) {
          final streamingUrl = await service.getStreamingUrl(file.path);
          final audio = _createStreamingAudio(file, streamingUrl);
          PlayService.instance.playbackService.addToNext(audio);
        } else {
          final downloadedFile = await _downloadToTempDir(service, file.path, file.name);
          final audio = await _createAudioWithMetadata(downloadedFile);
          PlayService.instance.playbackService.addToNext(audio);

          Future.delayed(const Duration(minutes: 30), () {
            downloadedFile.parent.delete(recursive: true).catchError((_) => downloadedFile.parent);
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
}
