import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:coriander_player/cloud_service/webdav_service.dart' as webdav;
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/utils.dart';

class CloudScanner {
  static Future<String> _getCloudCacheDir() async {
    final appDir = await getAppDataDir();
    final cacheDir = Directory(path.join(appDir.path, 'cloud_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  static Future<void> scanCloudFolder({
    required webdav.WebDavService service,
    required String folderPath,
    void Function(int foundCount)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    try {
      onStatus?.call('正在扫描音频文件...');

      final audioFiles = await service.scanAudioFiles(folderPath);
      onStatus?.call('找到 ${audioFiles.length} 个音频文件');

      final cloudCacheDir = await _getCloudCacheDir();
      int processedCount = 0;

      for (final file in audioFiles) {
        try {
          onStatus?.call('正在处理: ${file.name}');

          final localPath = path.join(
            cloudCacheDir,
            '${DateTime.now().millisecondsSinceEpoch}_${file.name}',
          );
          final bytes = await service.downloadFile(file.path);
          final localFile = File(localPath);
          await localFile.writeAsBytes(bytes);

          if (await localFile.exists()) {
            await buildIndexFromFoldersRecursively(
              folders: [cloudCacheDir],
              indexPath: (await getAppDataDir()).path,
            ).drain();

            processedCount++;
            onProgress?.call(processedCount);
          }
        } catch (e) {
          LOGGER.e('[CloudScanner] 处理文件失败: ${file.path} - $e');
          continue;
        }
      }

      onStatus?.call('扫描完成，共处理 $processedCount 个文件');
    } catch (e) {
      LOGGER.e('[CloudScanner] 扫描云文件夹失败: $e');
      onStatus?.call('扫描失败: $e');
      rethrow;
    }
  }

  static Future<void> rescanCloudConnection({
    required webdav.WebDavService service,
    required String rootPath,
    void Function(int foundCount)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    await scanCloudFolder(
      service: service,
      folderPath: rootPath,
      onProgress: onProgress,
      onStatus: onStatus,
    );
  }

  static Future<List<String>> getSupportedAudioExtensions() async {
    return [
      '.mp3',
      '.flac',
      '.wav',
      '.aac',
      '.ogg',
      '.m4a',
      '.wma',
      '.ape',
      '.opus',
    ];
  }
}
