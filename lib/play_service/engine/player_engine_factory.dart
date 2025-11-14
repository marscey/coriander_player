import 'dart:io';

import 'package:flutter/foundation.dart';
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
      default:
        throw UnimplementedError('Unsupported player engine type');
    }
  }
  
  // 根据平台和配置获取默认引擎
  static PlayerEngine getDefaultEngine() {
    final config = AppSettings.instance;
    final engineType = config.playerEngineType;
    
    if (engineType != null) {
      return createEngine(engineType);
    }
    
    // 根据平台选择默认引擎
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return createEngine(PlayerEngineType.mediaKit);
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      default:
        return createEngine(PlayerEngineType.bass);
    }
  }
}