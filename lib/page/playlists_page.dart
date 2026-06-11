import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  final _manager = PlaylistManager.instance;

  @override
  void initState() {
    super.initState();
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
    _manager.addListener(_onPlaylistsChanged);
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
    _manager.removeListener(_onPlaylistsChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  /// 歌单数据变更时自动刷新 UI
  void _onPlaylistsChanged() {
    if (mounted) setState(() {});
  }

  bool _isPlaylistPlaying(Playlist playlist) {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null) return false;
    return playlist.audios.containsKey(nowPlaying.path);
  }

  bool get _hasPlayingAudio {
    return PlayService.instance.playbackService.nowPlaying != null;
  }

  void _locatePlayingPlaylist() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未在播放音频')),
      );
      return;
    }

    Playlist? targetPlaylist;
    for (final playlist in _manager.allPlaylists) {
      if (playlist.audios.containsKey(nowPlaying.path)) {
        targetPlaylist = playlist;
        break;
      }
    }

    if (targetPlaylist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('播放文件不在任何歌单中')),
      );
      return;
    }

    context.push(app_paths.PLAYLIST_DETAIL_PAGE, extra: targetPlaylist);
  }

  void newPlaylist(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewPlaylistDialog(),
    );
    if (name == null) return;
    _manager.createPlaylist(name);
  }

  void editPlaylist(
    BuildContext context,
    Playlist playlist,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _EditPlaylistDialog(),
    );
    if (name == null) return;
    _manager.renamePlaylist(playlist, name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 内置歌单固定在前，自建歌单在后
    final builtInPlaylists = _manager.allPlaylists
        .where((p) => p.isBuiltIn)
        .toList();

    // 自建歌单作为可排序列表传入 UniPage
    final userPlaylists = _manager.userPlaylists;

    return UniPage<Playlist>(
      pref: AppPreference.instance.playlistsPagePref,
      title: "歌单",
      subtitle: "${_manager.allPlaylists.length} 个歌单",
      contentList: userPlaylists,
      // 内置歌单始终显示在列表顶部，不参与排序
      pinnedItems: builtInPlaylists,
      contentBuilder: (context, item, i, multiSelectController) {
        // 内置歌单与自建歌单之间的分隔线
        // 当当前项是第一个自建歌单时显示
        final showDivider = !item.isBuiltIn &&
            i == 0 &&
            builtInPlaylists.isNotEmpty;

        return Container(
          decoration: showDivider
              ? BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                )
              : null,
          child: ListTile(
            leading: PlayingIndicatorOverlay(
              size: PlayingIndicatorSize.medium,
              isActivelyPlaying: _isPlaylistPlaying(item),
              child: Icon(
                item.isBuiltIn
                    ? (item.builtInId == 'favorites'
                        ? Symbols.favorite
                        : Symbols.history)
                    : Symbols.queue_music,
                size: 36,
                color: item.isBuiltIn ? scheme.tertiary : scheme.primary,
              ),
            ),
            title: Row(
              children: [
                Text(
                  item.name,
                  softWrap: false,
                  maxLines: 1,
                ),
                if (item.isBuiltIn) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "内置",
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              "${item.audios.length}首乐曲",
              softWrap: false,
              maxLines: 1,
            ),
            trailing: item.isBuiltIn
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: "编辑",
                        onPressed: () => editPlaylist(context, item),
                        icon: const Icon(Symbols.edit),
                      ),
                      const SizedBox(width: 8.0),
                      IconButton(
                        tooltip: "删除",
                        onPressed: () => _manager.removePlaylist(item),
                        color: scheme.error,
                        icon: const Icon(Symbols.delete),
                      ),
                    ],
                  ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            onTap: () => context.push(
              app_paths.PLAYLIST_DETAIL_PAGE,
              extra: item,
            ),
          ),
        );
      },
      primaryAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasPlayingAudio)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: const Icon(Icons.my_location, size: 20),
                tooltip: "定位播放文件",
                onPressed: _locatePlayingPlaylist,
              ),
            ),
          FilledButton.icon(
            onPressed: () => newPlaylist(context),
            icon: const Icon(Symbols.add),
            label: const Text("新建歌单"),
            style: const ButtonStyle(
              fixedSize: WidgetStatePropertyAll(Size.fromHeight(40)),
            ),
          ),
        ],
      ),
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
          name: "歌曲数量",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort(
                    (a, b) => a.audios.length.compareTo(b.audios.length));
                break;
              case SortOrder.decending:
                list.sort(
                    (a, b) => b.audios.length.compareTo(a.audios.length));
                break;
            }
          },
        ),
      ],
    );
  }
}

class _NewPlaylistDialog extends StatelessWidget {
  const _NewPlaylistDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editingController = TextEditingController();

    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: SizedBox(
        width: 350.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  "新建歌单",
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  autofocus: true,
                  controller: editingController,
                  onSubmitted: (value) {
                    Navigator.pop(context, value);
                  },
                  decoration: const InputDecoration(
                    labelText: "歌单名称",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context, editingController.text);
                    },
                    child: const Text("创建"),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _EditPlaylistDialog extends StatelessWidget {
  const _EditPlaylistDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editingController = TextEditingController();

    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: SizedBox(
        width: 350.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  "修改歌单",
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  autofocus: true,
                  controller: editingController,
                  onSubmitted: (value) {
                    Navigator.pop(context, value);
                  },
                  decoration: const InputDecoration(
                    labelText: "新歌单名称",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context, editingController.text);
                    },
                    child: const Text("创建"),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
