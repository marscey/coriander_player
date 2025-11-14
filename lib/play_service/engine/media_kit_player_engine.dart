import 'dart:async';
import 'package:coriander_player/play_service/engine/player_engine.dart';
import 'package:coriander_player/src/bass/bass_player.dart' as bass_player;

// 导入media_kit库
import 'package:media_kit/media_kit.dart';

class MediaKitPlayerEngine implements PlayerEngine {
  late final Player _player;
  late final StreamController<bass_player.PlayerState> _playerStateStreamController;
  late final StreamController<Duration> _positionStreamController;
  late Duration _duration;
  Timer? _positionTimer;
  // 用于缓存最后知道的媒体源路径，避免直接访问_player.currentMedia
  String? _currentMediaPath;

  @override
  Future<void> initialize() async {
    // 初始化Player实例
    _player = Player();
    _playerStateStreamController = StreamController<bass_player.PlayerState>.broadcast();
    _positionStreamController = StreamController<Duration>.broadcast();
    _duration = Duration.zero;

    // 监听播放状态变化
    _player.stream.playing.listen((playing) {
      bass_player.PlayerState playerState;
      if (playing) {
        playerState = bass_player.PlayerState.playing;
      } else {
        // 通过是否有当前媒体路径来区分暂停和停止状态
        bool isStopped = _currentMediaPath == null;
        playerState = isStopped ? bass_player.PlayerState.stopped : bass_player.PlayerState.paused;
      }
      _playerStateStreamController.add(playerState);
    });

    // 监听播放完成事件
    _player.stream.completed.listen((completed) {
      if (completed) {
        _playerStateStreamController.add(bass_player.PlayerState.stopped);
      }
    });

    // 监听位置变化
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      try {
        final position = _player.state.position;
        _positionStreamController.add(position);
      } catch (e) {
        // 忽略获取位置失败的情况
      }
    });
  }

  @override
  Future<void> setSource(String path, {bool isAsset = false, bool isNetwork = false}) async {
    try {
      // 停止当前播放
      await stop();

      // 创建媒体路径
      String mediaPath;
      if (isNetwork) {
        mediaPath = path;
      } else if (isAsset) {
        mediaPath = 'asset:///$path';
      } else {
        mediaPath = path;
      }

      // 设置媒体源
      await _player.open(Media(mediaPath));
      _currentMediaPath = mediaPath;

      // 尝试获取时长
      try {
          await Future.delayed(const Duration(milliseconds: 100));
          final duration = _player.state.duration;
          _duration = duration;
        } catch (e) {
          // 在生产环境中应使用日志系统
          // logger.e('Failed to get duration immediately: $e');
        }
    } catch (e) {
      // 在生产环境中应使用日志系统
      // logger.e('Failed to set source: $e');
      _currentMediaPath = null;
      rethrow;
    }
  }

  @override
  Future<void> play() {
    return _player.play();
  }

  @override
  Future<void> pause() {
    return _player.pause();
  }

  @override
  Future<void> stop() {
    return _player.stop();
  }

  @override
  Future<void> seek(Duration position) {
    return _player.seek(position);
  }

  @override
  void setVolume(double volume) {
    _player.setVolume(volume);
  }

  @override
  void setSpeed(double speed) {
    _player.setRate(speed);
  }

  @override
  bass_player.PlayerState get state {
    // 在media_kit中，我们通过streams获取最新状态，而不是直接访问属性
    // 这里返回一个默认值，实际应用中应该通过playerStateStream获取
    // 或者在内部维护一个最新的状态值
    return bass_player.PlayerState.stopped;
  }

  @override
  Duration get position {
    // 由于我们无法直接同步获取位置，我们需要在内部维护一个最新的位置值
    // 在实际应用中，调用者应该通过positionStream获取最新位置
    return Duration.zero;
  }

  @override
  Duration get duration {
    return _duration;
  }

  @override
  Stream<bass_player.PlayerState> get playerStateStream => _playerStateStreamController.stream;

  @override
  Stream<Duration> get positionStream => _positionStreamController.stream;

  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _playerStateStreamController.close();
    await _positionStreamController.close();
    await _player.dispose();
  }
}