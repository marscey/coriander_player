import 'package:coriander_player/play_service/desktop_lyric_service.dart';
import 'package:coriander_player/play_service/lyric_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';

class PlayService {
  late final playbackService = PlaybackService(this);
  late final lyricService = LyricService(this);
  late final desktopLyricService = DesktopLyricService(this);

  PlayService._();

  static PlayService? _instance;
  static PlayService get instance {
    _instance ??= PlayService._();
    return _instance!;
  }

  /// 显式初始化 PlayService
  /// iOS/macOS 上需要等待 AudioService.init() 完成
  Future<void> initialize() async {
    await playbackService.initialize();
  }

  void close() {
    desktopLyricService.killDesktopLyric();
    playbackService.close();
  }
}
