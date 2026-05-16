import 'package:coriander_player/component/rectangle_progress_indicator.dart';
import 'package:coriander_player/component/responsive_builder.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class MiniNowPlaying extends StatelessWidget {
  const MiniNowPlaying({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(builder: (context, screenType) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8.0,
            0,
            8.0,
            screenType == ScreenType.small ? 8.0 : 32.0,
          ),
          child: SizedBox(
            height: 64.0,
            width: 600.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: kElevationToShadow[4],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LayoutBuilder(builder: (context, constraints) {
                  return RectangleProgressIndicator(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    child: const _NowPlayingForeground(),
                  );
                }),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _NowPlayingForeground extends StatelessWidget {
  const _NowPlayingForeground();

  void _showPlaylistBottomSheet(BuildContext context) {
    final playbackService = PlayService.instance.playbackService;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '播放列表',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: playbackService.playlist,
                    builder: (context, _) => Text(
                      '${playbackService.playlist.value.length} 首',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListenableBuilder(
                listenable: playbackService,
                builder: (context, _) {
                  final playlist = playbackService.playlist.value;
                  final currentIndex = playbackService.playlistIndex;
                  if (playlist.isEmpty) {
                    return const Center(child: Text('播放列表为空'));
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: playlist.length,
                    itemBuilder: (context, index) {
                      final item = playlist[index];
                      final isCurrent = index == currentIndex;
                      return ListTile(
                        dense: true,
                        selected: isCurrent,
                        leading: isCurrent
                            ? Icon(Symbols.play_arrow,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isCurrent
                              ? TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600)
                              : null,
                        ),
                        subtitle: Text(
                          item.subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(8.0),
      child: InkWell(
        onTap: () => context.push(app_paths.NOW_PLAYING_PAGE),
        borderRadius: BorderRadius.circular(8.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: ListenableBuilder(
            listenable: PlayService.instance.playbackService,
            builder: (context, _) {
              final playbackService = PlayService.instance.playbackService;
              final nowPlaying = playbackService.nowPlaying;
              final placeholder = Icon(
                Symbols.broken_image,
                size: 48.0,
                color: scheme.onSecondaryContainer,
              );

              return Row(
                children: [
                  nowPlaying != null
                      ? FutureBuilder(
                          future: nowPlaying.cover,
                          builder: (context, snapshot) =>
                              switch (snapshot.connectionState) {
                            ConnectionState.done => snapshot.data == null
                                ? placeholder
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(8.0),
                                    child: Image(
                                      image: snapshot.data!,
                                      width: 48.0,
                                      height: 48.0,
                                      errorBuilder: (_, __, ___) => placeholder,
                                    ),
                                  ),
                            _ => const SizedBox(
                                width: 48,
                                height: 48,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          },
                        )
                      : placeholder,
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          nowPlaying != null
                              ? nowPlaying.title
                              : "Coriander Player",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSecondaryContainer),
                        ),

                        Text(
                          nowPlaying != null
                              ? nowPlaying.subtitleText
                              : "Enjoy music",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSecondaryContainer),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4.0),

                  IconButton(
                    tooltip: '播放列表',
                    icon: Icon(Symbols.queue_music, color: scheme.onSecondaryContainer),
                    onPressed: () => _showPlaylistBottomSheet(context),
                  ),

                  StreamBuilder(
                    stream: playbackService.playerStateStream,
                    initialData: playbackService.playerState,
                    builder: (context, snapshot) {
                      late void Function() onPressed;
                      if (snapshot.data! == PlayerState.playing) {
                        onPressed = playbackService.pause;
                      } else if (snapshot.data! == PlayerState.completed) {
                        onPressed = playbackService.playAgain;
                      } else {
                        onPressed = playbackService.start;
                      }

                      return IconButton.filled(
                        tooltip:
                            snapshot.data! == PlayerState.playing ? "暂停" : "播放",
                        onPressed: onPressed,
                        icon: Icon(
                          snapshot.data! == PlayerState.playing
                              ? Symbols.pause
                              : Symbols.play_arrow,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
