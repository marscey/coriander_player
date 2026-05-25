import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';

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
  }

  /// macOS平台特定初始化
  static Future<void> _initializeForMacOS() async {
    await _configureAudioSession();
  }

  /// Android平台特定初始化
  static Future<void> _initializeForAndroid() async {
    await _configureAudioSession();
  }

  /// iOS平台特定初始化
  static Future<void> _initializeForiOS() async {
    await _configureAudioSession();
  }

  /// 配置音频会话 - 对 iOS/macOS/Android 均必要
  /// iOS: 设置 AVAudioSession category 为 playback 并激活，
  ///      确保后台播放、锁屏控制、蓝牙控制正常工作
  static Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      LOGGER.i("[PlatformInit] AudioSession configured as music/playback");

      // 关键：显式激活音频会话
      // iOS 上 MPNowPlayingInfoCenter 需要 AVAudioSession.setActive(true) 才能显示
      try {
        await session.setActive(true);
        LOGGER.i("[PlatformInit] AudioSession setActive(true) SUCCESS");
      } catch (e) {
        LOGGER.e("[PlatformInit] AudioSession setActive(true) FAILED: $e");
      }

      // 验证激活状态
      if (PlatformHelper.isIOS) {
        LOGGER.i("[PlatformInit] AudioSession isConfigured=${session.isConfigured}");
      }
    } catch (e) {
      // 音频会话配置失败不应阻止应用启动
      if (PlatformHelper.isDesktop) return;
      LOGGER.e("[PlatformInit] Failed to configure audio session: $e");
    }
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
