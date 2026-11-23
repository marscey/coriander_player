import 'dart:io';

import 'package:coriander_player/platform_helper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用数据目录名（与 Windows 端保持一致）
const String kAppDirName = 'coriander_player';

/// 应用数据根目录
///
/// - macOS：`~/Library/Application Support/coriander_player`
///   遵循 Apple 官方约定（Application Support 存放应用自建数据），
///   并避开 `~/Documents` —— 该目录常被云盘 / 系统“存储优化”抽成
///   `compressed,dataless` 占位文件，读不到内容会导致配置与数据库初始化失败。
/// - 其他平台：保持原有 `getApplicationDocumentsDirectory()/coriander_player`
Future<Directory> getAppDataDir() async {
  final base = await _baseDir();
  return Directory(p.join(base.path, kAppDirName)).create(recursive: true);
}

Future<Directory> _baseDir() async {
  if (PlatformHelper.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory(p.join(home, 'Library', 'Application Support'));
    }
  }
  return getApplicationDocumentsDirectory();
}

/// 日志目录
///
/// - macOS：`~/Library/Logs/coriander_player`（Console.app 可直接检索）
/// - 其他平台：`<appData>/logs`
Future<Directory> getLogsDir() async {
  if (PlatformHelper.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory(p.join(home, 'Library', 'Logs', kAppDirName))
          .create(recursive: true);
    }
  }
  final dataDir = await getAppDataDir();
  return Directory(p.join(dataDir.path, 'logs')).create(recursive: true);
}

/// 旧版数据目录（迁移前的位置）
Future<Directory> getLegacyAppDataDir() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, kAppDirName));
}

/// 从旧数据目录一次性迁移到新目录
///
/// macOS 从 `~/Documents/coriander_player` 迁到 Application Support。
/// 只复制可读取的文件；被云盘抽空（dataless）的文件会跳过并记录，不会中断启动。
Future<void> migrateAppData() async {
  try {
    final target = await getAppDataDir();
    final legacy = await getLegacyAppDataDir();
    if (p.equals(target.path, legacy.path)) return;
    if (target.listSync().isNotEmpty) return;
    if (!legacy.existsSync()) return;

    var copied = 0;
    for (final entity in legacy.listSync()) {
      final name = p.basename(entity.path);
      if (entity is! File) continue;
      try {
        entity.copySync(p.join(target.path, name));
        copied++;
      } catch (_) {
        // 云盘占位文件读不到内容，跳过即可，后续由应用重建
      }
    }

    // 旧版元数据库（sqflite 默认落在 Documents）
    try {
      final oldDb = File(p.join(p.dirname(legacy.path), 'coriander_metadata.db'));
      final newDb = File(p.join(target.path, 'coriander_metadata.db'));
      if (oldDb.existsSync() && !newDb.existsSync()) {
        oldDb.copySync(newDb.path);
        copied++;
      }
    } catch (_) {}

    if (copied > 0) {
      stdout.writeln('[storage] migrated $copied file(s) to ${target.path}');
    }
  } catch (err) {
    stdout.writeln('[storage] migrate failed: $err');
  }
}
