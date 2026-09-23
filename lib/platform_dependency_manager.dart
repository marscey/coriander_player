import 'dart:io';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:coriander_player/utils.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 平台能力与依赖管理。
///
/// 提供播放器引擎的平台支持性判断（单一真相源），
/// 被 [PlayerEngineFactory]、设置页 PlayerEngineSelector、
/// main.dart 启动校正逻辑共同使用。
class PlatformDependencyManager {
  static final PlatformDependencyManager _instance =
      PlatformDependencyManager._();
  static PlatformDependencyManager get instance => _instance;

  PackageInfo? _packageInfo;

  PlatformDependencyManager._();

  /// 初始化平台特定的依赖
  Future<void> initialize() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();

      if (Platform.isAndroid) {
        await _initializeAndroidDependencies();
      } else if (Platform.isIOS) {
        await _initializeIOSDependencies();
      } else if (Platform.isWindows) {
        await _initializeWindowsDependencies();
      } else if (Platform.isMacOS) {
        await _initializeMacOSDependencies();
      } else if (Platform.isLinux) {
        await _initializeLinuxDependencies();
      }

      LOGGER.i('平台特定依赖初始化成功: ${Platform.operatingSystem}');
    } catch (e, stackTrace) {
      LOGGER.e('平台特定依赖初始化失败: $e', stackTrace: stackTrace);
    }
  }

  /// 获取当前平台支持的播放器引擎列表。
  ///
  /// Windows、macOS 和 Linux 桌面平台支持 BASS 引擎；
  /// iOS 和 Android 移动平台不支持 BASS 引擎（无原生库）；
  /// 所有平台都支持 MediaKit 引擎。
  List<PlayerEngineType> getSupportedPlayerEngines() {
    final List<PlayerEngineType> supportedEngines = [];

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      supportedEngines.add(PlayerEngineType.bass);
    }
    supportedEngines.add(PlayerEngineType.mediaKit);

    return supportedEngines;
  }

  /// 检查指定的播放器引擎是否受当前平台支持
  bool isPlayerEngineSupported(PlayerEngineType engineType) {
    return getSupportedPlayerEngines().contains(engineType);
  }

  /// 获取推荐的播放器引擎（根据平台特性）。
  ///
  /// 注意：Linux 桌面端虽支持 BASS（见 [getSupportedPlayerEngines]），
  /// 但推荐使用 MediaKit。
  PlayerEngineType getRecommendedPlayerEngine() {
    // Windows和macOS平台推荐BASS引擎
    if (Platform.isWindows || Platform.isMacOS) {
      return PlayerEngineType.bass;
    }
    // Linux和移动端默认使用MediaKit引擎
    return PlayerEngineType.mediaKit;
  }

  /// Android平台特定初始化
  Future<void> _initializeAndroidDependencies() async {
    LOGGER.i('初始化Android平台依赖');
    // Android 特有的初始化代码（如请求权限、初始化音频会话等）
  }

  /// iOS平台特定初始化
  Future<void> _initializeIOSDependencies() async {
    LOGGER.i('初始化iOS平台依赖');
    // iOS 特有的初始化代码
  }

  /// Windows平台特定初始化
  Future<void> _initializeWindowsDependencies() async {
    LOGGER.i('初始化Windows平台依赖');
  }

  /// macOS平台特定初始化
  Future<void> _initializeMacOSDependencies() async {
    LOGGER.i('初始化macOS平台依赖');
    // macOS 特有的初始化代码
  }

  /// Linux平台特定初始化
  Future<void> _initializeLinuxDependencies() async {
    LOGGER.i('初始化Linux平台依赖');
    // Linux 特有的初始化代码
  }

  /// 获取当前平台的信息
  String getPlatformInfo() {
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;
    final packageName = _packageInfo?.packageName ?? '未知';
    final appVersion = _packageInfo?.version ?? '未知';

    return '平台: $os\n版本: $osVersion\n应用包名: $packageName\n应用版本: $appVersion';
  }
}
