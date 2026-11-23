import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/glass_theme/app_dialog.dart';
import 'package:coriander_player/component/auto_scroll_text.dart';
import 'package:coriander_player/component/scroll_aware_future_builder.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/glass_theme/glass_dialog.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/cloud_service/cloud_cover_prefetcher.dart';
import 'package:coriander_player/page/settings_page/edit_tag_dialog.dart';
import 'package:coriander_player/page/settings_page/glass_edit_tag_dialog.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

/// 由[playlist]和[audioIndex]确定audio，而不是直接传入audio，
/// 这是为了实现点击列表项播放乐曲时指定该列表为播放列表。
/// 同时，播放乐曲时也是需要index和playlist来定位audio和设置播放列表。
class AudioTile extends StatefulWidget {
  const AudioTile({
    super.key,
    required this.audioIndex,
    required this.playlist,
    this.focus = false,
    this.leading,
    this.action,
    this.multiSelectController,
  });

  final int audioIndex;
  final List<Audio> playlist;
  final bool focus;
  final Widget? leading;
  final Widget? action;
  final MultiSelectController? multiSelectController;

  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  int? _lastTapTime;
  late bool _isPlaying;
  late bool _isBuffering;
  late ImageProvider? _lastCoverImage;

  @override
  void initState() {
    super.initState();
    _isPlaying = _isNowPlaying;
    _isBuffering = _isBufferingState;
    _lastCoverImage = widget.playlist[widget.audioIndex].coverImage;
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
    AppSettings.instance.addListener(_onSettingsChanged);
    AudioLibrary.instance.addListener(_onLibraryChanged);
  }

  @override
  void didUpdateWidget(AudioTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // playlist 或 audioIndex 变化时同步缓存状态
    _isPlaying = _isNowPlaying;
    _isBuffering = _isBufferingState;
    _lastCoverImage = widget.playlist[widget.audioIndex].coverImage;
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
    AppSettings.instance.removeListener(_onSettingsChanged);
    AudioLibrary.instance.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    final isPlaying = _isNowPlaying;
    final isBuffering = _isBufferingState;
    if (isPlaying != _isPlaying || isBuffering != _isBuffering) {
      _isPlaying = isPlaying;
      _isBuffering = isBuffering;
      if (mounted) setState(() {});
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onLibraryChanged() {
    final currentCover = widget.playlist[widget.audioIndex].coverImage;
    if (!identical(currentCover, _lastCoverImage)) {
      _lastCoverImage = currentCover;
      if (mounted) setState(() {});
    }
  }

  bool get _isNowPlaying {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    final audio = widget.playlist[widget.audioIndex];
    return nowPlaying != null && nowPlaying.path == audio.path;
  }

  bool get _isBufferingState {
    return _isNowPlaying && PlayService.instance.playbackService.isBuffering;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final audio = widget.playlist[widget.audioIndex];

    // 云音频封面惰性预加载：仅可见项触发 Range 请求，异步不堵塞
    // prefetch 内部会去重和限流，可安全地在 build 中调用
    CloudCoverPrefetcher.instance.prefetch(audio);

    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        /// artists
        SubmenuButton(
          menuChildren: List.generate(
            audio.splitedArtists.length,
            (i) => MenuItemButton(
              onPressed: () {
                final Artist artist = AudioLibrary
                    .instance.artistCollection[audio.splitedArtists[i]]!;
                context.push(
                  app_paths.ARTIST_DETAIL_PAGE,
                  extra: artist,
                );
              },
              leadingIcon: const Icon(Symbols.artist),
              child: Text(audio.splitedArtists[i]),
            ),
          ),
          child: const Text("艺术家"),
        ),

        /// album
        MenuItemButton(
          onPressed: () {
            final Album album =
                AudioLibrary.instance.albumCollection[audio.album]!;
            context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album);
          },
          leadingIcon: const Icon(Symbols.album),
          child: Text(audio.album),
        ),

        /// 下一首播放
        MenuItemButton(
          onPressed: () {
            PlayService.instance.playbackService.addToNext(audio);
          },
          leadingIcon: const Icon(Symbols.plus_one),
          child: const Text("下一首播放"),
        ),

        /// 多选
        if (widget.multiSelectController != null)
          MenuItemButton(
            onPressed: () {
              widget.multiSelectController!.useMultiSelectView(true);
              widget.multiSelectController!.select(audio);
            },
            leadingIcon: const Icon(Symbols.select),
            child: const Text("多选"),
          ),

        /// add to playlist
        ListenableBuilder(
          listenable: PlaylistManager.instance,
          builder: (context, _) => SubmenuButton(
            menuChildren: List.generate(
              PlaylistManager.instance.allPlaylists.length,
              (i) => MenuItemButton(
                onPressed: () {
                  final playlists = PlaylistManager.instance.allPlaylists;
                  final target = playlists[i];
                  final added = target.audios.containsKey(audio.path);
                  if (added) {
                    showTextOnSnackBar("歌曲「${audio.title}」已存在");
                    return;
                  }

                  PlaylistManager.instance.addAudioToPlaylist(target, audio);
                  showTextOnSnackBar(
                    "成功将「${audio.title}」添加到歌单「${target.name}」",
                  );
                },
                leadingIcon: const Icon(Symbols.queue_music),
                child: Text(PlaylistManager.instance.allPlaylists[i].name),
              ),
            ),
            child: const Text("添加到歌单"),
          ),
        ),

        /// add to favorites
        MenuItemButton(
          onPressed: () {
            final favorites = BUILTIN_FAVORITES;
            final added = favorites.audios.containsKey(audio.path);
            if (added) {
              showTextOnSnackBar("歌曲「${audio.title}」已在\"我的最爱\"中");
              return;
            }
            PlaylistManager.instance.addAudioToPlaylist(favorites, audio);
            showTextOnSnackBar("成功将「${audio.title}」添加到「我的最爱\"");
          },
          leadingIcon: const Icon(Symbols.favorite),
          child: const Text("添加到我的最爱"),
        ),

        /// to detail page
        MenuItemButton(
          onPressed: () {
            context.push(app_paths.AUDIO_DETAIL_PAGE, extra: audio);
          },
          leadingIcon: const Icon(Symbols.info),
          child: const Text("详细信息"),
        ),

        /// edit tags
        MenuItemButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AppPreference.instance.glassActive
                  ? GlassEditTagDialog(audio: audio)
                  : EditTagDialog(audio: audio),
            ).then((saved) {
              if (saved == true) {
                audio.clearCoverCache();
                PlayService.instance.lyricService.updateLyric();
                PlayService.instance.playbackService.refreshNowPlaying();
              }
            });
          },
          leadingIcon: const Icon(Symbols.edit),
          child: const Text("编辑标签"),
        ),

        /// scrape metadata
        MenuItemButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AppPreference.instance.glassActive
                  ? GlassEditTagDialog(audio: audio, autoSearch: true)
                  : EditTagDialog(audio: audio, autoSearch: true),
            ).then((saved) {
              if (saved == true) {
                audio.clearCoverCache();
                PlayService.instance.lyricService.updateLyric();
                PlayService.instance.playbackService.refreshNowPlaying();
              }
            });
          },
          leadingIcon: const Icon(Symbols.search),
          child: const Text("刮削元数据"),
        ),

        /// remove from library
        MenuItemButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AdaptiveDialog(
                title: const Text('确认移除'),
                content: Text('确定将"${audio.title}"从音乐库中移除吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () {
                      AudioLibrary.instance.removeAudio(audio);
                      Navigator.pop(ctx);
                      showTextOnSnackBar('已从音乐库移除"${audio.title}"');
                    },
                    child: Text(
                      '移除',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            );
          },
          leadingIcon: Icon(Symbols.delete, color: scheme.error),
          child: Text('从音乐库移除', style: TextStyle(color: scheme.error)),
        ),
      ],
      builder: (context, controller, _) {
        final textColor =
            (widget.focus || _isNowPlaying) ? scheme.primary : scheme.onSurface;
        final placeholder = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.8),
                  scheme.primary.withValues(alpha: 0.4),
                ],
              ),
            ),
            child: Icon(
              Symbols.music_note,
              color: scheme.onSurface.withValues(alpha: 0.7),
              size: 24,
            ),
          ),
        );

        return Semantics(
          identifier: 'audio_tile_${widget.audioIndex}',
          child: Ink(
            height: 64.0,
            decoration: BoxDecoration(
              color: widget.multiSelectController == null
                  ? Colors.transparent
                  : widget.multiSelectController!.selected.contains(audio)
                      ? scheme.secondaryContainer
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: InkWell(
              focusColor: Colors.transparent,
              borderRadius: BorderRadius.circular(8.0),
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                  return;
                }

                if (widget.multiSelectController == null ||
                    !widget.multiSelectController!.enableMultiSelectView) {
                  // 单击正在播放的音频：不做操作；双击则从头重新播放
                  if (_isNowPlaying) {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (_lastTapTime != null && now - _lastTapTime! < 300) {
                      _lastTapTime = null;
                      PlayService.instance.playbackService
                          .play(widget.audioIndex, widget.playlist);
                    } else {
                      _lastTapTime = now;
                    }
                  } else {
                    _lastTapTime = null;
                    PlayService.instance.playbackService
                        .play(widget.audioIndex, widget.playlist);
                  }
                } else {
                  final isShiftPressed = HardwareKeyboard
                          .instance.logicalKeysPressed
                          .contains(LogicalKeyboardKey.shiftLeft) ||
                      HardwareKeyboard.instance.logicalKeysPressed
                          .contains(LogicalKeyboardKey.shiftRight);
                  if (isShiftPressed &&
                      widget.multiSelectController!.lastSelectedIndex >= 0) {
                    widget.multiSelectController!.selectRange(
                      widget.playlist,
                      widget.multiSelectController!.lastSelectedIndex,
                      widget.audioIndex,
                    );
                  } else if (widget.multiSelectController!.selected
                      .contains(audio)) {
                    widget.multiSelectController!.unselect(audio);
                  } else {
                    widget.multiSelectController!
                        .selectAtIndex(audio, widget.audioIndex);
                  }
                }
              },
              // 移动端长按进入多选模式并选中当前项
              onLongPress: () {
                if (widget.multiSelectController == null) return;
                if (PlatformHelper.isMobile) {
                  // 多选模式下长按：直接切换选中状态，不再弹底部菜单
                  // 非多选模式下长按：弹出底部操作菜单（含"多选"项可进入多选模式）
                  if (widget.multiSelectController!.enableMultiSelectView) {
                    if (widget.multiSelectController!.selected.contains(audio)) {
                      widget.multiSelectController!.unselect(audio);
                    } else {
                      widget.multiSelectController!
                          .selectAtIndex(audio, widget.audioIndex);
                    }
                    HapticFeedback.mediumImpact();
                  } else {
                    _showMobileContextMenu(context, audio);
                  }
                } else {
                  if (!widget.multiSelectController!.enableMultiSelectView) {
                    widget.multiSelectController!.useMultiSelectView(true);
                  }
                  widget.multiSelectController!
                      .selectAtIndex(audio, widget.audioIndex);
                  HapticFeedback.mediumImpact();
                }
              },
              onSecondaryTapDown: (details) {
                if (widget.multiSelectController?.enableMultiSelectView == true)
                  return;

                controller.open(
                    position: details.localPosition.translate(0, -240));
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: PlatformHelper.isMobile ? 4.0 : 8.0,
                ),
                child: Row(children: [
                  if (widget.multiSelectController != null &&
                      widget.multiSelectController!.enableMultiSelectView)
                    Padding(
                      padding: EdgeInsets.only(
                          right: PlatformHelper.isMobile ? 8.0 : 12.0),
                      child: Checkbox(
                        value: widget.multiSelectController!.selected
                            .contains(audio),
                        onChanged: (_) {
                          if (widget.multiSelectController!.selected
                              .contains(audio)) {
                            widget.multiSelectController!.unselect(audio);
                          } else {
                            widget.multiSelectController!
                                .selectAtIndex(audio, widget.audioIndex);
                          }
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                  else if (AppSettings.instance.showTrackIndex)
                    Padding(
                      padding: EdgeInsets.only(
                          right: PlatformHelper.isMobile ? 8.0 : 12.0),
                      child: SizedBox(
                        width: PlatformHelper.isMobile ? 24.0 : 32.0,
                        child: Text(
                          '${widget.audioIndex + 1}',
                          style: TextStyle(
                            color: (widget.focus || _isNowPlaying)
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ),

                  if (widget.leading != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: widget.leading!,
                    ),

                  /// cover
                  PlayingIndicatorOverlay(
                    size: PlayingIndicatorSize.small,
                    isActivelyPlaying: _isNowPlaying,
                    isBuffering: _isBuffering,
                    child: ScrollAwareFutureBuilder(
                      // 通过 coverImage 作为 key，当封面被 setCover 更新时
                      // （如 autoScrape 抓取到封面后），key 变化会触发 State 销毁重建，
                      // 让 _cachedData 失效，重新调用 audio.cover 拿到新封面。
                      key: ValueKey(audio.coverImage),
                      future: () => audio.cover,
                      builder: (context, snapshot) {
                        if (snapshot.data == null) {
                          return placeholder;
                        }

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image(
                            image: snapshot.data!,
                            width: 48.0,
                            height: 48.0,
                            errorBuilder: (_, __, ___) => placeholder,
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: PlatformHelper.isMobile ? 10.0 : 16.0),

                  /// title, artist and album
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: AutoScrollText(
                                text: audio.title,
                                style:
                                    TextStyle(color: textColor, fontSize: 16),
                                scrollSpeed: AppSettings.instance.marqueeSpeed,
                              ),
                            ),
                            if (audio.isCloudAudio)
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: Icon(
                                  Symbols.cloud,
                                  size: 14,
                                  color: scheme.outline,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2.0),
                        AutoScrollText(
                          text: audio.subtitleText,
                          style: TextStyle(color: textColor, fontSize: 13),
                          scrollSpeed: AppSettings.instance.marqueeSpeed,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Duration(seconds: audio.duration).toStringHMMSS(),
                        style: TextStyle(
                          color: (widget.focus || _isNowPlaying)
                              ? scheme.primary
                              : scheme.onSurface,
                        ),
                      ),
                      _buildAudioMetaRight(audio, scheme),
                    ],
                  ),
                  if (widget.action != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: widget.action!,
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建右侧元信息（时长下方：格式 · 文件大小）
  static Widget _buildAudioMetaRight(Audio audio, ColorScheme scheme) {
    final format = _getAudioFormat(audio);
    final parts = <String>[];
    if (format.isNotEmpty) parts.add(format);
    // 获取文件大小
    final fileSize = _getFileSize(audio);
    if (fileSize != null) parts.add(fileSize);

    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
    );
  }

  /// 获取音频文件大小
  static String? _getFileSize(Audio audio) {
    if (audio.isCloudAudio) {
      if (audio.fileSize != null && audio.fileSize! > 0) {
        return _formatFileSize(audio.fileSize!);
      }
      return null;
    }
    try {
      final file = File(audio.path);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        return _formatFileSize(bytes);
      }
    } catch (_) {}
    return null;
  }

  /// 格式化文件大小
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 从路径获取音频格式
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

  void _showMobileContextMenu(BuildContext context, Audio audio) {
    final scheme = Theme.of(context).colorScheme;
    HapticFeedback.mediumImpact();
    final useGlass = AppPreference.instance.glassActive;

    // 菜单项定义（顺序与桌面端右键菜单基本一致）
    final items = <_ContextMenuEntry>[
      _ContextMenuEntry(
        icon: Symbols.plus_one,
        title: '下一首播放',
        onTap: () => PlayService.instance.playbackService.addToNext(audio),
      ),
      _ContextMenuEntry(
        icon: Symbols.playlist_add,
        title: '添加到歌单',
        onTap: () => _showPlaylistPickerForAudio(context, audio),
      ),
      _ContextMenuEntry(
        icon: Symbols.favorite,
        title: '添加到我的最爱',
        onTap: () {
          final favorites = BUILTIN_FAVORITES;
          if (favorites.audios.containsKey(audio.path)) {
            showTextOnSnackBar("歌曲「${audio.title}」已在\"我的最爱\"中");
            return;
          }
          PlaylistManager.instance.addAudioToPlaylist(favorites, audio);
          showTextOnSnackBar("成功将「${audio.title}」添加到「我的最爱」");
        },
      ),
      _ContextMenuEntry(
        icon: Symbols.select,
        title: '多选',
        onTap: () {
          if (!widget.multiSelectController!.enableMultiSelectView) {
            widget.multiSelectController!.useMultiSelectView(true);
          }
          widget.multiSelectController!
              .selectAtIndex(audio, widget.audioIndex);
        },
      ),
      _ContextMenuEntry(
        icon: Symbols.info,
        title: '详细信息',
        onTap: () => context.push(app_paths.AUDIO_DETAIL_PAGE, extra: audio),
      ),
      _ContextMenuEntry(
        icon: Symbols.edit,
        title: '编辑标签',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppPreference.instance.glassActive
                  ? GlassEditTagDialog(audio: audio)
                  : EditTagDialog(audio: audio),
            ),
          ).then((saved) {
            if (saved == true) {
              audio.clearCoverCache();
              PlayService.instance.lyricService.updateLyric();
              PlayService.instance.playbackService.refreshNowPlaying();
            }
          });
        },
      ),
      _ContextMenuEntry(
        icon: Symbols.search,
        title: '刮削元数据',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AppPreference.instance.glassActive
                  ? GlassEditTagDialog(audio: audio, autoSearch: true)
                  : EditTagDialog(audio: audio, autoSearch: true),
            ),
          ).then((saved) {
            if (saved == true) {
              audio.clearCoverCache();
              PlayService.instance.lyricService.updateLyric();
              PlayService.instance.playbackService.refreshNowPlaying();
            }
          });
        },
      ),
      _ContextMenuEntry(
        icon: Symbols.delete,
        title: '从音乐库移除',
        isDestructive: true,
        onTap: () => _confirmRemoveAudio(context, audio),
      ),
    ];

    if (useGlass) {
      // Glass 模式：底部弹出 + GlassContainer（项目 sheetSettings 预设）
      // 与项目其他玻璃组件（GlassDialog/GlassMenuItem）视觉统一
      showAdaptiveSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: GlassContainer(
              useOwnLayer: true,
              quality: GlassQuality.premium,
              shape: const LiquidRoundedSuperellipse(borderRadius: 24),
              settings: sheetSettings,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Row(
                        children: [
                          Icon(Symbols.music_note,
                              color: scheme.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              audio.title,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: scheme.onSurface.withValues(alpha: 0.1),
                    ),
                    // 可滚动菜单列表
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final entry = items[i];
                          final color = entry.isDestructive
                              ? scheme.error
                              : scheme.onSurface;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                Navigator.pop(ctx);
                                entry.onTap?.call();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                child: Row(
                                  children: [
                                    Icon(entry.icon, size: 22, color: color),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        entry.title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: color,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      // 普通模式：保持 showModalBottomSheet，但用可滚动 ListView 包裹
      showAdaptiveSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  audio.title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final entry = items[i];
                    return ListTile(
                      leading: Icon(entry.icon,
                          color: entry.isDestructive ? scheme.error : null),
                      title: Text(
                        entry.title,
                        style: TextStyle(
                            color: entry.isDestructive ? scheme.error : null),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        entry.onTap?.call();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8.0),
            ],
          ),
        ),
      );
    }
  }

  /// 移除音频的二次确认对话框（Glass 模式用 GlassDialog）
  void _confirmRemoveAudio(BuildContext context, Audio audio) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;

    void doRemove() {
      AudioLibrary.instance.removeAudio(audio);
      showTextOnSnackBar('已从音乐库移除"${audio.title}"');
    }

    if (useGlass) {
      showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (ctx) => GlassDialog(
          title: '确认移除',
          width: 380,
          padding: const EdgeInsets.all(20),
          actions: [
            GlassDialogButton(
              label: '取消',
              icon: Symbols.close,
              onTap: () => Navigator.pop(ctx),
            ),
            GlassDialogButton(
              label: '移除',
              icon: Symbols.delete,
              primary: true,
              onTap: () {
                Navigator.pop(ctx);
                doRemove();
              },
            ),
          ],
          child: Text(
            '确定将"${audio.title}"从音乐库中移除吗？',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AdaptiveDialog(
          title: const Text('确认移除'),
          content: Text('确定将"${audio.title}"从音乐库中移除吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                doRemove();
              },
              child: Text('移除', style: TextStyle(color: scheme.error)),
            ),
          ],
        ),
      );
    }
  }

  /// 移动端单音频"添加到歌单"歌单选择器
  /// 与桌面端 SubmenuButton 行为对齐：选歌单即添加，已添加则提示
  void _showPlaylistPickerForAudio(BuildContext context, Audio audio) {
    final playlists = PlaylistManager.instance.allPlaylists;
    if (playlists.isEmpty) {
      showTextOnSnackBar('没有可用的歌单，请先创建歌单');
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;

    void addToPlaylist(int i) {
      final target = playlists[i];
      if (target.audios.containsKey(audio.path)) {
        showTextOnSnackBar("歌曲「${audio.title}」已存在");
        return;
      }
      PlaylistManager.instance.addAudioToPlaylist(target, audio);
      showTextOnSnackBar(
        "成功将「${audio.title}」添加到歌单「${target.name}」",
      );
    }

    if (useGlass) {
      // Glass 模式：底部弹出 + GlassContainer（与上下文菜单风格统一）
      showAdaptiveSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: GlassContainer(
              useOwnLayer: true,
              quality: GlassQuality.premium,
              shape: const LiquidRoundedSuperellipse(borderRadius: 24),
              settings: sheetSettings,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Row(
                        children: [
                          Icon(Symbols.playlist_add,
                              color: scheme.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '添加到歌单',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: scheme.onSurface.withValues(alpha: 0.1),
                    ),
                    Flexible(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        itemCount: playlists.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color:
                              scheme.onSurface.withValues(alpha: 0.08),
                        ),
                        itemBuilder: (ctx, i) => _GlassPlaylistPickerTile(
                          playlist: playlists[i],
                          alreadyAdded:
                              playlists[i].audios.containsKey(audio.path),
                          onTap: () {
                            Navigator.pop(ctx);
                            addToPlaylist(i);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showAdaptiveSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '添加到歌单',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (ctx, i) {
                    final playlist = playlists[i];
                    final alreadyAdded = playlist.audios.containsKey(audio.path);
                    return ListTile(
                      leading: Icon(Symbols.queue_music,
                          color: alreadyAdded ? scheme.outline : null),
                      title: Text(playlist.name),
                      trailing: alreadyAdded
                          ? const Icon(Symbols.check, size: 20)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        addToPlaylist(i);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8.0),
            ],
          ),
        ),
      );
    }
  }
}

/// 上下文菜单项定义
class _ContextMenuEntry {
  const _ContextMenuEntry({
    required this.icon,
    required this.title,
    this.isDestructive = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final bool isDestructive;
  final VoidCallback? onTap;
}

/// Glass 风格的歌单选择项，用于单音频"添加到歌单"弹窗
class _GlassPlaylistPickerTile extends StatelessWidget {
  const _GlassPlaylistPickerTile({
    required this.playlist,
    required this.alreadyAdded,
    required this.onTap,
  });

  final Playlist playlist;
  final bool alreadyAdded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = alreadyAdded ? scheme.outline : scheme.primary;
    final textColor = scheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(Symbols.queue_music, size: 22, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  playlist.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (alreadyAdded)
                Icon(Symbols.check, size: 18, color: scheme.outline)
              else
                Icon(Symbols.chevron_right,
                    size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
