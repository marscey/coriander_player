import 'dart:convert';
import 'dart:io';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 播放状态持久化服务
///
/// 保存和恢复当前播放列表、播放索引和播放进度。
/// 存储在独立的 playback_state.json 文件中。
class PlaybackStateService {
  PlaybackStateService._();
  static final PlaybackStateService instance = PlaybackStateService._();

  static const String _fileName = "playback_state.json";

  Future<Directory> get _appDataDir async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory(path.join(dir.path, "coriander_player"))
        .create(recursive: true);
  }

  /// 保存播放状态到磁盘
  ///
  /// playlist 每项为 {"path": "...", "connectionId": "...?"}
  /// 向后兼容：旧格式为 String 列表
  Future<void> save({
    required List<PlaylistEntry> playlist,
    required int currentIndex,
    required int positionSeconds,
    required int durationSeconds,
  }) async {
    try {
      final stateMap = {
        "playlist": playlist
            .map((e) => {"path": e.path, "connectionId": e.connectionId})
            .toList(),
        "currentIndex": currentIndex,
        "position": positionSeconds,
        "duration": durationSeconds,
      };
      final stateStr = json.encode(stateMap);
      final appDataDir = await _appDataDir;
      final statePath = path.join(appDataDir.path, _fileName);
      final output = await File(statePath).create(recursive: true);
      output.writeAsStringSync(stateStr);
    } catch (err, trace) {
      LOGGER.e("[PlaybackStateService] Failed to save state", stackTrace: trace);
    }
  }

  /// 从磁盘读取播放状态
  ///
  /// 返回 null 表示没有保存的状态或读取失败
  /// 向后兼容：旧格式 playlist 为 List<String>，自动转为 PlaylistEntry
  Future<PlaybackState?> load() async {
    try {
      final appDataDir = await _appDataDir;
      final statePath = path.join(appDataDir.path, _fileName);
      final file = File(statePath);
      if (!file.existsSync()) return null;

      final stateStr = file.readAsStringSync();
      if (stateStr.isEmpty) return null;

      final stateMap = json.decode(stateStr) as Map<String, dynamic>;
      final rawList = stateMap["playlist"] as List<dynamic>;
      // 向后兼容：旧格式为 List<String>，新格式为 List<Map>
      final playlist = rawList.map((item) {
        if (item is String) {
          return PlaylistEntry(path: item, connectionId: null);
        }
        final m = item as Map<String, dynamic>;
        return PlaylistEntry(
          path: m["path"]?.toString() ?? '',
          connectionId: m["connectionId"]?.toString(),
        );
      }).toList();
      final currentIndex = stateMap["currentIndex"] as int;
      final position = stateMap["position"] as int;
      final duration = stateMap["duration"] as int? ?? 0;

      return PlaybackState(
        playlist: playlist,
        currentIndex: currentIndex,
        positionSeconds: position,
        durationSeconds: duration,
      );
    } catch (err, trace) {
      LOGGER.e("[PlaybackStateService] Failed to load state", stackTrace: trace);
      return null;
    }
  }
}

/// 播放列表条目（path + connectionId）
class PlaylistEntry {
  final String path;
  final String? connectionId;

  const PlaylistEntry({required this.path, this.connectionId});
}

/// 播放状态数据
class PlaybackState {
  final List<PlaylistEntry> playlist;
  final int currentIndex;
  final int positionSeconds;
  final int durationSeconds;

  const PlaybackState({
    required this.playlist,
    required this.currentIndex,
    required this.positionSeconds,
    this.durationSeconds = 0,
  });
}
