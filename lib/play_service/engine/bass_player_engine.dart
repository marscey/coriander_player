import 'dart:async';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/play_service/engine/player_engine.dart';

class BassPlayerEngine implements PlayerEngine {
  late final BassPlayer _player;

  @override
  Future<void> initialize() async {
    _player = BassPlayer();
  }

  @override
  Future<void> setSource(String path,
      {bool isAsset = false,
      bool isNetwork = false,
      Map<String, String>? httpHeaders}) async {
    _player.setSource(path);
  }

  @override
  Future<void> play() async {
    _player.start();
  }

  @override
  Future<void> pause() async {
    _player.pause();
  }

  @override
  Future<void> stop() async {
    _player.pause();
    _player.seek(0);
  }

  @override
  Future<void> seek(Duration position) async {
    _player.seek(position.inSeconds.toDouble());
  }

  @override
  void setVolume(double volume) {
    _player.setVolumeDsp(volume);
  }

  @override
  void setSpeed(double speed) {}

  @override
  PlayerState get state => _player.playerState;

  @override
  Duration get position => Duration(seconds: _player.position.toInt());

  @override
  Duration get duration => Duration(seconds: _player.length.toInt());

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Stream<Duration> get positionStream =>
      _player.positionStream.map((seconds) => Duration(seconds: seconds.toInt()));

  @override
  Future<void> dispose() async {
    _player.free();
  }
}
