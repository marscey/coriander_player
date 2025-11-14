import 'dart:async';
import 'package:coriander_player/src/bass/bass_player.dart';

abstract class PlayerEngine {
  // 初始化播放器
  Future<void> initialize();
  
  // 设置音频源
  Future<void> setSource(String path, {bool isAsset = false, bool isNetwork = false});
  
  // 播放控制
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  
  // 音频属性控制
  void setVolume(double volume);
  void setSpeed(double speed);
  
  // 状态获取
  PlayerState get state;
  Duration get position;
  Duration get duration;
  
  // 状态流
  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  
  // 释放资源
  Future<void> dispose();
}