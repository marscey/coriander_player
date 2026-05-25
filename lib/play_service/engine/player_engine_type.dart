import 'dart:io';

enum PlayerEngineType {
  bass,
  mediaKit;

  /// 获取当前平台默认的播放引擎类型
  /// 移动端默认 MediaKit，桌面端默认 BASS
  static PlayerEngineType get defaultForPlatform {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return PlayerEngineType.bass;
    }
    return PlayerEngineType.mediaKit;
  }
}