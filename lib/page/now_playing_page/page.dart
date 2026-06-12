// ignore_for_file: camel_case_types

import 'dart:async';
import 'dart:ui';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:coriander_player/component/auto_scroll_text.dart';
import 'package:coriander_player/component/title_bar.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/component/responsive_builder.dart';
import 'package:coriander_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:coriander_player/page/settings_page/edit_tag_dialog.dart';
import 'package:coriander_player/page/now_playing_page/component/filled_icon_button_style.dart';
import 'package:coriander_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

part 'small_page.dart';
part 'large_page.dart';
part 'player_engine_indicator.dart';

enum NowPlayingViewMode {
  onlyMain,
  withLyric,
  withPlaylist;

  static NowPlayingViewMode? fromString(String nowPlayingViewMode) {
    for (var value in NowPlayingViewMode.values) {
      if (value.name == nowPlayingViewMode) return value;
    }
    return null;
  }
}

final NOW_PLAYING_VIEW_MODE = ValueNotifier(
  AppPreference.instance.nowPlayingPagePref.nowPlayingViewMode,
);

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage>
    with TickerProviderStateMixin {
  final playbackService = PlayService.instance.playbackService;
  ImageProvider<Object>? nowPlayingCover;

  // 移动端手势相关：向下滑动收起
  double _dragOffsetY = 0.0;
  AnimationController? _dismissAnimCtrl;

  void updateCover() {
    final audio = playbackService.nowPlaying;
    if (audio == null) {
      if (nowPlayingCover != null && mounted) {
        setState(() {
          nowPlayingCover = null;
        });
      }
      return;
    }
    audio.cover.then((cover) {
      if (mounted && !identical(cover, nowPlayingCover)) {
        setState(() {
          nowPlayingCover = cover;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _dismissAnimCtrl = AnimationController(
      vsync: this,
      upperBound: 800,
    )..addListener(() {
        setState(() {
          _dragOffsetY = _dismissAnimCtrl!.value;
        });
      });
    playbackService.addListener(updateCover);
    updateCover();
  }

  @override
  void dispose() {
    playbackService.removeListener(updateCover);
    _dismissAnimCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final body = Stack(
      fit: StackFit.expand,
      alignment: AlignmentDirectional.center,
      children: [
        if (nowPlayingCover != null) ...[
          Image(
            image: nowPlayingCover!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.secondaryContainer.withValues(alpha: 0.5),
                  scheme.secondaryContainer.withValues(alpha: 0.85),
                  scheme.surface.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.05),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ],
        ChangeNotifierProvider.value(
          value: PlayService.instance.playbackService,
          builder: (context, _) {
            return ResponsiveBuilder2(builder: (context, screenType) {
              switch (screenType) {
                case ScreenType.small:
                  return const _NowPlayingPage_Small();
                case ScreenType.medium:
                case ScreenType.large:
                  return const _NowPlayingPage_Large();
              }
            });
          },
        ),
      ],
    );

    // 移动端：无 AppBar，支持手势关闭
    if (PlatformHelper.isMobile) {
      return Scaffold(
        backgroundColor: scheme.secondaryContainer,
        body: Stack(
          children: [
            // 内容区（占满整个屏幕）
            Positioned.fill(
              child: GestureDetector(
                onVerticalDragStart: (_) {
                  _dismissAnimCtrl?.stop();
                  _dragOffsetY = _dismissAnimCtrl?.value ?? 0.0;
                },
                onVerticalDragUpdate: (details) {
                  if (details.delta.dy > 0) {
                    setState(() {
                      _dragOffsetY += details.delta.dy;
                    });
                  }
                },
                onVerticalDragEnd: (details) {
                  if (_dragOffsetY > 150 ||
                      (details.primaryVelocity != null &&
                          details.primaryVelocity! > 500)) {
                    if (context.canPop()) {
                      context.pop();
                      return;
                    }
                  }
                  // 弹回动画
                  _dismissAnimCtrl?.animateTo(
                    0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: Transform.translate(
                  offset: Offset(0, _dragOffsetY),
                  child: body,
                ),
              ),
            ),
            // 顶部栏（始终在最上层）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: ChangeNotifierProvider.value(
                  value: PlayService.instance.playbackService,
                  child: const _NowPlayingMobileTopBar(),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 桌面端：保留 AppBar
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              const NavBackBtn(),
              const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
              if (!PlatformHelper.isMacOS) const WindowControlls(),
            ],
          ),
        ),
      ),
      backgroundColor: scheme.secondaryContainer,
      body: body,
    );
  }
}

class _ExclusiveModeSwitch extends StatelessWidget {
  const _ExclusiveModeSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: PlayService.instance.playbackService.wasapiExclusive,
      builder: (context, exclusive, _) => IconButton(
        tooltip: "独占模式；现在：${exclusive ? "启用" : "禁用"}",
        onPressed: () {
          PlayService.instance.playbackService.useExclusiveMode(!exclusive);
        },
        icon: Center(
          child: Text(
            exclusive ? "Excl" : "Shrd",
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingMoreAction extends StatelessWidget {
  const _NowPlayingMoreAction();

  @override
  Widget build(BuildContext context) {
    final playbackService = context.watch<PlaybackService>();
    final nowPlaying = playbackService.nowPlaying;
    final scheme = Theme.of(context).colorScheme;

    if (nowPlaying == null) {
      return IconButton(
        tooltip: "更多",
        onPressed: null,
        icon: const Icon(Symbols.more_vert),
        color: scheme.onSecondaryContainer,
      );
    }

    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          menuChildren: List.generate(
            nowPlaying.splitedArtists.length,
            (i) => MenuItemButton(
              onPressed: () {
                final Artist artist = AudioLibrary
                    .instance.artistCollection[nowPlaying.splitedArtists[i]]!;
                context.push(
                  app_paths.ARTIST_DETAIL_PAGE,
                  extra: artist,
                );
              },
              leadingIcon: const Icon(Symbols.people),
              child: Text(nowPlaying.splitedArtists[i]),
            ),
          ),
          child: const Text("艺术家"),
        ),
        MenuItemButton(
          onPressed: () {
            final Album album =
                AudioLibrary.instance.albumCollection[nowPlaying.album]!;
            context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album);
          },
          leadingIcon: const Icon(Symbols.album),
          child: Text(nowPlaying.album),
        ),
        MenuItemButton(
          onPressed: () {
            context.push(app_paths.AUDIO_DETAIL_PAGE, extra: nowPlaying);
          },
          leadingIcon: const Icon(Symbols.info),
          child: const Text("详细信息"),
        ),
        MenuItemButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => EditTagDialog(audio: nowPlaying),
            ).then((saved) {
              if (saved == true) {
                nowPlaying.clearCoverCache();
                PlayService.instance.lyricService.updateLyric();
                playbackService.refreshNowPlaying();
              }
            });
          },
          leadingIcon: const Icon(Symbols.edit),
          child: const Text("编辑标签"),
        ),
        MenuItemButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) =>
                  EditTagDialog(audio: nowPlaying, autoSearch: true),
            ).then((saved) {
              if (saved == true) {
                nowPlaying.clearCoverCache();
                PlayService.instance.lyricService.updateLyric();
                playbackService.refreshNowPlaying();
              }
            });
          },
          leadingIcon: const Icon(Symbols.search),
          child: const Text("刮削元数据"),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: "更多",
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        icon: const Icon(Symbols.more_vert),
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

class _DesktopLyricSwitch extends StatelessWidget {
  const _DesktopLyricSwitch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: PlayService.instance.desktopLyricService,
      builder: (context, _) {
        final desktopLyricService = PlayService.instance.desktopLyricService;
        return FutureBuilder(
          future: desktopLyricService.desktopLyric,
          builder: (context, snapshot) => IconButton(
            tooltip: "桌面歌词；现在：${snapshot.data == null ? "禁用" : "启用"}",
            onPressed: snapshot.data == null
                ? desktopLyricService.startDesktopLyric
                : desktopLyricService.isLocked
                    ? desktopLyricService.sendUnlockMessage
                    : desktopLyricService.killDesktopLyric,
            icon: snapshot.connectionState == ConnectionState.done
                ? Icon(
                    desktopLyricService.isLocked ? Symbols.lock : Symbols.toast,
                    fill: snapshot.data == null ? 0 : 1,
                  )
                : const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(),
                  ),
            color: scheme.onSecondaryContainer,
          ),
        );
      },
    );
  }
}

class _NowPlayingVolDspSlider extends StatefulWidget {
  const _NowPlayingVolDspSlider();

  @override
  State<_NowPlayingVolDspSlider> createState() =>
      _NowPlayingVolDspSliderState();
}

class _NowPlayingVolDspSliderState extends State<_NowPlayingVolDspSlider> {
  final playbackService = PlayService.instance.playbackService;
  final dragVolDsp = ValueNotifier(
    AppPreference.instance.playbackPref.volumeDsp,
  );
  bool isDragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      menuChildren: [
        SliderTheme(
          data: const SliderThemeData(
            showValueIndicator: ShowValueIndicator.always,
          ),
          child: ValueListenableBuilder(
            valueListenable: dragVolDsp,
            builder: (context, dragVolDspValue, _) => Slider(
              thumbColor: scheme.primary,
              activeColor: scheme.primary,
              inactiveColor: scheme.outline,
              min: 0.0,
              max: 1.0,
              value: isDragging ? dragVolDspValue : playbackService.volumeDsp,
              label: "${(dragVolDspValue * 100).toInt()}",
              onChangeStart: (value) {
                isDragging = true;
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
              onChanged: (value) {
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
              onChangeEnd: (value) {
                isDragging = false;
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: "音量",
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        icon: const Icon(Symbols.volume_up),
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

class _NowPlayingPlayModeSwitch extends StatelessWidget {
  const _NowPlayingPlayModeSwitch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return ValueListenableBuilder(
      valueListenable: playbackService.playMode,
      builder: (context, playMode, _) {
        late IconData result;
        if (playMode == PlayMode.forward) {
          result = Symbols.repeat;
        } else if (playMode == PlayMode.loop) {
          result = Symbols.repeat_on;
        } else {
          result = Symbols.repeat_one_on;
        }

        return IconButton(
          tooltip: "播放模式；现在：${switch (playMode) {
            PlayMode.forward => "顺序播放",
            PlayMode.loop => "列表循环",
            PlayMode.singleLoop => "单曲循环",
          }}",
          onPressed: () {
            if (playMode == PlayMode.forward) {
              playbackService.setPlayMode(PlayMode.loop);
            } else if (playMode == PlayMode.loop) {
              playbackService.setPlayMode(PlayMode.singleLoop);
            } else {
              playbackService.setPlayMode(PlayMode.forward);
            }
          },
          icon: Icon(result),
          color: scheme.onSecondaryContainer,
        );
      },
    );
  }
}

class _NowPlayingShuffleSwitch extends StatelessWidget {
  const _NowPlayingShuffleSwitch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return ValueListenableBuilder(
      valueListenable: playbackService.shuffle,
      builder: (context, shuffle, _) => IconButton(
        tooltip: "随机；现在：${shuffle ? "启用" : "禁用"}",
        onPressed: () {
          playbackService.useShuffle(!shuffle);
        },
        icon: Icon(shuffle ? Symbols.shuffle_on : Symbols.shuffle),
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

/// previous audio, pause/resume, next audio
class _NowPlayingMainControls extends StatelessWidget {
  const _NowPlayingMainControls();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: "上一曲",
          onPressed: playbackService.lastAudio,
          icon: const Icon(Symbols.skip_previous),
          style: LargeFilledIconButtonStyle(primary: false, scheme: scheme),
        ),
        const SizedBox(width: 16),
        StreamBuilder(
          stream: playbackService.playerStateStream,
          initialData: playbackService.playerState,
          builder: (context, snapshot) {
            final playerState = snapshot.data!;
            late void Function() onTap;
            if (playerState == PlayerState.playing) {
              onTap = playbackService.pause;
            } else if (playerState == PlayerState.completed) {
              onTap = playbackService.playAgain;
            } else {
              onTap = playbackService.start;
            }

            return IconButton(
              tooltip: playerState == PlayerState.playing ? "暂停" : "播放",
              onPressed: onTap,
              icon: Icon(
                playerState == PlayerState.playing
                    ? Symbols.pause
                    : Symbols.play_arrow,
              ),
              style: LargeFilledIconButtonStyle(primary: true, scheme: scheme),
            );
          },
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: "下一曲",
          onPressed: playbackService.nextAudio,
          icon: const Icon(Symbols.skip_next),
          style: LargeFilledIconButtonStyle(primary: false, scheme: scheme),
        ),
      ],
    );
  }
}

/// suiggly slider, position and length
class _NowPlayingSlider extends StatefulWidget {
  const _NowPlayingSlider();

  @override
  State<_NowPlayingSlider> createState() => _NowPlayingSliderState();
}

class _NowPlayingSliderState extends State<_NowPlayingSlider> {
  final dragPosition = ValueNotifier(0.0);
  bool isDragging = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = context.watch<PlaybackService>();

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            showValueIndicator: ShowValueIndicator.always,
            secondaryActiveTrackColor: scheme.primary.withValues(alpha: 0.45),
            inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
          ),
          child: StreamBuilder(
            stream: playbackService.durationStream,
            initialData: playbackService.length,
            builder: (context, durationSnapshot) {
              final sliderMax = (durationSnapshot.data ?? 0.0) > 0
                  ? (durationSnapshot.data ?? 0.0)
                  : 1.0;
              return StreamBuilder(
                stream: playbackService.bufferStream,
                initialData: playbackService.buffer,
                builder: (context, bufferSnapshot) => StreamBuilder(
                  stream: playbackService.playerStateStream,
                  initialData: playbackService.playerState,
                  builder: (context, playerStateSnapshot) => ListenableBuilder(
                    listenable: dragPosition,
                    builder: (context, _) => StreamBuilder(
                      stream: playbackService.positionStream,
                      initialData: playbackService.position,
                      builder: (context, positionSnapshot) {
                        final sliderValue = isDragging
                            ? dragPosition.value
                            : (positionSnapshot.data! > sliderMax
                                    ? sliderMax
                                    : positionSnapshot.data!)
                                .clamp(0.0, sliderMax);
                        final bufferValue =
                            (bufferSnapshot.data ?? 0.0).clamp(0.0, sliderMax);
                        return Slider(
                          thumbColor: scheme.primary,
                          activeColor: scheme.primary,
                          min: 0.0,
                          max: sliderMax,
                          value: sliderValue,
                          secondaryTrackValue: bufferValue,
                          label: Duration(
                            milliseconds: (dragPosition.value * 1000).toInt(),
                          ).toStringHMMSS(),
                          onChangeStart: (value) {
                            isDragging = true;
                            dragPosition.value = value;
                          },
                          onChanged: (value) {
                            dragPosition.value = value;
                          },
                          onChangeEnd: (value) {
                            isDragging = false;
                            playbackService.seek(value);
                          },
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StreamBuilder(
                stream: playbackService.positionStream,
                initialData: playbackService.position,
                builder: (context, snapshot) {
                  final pos = snapshot.data!;
                  return Text(
                    Duration(
                      milliseconds: (pos * 1000).toInt(),
                    ).toStringHMMSS(),
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  );
                },
              ),
              StreamBuilder(
                stream: playbackService.durationStream,
                initialData: playbackService.length,
                builder: (context, snapshot) {
                  final dur = snapshot.data ?? 0.0;
                  return Text(
                    Duration(
                      milliseconds: (dur * 1000).toInt(),
                    ).toStringHMMSS(),
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  );
                },
              ),
            ],
          ),
        )
      ],
    );
  }
}

/// title, artist, album, cover
class _NowPlayingInfo extends StatefulWidget {
  const _NowPlayingInfo();

  @override
  State<_NowPlayingInfo> createState() => __NowPlayingInfoState();
}

class __NowPlayingInfoState extends State<_NowPlayingInfo> {
  final playbackService = PlayService.instance.playbackService;
  final lyricService = PlayService.instance.lyricService;
  Future<ImageProvider<Object>?>? nowPlayingCover;
  String? _currentLyricText;
  StreamSubscription? _lyricLineSub;

  void updateCover() {
    final newCover = playbackService.nowPlaying?.largeCover;
    if (identical(newCover, nowPlayingCover)) return;
    setState(() {
      nowPlayingCover = newCover;
    });
  }

  void _onLyricLineChanged(int lineIndex) {
    lyricService.currLyricFuture.then((lyric) {
      if (lyric == null || lineIndex < 0 || lineIndex >= lyric.lines.length) {
        if (_currentLyricText != null) {
          setState(() => _currentLyricText = null);
        }
        return;
      }
      final line = lyric.lines[lineIndex];
      final text = line is SyncLyricLine
          ? line.content
          : (line is UnsyncLyricLine ? line.content : '');
      if (text.isNotEmpty && text != _currentLyricText) {
        setState(() => _currentLyricText = text);
      } else if (text.isEmpty && _currentLyricText != null) {
        setState(() => _currentLyricText = null);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    playbackService.addListener(updateCover);
    nowPlayingCover = playbackService.nowPlaying?.largeCover;
    _lyricLineSub = lyricService.lyricLineStream.listen(_onLyricLineChanged);
  }

  @override
  void dispose() {
    playbackService.removeListener(updateCover);
    _lyricLineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nowPlaying = playbackService.nowPlaying;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        final coverSize = (availableWidth * 0.80).clamp(220.0, 380.0);
        final titleFontSize = (availableWidth * 0.055).clamp(18.0, 26.0);
        const artistFontSize = 14.0;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: coverSize,
                    height: coverSize,
                    child: RepaintBoundary(
                      child: nowPlayingCover == null
                          ? _buildPlaceholder(scheme, coverSize)
                          : FutureBuilder(
                              future: nowPlayingCover,
                              builder: (context, snapshot) {
                                return switch (snapshot.connectionState) {
                                  ConnectionState.done => snapshot.data == null
                                      ? _buildPlaceholder(scheme, coverSize)
                                      : ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(20.0),
                                          child: Image(
                                            image: snapshot.data!,
                                            width: coverSize,
                                            height: coverSize,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _buildPlaceholder(
                                                    scheme, coverSize),
                                          ),
                                        ),
                                  _ => Center(
                                      child: SizedBox(
                                        width: coverSize * 0.15,
                                        height: coverSize * 0.15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.0,
                                          color: scheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ),
                                };
                              },
                            ),
                    ),
                  ),
                  SizedBox(height: availableHeight * 0.03),
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: availableWidth * 0.08),
                    child: Column(
                      children: [
                        SizedBox(
                          height: titleFontSize * 1.25 + 4,
                          child: AutoScrollText(
                            text: nowPlaying == null
                                ? "Coriander Music"
                                : (_currentLyricText ?? nowPlaying.title),
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: titleFontSize,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: artistFontSize + 2,
                          child: AutoScrollText(
                            text: nowPlaying == null
                                ? "Enjoy Music"
                                : (_currentLyricText != null
                                    ? '${nowPlaying.title} - ${nowPlaying.artist}'
                                    : nowPlaying.subtitleText),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: artistFontSize,
                            ),
                          ),
                        ),
                        if (nowPlaying != null) ...[
                          const SizedBox(height: 6),
                          _buildAudioMeta(nowPlaying, scheme),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(ColorScheme scheme, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.0),
        color: scheme.surfaceContainerHighest,
      ),
      child: Icon(
        Symbols.music_note,
        size: size * 0.35,
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  /// 构建音频元信息（格式、码率、采样率、流派、年份）
  Widget _buildAudioMeta(Audio audio, ColorScheme scheme) {
    final parts = <String>[];
    final ext = _getAudioFormat(audio);
    if (ext.isNotEmpty) parts.add(ext);
    if (audio.bitrate != null) parts.add('${audio.bitrate}kbps');
    if (audio.sampleRate != null) {
      final sr = audio.sampleRate!;
      parts
          .add(sr >= 1000 ? '${(sr / 1000).toStringAsFixed(1)}kHz' : '${sr}Hz');
    }
    if (audio.genre.isNotEmpty) parts.add(audio.genre);
    if (audio.date.isNotEmpty) {
      parts.add(audio.date);
    } else if (audio.year != null) {
      parts.add('${audio.year}');
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      maxLines: 1,
      style: TextStyle(
        color: scheme.onSecondaryContainer.withValues(alpha: 0.7),
        fontSize: 12,
      ),
    );
  }

  static String _getAudioFormat(Audio audio) {
    final ext = p.extension(audio.path).toLowerCase();
    switch (ext) {
      case '.mp3':
        return 'MP3';
      case '.flac':
        return 'FLAC';
      case '.wav':
        return 'WAV';
      case '.aac':
        return 'AAC';
      case '.m4a':
        return 'M4A';
      case '.ogg':
        return 'OGG';
      case '.opus':
        return 'OPUS';
      case '.ape':
        return 'APE';
      case '.wma':
        return 'WMA';
      case '.alac':
        return 'ALAC';
      default:
        return ext.isNotEmpty ? ext.substring(1).toUpperCase() : '';
    }
  }
}
