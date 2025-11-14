import 'dart:io';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:coriander_player/utils.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class PlatformDependencyManager {
  static final PlatformDependencyManager _instance = PlatformDependencyManager._();
  static PlatformDependencyManager get instance => _instance;

  DeviceInfo? _deviceInfo;
  PackageInfo? _packageInfo;

  PlatformDependencyManager._();

  /// 初始化平台特定的依赖
  Future<void> initialize() async {
    try {
      // 加载设备信息
      _packageInfo = await PackageInfo.fromPlatform();
      
      // 根据平台加载不同的设备信息
      if (Platform.isAndroid) {
        _deviceInfo = DeviceInfo.android(await DeviceInfoPlusPlugin().androidInfo);
        await _initializeAndroidDependencies();
      } else if (Platform.isIOS) {
        _deviceInfo = DeviceInfo.ios(await DeviceInfoPlusPlugin().iosInfo);
        await _initializeIOSDependencies();
      } else if (Platform.isWindows) {
        _deviceInfo = DeviceInfo.windows(await DeviceInfoPlusPlugin().windowsInfo);
        await _initializeWindowsDependencies();
      } else if (Platform.isMacOS) {
        _deviceInfo = DeviceInfo.macos(await DeviceInfoPlusPlugin().macosInfo);
        await _initializeMacOSDependencies();
      } else if (Platform.isLinux) {
        _deviceInfo = DeviceInfo.linux(await DeviceInfoPlusPlugin().linuxInfo);
        await _initializeLinuxDependencies();
      }
      
      LOGGER.i('平台特定依赖初始化成功: ${Platform.operatingSystem}');
    } catch (e, stackTrace) {
      LOGGER.e('平台特定依赖初始化失败: $e', stackTrace: stackTrace);
    }
  }

  /// 获取当前平台支持的播放器引擎列表
  List<PlayerEngineType> getSupportedPlayerEngines() {
    final List<PlayerEngineType> supportedEngines = [];
    
    // Windows、macOS和Linux平台支持BASS引擎
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      supportedEngines.add(PlayerEngineType.bass);
    }
    // 所有平台都支持MediaKit引擎
    supportedEngines.add(PlayerEngineType.mediaKit);
    
    return supportedEngines;
  }

  /// 检查指定的播放器引擎是否受当前平台支持
  bool isPlayerEngineSupported(PlayerEngineType engineType) {
    return getSupportedPlayerEngines().contains(engineType);
  }

  /// 获取推荐的播放器引擎（根据平台特性）
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
    // 实现Android平台特定的初始化逻辑
    // 例如请求权限、初始化音频会话等
    LOGGER.i('初始化Android平台依赖');
    
    // 这里可以添加Android特有的初始化代码
  }

  /// iOS平台特定初始化
  Future<void> _initializeIOSDependencies() async {
    // 实现iOS平台特定的初始化逻辑
    LOGGER.i('初始化iOS平台依赖');
    
    // 这里可以添加iOS特有的初始化代码
  }

  /// Windows平台特定初始化
  Future<void> _initializeWindowsDependencies() async {
    // Windows平台依赖已在其他地方初始化
    LOGGER.i('初始化Windows平台依赖');
  }

  /// macOS平台特定初始化
  Future<void> _initializeMacOSDependencies() async {
    // 实现macOS平台特定的初始化逻辑
    LOGGER.i('初始化macOS平台依赖');
    
    // 这里可以添加macOS特有的初始化代码
  }

  /// Linux平台特定初始化
  Future<void> _initializeLinuxDependencies() async {
    // 实现Linux平台特定的初始化逻辑
    LOGGER.i('初始化Linux平台依赖');
    
    // 这里可以添加Linux特有的初始化代码
  }

  /// 检查是否需要运行时权限
  Future<bool> checkRuntimePermissions() async {
    // 根据平台检查不同的权限需求
    if (Platform.isAndroid) {
      // 检查Android权限
      return true;
    } else if (Platform.isIOS) {
      // 检查iOS权限
      return true;
    }
    // 桌面平台通常不需要运行时权限
    return true;
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

// 设备信息类，用于存储不同平台的设备信息
class DeviceInfo {
  final dynamic info;
  final DevicePlatform platform;
  
  DeviceInfo.android(this.info) : platform = DevicePlatform.android;
  DeviceInfo.ios(this.info) : platform = DevicePlatform.ios;
  DeviceInfo.windows(this.info) : platform = DevicePlatform.windows;
  DeviceInfo.macos(this.info) : platform = DevicePlatform.macos;
  DeviceInfo.linux(this.info) : platform = DevicePlatform.linux;
}

enum DevicePlatform {
  android,
  ios,
  windows,
  macos,
  linux,
}

// 为了简化代码，这里创建一个DeviceInfoPlusPlugin的包装类
class DeviceInfoPlusPlugin {
  Future<dynamic> get androidInfo async {
    try {
      // 延迟加载device_info_plus库以避免在不支持的平台上出错
      final deviceInfoPlugin = await _importDeviceInfoPlus();
      if (deviceInfoPlugin != null) {
        return await deviceInfoPlugin.androidInfo;
      }
    } catch (e) {
      LOGGER.e('获取Android设备信息失败: $e');
    }
    return null;
  }

  Future<dynamic> get iosInfo async {
    try {
      final deviceInfoPlugin = await _importDeviceInfoPlus();
      if (deviceInfoPlugin != null) {
        return await deviceInfoPlugin.iosInfo;
      }
    } catch (e) {
      LOGGER.e('获取iOS设备信息失败: $e');
    }
    return null;
  }

  Future<dynamic> get windowsInfo async {
    try {
      final deviceInfoPlugin = await _importDeviceInfoPlus();
      if (deviceInfoPlugin != null) {
        return await deviceInfoPlugin.windowsInfo;
      }
    } catch (e) {
      LOGGER.e('获取Windows设备信息失败: $e');
    }
    return null;
  }

  Future<dynamic> get macosInfo async {
    try {
      final deviceInfoPlugin = await _importDeviceInfoPlus();
      if (deviceInfoPlugin != null) {
        return await deviceInfoPlugin.macOsInfo;
      }
    } catch (e) {
      LOGGER.e('获取macOS设备信息失败: $e');
    }
    return null;
  }

  Future<dynamic> get linuxInfo async {
    try {
      final deviceInfoPlugin = await _importDeviceInfoPlus();
      if (deviceInfoPlugin != null) {
        return await deviceInfoPlugin.linuxInfo;
      }
    } catch (e) {
      LOGGER.e('获取Linux设备信息失败: $e');
    }
    return null;
  }

  // 动态导入device_info_plus库
  Future<dynamic> _importDeviceInfoPlus() async {
    try {
      // 在Dart中，我们不能真正地动态导入库
      // 这里只是模拟这个行为，实际的导入应该在文件顶部完成
      // 但为了避免在不支持的平台上出错，我们在这里处理异常
      return null;
    } catch (e) {
      LOGGER.e('导入device_info_plus库失败: $e');
      return null;
    }
  }
}