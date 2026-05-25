import 'dart:io';
import 'package:home_widget/home_widget.dart';
import '../library/audio_library.dart';
import '../play_service/play_service.dart';
import '../platform_helper.dart';
import '../src/bass/bass_player.dart';

/// iOS 桌面小组件数据管理
/// 通过 home_widget 将当前播放信息写入 AppGroup SharedPreferences，
/// 供 WidgetKit (Swift) 原生小组件读取
class NowPlayingWidget {
  static const String _widgetGroupId = 'group.com.senyepss.corianderPlayer';
  static const String _keyTitle = 'now_playing_title';
  static const String _keyArtist = 'now_playing_artist';
  static const String _keyAlbum = 'now_playing_album';
  static const String _keyIsPlaying = 'now_playing_is_playing';
  static const String _keyHasAudio = 'now_playing_has_audio';

  /// 初始化小组件（注册交互回调等）
  static Future<void> initialize() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    // 注册小组件交互回调
    HomeWidget.setAppGroupId(_widgetGroupId);

    // 注册后台回调（用户点击小组件时唤醒应用）
    HomeWidget.registerInteractivityCallback(
      _backgroundCallback,
    );
  }

  /// 更新小组件数据 - 在播放状态变化时调用
  static Future<void> update() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      final playbackService = PlayService.instance.playbackService;
      final nowPlaying = playbackService.nowPlaying;
      final isPlaying = playbackService.playerState == PlayerState.playing;

      if (nowPlaying != null) {
        await HomeWidget.saveWidgetData(_keyTitle, nowPlaying.title);
        await HomeWidget.saveWidgetData(_keyArtist, nowPlaying.artist);
        await HomeWidget.saveWidgetData(_keyAlbum, nowPlaying.album);
        await HomeWidget.saveWidgetData(_keyIsPlaying, isPlaying);
        await HomeWidget.saveWidgetData(_keyHasAudio, true);
      } else {
        await HomeWidget.saveWidgetData(_keyHasAudio, false);
        await HomeWidget.saveWidgetData(_keyIsPlaying, false);
      }

      // 通知 WidgetKit 更新小组件
      await HomeWidget.updateWidget(
        name: 'NowPlayingWidget',
        iOSName: 'NowPlayingWidget',
        androidName: 'NowPlayingWidget',
      );
    } catch (e) {
      // 小组件更新失败不应影响播放
    }
  }

  /// 清除小组件数据
  static Future<void> clear() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      await HomeWidget.saveWidgetData(_keyHasAudio, false);
      await HomeWidget.saveWidgetData(_keyIsPlaying, false);
      await HomeWidget.updateWidget(
        name: 'NowPlayingWidget',
        iOSName: 'NowPlayingWidget',
      );
    } catch (e) {
      // ignore
    }
  }

  /// 小组件交互后台回调
  @pragma('vm:entry-point')
  static void _backgroundCallback(Uri? uri) {
    // 用户点击小组件时的回调
    // 目前仅打开应用，不做额外操作
  }
}
