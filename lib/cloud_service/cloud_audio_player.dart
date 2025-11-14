import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:coriander_player/cloud_service/webdav_service.dart' as webdav;
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';

class CloudAudioPlayer {
  static Future<void> playCloudFile({
    required webdav.WebDavService service,
    required String filePath,
    required String fileName,
    void Function()? onPlayStarted,
  }) async {
    try {
      // 获取文件的临时下载路径
      final tempDir = Directory.systemTemp.path;
      final tempFilePath = '$tempDir/cloud_${DateTime.now().millisecondsSinceEpoch}_${fileName.replaceAll('/', '_')}';
      
      // 下载文件到临时目录
      final bytes = await service.downloadFile(filePath);
      final downloadedFile = File(tempFilePath);
      await downloadedFile.writeAsBytes(bytes);
      
      if (await downloadedFile.exists()) {
        // 创建临时音频对象并播放
        final audio = Audio(
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
        
        // 播放音频
      PlayService.instance.playbackService.play(0, [audio]);
        
        // 清理临时文件（延迟清理，给播放留出时间）
        Future.delayed(const Duration(minutes: 5), () {
          downloadedFile.delete().catchError((_) {});
        });
        
        onPlayStarted?.call();
      } else {
        throw Exception('文件下载失败');
      }
    } catch (e) {
      debugPrint('播放云文件失败: $e');
      rethrow;
    }
  }

  static Future<void> addCloudFolderToPlaylist({
    required webdav.WebDavService service,
    required String folderPath,
    void Function(int addedCount)? onProgress,
  }) async {
    try {
      // 扫描文件夹中的所有音频文件
      final audioFiles = await service.scanAudioFiles(folderPath);
      
      int addedCount = 0;
      for (final file in audioFiles) {
        try {
          // 下载文件到临时目录
          final tempDir = Directory.systemTemp.path;
          final fileName = file.path.split('/').last;
          final tempFilePath = '$tempDir/cloud_${DateTime.now().millisecondsSinceEpoch}_$fileName';
          
          final bytes = await service.downloadFile(file.path);
          final downloadedFile = File(tempFilePath);
          await downloadedFile.writeAsBytes(bytes);
          
          if (await downloadedFile.exists()) {
            // 创建临时音频对象并添加到播放列表
        final audio = Audio(
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
        
        // 添加到播放列表
        PlayService.instance.playbackService.addToNext(audio);
            addedCount++;
            onProgress?.call(addedCount);
            
            // 延迟清理临时文件
            Future.delayed(const Duration(minutes: 30), () {
              downloadedFile.delete().catchError((_) {});
            });
          }
        } catch (e) {
          debugPrint('添加文件失败: ${file.path} - $e');
          continue;
        }
      }
      
      onProgress?.call(addedCount);
    } catch (e) {
      debugPrint('添加云文件夹到播放列表失败: $e');
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
        
        final tempDir = Directory.systemTemp.path;
        final fileName = file.name;
        final tempFilePath = '$tempDir/cloud_${DateTime.now().millisecondsSinceEpoch}_$fileName';
        
        final bytes = await service.downloadFile(file.path);
        final downloadedFile = File(tempFilePath);
        await downloadedFile.writeAsBytes(bytes);
        
        if (await downloadedFile.exists()) {
          final audio = Audio(
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
          
          // 添加到播放列表
          PlayService.instance.playbackService.addToNext(audio);
          addedCount++;
          onProgress?.call(addedCount);
          
          Future.delayed(const Duration(minutes: 30), () {
            downloadedFile.delete().catchError((_) {});
          });
        }
      } catch (e) {
        debugPrint('添加文件失败: ${file.path} - $e');
        continue;
      }
    }
    
    onProgress?.call(addedCount);
  }
}