import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/component/scroll_aware_future_builder.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/page/settings_page/edit_tag_dialog.dart';
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
  @override
  void initState() {
    super.initState();
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
    AppSettings.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
    AppSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  bool get _isNowPlaying {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    final audio = widget.playlist[widget.audioIndex];
    return nowPlaying != null && nowPlaying.path == audio.path;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final audio = widget.playlist[widget.audioIndex];

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
              builder: (context) => EditTagDialog(audio: audio),
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
              builder: (context) =>
                  EditTagDialog(audio: audio, autoSearch: true),
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
              builder: (ctx) => AlertDialog(
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
        final placeholder = Icon(
          Symbols.broken_image,
          size: 48.0,
          color: scheme.onSurface,
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
                  PlayService.instance.playbackService
                      .play(widget.audioIndex, widget.playlist);
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
                  _showMobileContextMenu(context, audio);
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
                    child: ScrollAwareFutureBuilder(
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
                              child: Text(
                                audio.title,
                                style:
                                    TextStyle(color: textColor, fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                        Text(
                          audio.subtitleText,
                          style: TextStyle(color: textColor, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
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
            ListTile(
              leading: const Icon(Symbols.plus_one),
              title: const Text("下一首播放"),
              onTap: () {
                Navigator.pop(ctx);
                PlayService.instance.playbackService.addToNext(audio);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.select),
              title: const Text("多选"),
              onTap: () {
                Navigator.pop(ctx);
                if (!widget.multiSelectController!.enableMultiSelectView) {
                  widget.multiSelectController!.useMultiSelectView(true);
                }
                widget.multiSelectController!
                    .selectAtIndex(audio, widget.audioIndex);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.info),
              title: const Text("详细信息"),
              onTap: () {
                Navigator.pop(ctx);
                context.push(app_paths.AUDIO_DETAIL_PAGE, extra: audio);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.edit),
              title: const Text("编辑标签"),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditTagDialog(audio: audio),
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
            ListTile(
              leading: const Icon(Symbols.search),
              title: const Text("刮削元数据"),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        EditTagDialog(audio: audio, autoSearch: true),
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
            ListTile(
              leading: Icon(Symbols.delete, color: scheme.error),
              title: Text("从音乐库移除", style: TextStyle(color: scheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                AudioLibrary.instance.removeAudio(audio);
                showTextOnSnackBar('已从音乐库移除"${audio.title}"');
              },
            ),
            const SizedBox(height: 8.0),
          ],
        ),
      ),
    );
  }
}
