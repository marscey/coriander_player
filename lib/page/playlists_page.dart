import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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

  Widget _buildPlaylistTile(BuildContext context, Playlist item, int i,
      bool isBuiltInDivider) {
    final useGlass = AppPreference.instance.glassActive;
    final scheme = Theme.of(context).colorScheme;

    if (useGlass) {
      return _GlassPlaylistTile(
        item: item,
        scheme: scheme,
        isPlaying: _isPlaylistPlaying(item),
        showDivider: isBuiltInDivider,
        onEdit: () => editPlaylist(context, item),
        onDelete: () => _manager.removePlaylist(item),
        onTap: () => context.push(app_paths.PLAYLIST_DETAIL_PAGE, extra: item),
      );
    }

    return Container(
      decoration: isBuiltInDivider
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 4.0),
        leading: PlayingIndicatorOverlay(
          size: PlayingIndicatorSize.medium,
          isActivelyPlaying: _isPlaylistPlaying(item),
          child: Container(
            width: 48.0,
            height: 48.0,
            decoration: BoxDecoration(
              color: item.isBuiltIn
                  ? scheme.tertiaryContainer
                  : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Icon(
              item.isBuiltIn
                  ? (item.builtInId == 'favorites'
                      ? Symbols.favorite
                      : Symbols.history)
                  : Symbols.queue_music,
              size: 28,
              color: item.isBuiltIn
                  ? scheme.onTertiaryContainer
                  : scheme.onPrimaryContainer,
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
  }

  @override
  Widget build(BuildContext context) {
    // 内置歌单固定在前，自建歌单在后
    final builtInPlaylists = _manager.allPlaylists.where((p) => p.isBuiltIn).toList();

    // 自建歌单作为可排序列表传入 UniPage
    final userPlaylists = _manager.userPlaylists;

    return UniPage<Playlist>(
      pref: AppPreference.instance.playlistsPagePref,
      title: "歌单",
      subtitle: "${_manager.allPlaylists.length} 个歌单",
      contentList: userPlaylists,
      pinnedItems: builtInPlaylists,
      contentBuilder: (context, item, i, multiSelectController) {
        final showDivider = !item.isBuiltIn && i == 0 && builtInPlaylists.isNotEmpty;
        return _buildPlaylistTile(context, item, i, showDivider);
      },
      primaryAction: FilledButton.icon(
        onPressed: () => newPlaylist(context),
        icon: const Icon(Symbols.add),
        label: const Text("新建歌单"),
        style: const ButtonStyle(
          fixedSize: WidgetStatePropertyAll(Size.fromHeight(40)),
        ),
      ),
      glassMenuItems: [
        if (_hasPlayingAudio)
          GlassMenuItem(
            title: '定位播放文件',
            icon: const Icon(Icons.my_location, size: 20),
            onTap: _locatePlayingPlaylist,
          ),
        GlassMenuItem(
          title: '新建歌单',
          icon: const Icon(Symbols.add, size: 20),
          onTap: () => newPlaylist(context),
        ),
        const GlassMenuDivider(),
      ],
      showBackButton: false,
      showSettingsButton: true,
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
                list.sort((a, b) => a.name.compareTo(b.name));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.name.compareTo(a.name));
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
                list.sort((a, b) => a.audios.length.compareTo(b.audios.length));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.audios.length.compareTo(a.audios.length));
                break;
            }
          },
        ),
      ],
    );
  }
}

class _GlassPlaylistTile extends StatelessWidget {
  const _GlassPlaylistTile({
    required this.item,
    required this.scheme,
    required this.isPlaying,
    required this.showDivider,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  final Playlist item;
  final ColorScheme scheme;
  final bool isPlaying;
  final bool showDivider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: item.isBuiltIn
              ? scheme.tertiaryContainer.withValues(alpha: 0.4)
              : scheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: scheme.onSurface.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            PlayingIndicatorOverlay(
              size: PlayingIndicatorSize.medium,
              isActivelyPlaying: isPlaying,
              child: Container(
                width: 48.0,
                height: 48.0,
                decoration: BoxDecoration(
                  color: item.isBuiltIn
                      ? scheme.tertiaryContainer
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Icon(
                  item.isBuiltIn
                      ? (item.builtInId == 'favorites'
                          ? Symbols.favorite
                          : Symbols.history)
                      : Symbols.queue_music,
                  size: 28,
                  color: item.isBuiltIn
                      ? scheme.onTertiaryContainer
                      : scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          softWrap: false,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 15.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.isBuiltIn) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: scheme.onTertiaryContainer.withValues(alpha: 0.2),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            "内置",
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onTertiaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    "${item.audios.length} 首乐曲",
                    softWrap: false,
                    maxLines: 1,
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12.0,
                    ),
                  ),
                ],
              ),
            ),
            if (!item.isBuiltIn) ...[
              IconButton(
                tooltip: "编辑",
                onPressed: onEdit,
                icon: Icon(Symbols.edit, color: scheme.onSurface.withValues(alpha: 0.7), size: 20),
              ),
              IconButton(
                tooltip: "删除",
                onPressed: onDelete,
                color: scheme.error,
                icon: Icon(Symbols.delete, size: 20),
              ),
            ],
          ],
        ),
      ),
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
              TextField(
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
              TextField(
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
