import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:desktop_lyric/message.dart' as msg;

class DesktopLyricService extends ChangeNotifier {
  final PlayService playService;
  DesktopLyricService(this.playService);

  PlaybackService get _playbackService => playService.playbackService;

  Future<Process?> desktopLyric = Future.value(null);
  StreamSubscription? _desktopLyricSubscription;

  bool _isLocked = false;
  bool get isLocked => PlatformHelper.isDesktop ? _isLocked : false;
  set isLocked(bool value) => _isLocked = value;

  Future<void> startDesktopLyric() async {
    if (!PlatformHelper.isDesktop) return;

    // 移除macOS平台的限制，允许在所有桌面平台上启动桌面歌词
    
    final desktopLyricPath = PlatformHelper.desktopLyricExecutablePath;

    final nowPlaying = _playbackService.nowPlaying;
    final currScheme = ThemeProvider.instance.currScheme;
    final isDarkMode = ThemeProvider.instance.themeMode == ThemeMode.dark;

    desktopLyric = Process.start(desktopLyricPath, [
      json.encode(msg.InitArgsMessage(
        _playbackService.playerState == PlayerState.playing,
        nowPlaying?.title ?? "无",
        nowPlaying?.artist ?? "无",
        nowPlaying?.album ?? "无",
        isDarkMode,
        currScheme.primary.value,
        currScheme.surfaceContainer.value,
        currScheme.onSurface.value,
      ).toJson())
    ]);

    final process = await desktopLyric;

    process?.stderr.transform(utf8.decoder).listen((event) {
      LOGGER.e("[desktop lyric] $event");
    });

    // 使用更强大的StreamTransformer来过滤和验证消息
    final streamTransformer = StreamTransformer<String, String>.fromHandlers(
      handleData: (data, sink) {
        LOGGER.d("[desktop lyric] Raw data received: $data");
        
        // 分割消息行
        final lines = data.split('\n');
        for (final line in lines) {
          final trimmedLine = line.trim();
          
          // 严格过滤逻辑
          if (trimmedLine.isEmpty) {
            LOGGER.d("[desktop lyric] Filtered out empty line");
            continue;
          }
          
          if (trimmedLine.startsWith('^')) {
            LOGGER.d("[desktop lyric] Filtered out command prompt: $trimmedLine");
            continue;
          }
          
          // 尝试提前验证JSON格式
          try {
            // 检查是否以{开头并以}结尾
            if (trimmedLine.startsWith('{') && trimmedLine.endsWith('}')) {
              // 尝试解析JSON以确认有效性
              json.decode(trimmedLine);
              sink.add(trimmedLine);
              LOGGER.d("[desktop lyric] Valid JSON message added to stream");
            } else {
              LOGGER.d("[desktop lyric] Filtered out non-JSON format: $trimmedLine");
            }
          } catch (e) {
            LOGGER.d("[desktop lyric] Filtered out invalid JSON: $trimmedLine. Error: $e");
          }
        }
      },
    );

    _desktopLyricSubscription = process?.stdout
        .transform(utf8.decoder)
        .transform(streamTransformer)
        .listen(
      (event) {
        try {
          // 添加日志以查看经过严格过滤后的消息
          LOGGER.d("[desktop lyric] Processing validated JSON message: $event");
          
          final Map messageMap = json.decode(event);
          final String messageType = messageMap["type"];
          final messageContent = messageMap["message"] as Map<String, dynamic>;
          if (messageType ==
              msg.getMessageTypeName<msg.ControlEventMessage>()) {
            final controlEvent = 
                msg.ControlEventMessage.fromJson(messageContent);
            switch (controlEvent.event) {
              case msg.ControlEvent.pause:
                _playbackService.pause();
                break;
              case msg.ControlEvent.start:
                _playbackService.start();
                break;
              case msg.ControlEvent.previousAudio:
                _playbackService.lastAudio();
                break;
              case msg.ControlEvent.nextAudio:
                _playbackService.nextAudio();
                break;
              case msg.ControlEvent.lock:
                isLocked = true;
                notifyListeners();
                break;
              case msg.ControlEvent.close:
                killDesktopLyric();
                break;
            }
          }
        } catch (err) {
          LOGGER.e("[desktop lyric] Error parsing message: $err\nOriginal message: $event");
        }
      },
    );

    notifyListeners();
  }

  Future<bool> get canSendMessage => desktopLyric.then(
        (value) => value != null,
      );

  void sendMessage(msg.Message message) {
    desktopLyric.then((value) {
      value?.stdin.write(message.buildMessageJson());
    }).catchError((err, trace) {
      LOGGER.e(err, stackTrace: trace);
    });
  }

  void killDesktopLyric() {
    if (!PlatformHelper.isDesktop) return;

    desktopLyric.then((value) {
      value?.kill();
      desktopLyric = Future.value(null);

      _desktopLyricSubscription?.cancel();
      _desktopLyricSubscription = null;

      notifyListeners();
    }).catchError((err, trace) {
      LOGGER.e(err, stackTrace: trace);
    });
  }

  void sendUnlockMessage() {
    if (!PlatformHelper.isDesktop) return;

    sendMessage(const msg.UnlockMessage());
    isLocked = false;
    notifyListeners();
  }

  void sendThemeModeMessage(bool darkMode) {
    sendMessage(msg.ThemeModeChangedMessage(darkMode));
  }

  void sendThemeMessage(ColorScheme scheme) {
    sendMessage(msg.ThemeChangedMessage(
      scheme.primary.value,
      scheme.surfaceContainer.value,
      scheme.onSurface.value,
    ));
  }

  void sendPlayerStateMessage(bool isPlaying) {
    sendMessage(msg.PlayerStateChangedMessage(isPlaying));
  }

  void sendNowPlayingMessage(Audio nowPlaying) {
    sendMessage(msg.NowPlayingChangedMessage(
      nowPlaying.title,
      nowPlaying.artist,
      nowPlaying.album,
    ));
  }

  void sendLyricLineMessage(LyricLine line) {
    if (line is SyncLyricLine) {
      sendMessage(msg.LyricLineChangedMessage(
        line.content,
        line.length,
        line.translation,
      ));
    } else if (line is LrcLine) {
      final splitted = line.content.split("┃");
      final content = splitted.first;
      final translation = splitted.length > 1 ? splitted[1] : null;
      sendMessage(msg.LyricLineChangedMessage(
        content,
        line.length,
        translation,
      ));
    }
  }
}
