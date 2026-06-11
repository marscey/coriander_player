import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

/// 流派服务 - 从 MetadataStore 查询流派信息并关联 AudioLibrary
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

  /// 从 MetadataStore 加载流派数据并关联 AudioLibrary
  Future<void> load() async {
    try {
      final db = await MetadataStore.instance.database;
      final results = await db.rawQuery(
        'SELECT DISTINCT genre FROM ${MetadataStore.metadataTable} WHERE genre IS NOT NULL AND genre != ""',
      );

      final Map<String, Genre> newCollection = {};

      for (final row in results) {
        final genreName = row['genre'] as String;
        if (genreName.isEmpty) continue;
        newCollection.putIfAbsent(genreName, () => Genre(name: genreName));
      }

      // 关联 AudioLibrary 中的音频到流派
      for (Audio audio in AudioLibrary.instance.audioCollection) {
        try {
          final record = await MetadataStore.instance
              .getMetadataByPath(audio.path);
          if (record?.genre != null && record!.genre!.isNotEmpty) {
            newCollection
                .putIfAbsent(record.genre!, () => Genre(name: record.genre!))
                .works
                .add(audio);
          }
        } catch (_) {
          // 忽略单个音频的查询错误
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
