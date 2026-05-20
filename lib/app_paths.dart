// ignore_for_file: constant_identifier_names

const String AUDIOS_PAGE = "/audios";
const String AUDIO_DETAIL_PAGE = "/audios/detail";

const String ARTISTS_PAGE = "/artists";
const String ARTIST_DETAIL_PAGE = "/artists/detail";

const String ALBUMS_PAGE = "/albums";
const String ALBUM_DETAIL_PAGE = "/albums/detail";

const String FOLDERS_PAGE = "/folders";
const String FOLDER_DETAIL_PAGE = "/folders/detail";

const String PLAYLISTS_PAGE = "/playlists";
const String PLAYLIST_DETAIL_PAGE = "/playlists/detail";

const String RECENT_PLAYS_PAGE = "/recent";

const String SEARCH_PAGE = "/search";
const String SEARCH_RESULT_PAGE = "/search/result";

const String NOW_PLAYING_PAGE = "/nowplaying";

const String SETTINGS_PAGE = "/settings";
const String SETTINGS_ISSUE_PAGE = "/settings/issue";

const String WELCOMING_PAGE = "/welcoming";

const String UPDATING_DIALOG = "/updating";

const String CLOUD_CONNECTIONS_PAGE = "/cloud";
const String CLOUD_BROWSER_PAGE = "/cloud/browser"; // 实际路径: /cloud/browser/:connectionId

/// 可以作为 start page 的 pages
const List<String> START_PAGES = [
  AUDIOS_PAGE,
  ARTISTS_PAGE,
  ALBUMS_PAGE,
  FOLDERS_PAGE,
  CLOUD_CONNECTIONS_PAGE,
  PLAYLISTS_PAGE,
  RECENT_PLAYS_PAGE
];
