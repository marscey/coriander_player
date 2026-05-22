import 'dart:convert';
import 'dart:io';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 最近播放记录条目
class RecentPlayEntry {
  final String audioPath;
  final int playedAt; // secs since UNIX EPOCH
  Audio? audioRef; // 内存中的Audio引用，不序列化

  RecentPlayEntry({required this.audioPath, required this.playedAt, this.audioRef});

  Map toMap() => {
        'audioPath': audioPath,
        'playedAt': playedAt,
      };

  factory RecentPlayEntry.fromMap(Map map) => RecentPlayEntry(
        audioPath: map['audioPath'],
        playedAt: map['playedAt'],
      );
}

/// 最近播放服务 - 单例
/// 记录用户播放过的音频，按播放时间倒序排列，去重（同一首歌只保留最近一次）
class RecentPlayService extends ChangeNotifier {
  static RecentPlayService get instance {
    _instance ??= RecentPlayService._();
    return _instance!;
  }

  static RecentPlayService? _instance;

  RecentPlayService._();

  /// 最多保留的记录数
  static const int maxRecords = 200;

  List<RecentPlayEntry> _entries = [];
  List<RecentPlayEntry> get entries => _entries;

  /// 获取最近播放的 Audio 列表
  /// 先从 AudioLibrary.audioCollection 查找，找不到则使用内存中的 audioRef（云音频场景）
  List<Audio> get recentAudios {
    final audios = <Audio>[];
    for (final entry in _entries) {
      final audio = AudioLibrary.instance.audioCollection
          .where((a) => a.path == entry.audioPath)
          .firstOrNull;
      if (audio != null) {
        audios.add(audio);
        // 更新内存引用
        entry.audioRef = audio;
      } else if (entry.audioRef != null) {
        // 云音频可能不在 audioCollection 中，使用内存引用
        audios.add(entry.audioRef!);
      }
    }
    return audios;
  }

  Future<String> _getFilePath() async {
    final supportPath = (await getAppDataDir()).path;
    return p.join(supportPath, 'recent_plays.json');
  }

  Future<void> load() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      _entries =
          jsonList.map((m) => RecentPlayEntry.fromMap(m as Map)).toList();
      LOGGER.i('[RecentPlayService] loaded ${_entries.length} entries');
    } catch (e) {
      LOGGER.e('[RecentPlayService] failed to load: $e');
    }
  }

  Future<void> _save() async {
    try {
      final filePath = await _getFilePath();
      final jsonList = _entries.map((e) => e.toMap()).toList();
      await File(filePath).writeAsString(jsonEncode(jsonList));
    } catch (e) {
      LOGGER.e('[RecentPlayService] failed to save: $e');
    }
  }

  /// 记录一次播放
  Future<void> recordPlay(Audio audio) async {
    // 去重：移除已有的同一首歌的记录
    _entries.removeWhere((e) => e.audioPath == audio.path);

    // 在列表头部插入新记录，同时保存Audio引用
    _entries.insert(
      0,
      RecentPlayEntry(
        audioPath: audio.path,
        playedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        audioRef: audio,
      ),
    );

    // 限制最大记录数
    if (_entries.length > maxRecords) {
      _entries = _entries.sublist(0, maxRecords);
    }

    notifyListeners();
    await _save();
  }

  /// 清空所有记录
  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _save();
  }

  /// 移除指定路径的记录
  Future<void> remove(String audioPath) async {
    _entries.removeWhere((e) => e.audioPath == audioPath);
    notifyListeners();
    await _save();
  }
}
