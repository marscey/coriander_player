import 'dart:io';
import 'package:coriander_player/platform_helper.dart';

class PlatformSpecificInitialization {
  /// 针对不同平台进行特定的初始化
  static Future<void> initializeForPlatform() async {
    switch (Platform.operatingSystem) {
      case 'windows':
        await _initializeForWindows();
        break;
      case 'macos':
        await _initializeForMacOS();
        break;
      case 'android':
        await _initializeForAndroid();
        break;
      case 'ios':
        await _initializeForiOS();
        break;
      default:
        // 其他平台不需要特定的初始化
        break;
    }
  }

  /// Windows平台特定初始化
  static Future<void> _initializeForWindows() async {
    // Windows平台上的BASS库初始化主要在BassPlayer类中完成
    // 这里可以添加一些Windows特有的配置
  }

  /// macOS平台特定初始化
  static Future<void> _initializeForMacOS() async {
    // macOS平台上可能需要的特定初始化
    // 例如配置音频会话或权限
  }

  /// Android平台特定初始化
  static Future<void> _initializeForAndroid() async {
    // 在Android平台上，可能需要请求音频焦点或处理Doze模式
    // 这些操作通常会在MediaKitPlayerEngine中处理
  }

  /// iOS平台特定初始化
  static Future<void> _initializeForiOS() async {
    // 在iOS平台上，可能需要配置音频会话类别
    // 例如设置后台播放或混音模式
  }

  /// 检查平台是否支持指定的播放引擎
  static bool isEngineSupportedForPlatform(String engineType) {
    switch (engineType) {
      case 'bass':
        // BASS库主要支持桌面平台
        return Platform.isWindows || Platform.isMacOS;
      case 'mediaKit':
        // media_kit库应该支持所有平台，但在不同平台上可能有不同的功能支持
        return true;
      default:
        return false;
    }
  }

  /// 获取平台推荐的最佳播放引擎
  static String getRecommendedEngineForPlatform() {
    if (Platform.isWindows || Platform.isMacOS) {
      // 桌面平台优先使用BASS引擎，因为它有更好的音频质量和格式支持
      return 'bass';
    } else if (Platform.isAndroid || Platform.isIOS) {
      // 移动平台优先使用media_kit引擎，因为它有更好的网络流媒体支持
      return 'mediaKit';
    } else {
      // 其他平台默认使用BASS引擎
      return 'bass';
    }
  }
}