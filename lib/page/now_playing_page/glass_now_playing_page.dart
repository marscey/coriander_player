import 'dart:async';
import 'dart:ui';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/glass_theme/app_dialog.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/auto_scroll_text.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:coriander_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:coriander_player/page/now_playing_page/page.dart';
import 'package:coriander_player/page/settings_page/glass_edit_tag_dialog.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Now Playing 页面 — iOS 26 Liquid Glass 风格
///
/// 布局：
/// - 全屏沉浸式背景：专辑封面 blur + 渐变暗化
/// - GlassScaffold 承载内容
/// - 顶部栏：返回按钮 + 歌名 + 更多菜单（Glass 风格）
/// - 中间：封面 / 歌词 / 播放列表切换
/// - 底部：进度条 + 播放控制按钮 + 功能按钮（Glass 风格）
class GlassNowPlayingPage extends StatefulWidget {
  const GlassNowPlayingPage({super.key});

  @override
  State<GlassNowPlayingPage> createState() => _GlassNowPlayingPageState();
}

class _GlassNowPlayingPageState extends State<GlassNowPlayingPage>
    with TickerProviderStateMixin {
  final playbackService = PlayService.instance.playbackService;
  ImageProvider<Object>? nowPlayingCover;

  // 下滑关闭手势
  double _dragOffsetY = 0.0;
  AnimationController? _dismissAnimCtrl;

  void updateCover() {
    final audio = playbackService.nowPlaying;
    if (audio == null) {
      if (nowPlayingCover != null && mounted) {
        setState(() => nowPlayingCover = null);
      }
      return;
    }
    audio.cover.then((cover) {
      if (mounted && !identical(cover, nowPlayingCover)) {
        setState(() => nowPlayingCover = cover);
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
    final scheme = Theme.of(context).colorScheme;

    final body = _GlassNowPlayingBody(cover: nowPlayingCover);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 沉浸式背景
          Positioned.fill(child: _buildBackground(scheme)),
          // 内容区（支持手势关闭）
          Positioned.fill(
            child: GestureDetector(
              onVerticalDragStart: (_) {
                _dismissAnimCtrl?.stop();
                _dragOffsetY = _dismissAnimCtrl?.value ?? 0.0;
              },
              onVerticalDragUpdate: (details) {
                if (details.delta.dy > 0) {
                  setState(() => _dragOffsetY += details.delta.dy);
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
              child: _GlassNowPlayingTopBar(cover: nowPlayingCover),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(ColorScheme scheme) {
    if (nowPlayingCover != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
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
                  scheme.primary.withValues(alpha: 0.18),
                  scheme.secondaryContainer.withValues(alpha: 0.55),
                  scheme.surface.withValues(alpha: 0.9),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.22),
                  Colors.black.withValues(alpha: 0.06),
                ],
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 140, sigmaY: 140),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ],
      );
    }

    return buildGlassBackground(scheme);
  }
}

/// 顶部栏：返回按钮 + 歌名 + 更多菜单
class _GlassNowPlayingTopBar extends StatelessWidget {
  const _GlassNowPlayingTopBar({this.cover});

  final ImageProvider<Object>? cover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return ListenableBuilder(
      listenable: playbackService,
      builder: (context, _) {
        final nowPlaying = playbackService.nowPlaying;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              GlassButton(
                icon: Icon(Symbols.keyboard_arrow_down, size: 24),
                iconSize: 24,
                width: 44,
                height: 44,
                useOwnLayer: true,
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Column(
                    children: [
                      Text(
                        nowPlaying?.title ?? "",
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (nowPlaying != null)
                        Text(
                          nowPlaying.artist,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const _GlassNowPlayingMoreAction(),
            ],
          ),
        );
      },
    );
  }
}

/// 更多操作按钮
class _GlassNowPlayingMoreAction extends StatelessWidget {
  const _GlassNowPlayingMoreAction();

  @override
  Widget build(BuildContext context) {
    final playbackService = PlayService.instance.playbackService;
    final nowPlaying = playbackService.nowPlaying;

    if (nowPlaying == null) {
      return GlassButton(
        icon: const Icon(Icons.more_vert, size: 20),
        iconSize: 20,
        width: 44,
        height: 44,
        useOwnLayer: true,
        onTap: () {},
      );
    }

    return GlassMenu(
      menuWidth: 220,
      quality: navButtonQuality,
      triggerBuilder: (context, toggleMenu) => GlassButton(
        onTap: toggleMenu,
        icon: const Icon(Icons.more_vert, size: 20),
        iconSize: 20,
        width: 44,
        height: 44,
        useOwnLayer: true,
      ),
      items: [
        // 添加到歌单
        ListenableBuilder(
          listenable: PlaylistManager.instance,
          builder: (context, _) => GlassMenuItem(
            title: '添加到歌单',
            icon: const Icon(Symbols.queue_music, size: 20),
            onTap: () {
              _showAddToPlaylistSheet(context, nowPlaying);
            },
          ),
        ),
        GlassMenuItem(
          title: '添加到我的最爱',
          icon: const Icon(Symbols.favorite, size: 20),
          onTap: () {
            final favorites = BUILTIN_FAVORITES;
            final added = favorites.audios.containsKey(nowPlaying.path);
            if (added) {
              showTextOnSnackBar("歌曲「${nowPlaying.title}」已在\"我的最爱\"中");
              return;
            }
            PlaylistManager.instance.addAudioToPlaylist(favorites, nowPlaying);
            showTextOnSnackBar("成功将「${nowPlaying.title}」添加到「我的最爱」");
          },
        ),
        const GlassMenuDivider(),
        // 艺术家
        if (nowPlaying.splitedArtists.isNotEmpty)
          ...nowPlaying.splitedArtists.map(
            (artistName) => GlassMenuItem(
              title: artistName,
              icon: const Icon(Symbols.person, size: 20),
              onTap: () {
                final artist =
                    AudioLibrary.instance.artistCollection[artistName];
                if (artist != null) {
                  context.push(app_paths.ARTIST_DETAIL_PAGE, extra: artist);
                }
              },
            ),
          ),
        GlassMenuItem(
          title: '查看专辑',
          icon: const Icon(Symbols.album, size: 20),
          onTap: () {
            final album =
                AudioLibrary.instance.albumCollection[nowPlaying.album];
            if (album != null) {
              context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album);
            }
          },
        ),
        GlassMenuItem(
          title: '详细信息',
          icon: const Icon(Symbols.info, size: 20),
          onTap: () {
            context.push(app_paths.AUDIO_DETAIL_PAGE, extra: nowPlaying);
          },
        ),
        const GlassMenuDivider(),
        GlassMenuItem(
          title: '编辑标签',
          icon: const Icon(Symbols.edit, size: 20),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => GlassEditTagDialog(audio: nowPlaying),
            ).then((saved) {
              if (saved == true) {
                nowPlaying.clearCoverCache();
                PlayService.instance.lyricService.updateLyric();
                playbackService.refreshNowPlaying();
              }
            });
          },
        ),
        GlassMenuItem(
          title: '刮削元数据',
          icon: const Icon(Symbols.search, size: 20),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) =>
                  GlassEditTagDialog(audio: nowPlaying, autoSearch: true),
            ).then((saved) {
              if (saved == true) {
                nowPlaying.clearCoverCache();
                PlayService.instance.lyricService.updateLyric();
                playbackService.refreshNowPlaying();
              }
            });
          },
        ),
      ],
    );
  }

  void _showAddToPlaylistSheet(BuildContext context, Audio audio) {
    final playlists = PlaylistManager.instance.allPlaylists;
    showAdaptiveSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '添加到歌单',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...playlists.map(
              (pl) => ListTile(
                leading: const Icon(Symbols.queue_music),
                title: Text(pl.name),
                onTap: () {
                  final added = pl.audios.containsKey(audio.path);
                  if (added) {
                    showTextOnSnackBar("歌曲「${audio.title}」已在歌单「${pl.name}」中");
                  } else {
                    PlaylistManager.instance.addAudioToPlaylist(pl, audio);
                    showTextOnSnackBar("成功将「${audio.title}」添加到歌单「${pl.name}」");
                  }
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Now Playing 主体内容
class _GlassNowPlayingBody extends StatelessWidget {
  const _GlassNowPlayingBody({this.cover});

  final ImageProvider<Object>? cover;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部留白（给顶部栏留空间）
        SizedBox(
          height: MediaQuery.of(context).padding.top + 52,
        ),
        // 中间内容区（封面/歌词/播放列表）
        Expanded(
          child: ValueListenableBuilder<NowPlayingViewMode>(
            valueListenable: NOW_PLAYING_VIEW_MODE,
            builder: (context, mode, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: switch (mode) {
                NowPlayingViewMode.onlyMain =>
                  _GlassNowPlayingInfo(cover: cover),
                NowPlayingViewMode.withLyric => const VerticalLyricView(),
                NowPlayingViewMode.withPlaylist => const CurrentPlaylistView(),
              },
            ),
          ),
        ),
        // 进度条
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _GlassNowPlayingSlider(),
        ),
        const SizedBox(height: 8.0),
        // 主控制按钮
        const _GlassNowPlayingMainControls(),
        const SizedBox(height: 8.0),
        // 底部功能按钮
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const _GlassNowPlayingViewSwitchButton(),
              const _GlassNowPlayingShuffleSwitch(),
              const _GlassNowPlayingPlayModeSwitch(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 封面 + 歌曲信息
class _GlassNowPlayingInfo extends StatefulWidget {
  const _GlassNowPlayingInfo({this.cover});

  final ImageProvider<Object>? cover;

  @override
  State<_GlassNowPlayingInfo> createState() => _GlassNowPlayingInfoState();
}

class _GlassNowPlayingInfoState extends State<_GlassNowPlayingInfo> {
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

        final coverSize = (availableWidth * 0.78).clamp(220.0, 360.0);
        final titleFontSize = (availableWidth * 0.052).clamp(17.0, 24.0);
        const artistFontSize = 14.0;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 封面（GlassCard 包裹，圆角方形）
                  SizedBox(
                    width: coverSize,
                    height: coverSize,
                    child: GlassCard(
                      padding: EdgeInsets.zero,
                      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                      settings: cardSettings,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: nowPlayingCover == null
                            ? _buildPlaceholder(scheme, coverSize)
                            : FutureBuilder(
                                future: nowPlayingCover,
                                builder: (context, snapshot) {
                                  return switch (snapshot.connectionState) {
                                    ConnectionState.done =>
                                      snapshot.data == null
                                          ? _buildPlaceholder(
                                              scheme, coverSize)
                                          : Image(
                                              image: snapshot.data!,
                                              width: coverSize,
                                              height: coverSize,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _buildPlaceholder(
                                                      scheme, coverSize),
                                            ),
                                    _ => Center(
                                        child: SizedBox(
                                          width: coverSize * 0.12,
                                          height: coverSize * 0.12,
                                          child: CupertinoActivityIndicator(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                  };
                                },
                              ),
                      ),
                    ),
                  ),
                  SizedBox(height: availableHeight * 0.03),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: availableWidth * 0.08),
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
                            scrollSpeed: AppSettings.instance.marqueeSpeed,
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
                            scrollSpeed: AppSettings.instance.marqueeSpeed,
                          ),
                        ),
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
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Symbols.music_note,
        size: size * 0.35,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 进度条 — Glass 风格
class _GlassNowPlayingSlider extends StatefulWidget {
  const _GlassNowPlayingSlider();

  @override
  State<_GlassNowPlayingSlider> createState() =>
      _GlassNowPlayingSliderState();
}

class _GlassNowPlayingSliderState extends State<_GlassNowPlayingSlider> {
  final dragPosition = ValueNotifier(0.0);
  bool isDragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            showValueIndicator: ShowValueIndicator.always,
            secondaryActiveTrackColor: scheme.primary.withValues(alpha: 0.45),
            inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
          ),
          child: ListenableBuilder(
            listenable: playbackService,
            builder: (context, _) {
              final isRestored = playbackService.isRestoredState;
              final displayDuration = playbackService.displayLength;
              final displayPosition = playbackService.displayPosition;
              final displayBuffer = playbackService.displayBuffer;
              return StreamBuilder(
                stream: playbackService.durationStream,
                builder: (context, durationSnapshot) {
                  final duration = isRestored
                      ? displayDuration
                      : (durationSnapshot.data ?? displayDuration);
                  final sliderMax =
                      (duration > 0) ? duration : 1.0;
                  return StreamBuilder(
                    stream: playbackService.bufferStream,
                    builder: (context, bufferSnapshot) => StreamBuilder(
                      stream: playbackService.playerStateStream,
                      initialData: playbackService.playerState,
                      builder: (context, playerStateSnapshot) =>
                          ListenableBuilder(
                        listenable: dragPosition,
                        builder: (context, _) => StreamBuilder(
                          stream: playbackService.positionStream,
                          builder: (context, positionSnapshot) {
                            final pos = isRestored
                                ? displayPosition
                                : (positionSnapshot.data ?? displayPosition);
                            final sliderValue = isDragging
                                ? dragPosition.value
                                : (pos > sliderMax
                                        ? sliderMax
                                        : pos)
                                    .clamp(0.0, sliderMax);
                            final buf = isRestored
                                ? displayBuffer
                                : (bufferSnapshot.data ?? displayBuffer);
                            final bufferValue = buf.clamp(0.0, sliderMax);
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
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ListenableBuilder(
                listenable: playbackService,
                builder: (context, _) {
                  final isRestored = playbackService.isRestoredState;
                  return StreamBuilder(
                    stream: playbackService.positionStream,
                    builder: (context, snapshot) {
                      final pos = isRestored
                          ? playbackService.displayPosition
                          : (snapshot.data ?? playbackService.displayPosition);
                      return Text(
                        Duration(
                          milliseconds: (pos * 1000).toInt(),
                        ).toStringHMMSS(),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      );
                    },
                  );
                },
              ),
              ListenableBuilder(
                listenable: playbackService,
                builder: (context, _) {
                  final isRestored = playbackService.isRestoredState;
                  return StreamBuilder(
                    stream: playbackService.durationStream,
                    builder: (context, snapshot) {
                      final dur = isRestored
                          ? playbackService.displayLength
                          : (snapshot.data ?? playbackService.displayLength);
                      return Text(
                        Duration(
                          milliseconds: (dur * 1000).toInt(),
                        ).toStringHMMSS(),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 主控制按钮：上一曲、播放/暂停、下一曲 — Glass 风格
class _GlassNowPlayingMainControls extends StatelessWidget {
  const _GlassNowPlayingMainControls();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 上一曲
        GlassButton(
          icon: const Icon(Symbols.skip_previous, size: 28),
          iconSize: 28,
          width: 56,
          height: 56,
          useOwnLayer: true,
          onTap: playbackService.lastAudio,
        ),
        const SizedBox(width: 20),
        // 播放/暂停（大按钮）— 恢复加载期间显示 loading 并禁用
        ListenableBuilder(
          listenable: playbackService,
          builder: (context, _) {
            if (playbackService.isStartingFromRestored) {
              return GlassButton.custom(
                onTap: () {},
                width: 72,
                height: 72,
                useOwnLayer: true,
                settings: navButtonSettings.copyWith(
                  thickness: 30,
                ),
                shape: const LiquidRoundedSuperellipse(borderRadius: 36),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(scheme.onSurface),
                  ),
                ),
              );
            }
            return StreamBuilder(
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

                return GlassButton.custom(
                  onTap: onTap,
                  width: 72,
                  height: 72,
                  useOwnLayer: true,
                  settings: navButtonSettings.copyWith(
                    thickness: 30,
                  ),
                  shape: const LiquidRoundedSuperellipse(borderRadius: 36),
                  child: Icon(
                    playerState == PlayerState.playing
                        ? Symbols.pause
                        : Symbols.play_arrow,
                    size: 32,
                    color: scheme.onSurface,
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(width: 20),
        // 下一曲
        GlassButton(
          icon: const Icon(Symbols.skip_next, size: 28),
          iconSize: 28,
          width: 56,
          height: 56,
          useOwnLayer: true,
          onTap: playbackService.nextAudio,
        ),
      ],
    );
  }
}

/// 视图切换按钮
class _GlassNowPlayingViewSwitchButton extends StatelessWidget {
  const _GlassNowPlayingViewSwitchButton();

  @override
  Widget build(BuildContext context) {
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

        return GlassButton(
          icon: Icon(icon, size: 20),
          iconSize: 20,
          width: 44,
          height: 44,
          useOwnLayer: true,
          onTap: () {
            NOW_PLAYING_VIEW_MODE.value = nextMode;
            AppPreference.instance.nowPlayingPagePref.nowPlayingViewMode =
                nextMode;
          },
        );
      },
    );
  }
}

/// 随机播放切换
class _GlassNowPlayingShuffleSwitch extends StatelessWidget {
  const _GlassNowPlayingShuffleSwitch();

  @override
  Widget build(BuildContext context) {
    final playbackService = PlayService.instance.playbackService;

    return ValueListenableBuilder(
      valueListenable: playbackService.shuffle,
      builder: (context, shuffle, _) => GlassButton(
        icon: Icon(shuffle ? Symbols.shuffle_on : Symbols.shuffle, size: 20),
        iconSize: 20,
        width: 44,
        height: 44,
        useOwnLayer: true,
        onTap: () {
          playbackService.useShuffle(!shuffle);
        },
      ),
    );
  }
}

/// 播放模式切换
class _GlassNowPlayingPlayModeSwitch extends StatelessWidget {
  const _GlassNowPlayingPlayModeSwitch();

  @override
  Widget build(BuildContext context) {
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

        return GlassButton(
          icon: Icon(result, size: 20),
          iconSize: 20,
          width: 44,
          height: 44,
          useOwnLayer: true,
          onTap: () {
            if (playMode == PlayMode.forward) {
              playbackService.setPlayMode(PlayMode.loop);
            } else if (playMode == PlayMode.loop) {
              playbackService.setPlayMode(PlayMode.singleLoop);
            } else {
              playbackService.setPlayMode(PlayMode.forward);
            }
          },
        );
      },
    );
  }
}
