import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/play_service/engine/bass_player_engine.dart';
import 'package:coriander_player/play_service/engine/media_kit_player_engine.dart';
import 'package:coriander_player/play_service/engine/player_engine.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';

class PlayerEngineFactory {
  static PlayerEngine createEngine(PlayerEngineType type) {
    switch (type) {
      case PlayerEngineType.bass:
        return BassPlayerEngine();
      case PlayerEngineType.mediaKit:
        return MediaKitPlayerEngine();
    }
  }

  /// BASS 引擎仅在桌面平台可用
  static bool _isBassSupported() {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  // 根据平台和配置获取默认引擎
  static PlayerEngine getDefaultEngine() {
    final config = AppSettings.instance;
    final engineType = config.playerEngineType;

    // 如果配置了引擎类型，验证平台兼容性
    if (engineType != null) {
      if (engineType == PlayerEngineType.bass && !_isBassSupported()) {
        // 配置了 BASS 但当前平台不支持，回退到 MediaKit
        return createEngine(PlayerEngineType.mediaKit);
      }
      return createEngine(engineType);
    }

    // 根据平台选择默认引擎
    if (_isBassSupported()) {
      return createEngine(PlayerEngineType.bass);
    }
    // 移动端默认使用 MediaKit
    return createEngine(PlayerEngineType.mediaKit);
  }
}