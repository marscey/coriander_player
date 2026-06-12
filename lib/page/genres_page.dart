import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/genre_service.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class GenresPage extends StatelessWidget {
  const GenresPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GenreService.instance,
      builder: (context, _) {
        final contentList = GenreService.instance.genres;
        return UniPage<Genre>(
          pref: AppPreference.instance.genresPagePref,
          title: "流派",
          subtitle: "${contentList.length} 个流派",
          contentList: contentList,
          contentBuilder: (context, item, i, multiSelectController) =>
              _GenreTile(genre: item),
          enableShufflePlay: false,
          enableSortMethod: true,
          enableSortOrder: true,
          enableContentViewSwitch: true,
          sortMethods: [
            SortMethodDesc(
              icon: Symbols.title,
              name: "名称",
              method: (list, order) {
                switch (order) {
                  case SortOrder.ascending:
                    list.sort((a, b) => a.name.localeCompareTo(b.name));
                    break;
                  case SortOrder.decending:
                    list.sort((a, b) => b.name.localeCompareTo(a.name));
                    break;
                }
              },
            ),
            SortMethodDesc(
              icon: Symbols.music_note,
              name: "作品数量",
              method: (list, order) {
                switch (order) {
                  case SortOrder.ascending:
                    list.sort(
                        (a, b) => a.works.length.compareTo(b.works.length));
                    break;
                  case SortOrder.decending:
                    list.sort(
                        (a, b) => b.works.length.compareTo(a.works.length));
                    break;
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _GenreTile extends StatelessWidget {
  const _GenreTile({required this.genre});

  final Genre genre;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: genre.name,
      child: Semantics(
        identifier: "genre_tile",
        button: true,
        child: InkWell(
          onTap: () {
            context.push(
              app_paths.GENRE_DETAIL_PAGE,
              extra: genre,
            );
          },
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Container(
                  width: 48.0,
                  height: 48.0,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Icon(
                    Symbols.genres,
                    color: scheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          genre.name,
                          softWrap: false,
                          maxLines: 1,
                          style: TextStyle(color: scheme.onSurface),
                        ),
                        Text(
                          "${genre.works.length} 首乐曲",
                          softWrap: false,
                          maxLines: 1,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GenreDetailPage extends StatefulWidget {
  const GenreDetailPage({super.key, required this.genre});

  final Genre genre;

  @override
  State<GenreDetailPage> createState() => _GenreDetailPageState();
}

class _GenreDetailPageState extends State<GenreDetailPage> {
  final multiSelectController = MultiSelectController<Audio>();

  @override
  Widget build(BuildContext context) {
    final contentList = widget.genre.works;

    return UniPage<Audio>(
      pref: AppPreference.instance.genreDetailPagePref,
      title: widget.genre.name,
      subtitle: "${contentList.length} 首乐曲",
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) => AudioTile(
        audioIndex: i,
        playlist: contentList,
        multiSelectController: multiSelectController,
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        AddAllToPlaylist(multiSelectController: multiSelectController),
        MultiSelectSelectOrClearAll(
          multiSelectController: multiSelectController,
          contentList: contentList,
        ),
        MultiSelectExit(multiSelectController: multiSelectController),
      ],
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: "标题",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.title.localeCompareTo(b.title));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.title.localeCompareTo(a.title));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.artist,
          name: "艺术家",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.artist.localeCompareTo(b.artist));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.artist.localeCompareTo(a.artist));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.album,
          name: "专辑",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.album.localeCompareTo(b.album));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.album.localeCompareTo(a.album));
                break;
            }
          },
        ),
      ],
    );
  }
}
