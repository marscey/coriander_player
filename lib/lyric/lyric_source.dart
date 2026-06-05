import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';

enum LyricSourceType {
  qq("qq"),
  kugou("kugou"),
  netease("netease"),
  local("local");

  final String name;
  const LyricSourceType(this.name);
}

/// 默认歌词来源
class LyricSource {
  LyricSourceType source;
  int? qqSongId;
  String? kugouSongHash;
  String? neteaseSongId;

  /// 歌词时间偏移（毫秒），正值=歌词提前显示，负值=歌词延后显示
  int offsetMs;

  LyricSource(this.source,
      {this.qqSongId, this.kugouSongHash, this.neteaseSongId, this.offsetMs = 0});

  static LyricSource fromMap(Map map) {
    final offsetMs = map["offsetMs"] as int? ?? 0;
    if (map["source"] == "qq") {
      final id = map["id"];
      return LyricSource(LyricSourceType.qq,
          qqSongId: id is int ? id : int.tryParse(id?.toString() ?? ''),
          offsetMs: offsetMs);
    } else if (map["source"] == "kugou") {
      return LyricSource(LyricSourceType.kugou,
          kugouSongHash: map["id"]?.toString(), offsetMs: offsetMs);
    } else if (map["source"] == "netease") {
      return LyricSource(LyricSourceType.netease,
          neteaseSongId: map["id"]?.toString(), offsetMs: offsetMs);
    } else {
      return LyricSource(LyricSourceType.local, offsetMs: offsetMs);
    }
  }

  Map toMap() {
    final base = switch (source) {
      LyricSourceType.qq => {"source": source.name, "id": qqSongId},
      LyricSourceType.kugou => {"source": source.name, "id": kugouSongHash},
      LyricSourceType.netease => {"source": source.name, "id": neteaseSongId},
      LyricSourceType.local => {"source": source.name, "id": null},
    };
    if (offsetMs != 0) base["offsetMs"] = offsetMs;
    return base;
  }
}

Map<String, LyricSource> LYRIC_SOURCES = {};

Future<void> readLyricSources() async {
  try {
    final supportPath = (await getAppDataDir()).path;
    final lyricSourcePath = PlatformHelper.joinPaths([supportPath, "lyric_source.json"]);

    final lyricSourceStr = File(lyricSourcePath).readAsStringSync();
    final Map lyricSourceJson = json.decode(lyricSourceStr);

    for (final item in lyricSourceJson.entries) {
      final path = item.key as String;
      // 云音频路径不是本地文件路径，跳过文件存在性检查
      final isCloudPath = !path.startsWith('/') && !path.contains(':\\');
      if (!isCloudPath && !File(path).existsSync()) continue;
      LYRIC_SOURCES[path] = LyricSource.fromMap(item.value);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

Future<void> saveLyricSources() async {
  try {
    final supportPath = (await getAppDataDir()).path;
    final lyricSourcePath = PlatformHelper.joinPaths([supportPath, "lyric_source.json"]);

    Map<String, Map> lyricSourceMaps = {};
    for (final item in LYRIC_SOURCES.entries) {
      lyricSourceMaps[item.key] = item.value.toMap();
    }

    final lyricSourceJson = json.encode(lyricSourceMaps);
    final output = await File(lyricSourcePath).create(recursive: true);
    await output.writeAsString(lyricSourceJson);
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}
