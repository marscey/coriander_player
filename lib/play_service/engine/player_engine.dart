import 'dart:async';
import 'package:coriander_player/src/bass/bass_player.dart';

abstract class PlayerEngine {
  Future<void> initialize();

  Future<void> setSource(String path,
      {bool isAsset = false,
      bool isNetwork = false,
      Map<String, String>? httpHeaders});

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  void setVolume(double volume);
  void setSpeed(double speed);

  PlayerState get state;
  Duration get position;
  Duration get duration;
  Duration get buffer;

  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get bufferStream;
  Stream<Duration> get durationStream;

  Future<void> dispose();
}
