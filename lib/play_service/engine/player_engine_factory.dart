import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/platform_dependency_manager.dart';
import 'package:coriander_player/play_service/engine/bass_player_engine.dart';
import 'package:coriander_player/play_service/engine/media_kit_player_engine.dart';
import 'package:coriander_player/play_service/engine/player_engine.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';

/// 播放器引擎的创建入口。
///
/// 平台支持性判断统一由 [PlatformDependencyManager] 提供（单一真相源），
/// 与设置页（PlayerEngineSelector）及 main.dart 启动校正逻辑共享同一来源。
class PlayerEngineFactory {
  static PlayerEngine createEngine(PlayerEngineType type) {
    switch (type) {
      case PlayerEngineType.bass:
        return BassPlayerEngine();
      case PlayerEngineType.mediaKit:
        return MediaKitPlayerEngine();
    }
  }

  // 根据平台和配置获取默认引擎
  static PlayerEngine getDefaultEngine() {
    final engineType = AppSettings.instance.playerEngineType;
    final dependencyManager = PlatformDependencyManager.instance;

    // 如果配置了引擎类型，验证平台兼容性
    if (engineType != null) {
      if (dependencyManager.isPlayerEngineSupported(engineType)) {
        return createEngine(engineType);
      }
      // 配置的引擎当前平台不支持，回退到 MediaKit
      return createEngine(PlayerEngineType.mediaKit);
    }

    // 未配置时按平台默认：桌面端（Windows/macOS/Linux）支持 BASS 则优先 BASS，
    // 移动端使用 MediaKit。
    // 注意：此处不用 getRecommendedPlayerEngine()——它对 Linux 推荐 MediaKit，
    // 与历史默认行为（Linux 默认 BASS）不同。
    if (dependencyManager.isPlayerEngineSupported(PlayerEngineType.bass)) {
      return createEngine(PlayerEngineType.bass);
    }
    return createEngine(PlayerEngineType.mediaKit);
  }
}
