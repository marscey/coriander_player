import 'dart:typed_data';

/// 刮削结果 - 统一的数据结构
class ScrapeResult {
  final String? title;
  final String? artist;
  final String? album;
  final int? track;
  final int? year;
  final String? genre;
  final String? lyricText;
  final bool lyricSynced;
  final String? coverUrl;
  final String? mbRecordingId;
  final String? mbReleaseId;
  final String? mbArtistId;

  /// 匹配置信度 (0.0 - 1.0)
  final double score;

  /// 刮削源标识（netease/qq/kugou/musicbrainz）
  final String source;

  /// 平台特定 ID，用于后续查询歌词/封面
  /// 例如：{"neteaseSongId": "123", "qqSongId": 456, "kugouHash": "abc"}
  final Map<String, dynamic> platformIds;

  const ScrapeResult({
    this.title,
    this.artist,
    this.album,
    this.track,
    this.year,
    this.genre,
    this.lyricText,
    this.lyricSynced = false,
    this.coverUrl,
    this.mbRecordingId,
    this.mbReleaseId,
    this.mbArtistId,
    this.score = 0.0,
    required this.source,
    this.platformIds = const {},
  });

  ScrapeResult copyWith({
    String? title,
    String? artist,
    String? album,
    int? track,
    int? year,
    String? genre,
    String? lyricText,
    bool? lyricSynced,
    String? coverUrl,
    String? mbRecordingId,
    String? mbReleaseId,
    String? mbArtistId,
    double? score,
    String? source,
    Map<String, dynamic>? platformIds,
  }) {
    return ScrapeResult(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      track: track ?? this.track,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      lyricText: lyricText ?? this.lyricText,
      lyricSynced: lyricSynced ?? this.lyricSynced,
      coverUrl: coverUrl ?? this.coverUrl,
      mbRecordingId: mbRecordingId ?? this.mbRecordingId,
      mbReleaseId: mbReleaseId ?? this.mbReleaseId,
      mbArtistId: mbArtistId ?? this.mbArtistId,
      score: score ?? this.score,
      source: source ?? this.source,
      platformIds: platformIds ?? this.platformIds,
    );
  }

  @override
  String toString() {
    return 'ScrapeResult(source: $source, title: $title, artist: $artist, '
        'album: $album, score: ${score.toStringAsFixed(3)})';
  }
}

/// 可插拔刮削源抽象接口
///
/// 每个刮削源实现此接口，提供搜索、歌词获取、封面获取功能。
/// 通过 ScraperOrchestrator 统一调度，支持优先级和降级策略。
abstract class MetadataScraper {
  /// 唯一标识（对应 ScraperConfig 的 type）
  String get id;

  /// 显示名称
  String get name;

  /// 搜索元数据
  ///
  /// [query] 搜索关键词（通常是歌曲名）
  /// [artist] 可选的艺术家名，用于精确匹配
  /// [album] 可选的专辑名，用于精确匹配
  Future<List<ScrapeResult>> search(
    String query, {
    String? artist,
    String? album,
  });

  /// 获取歌词
  ///
  /// [result] 之前搜索返回的结果，包含平台特定 ID
  /// 返回 LRC 格式歌词文本，或 null
  Future<String?> fetchLyric(ScrapeResult result);

  /// 获取封面图片数据
  ///
  /// [result] 之前搜索返回的结果，包含平台特定 ID 或 coverUrl
  /// 返回图片二进制数据，或 null
  Future<Uint8List?> fetchCover(ScrapeResult result);
}
