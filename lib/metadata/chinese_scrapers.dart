import 'dart:math';
import 'dart:typed_data';

import 'package:coriander_player/metadata/metadata_scraper.dart';
import 'package:coriander_player/utils.dart';
import 'package:http/http.dart' as http;
import 'package:music_api/music_api.dart';

/// 下载图片的通用方法
Future<Uint8List?> _downloadImage(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return Uint8List.fromList(response.bodyBytes);
    }
    LOGGER.e("[Scraper] download image failed: HTTP ${response.statusCode}");
    return null;
  } catch (e) {
    LOGGER.e("[Scraper] download image failed: $e");
    return null;
  }
}

/// 网易云音乐刮削源
class NeteaseScraper extends MetadataScraper {
  @override
  String get id => 'netease';

  @override
  String get name => '网易云音乐';

  @override
  Future<List<ScrapeResult>> search(
    String query, {
    String? artist,
    String? album,
  }) async {
    try {
      final answer = await Netease.search(keyWord: query);
      final data = answer.data;
      if (data == null) return [];

      final result = data["result"];
      if (result == null) return [];

      final List? songs = result["songs"];
      if (songs == null) return [];

      final results = <ScrapeResult>[];
      for (int i = 0; i < min(songs.length, 10); i++) {
        final song = songs[i];
        final title = song["name"] ?? "";

        final List? artistList = song["artists"];
        final artists = artistList != null
            ? artistList.map<String>((a) => a["name"] ?? "").join("、")
            : "";

        final albumName = song["album"]?["name"] ?? "";
        final albumId = song["album"]?["id"]?.toString();
        final songId = song["id"]?.toString();

        // 封面 URL
        String? coverUrl;
        final picUrl = song["album"]?["picUrl"];
        if (picUrl is String && picUrl.isNotEmpty) {
          coverUrl = picUrl;
        }

        final score =
            _computeScore(query, artist, album, title, artists, albumName);

        results.add(ScrapeResult(
          title: title.isNotEmpty ? title : null,
          artist: artists.isNotEmpty ? artists : null,
          album: albumName.isNotEmpty ? albumName : null,
          coverUrl: coverUrl,
          score: score,
          source: id,
          platformIds: {
            'neteaseSongId': songId,
            'neteaseAlbumId': albumId,
          },
        ));
      }

      return results;
    } catch (e) {
      LOGGER.e("[NeteaseScraper] search failed: $e");
      return [];
    }
  }

  @override
  Future<String?> fetchLyric(ScrapeResult result) async {
    final songId = result.platformIds['neteaseSongId'];
    if (songId == null) return null;

    try {
      final answer = await Netease.lyric(id: songId.toString());
      final lrcObj = answer.data?["lrc"];
      if (lrcObj == null) return null;

      final lrcText = lrcObj["lyric"];
      if (lrcText is String && lrcText.isNotEmpty) {
        // 拼接翻译歌词
        final tlyric = answer.data?["tlyric"]?["lyric"];
        if (tlyric is String && tlyric.isNotEmpty) {
          return '$lrcText\n$tlyric';
        }
        return lrcText;
      }
      return null;
    } catch (e) {
      LOGGER.e("[NeteaseScraper] fetchLyric failed: $e");
      return null;
    }
  }

  @override
  Future<Uint8List?> fetchCover(ScrapeResult result) async {
    // 优先使用搜索结果中的封面 URL
    if (result.coverUrl != null && result.coverUrl!.isNotEmpty) {
      return _downloadImage(result.coverUrl!);
    }

    // 通过专辑 ID 获取封面
    final albumId = result.platformIds['neteaseAlbumId'];
    if (albumId == null) return null;

    try {
      final answer =
          await Netease.albumInfo(id: albumId.toString());
      final album = answer.data?["album"];
      if (album == null) return null;

      final picUrl = album["picUrl"];
      if (picUrl is String && picUrl.isNotEmpty) {
        return _downloadImage(picUrl);
      }

      final blurPicUrl = album["blurPicUrl"];
      if (blurPicUrl is String && blurPicUrl.isNotEmpty) {
        return _downloadImage(blurPicUrl);
      }

      return null;
    } catch (e) {
      LOGGER.e("[NeteaseScraper] fetchCover failed: $e");
      return null;
    }
  }
}

/// QQ音乐刮削源
class QQScraper extends MetadataScraper {
  @override
  String get id => 'qq';

  @override
  String get name => 'QQ音乐';

  @override
  Future<List<ScrapeResult>> search(
    String query, {
    String? artist,
    String? album,
  }) async {
    try {
      final answer = await QQ.search(keyWord: query);
      final data = answer.data;
      if (data == null) return [];

      final req = data["req"];
      if (req == null) return [];

      final reqData = req["data"];
      if (reqData == null) return [];

      final body = reqData["body"];
      if (body == null) return [];

      final List? itemSong = body["item_song"];
      if (itemSong == null) return [];

      final results = <ScrapeResult>[];
      for (int i = 0; i < min(itemSong.length, 10); i++) {
        final song = itemSong[i];
        final title = song["name"] ?? "";

        final List? singer = song["singer"];
        final artists = singer != null
            ? singer.map<String>((s) => s["name"] ?? "").join("、")
            : "";

        final albumName = song["album"]?["title"] ?? "";
        final albumMid = song["album"]?["mid"];
        final songId = song["id"];
        final songMid = song["mid"];

        // QQ音乐封面 URL 可由 albumMid 构造
        String? coverUrl;
        if (albumMid is String && albumMid.isNotEmpty) {
          coverUrl =
              'https://y.qq.com/music/photo_new/T002R300x300M000$albumMid.jpg';
        }

        final score =
            _computeScore(query, artist, album, title, artists, albumName);

        results.add(ScrapeResult(
          title: title.isNotEmpty ? title : null,
          artist: artists.isNotEmpty ? artists : null,
          album: albumName.isNotEmpty ? albumName : null,
          coverUrl: coverUrl,
          score: score,
          source: id,
          platformIds: {
            'qqSongId': songId,
            'qqSongMid': songMid,
            'qqAlbumMid': albumMid,
          },
        ));
      }

      return results;
    } catch (e) {
      LOGGER.e("[QQScraper] search failed: $e");
      return [];
    }
  }

  @override
  Future<String?> fetchLyric(ScrapeResult result) async {
    final songId = result.platformIds['qqSongId'];
    if (songId == null) return null;

    try {
      final int id = songId is int ? songId : int.parse(songId.toString());
      final answer = await QQ.songLyric3(songId: id);
      final data = answer.data;
      final qrcText = data?["lyric"];
      if (qrcText is String && qrcText.isNotEmpty) {
        final trans = data?["trans"];
        if (trans is String && trans.isNotEmpty) {
          return '$qrcText\n$trans';
        }
        return qrcText;
      }
      return null;
    } catch (e) {
      LOGGER.e("[QQScraper] fetchLyric failed: $e");
      return null;
    }
  }

  @override
  Future<Uint8List?> fetchCover(ScrapeResult result) async {
    // 优先使用构造的封面 URL
    if (result.coverUrl != null && result.coverUrl!.isNotEmpty) {
      return _downloadImage(result.coverUrl!);
    }

    // 通过 albumMid 构造封面 URL
    final albumMid = result.platformIds['qqAlbumMid'];
    if (albumMid is String && albumMid.isNotEmpty) {
      final url =
          'https://y.qq.com/music/photo_new/T002R300x300M000$albumMid.jpg';
      return _downloadImage(url);
    }

    return null;
  }
}

/// 酷狗音乐刮削源
class KuGouScraper extends MetadataScraper {
  @override
  String get id => 'kugou';

  @override
  String get name => '酷狗音乐';

  @override
  Future<List<ScrapeResult>> search(
    String query, {
    String? artist,
    String? album,
  }) async {
    try {
      final answer = await KuGou.searchSong(keyword: query);
      final data = answer.data;
      if (data == null) return [];

      final dataObj = data["data"];
      if (dataObj == null) return [];

      final List? info = dataObj["info"];
      if (info == null) return [];

      final results = <ScrapeResult>[];
      for (int i = 0; i < min(info.length, 10); i++) {
        final item = info[i];
        final title = item["songname"] ?? "";
        final artists = item["singername"] ?? "";
        final albumName = item["album_name"] ?? "";
        final hash = item["hash"];
        final albumId = item["album_id"];

        final score =
            _computeScore(query, artist, album, title, artists, albumName);

        results.add(ScrapeResult(
          title: title.isNotEmpty ? title : null,
          artist: artists.isNotEmpty ? artists : null,
          album: albumName.isNotEmpty ? albumName : null,
          score: score,
          source: id,
          platformIds: {
            'kugouHash': hash,
            'kugouAlbumId': albumId,
          },
        ));
      }

      return results;
    } catch (e) {
      LOGGER.e("[KuGouScraper] search failed: $e");
      return [];
    }
  }

  @override
  Future<String?> fetchLyric(ScrapeResult result) async {
    final hash = result.platformIds['kugouHash'];
    if (hash == null) return null;

    try {
      // 优先尝试 KRC 格式（逐字歌词）
      final answer = await KuGou.krc(hash: hash.toString());
      final krcText = answer.data?["lyric"];
      if (krcText is String && krcText.isNotEmpty) {
        return krcText;
      }

      // 降级到 LRC 格式
      final lrcAnswer = await KuGou.lrc(hash: hash.toString());
      final lrcText = lrcAnswer.data?["lrc"];
      if (lrcText is String && lrcText.isNotEmpty) {
        return lrcText;
      }

      return null;
    } catch (e) {
      LOGGER.e("[KuGouScraper] fetchLyric failed: $e");
      return null;
    }
  }

  @override
  Future<Uint8List?> fetchCover(ScrapeResult result) async {
    final hash = result.platformIds['kugouHash'];
    if (hash == null) return null;

    try {
      final answer = await KuGou.musicInfo(hash: hash.toString());
      final data = answer.data;
      if (data == null) return null;

      // 尝试从歌曲详情获取封面
      final imgUrl = data["imgUrl"];
      if (imgUrl is String && imgUrl.isNotEmpty) {
        return _downloadImage(imgUrl);
      }

      // 通过专辑 ID 获取封面
      final albumId = result.platformIds['kugouAlbumId'] ?? data["album_id"];
      if (albumId != null) {
        final albumAnswer =
            await KuGou.albumInfo(albumId: albumId.toString());
        final albumData = albumAnswer.data;
        if (albumData != null) {
          final coverUrl = albumData["data"]?["imgurl"];
          if (coverUrl is String && coverUrl.isNotEmpty) {
            return _downloadImage(coverUrl);
          }
        }
      }

      return null;
    } catch (e) {
      LOGGER.e("[KuGouScraper] fetchCover failed: $e");
      return null;
    }
  }
}

/// 计算搜索结果与查询的匹配度
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
  final minTitleLen = min(query.length, resultTitle.length);
  for (int i = 0; i < minTitleLen; i++) {
    if (query[i] == resultTitle[i]) score++;
  }

  // 艺术家匹配
  if (queryArtist != null && queryArtist.isNotEmpty) {
    final minArtistLen = min(queryArtist.length, resultArtist.length);
    for (int i = 0; i < minArtistLen; i++) {
      if (queryArtist[i] == resultArtist[i]) score++;
    }
  }

  // 专辑匹配
  if (queryAlbum != null && queryAlbum.isNotEmpty) {
    final minAlbumLen = min(queryAlbum.length, resultAlbum.length);
    for (int i = 0; i < minAlbumLen; i++) {
      if (queryAlbum[i] == resultAlbum[i]) score++;
    }
  }

  return score / maxLen;
}
