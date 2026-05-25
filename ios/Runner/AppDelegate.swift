import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 在应用启动时配置并激活 AVAudioSession
    // 这是 iOS 锁屏/控制中心显示播放信息的必要条件
    // 必须在 Flutter 插件注册之前设置，确保 audio_service 能正确使用
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playback, mode: .default, options: [])
      try audioSession.setActive(true)
      NSLog("[AppDelegate] AVAudioSession configured: category=playback, active=true")
    } catch {
      NSLog("[AppDelegate] ERROR: AVAudioSession configuration failed: \(error)")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
