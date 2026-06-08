part of 'page.dart';

class _NowPlayingPage_Small extends StatelessWidget {
  const _NowPlayingPage_Small();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<NowPlayingViewMode>(
            valueListenable: NOW_PLAYING_VIEW_MODE,
            builder: (context, mode, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: switch (mode) {
                NowPlayingViewMode.onlyMain => const _NowPlayingInfo(),
                NowPlayingViewMode.withLyric => const VerticalLyricView(),
                NowPlayingViewMode.withPlaylist => const CurrentPlaylistView(),
              },
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: _NowPlayingSlider(),
        ),
        const SizedBox(height: 12.0),
        const _NowPlayingMainControls(),
        const SizedBox(height: 12.0),
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const _NowPlayingMobileViewSwitchButton(),
              const _NowPlayingShuffleSwitch(),
              const _NowPlayingPlayModeSwitch(),
              const PlayerEngineIndicator(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 移动端顶部导航栏：返回↓ + 歌名 + 更多菜单
class _NowPlayingMobileTopBar extends StatelessWidget {
  const _NowPlayingMobileTopBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return ListenableBuilder(
      listenable: playbackService,
      builder: (context, _) {
        final nowPlaying = playbackService.nowPlaying;
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: "返回",
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                icon: Icon(
                  Symbols.keyboard_arrow_down,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    nowPlaying?.title ?? "",
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSecondaryContainer,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const _NowPlayingMoreAction(),
            ],
          ),
        );
      },
    );
  }
}

class _NowPlayingMobileViewSwitchButton extends StatelessWidget {
  const _NowPlayingMobileViewSwitchButton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<NowPlayingViewMode>(
      valueListenable: NOW_PLAYING_VIEW_MODE,
      builder: (context, mode, _) {
        final (icon, tooltip, nextMode) = switch (mode) {
          NowPlayingViewMode.onlyMain => (
              Symbols.lyrics,
              '查看歌词',
              NowPlayingViewMode.withLyric,
            ),
          NowPlayingViewMode.withLyric => (
              Symbols.queue_music,
              '查看播放列表',
              NowPlayingViewMode.withPlaylist,
            ),
          NowPlayingViewMode.withPlaylist => (
              Symbols.music_note,
              '返回封面',
              NowPlayingViewMode.onlyMain,
            ),
        };

        return IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: scheme.onSecondaryContainer),
          onPressed: () {
            NOW_PLAYING_VIEW_MODE.value = nextMode;
            AppPreference.instance.nowPlayingPagePref.nowPlayingViewMode =
                nextMode;
          },
        );
      },
    );
  }
}
