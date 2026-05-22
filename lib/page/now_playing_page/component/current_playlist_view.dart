import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/component/playlist_audio_item.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';

class CurrentPlaylistView extends StatefulWidget {
  const CurrentPlaylistView({super.key});

  @override
  State<CurrentPlaylistView> createState() => _CurrentPlaylistViewState();
}

class _CurrentPlaylistViewState extends State<CurrentPlaylistView> {
  final playbackService = PlayService.instance.playbackService;
  late final ScrollController scrollController;

  void _toNowPlaying() {
    if (scrollController.hasClients) {
      final itemHeight = 56.0;
      final viewportHeight = scrollController.position.viewportDimension;
      final targetOffset =
          playbackService.playlistIndex * itemHeight - (viewportHeight / 2) + (itemHeight / 2);
      final maxExtent = scrollController.position.maxScrollExtent;
      scrollController.animateTo(
        targetOffset.clamp(0.0, maxExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: playbackService.playlistIndex * 56.0,
    );
    playbackService.addListener(_toNowPlaying);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Text(
                  "播放列表",
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                LocatePlayingButton(
                  hasPlayingAudio: playbackService.nowPlaying != null,
                  onLocate: _toNowPlaying,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: playbackService.shuffle,
              builder: (context, _) {
                return ListView.builder(
                  controller: scrollController,
                  itemCount: playbackService.playlist.value.length,
                  itemExtent: 56.0,
                  itemBuilder: (context, index) {
                    final item = playbackService.playlist.value[index];
                    final isNowPlaying =
                        playbackService.nowPlaying?.path == item.path;
                    return PlaylistAudioItem(
                      audio: item,
                      index: index,
                      isNowPlaying: isNowPlaying,
                      textColor: scheme.onSecondaryContainer,
                      onTap: () {
                        playbackService.playIndexOfPlaylist(index);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    playbackService.removeListener(_toNowPlaying);
    scrollController.dispose();
  }
}
