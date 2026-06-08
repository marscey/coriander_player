import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class AudiosPage extends StatefulWidget {
  final Audio? locateTo;
  const AudiosPage({super.key, this.locateTo});

  @override
  State<AudiosPage> createState() => _AudiosPageState();
}

class _AudiosPageState extends State<AudiosPage> {
  @override
  void initState() {
    super.initState();
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasPlayingAudioInLibrary {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null) return false;
    // 只有当播放的音频在音乐库中时才显示定位按钮
    return AudioLibrary.instance.audioCollection
        .any((a) => a.path == nowPlaying.path);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AudioLibrary.instance,
      builder: (context, _) {
        final contentList = List<Audio>.from(AudioLibrary.instance.audioCollection);
        final multiSelectController = MultiSelectController<Audio>();
        return UniPage<Audio>(
      pref: AppPreference.instance.audiosPagePref,
      title: "音乐库",
      subtitle: "${contentList.length} 首乐曲",
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) => AudioTile(
        audioIndex: i,
        playlist: contentList,
        focus: item == widget.locateTo,
        multiSelectController: multiSelectController,
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      locateTo: widget.locateTo,
      multiSelectController: multiSelectController,
      emptyStateBuilder: (context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.library_music, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('音乐库为空', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('从云服务扫描音频或添加本地文件夹', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      ),
      multiSelectViewActions: [
        BatchScrapeMetadata(multiSelectController: multiSelectController),
        AddAllToPlaylist(multiSelectController: multiSelectController),
        RemoveFromLibrary(multiSelectController: multiSelectController),
        MultiSelectSelectOrClearAll(
          multiSelectController: multiSelectController,
          contentList: contentList,
        ),
        MultiSelectExit(multiSelectController: multiSelectController),
      ],
      primaryAction: LocatePlayingButton(
        hasPlayingAudio: _hasPlayingAudioInLibrary,
        onLocate: () {
          final nowPlaying =
              PlayService.instance.playbackService.nowPlaying;
          if (nowPlaying == null) return;
          // 通过 push 带上 locateTo 参数，让 UniPage 自动滚动
          context.push('/audios', extra: nowPlaying);
        },
      ),
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
                list.sort((a, b) => b.album.localeCompareTo(b.album));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.add,
          name: "创建时间",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.created.compareTo(b.created));
                break;
              case SortOrder.decending:
                list.sort((a, b) => a.created.compareTo(b.created));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.edit,
          name: "修改时间",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.modified.compareTo(b.modified));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.modified.compareTo(b.modified));
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
