import 'dart:convert';
import 'dart:typed_data';

import 'package:coriander_player/metadata/metadata_scraper.dart';
import 'package:coriander_player/utils.dart';
import 'package:http/http.dart' as http;

/// MusicBrainz 刮削源
///
/// 使用 MusicBrainz API 搜索录音（recording），获取元数据和 MusicBrainz ID。
/// 封面通过 Cover Art Archive API 获取。
///
/// API 文档：
/// - 搜索：https://musicbrainz.org/doc/MusicBrainz_API#Search
/// - 封面：https://musicbrainz.org/doc/Cover_Art_Archive/API
class MusicBrainzScraper extends MetadataScraper {
  /// API 基础地址（可通过 MetadataStore.updateScraperApiBase 替换）
  String apiBase;

  /// HTTP 客户端
  final http.Client _client;

  /// 请求间隔控制（MusicBrainz 要求每秒不超过1次请求）
  DateTime? _lastRequestTime;

  MusicBrainzScraper({
    this.apiBase = 'https://musicbrainz.org/ws/2',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get id => 'musicbrainz';

  @override
  String get name => 'MusicBrainz';

  @override
  Future<List<ScrapeResult>> search(
    String query, {
    String? artist,
    String? album,
  }) async {
    try {
      // 构建搜索查询
      final parts = <String>[];
      parts.add('recording:"$query"');
      if (artist != null && artist.isNotEmpty) {
        parts.add('artist:"$artist"');
      }
      if (album != null && album.isNotEmpty) {
        parts.add('release:"$album"');
      }
      final q = parts.join(' AND ');

      final url = Uri.parse('$apiBase/recording?query=${Uri.encodeComponent(q)}&fmt=json&limit=10');
      final response = await _throttledGet(url);

      if (response.statusCode != 200) {
        LOGGER.e("[MusicBrainzScraper] search failed: HTTP ${response.statusCode}");
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final List? recordings = json["recordings"];
      if (recordings == null) return [];

      final results = <ScrapeResult>[];
      for (final recording in recordings) {
        final title = recording["title"] as String? ?? "";

        // 提取艺术家
        String artists = "";
        final List? artistCredits = recording["artist-credit"];
        if (artistCredits != null) {
          artists = artistCredits
              .map<String>((ac) => (ac["name"] ?? ac["artist"]?["name"] ?? "") as String)
              .join("、");
        }

        // 提取专辑（release）
        String? albumName;
        String? mbReleaseId;
        final List? releases = recording["releases"];
        if (releases != null && releases.isNotEmpty) {
          albumName = releases.first["title"] as String?;
          mbReleaseId = releases.first["id"] as String?;
        }

        final mbRecordingId = recording["id"] as String?;
        final mbArtistId = artistCredits?.first?["artist"]?["id"] as String?;

        // 计算匹配度
        final score = _computeScore(query, artist, album, title, artists, albumName ?? "");

        results.add(ScrapeResult(
          title: title.isNotEmpty ? title : null,
          artist: artists.isNotEmpty ? artists : null,
          album: albumName,
          score: score,
          source: id,
          mbRecordingId: mbRecordingId,
          mbReleaseId: mbReleaseId,
          mbArtistId: mbArtistId,
          platformIds: {
            'mbRecordingId': mbRecordingId,
            'mbReleaseId': mbReleaseId,
          },
        ));
      }

      return results;
    } catch (e) {
      LOGGER.e("[MusicBrainzScraper] search failed: $e");
      return [];
    }
  }

  @override
  Future<String?> fetchLyric(ScrapeResult result) async {
    // MusicBrainz 不提供歌词服务
    return null;
  }

  @override
  Future<Uint8List?> fetchCover(ScrapeResult result) async {
    // 通过 Cover Art Archive 获取封面
    final mbReleaseId = result.platformIds['mbReleaseId'] ?? result.mbReleaseId;
    if (mbReleaseId == null) return null;

    try {
      final url = Uri.parse('https://coverartarchive.org/release/$mbReleaseId/front');
      final response = await _throttledGet(url);

      if (response.statusCode == 200) {
        return Uint8List.fromList(response.bodyBytes);
      }

      // 尝试 500px 版本
      final url500 = Uri.parse('https://coverartarchive.org/release/$mbReleaseId/front-500');
      final response500 = await _throttledGet(url500);

      if (response500.statusCode == 200) {
        return Uint8List.fromList(response500.bodyBytes);
      }

      LOGGER.e("[MusicBrainzScraper] fetchCover failed: HTTP ${response.statusCode}");
      return null;
    } catch (e) {
      LOGGER.e("[MusicBrainzScraper] fetchCover failed: $e");
      return null;
    }
  }

  /// 限速 GET 请求（MusicBrainz 要求每秒不超过1次）
  Future<http.Response> _throttledGet(Uri url) async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed.inMilliseconds < 1100) {
        await Future.delayed(Duration(milliseconds: 1100 - elapsed.inMilliseconds));
      }
    }

    _lastRequestTime = DateTime.now();

    return _client.get(url, headers: {
      'User-Agent': 'CorianderPlayer/1.0 (https://github.com/coriander-player)',
      'Accept': 'application/json',
    });
  }

  /// 计算匹配度
  double _computeScore(
    String query,
    String? queryArtist,
    String? queryAlbum,
    String resultTitle,
    String resultArtist,
    String resultAlbum,
  ) {
    int maxLen = query.length +
        (queryArtist?.length ?? 0) +
        (queryAlbum?.length ?? 0);
    if (maxLen == 0) return 0.0;

    int score = 0;

    // 标题匹配
    final minTitleLen = query.length < resultTitle.length
        ? query.length
        : resultTitle.length;
    for (int i = 0; i < minTitleLen; i++) {
      if (query[i].toLowerCase() == resultTitle[i].toLowerCase()) score++;
    }

    // 艺术家匹配
    if (queryArtist != null && queryArtist.isNotEmpty) {
      final minArtistLen = queryArtist.length < resultArtist.length
          ? queryArtist.length
          : resultArtist.length;
      for (int i = 0; i < minArtistLen; i++) {
        if (queryArtist[i].toLowerCase() == resultArtist[i].toLowerCase()) {
          score++;
        }
      }
    }

    // 专辑匹配
    if (queryAlbum != null && queryAlbum.isNotEmpty) {
      final minAlbumLen = queryAlbum.length < resultAlbum.length
          ? queryAlbum.length
          : resultAlbum.length;
      for (int i = 0; i < minAlbumLen; i++) {
        if (queryAlbum[i].toLowerCase() == resultAlbum[i].toLowerCase()) {
          score++;
        }
      }
    }

    return score / maxLen;
  }
}
