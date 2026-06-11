// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/recent_play_service.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

List<Playlist> PLAYLISTS = [];

/// 内置歌单：我的最爱
final Playlist BUILTIN_FAVORITES = Playlist(
  "我的最爱",
  {},
  isBuiltIn: true,
  builtInId: 'favorites',
);

/// 内置歌单：最近播放
final Playlist BUILTIN_RECENT = Playlist(
  "最近播放",
  {},
  isBuiltIn: true,
  builtInId: 'recent',
);

/// 歌单管理器（ChangeNotifier）
/// 统一管理歌单的增删改操作，并通知所有监听者刷新 UI
class PlaylistManager extends ChangeNotifier {
  static PlaylistManager get instance {
    _instance ??= PlaylistManager._();
    return _instance!;
  }

  static PlaylistManager? _instance;

  PlaylistManager._();

  /// 获取所有歌单（内置歌单在前，用户歌单在后，顺序固定不受排序影响）
  /// 最近播放内置歌单会动态从 RecentPlayService 获取内容
  List<Playlist> get allPlaylists {
    // 动态更新"最近播放"内置歌单的内容
    final recentAudios = RecentPlayService.instance.recentAudios;
    BUILTIN_RECENT.audios = {
      for (final audio in recentAudios) audio.path: audio,
    };

    final builtIn = PLAYLISTS.where((p) => p.isBuiltIn).toList();
    final user = PLAYLISTS.where((p) => !p.isBuiltIn).toList();
    return [...builtIn, ...user];
  }

  /// 获取仅用户自建歌单列表（用于排序等操作）
  List<Playlist> get userPlaylists =>
      PLAYLISTS.where((p) => !p.isBuiltIn).toList();

  void _notify() {
    notifyListeners();
  }

  /// 新建歌单
  void createPlaylist(String name) {
    PLAYLISTS.add(Playlist(name, {}));
    savePlaylists();
    _notify();
  }

  /// 删除用户歌单
  void removePlaylist(Playlist playlist) {
    if (playlist.isBuiltIn) return;
    PLAYLISTS.remove(playlist);
    savePlaylists();
    _notify();
  }

  /// 重命名歌单
  void renamePlaylist(Playlist playlist, String newName) {
    if (playlist.isBuiltIn) return;
    playlist.name = newName;
    savePlaylists();
    _notify();
  }

  /// 添加歌曲到指定歌单
  void addAudioToPlaylist(Playlist playlist, Audio audio) {
    if (!playlist.audios.containsKey(audio.path)) {
      playlist.audios[audio.path] = audio;
      savePlaylists();
      _notify();
    }
  }

  /// 批量添加歌曲到指定歌单
  void addAudiosToPlaylist(Playlist playlist, Iterable<Audio> audios) {
    bool changed = false;
    for (var audio in audios) {
      if (!playlist.audios.containsKey(audio.path)) {
        playlist.audios[audio.path] = audio;
        changed = true;
      }
    }
    if (changed) {
      savePlaylists();
      _notify();
    }
  }

  /// 从歌单中移除歌曲
  void removeAudioFromPlaylist(Playlist playlist, Audio audio) {
    if (playlist.isBuiltIn && playlist.builtInId == 'recent') return;
    playlist.audios.remove(audio.path);
    savePlaylists();
    _notify();
  }

  /// 批量移除歌曲
  void removeAudiosFromPlaylist(Playlist playlist, Iterable<Audio> audios) {
    if (playlist.isBuiltIn && playlist.builtInId == 'recent') return;
    for (var audio in audios) {
      playlist.audios.remove(audio.path);
    }
    savePlaylists();
    _notify();
  }
}

/// 兼容旧代码：获取所有歌单（直接读取，不触发通知）
List<Playlist> get allPlaylists => PlaylistManager.instance.allPlaylists;

Future<void> readPlaylists() async {
  try {
    final supportPath = (await getAppDataDir()).path;
    final playlistsPath =
        PlatformHelper.joinPaths([supportPath, "playlists.json"]);

    final playlistsStr = File(playlistsPath).readAsStringSync();
    final List playlistsJson = json.decode(playlistsStr);

    for (Map item in playlistsJson) {
      final playlist = Playlist.fromMap(item);
      if (playlist.isBuiltIn) {
        // "我的最爱"内置歌单：恢复持久化的歌曲数据
        if (playlist.builtInId == 'favorites') {
          BUILTIN_FAVORITES.audios = playlist.audios;
        }
        // "最近播放"内置歌单：内容由 RecentPlayService 动态管理，跳过
        continue;
      }
      PLAYLISTS.add(playlist);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  // 确保内置歌单在列表顶部
  _ensureBuiltInPlaylists();
}

/// 确保内置歌单存在且位于列表顶部
void _ensureBuiltInPlaylists() {
  // 移除可能已存在的内置歌单
  PLAYLISTS.removeWhere((p) => p.isBuiltIn);

  // 在列表头部插入内置歌单
  PLAYLISTS.insert(0, BUILTIN_FAVORITES);
  PLAYLISTS.insert(1, BUILTIN_RECENT);
}

Future<void> savePlaylists() async {
  try {
    final supportPath = (await getAppDataDir()).path;
    final playlistsPath =
        PlatformHelper.joinPaths([supportPath, "playlists.json"]);

    List<Map> playlistMaps = [];
    for (final item in PLAYLISTS) {
      playlistMaps.add(item.toMap());
    }

    final playlistsJson = json.encode(playlistMaps);
    final output = await File(playlistsPath).create(recursive: true);
    await output.writeAsString(playlistsJson);
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

class Playlist {
  String name;

  /// path, audio
  Map<String, Audio> audios;

  /// 是否为内置歌单（不可删除、不可重命名）
  final bool isBuiltIn;

  /// 内置歌单的唯一标识（favorites / recent）
  final String? builtInId;

  Playlist(this.name, this.audios, {this.isBuiltIn = false, this.builtInId});

  Map toMap() {
    final List<Map> audioMaps = [];
    for (var item in audios.values) {
      audioMaps.add(item.toMap());
    }
    return {
      "name": name,
      "audios": audioMaps,
      "isBuiltIn": isBuiltIn,
      "builtInId": builtInId,
    };
  }

  factory Playlist.fromMap(Map map) {
    final Map<String, Audio> audios = {};
    final List audioMaps = map["audios"];
    for (var item in audioMaps) {
      final audio = Audio.fromMap(item);
      audios[audio.path] = audio;
    }
    return Playlist(
      map["name"],
      audios,
      isBuiltIn: map["isBuiltIn"] ?? false,
      builtInId: map["builtInId"],
    );
  }
}
