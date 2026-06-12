// ignore_for_file: constant_identifier_names

const String AUDIOS_PAGE = "/audios";
const String AUDIO_DETAIL_PAGE = "/audios/detail";

const String CATEGORIES_PAGE = "/categories";
const String ARTISTS_PAGE = "/categories/artists";
const String ARTIST_DETAIL_PAGE = "/categories/artists/detail";
const String ALBUMS_PAGE = "/categories/albums";
const String ALBUM_DETAIL_PAGE = "/categories/albums/detail";
const String GENRES_PAGE = "/categories/genres";
const String GENRE_DETAIL_PAGE = "/categories/genres/detail";

const String FOLDERS_PAGE = "/folders";
const String FOLDER_DETAIL_PAGE = "/folders/detail";

const String PLAYLISTS_PAGE = "/playlists";
const String PLAYLIST_DETAIL_PAGE = "/playlists/detail";

const String SEARCH_PAGE = "/search";
const String SEARCH_RESULT_PAGE = "/search/result";

const String NOW_PLAYING_PAGE = "/nowplaying";

const String SETTINGS_PAGE = "/settings";
const String SETTINGS_ISSUE_PAGE = "/settings/issue";

const String WELCOMING_PAGE = "/welcoming";

const String UPDATING_DIALOG = "/updating";

const String CLOUD_CONNECTIONS_PAGE = "/cloud";
const String CLOUD_BROWSER_PAGE =
    "/cloud/browser"; // 实际路径: /cloud/browser/:connectionId

/// 可以作为 start page 的 pages
const List<String> START_PAGES = [
  AUDIOS_PAGE,
  PLAYLISTS_PAGE,
  CATEGORIES_PAGE,
  FOLDERS_PAGE,
  CLOUD_CONNECTIONS_PAGE,
];
