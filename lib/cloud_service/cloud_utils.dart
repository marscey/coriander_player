import 'dart:io';
import 'package:coriander_player/app_settings.dart';
import 'package:path/path.dart' as path;

/// 获取临时目录路径
Future<String> getTempDir() async {
  final tempDir = await getAppDataDir();
  return Directory(path.join(tempDir.path, 'temp')).create(recursive: true).then((dir) => dir.path);
}

/// 获取下载目录路径
Future<String> getDownloadDir() async {
  final docDir = await getAppDataDir();
  return Directory(path.join(docDir.path, 'Downloads')).create(recursive: true).then((dir) => dir.path);
}

/// 获取文档目录路径
Future<String> getDocumentsDir() async {
  return (await getAppDataDir()).path;
}

/// 清理临时文件
Future<void> cleanupTempFiles() async {
  try {
    final tempDir = await getTempDir();
    final dir = Directory(tempDir);
    
    if (await dir.exists()) {
      final files = await dir.list().where((entity) => entity is File).toList();
      final now = DateTime.now();
      
      for (final file in files) {
        final stat = await (file as File).stat();
        if (now.difference(stat.modified).inMinutes > 30) {
          await file.delete();
        }
      }
    }
  } catch (e) {
    // 清理失败时静默处理
  }
}

/// 检查文件是否为音频文件
bool isAudioFile(String fileName) {
  final audioExtensions = {
    '.mp3', '.flac', '.wav', '.aac', '.ogg', '.m4a', '.wma', '.ape', '.opus'
  };
  
  final extension = fileName.toLowerCase();
  for (final audioExt in audioExtensions) {
    if (extension.endsWith(audioExt)) {
      return true;
    }
  }
  
  return false;
}

/// 格式化文件大小
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = (bytes.toString().length / 3).floor();
  i = i.clamp(0, suffixes.length - 1);
  
  final size = bytes / (1024 * i);
  return '${size.toStringAsFixed(1)} ${suffixes[i]}';
}

/// 格式化日期时间
String formatDateTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);
  
  if (difference.inDays == 0) {
    return '今天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  } else if (difference.inDays == 1) {
    return '昨天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  } else if (difference.inDays < 7) {
    return '${difference.inDays}天前';
  } else {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}