import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

/// 流派服务 - 从 AudioLibrary 获取流派信息
class GenreService extends ChangeNotifier {
  static GenreService get instance {
    _instance ??= GenreService._();
    return _instance!;
  }

  static GenreService? _instance;

  GenreService._();

  Map<String, Genre> _genreCollection = {};
  Map<String, Genre> get genreCollection => _genreCollection;

  List<Genre> get genres => _genreCollection.values.toList();

  /// 从 AudioLibrary.genreCollection 加载流派数据
  Future<void> load() async {
    try {
      final Map<String, Genre> newCollection = {};

      // 从 AudioLibrary.genreCollection 获取（本地扫描 + 云音频的 genre 标签）
      for (final entry in AudioLibrary.instance.genreCollection.entries) {
        final genreName = entry.key;
        if (genreName.isEmpty) continue;
        final genre = newCollection.putIfAbsent(
          genreName,
          () => Genre(name: genreName),
        );
        for (final audio in entry.value.works) {
          if (!genre.works.any((a) => a.path == audio.path)) {
            genre.works.add(audio);
          }
        }
      }

      _genreCollection = newCollection;
      notifyListeners();
      LOGGER.i('[GenreService] loaded ${_genreCollection.length} genres');
    } catch (e) {
      LOGGER.e('[GenreService] failed to load: $e');
    }
  }

  /// 刷新流派数据（当 AudioLibrary 变化时调用）
  Future<void> refresh() async {
    await load();
  }
}
