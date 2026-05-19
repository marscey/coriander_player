import 'dart:convert';
import 'dart:math';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/krc.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/qrc.dart';
import 'package:coriander_player/utils.dart';
import 'package:music_api/music_api.dart';

enum ResultSource { qq, kugou, netease }

double _computeScore(Audio audio, String title, String artists, String album) {
  int maxScore = audio.title.length + audio.artist.length + audio.album.length;
  int score = 0;

  int minTitleLength = min(audio.title.length, title.length);
  for (int i = 0; i < minTitleLength; ++i) {
    if (audio.title[i] == title[i]) score += 1;
  }

  int minArtistLength = min(audio.artist.length, artists.length);
  for (int i = 0; i < minArtistLength; ++i) {
    if (audio.artist[i] == artists[i]) score += 1;
  }

  int minAlbumLength = min(audio.album.length, album.length);
  for (int i = 0; i < minAlbumLength; ++i) {
    if (audio.album[i] == album[i]) score += 1;
  }

  return score / maxScore;
}

class SongSearchResult {
  ResultSource source;
  String title;
  String artists;
  String album;
  double score;

  /// for qq result
  int? qqSongId;

  /// for netease result
  String? neteaseSongId;

  /// for kugou result
  String? kugouSongHash;

  SongSearchResult(
      this.source, this.title, this.artists, this.album, this.score,
      {this.qqSongId, this.neteaseSongId, this.kugouSongHash});

  @override
  String toString() {
    return json.encode({
      "source": source.toString(),
      "title": title,
      "artists": artists,
      "album": album,
      "score": score,
    });
  }

  static SongSearchResult fromQQSearchResult(Map itemSong, Audio audio) {
    final List singer = itemSong["singer"];
    final buffer = StringBuffer(singer.first["name"]);
    for (int i = 1; i < singer.length; ++i) {
      buffer.write("、${singer[i]["name"]}");
    }

    final title = itemSong["name"] ?? "";
    final album = itemSong["album"]["title"] ?? "";
    final artists = buffer.toString();

    return SongSearchResult(
      ResultSource.qq,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      qqSongId: itemSong["id"],
    );
  }

  static SongSearchResult fromNeteaseSearchResult(Map song, Audio audio) {
    final title = song["name"] ?? "";

    final List artistList = song["artists"];
    final buffer = StringBuffer(artistList.first["name"]);
    for (int i = 1; i < artistList.length; ++i) {
      buffer.write("、${artistList[i]["name"]}");
    }
    final artists = buffer.toString();

    final album = song["album"]["name"] ?? "";

    return SongSearchResult(
      ResultSource.netease,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      neteaseSongId: song["id"].toString(),
    );
  }

  static SongSearchResult fromKugouSearchResult(Map info, Audio audio) {
    final title = info["songname"];
    final album = info["album_name"];
    final artists = info["singername"];

    return SongSearchResult(
      ResultSource.kugou,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      kugouSongHash: info["hash"],
    );
  }
}

Future<List<SongSearchResult>> uniSearch(Audio audio, {String? customQuery}) async {
  final query = customQuery ?? audio.title;
  try {
    List<SongSearchResult> result = [];

    try {
      final kugouAnswer = (await KuGou.searchSong(keyword: query)).data;
      if (kugouAnswer != null) {
        final kugouData = kugouAnswer["data"];
        if (kugouData != null) {
          final List? kugouResultList = kugouData["info"];
          if (kugouResultList != null) {
            for (int j = 0; j < kugouResultList.length; j++) {
              if (j >= 5) break;
              result.add(SongSearchResult.fromKugouSearchResult(
                kugouResultList[j],
                audio,
              ));
            }
          }
        }
      }
    } catch (e) {
      LOGGER.e("[uniSearch] kugou search failed: $e");
    }

    try {
      final neteaseAnswer = (await Netease.search(keyWord: query)).data;
      if (neteaseAnswer != null) {
        final neteaseResult = neteaseAnswer["result"];
        if (neteaseResult != null) {
          final List? neteaseResultList = neteaseResult["songs"];
          if (neteaseResultList != null) {
            for (int k = 0; k < neteaseResultList.length; k++) {
              if (k >= 5) break;
              result.add(SongSearchResult.fromNeteaseSearchResult(
                neteaseResultList[k],
                audio,
              ));
            }
          }
        }
      }
    } catch (e) {
      LOGGER.e("[uniSearch] netease search failed: $e");
    }

    try {
      final qqAnswer = (await QQ.search(keyWord: query)).data;
      if (qqAnswer != null) {
        final qqReq = qqAnswer["req"];
        if (qqReq != null) {
          final qqReqData = qqReq["data"];
          if (qqReqData != null) {
            final qqBody = qqReqData["body"];
            if (qqBody != null) {
              final List? qqResultList = qqBody["item_song"];
              if (qqResultList != null) {
                for (int i = 0; i < qqResultList.length; i++) {
                  if (i >= 5) break;
                  result.add(SongSearchResult.fromQQSearchResult(
                    qqResultList[i],
                    audio,
                  ));
                }
              }
            }
          }
        }
      }
    } catch (e) {
      LOGGER.e("[uniSearch] qq search failed: $e");
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  } catch (err, trace) {
    LOGGER.e("query: $query");
    LOGGER.e(err, stackTrace: trace);
  }
  return Future.value([]);
}

Future<Lrc?> _getNeteaseUnsyncLyric(String neteaseSongId) async {
  try {
    final answer = await Netease.lyric(id: neteaseSongId);
    final lrcObj = answer.data?["lrc"];
    if (lrcObj == null) return null;
    final lrcText = lrcObj["lyric"];
    if (lrcText is String) {
      final lrcTrans = answer.data?["tlyric"]?["lyric"];
      return Lrc.fromLrcText(
        lrcText + (lrcTrans ?? ''),
        LrcSource.web,
        separator: "┃",
      );
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Qrc?> _getQQSyncLyric(int qqSongId) async {
  try {
    final answer = await QQ.songLyric3(songId: qqSongId);
    final qrcText = answer.data?["lyric"];
    if (qrcText is String) {
      final qrcTransRawStr = answer.data?["trans"];
      if (qrcTransRawStr is String) {
        return Qrc.fromQrcText(qrcText, qrcTransRawStr);
      }
      return Qrc.fromQrcText(qrcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Krc?> _getKugouSyncLyric(String kugouSongHash) async {
  try {
    final answer = await KuGou.krc(hash: kugouSongHash);
    final krcText = answer.data?["lyric"];
    if (krcText is String) {
      return Krc.fromKrcText(krcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Lyric?> getOnlineLyric({
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
}) async {
  Lyric? lyric;
  if (qqSongId != null) {
    lyric = (await _getQQSyncLyric(qqSongId));
  } else if (kugouSongHash != null) {
    lyric = (await _getKugouSyncLyric(kugouSongHash));
  } else if (neteaseSongId != null) {
    lyric = await _getNeteaseUnsyncLyric(neteaseSongId);
  }
  return lyric;
}

Future<Lyric?> getMostMatchedLyric(Audio audio) async {
  final unisearchResult = await uniSearch(audio);
  if (unisearchResult.isEmpty) return null;

  final mostMatch = unisearchResult.first;

  return switch (mostMatch.source) {
    ResultSource.qq => getOnlineLyric(qqSongId: mostMatch.qqSongId),
    ResultSource.kugou =>
      getOnlineLyric(kugouSongHash: mostMatch.kugouSongHash),
    ResultSource.netease =>
      getOnlineLyric(neteaseSongId: mostMatch.neteaseSongId),
  };
}
