import 'dart:async';
import 'package:coriander_player/play_service/engine/player_engine.dart';
import 'package:coriander_player/src/bass/bass_player.dart' as bass_player;
import 'package:coriander_player/utils.dart';
import 'package:media_kit/media_kit.dart';

class MediaKitPlayerEngine implements PlayerEngine {
  Player? _player;
  StreamController<bass_player.PlayerState>? _playerStateStreamController;
  StreamController<Duration>? _positionStreamController;
  Timer? _positionTimer;
  String? _currentMediaPath;
  bass_player.PlayerState _currentState = bass_player.PlayerState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  bool _isDisposed = false;

  List<StreamSubscription> _playerSubscriptions = [];

  @override
  Future<void> initialize() async {
    LOGGER.i("[MediaKit] initialize START");
    _player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.info,
      ),
    );
    _playerStateStreamController =
        StreamController<bass_player.PlayerState>.broadcast();
    _positionStreamController = StreamController<Duration>.broadcast();

    _playerSubscriptions = [
      _player!.stream.playing.listen(_onPlayingChanged),
      _player!.stream.completed.listen(_onCompleted),
      _player!.stream.duration.listen(_onDurationChanged),
      _player!.stream.position.listen(_onPositionChanged),
      _player!.stream.error.listen((error) {
        LOGGER.e("[MediaKit] error: $error");
      }),
      _player!.stream.log.listen((log) {
        if (log.level == 'error' || log.level == 'warn') {
          LOGGER.w("[MediaKit] log[${log.level}][${log.prefix}]: ${log.text}");
        }
      }),
    ];

    _positionTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isDisposed || _player == null) return;
      try {
        final pos = _player!.state.position;
        if (pos.inMilliseconds >= 0) {
          _currentPosition = pos;
          _positionStreamController?.add(_currentPosition);
        }
      } catch (_) {}
    });
    LOGGER.i("[MediaKit] initialize DONE");
  }

  void _onPlayingChanged(bool playing) {
    if (_isDisposed) return;
    LOGGER.i("[MediaKit] playing changed: $playing (currentMediaPath=$_currentMediaPath)");
    if (playing) {
      _currentState = bass_player.PlayerState.playing;
    } else {
      _currentState = _currentMediaPath == null
          ? bass_player.PlayerState.stopped
          : bass_player.PlayerState.paused;
    }
    _playerStateStreamController?.add(_currentState);
  }

  void _onCompleted(bool completed) {
    if (_isDisposed) return;
    LOGGER.i("[MediaKit] completed: $completed");
    if (completed) {
      _currentState = bass_player.PlayerState.completed;
      _playerStateStreamController?.add(bass_player.PlayerState.completed);
    }
  }

  void _onDurationChanged(Duration duration) {
    if (_isDisposed) return;
    if (duration.inMilliseconds > 0) {
      _currentDuration = duration;
      LOGGER.i("[MediaKit] duration updated: ${duration.inMilliseconds}ms");
    }
  }

  void _onPositionChanged(Duration position) {
    if (_isDisposed) return;
    if (position.inMilliseconds >= 0) {
      _currentPosition = position;
    }
  }

  @override
  Future<void> setSource(String path,
      {bool isAsset = false,
      bool isNetwork = false,
      Map<String, String>? httpHeaders}) async {
    if (_isDisposed || _player == null) return;

    LOGGER.i("[MediaKit] setSource START: path=$path, isNetwork=$isNetwork, hasHeaders=${httpHeaders != null}");

    _currentMediaPath = null;
    _currentDuration = Duration.zero;
    _currentPosition = Duration.zero;
    _currentState = bass_player.PlayerState.stopped;
    _playerStateStreamController?.add(_currentState);

    Media media;
    if (isNetwork) {
      media = Media(path, httpHeaders: httpHeaders);
    } else if (isAsset) {
      media = Media('asset:///$path');
    } else {
      media = Media(path);
    }

    LOGGER.i("[MediaKit] calling player.open with play=false...");
    await _player!.open(media, play: false);
    LOGGER.i("[MediaKit] player.open completed");

    _currentMediaPath = path;
    _currentState = bass_player.PlayerState.paused;
    _playerStateStreamController?.add(_currentState);

    _currentDuration = _player!.state.duration;
    LOGGER.i("[MediaKit] duration after open: ${_currentDuration.inMilliseconds}ms");
    LOGGER.i("[MediaKit] setSource DONE");
  }

  @override
  Future<void> play() async {
    if (_isDisposed || _player == null) return;
    LOGGER.i("[MediaKit] play");
    await _player!.play();
    _currentState = bass_player.PlayerState.playing;
    _playerStateStreamController?.add(_currentState);
  }

  @override
  Future<void> pause() async {
    if (_isDisposed || _player == null) return;
    LOGGER.i("[MediaKit] pause");
    await _player!.pause();
    _currentState = bass_player.PlayerState.paused;
    _playerStateStreamController?.add(_currentState);
  }

  @override
  Future<void> stop() async {
    if (_isDisposed || _player == null) return;
    LOGGER.i("[MediaKit] stop");
    try {
      await _player!.stop();
    } catch (_) {}
    _currentMediaPath = null;
    _currentState = bass_player.PlayerState.stopped;
    _currentPosition = Duration.zero;
    _playerStateStreamController?.add(_currentState);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isDisposed || _player == null) return;
    await _player!.seek(position);
  }

  @override
  void setVolume(double volume) {
    if (_isDisposed || _player == null) return;
    _player!.setVolume(volume * 100);
  }

  @override
  void setSpeed(double speed) {
    if (_isDisposed || _player == null) return;
    _player!.setRate(speed);
  }

  @override
  bass_player.PlayerState get state => _currentState;

  @override
  Duration get position {
    if (_isDisposed || _player == null) return Duration.zero;
    final pos = _currentPosition;
    return pos.inMilliseconds >= 0 ? pos : Duration.zero;
  }

  @override
  Duration get duration {
    if (_isDisposed || _player == null) return Duration.zero;
    final d = _currentDuration;
    return d.inMilliseconds > 0 ? d : Duration.zero;
  }

  @override
  Stream<bass_player.PlayerState> get playerStateStream =>
      _playerStateStreamController?.stream ?? const Stream.empty();

  @override
  Stream<Duration> get positionStream =>
      _positionStreamController?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    LOGGER.i("[MediaKit] dispose START");

    _positionTimer?.cancel();
    _positionTimer = null;

    for (final sub in _playerSubscriptions) {
      await sub.cancel();
    }
    _playerSubscriptions = [];

    await _playerStateStreamController?.close();
    _playerStateStreamController = null;

    await _positionStreamController?.close();
    _positionStreamController = null;

    try {
      await _player?.stop();
    } catch (_) {}

    await _player?.dispose();
    _player = null;
    LOGGER.i("[MediaKit] dispose DONE");
  }
}
