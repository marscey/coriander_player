import 'dart:async';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/play_service/engine/player_engine.dart';

class BassPlayerEngine implements PlayerEngine {
  late final BassPlayer _player;

  @override
  Future<void> initialize() async {
    _player = BassPlayer();
    // BassPlayer 在构造函数中已经初始化了，所以这里不需要额外的异步初始化
  }

  @override
  Future<void> setSource(String path, {bool isAsset = false, bool isNetwork = false}) {
    // BASS 库主要用于本地文件播放，暂时不支持 asset 和网络流
    // 在 future 版本中可以扩展这个功能
    _player.setSource(path);
    return Future.value();
  }

  @override
  Future<void> play() {
    _player.start();
    return Future.value();
  }

  @override
  Future<void> pause() {
    _player.pause();
    return Future.value();
  }

  @override
  Future<void> stop() {
    // BassPlayer 没有直接的 stop 方法，可以通过 pause 和 seek 到开始位置来模拟
    _player.pause();
    _player.seek(0);
    return Future.value();
  }

  @override
  Future<void> seek(Duration position) {
    _player.seek(position.inSeconds.toDouble());
    return Future.value();
  }

  @override
  void setVolume(double volume) {
    // BASS 库使用 setVolumeDsp 方法来设置音量
    _player.setVolumeDsp(volume);
  }

  @override
  void setSpeed(double speed) {
    // BASS 库目前没有直接暴露设置播放速度的方法
    // 这个功能可以在 future 版本中通过 BASS 库的 BASS_ATTRIB_TEMPO 属性来实现
  }

  @override
  PlayerState get state {
    return _player.playerState;
  }

  @override
  Duration get position {
    return Duration(seconds: _player.position.toInt());
  }

  @override
  Duration get duration {
    return Duration(seconds: _player.length.toInt());
  }

  @override
  Stream<PlayerState> get playerStateStream {
    return _player.playerStateStream;
  }

  @override
  Stream<Duration> get positionStream {
    return _player.positionStream.map((seconds) => Duration(seconds: seconds.toInt()));
  }

  @override
  Future<void> dispose() {
    _player.free();
    return Future.value();
  }
}