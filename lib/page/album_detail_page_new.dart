import 'dart:ui';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 专辑详情页面
class AlbumDetailPageNew extends StatefulWidget {
  const AlbumDetailPageNew({super.key, required this.album});

  final Album album;

  @override
  State<AlbumDetailPageNew> createState() => _AlbumDetailPageNewState();
}

class _AlbumDetailPageNewState extends State<AlbumDetailPageNew> {
  late SortMethodDesc<Audio>? currSortMethod;
  late SortOrder currSortOrder;
  late ContentView currContentView;
  late MultiSelectController<Audio> multiSelectController;
  late List<Audio> sortedAudios;
  late ScrollController _scrollController;
  late ValueNotifier<double> _scrollNotifier;

  @override
  void initState() {
    super.initState();
    currSortMethod = SortMethodDesc(
      icon: Symbols.numbers,
      name: "音轨",
      method: (list, order) {
        switch (order) {
          case SortOrder.ascending:
            list.sort((a, b) => a.track.compareTo(b.track));
            break;
          case SortOrder.decending:
            list.sort((a, b) => b.track.compareTo(a.track));
            break;
        }
      },
    );
    currSortOrder = SortOrder.ascending;
    currContentView = ContentView.list;
    multiSelectController = MultiSelectController<Audio>();
    sortedAudios = List.from(widget.album.works);
    currSortMethod?.method(sortedAudios, currSortOrder);
    _scrollController = ScrollController();
    _scrollNotifier = ValueNotifier(0.0);
    _scrollController.addListener(_onScroll);

    // 设置沉浸式状态栏
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollNotifier.dispose();
    // 恢复状态栏样式
    final brightness = Theme.of(context).brightness;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: brightness,
    ));
    super.dispose();
  }

  void _onScroll() {
    _scrollNotifier.value = _scrollController.offset;
  }

  String _formatTotalDuration() {
    final totalSeconds = sortedAudios.fold<int>(0, (sum, audio) => sum + audio.duration);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes 分钟 ${seconds.toString().padLeft(2, '0')} 秒';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final album = widget.album;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final navBarHeight = 56.0;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          // 滚动内容区
          Positioned.fill(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // 顶部间距
                SliverToBoxAdapter(
                  child: SizedBox(height: statusBarHeight + navBarHeight + 8.0),
                ),

                // 大标题（使用 ValueListenableBuilder 避免全量 rebuild）
                SliverToBoxAdapter(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scrollNotifier,
                    builder: (context, scrollOffset, _) {
                      final opacity = (1.0 - scrollOffset / 100.0).clamp(0.0, 1.0);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
                        child: Opacity(
                          opacity: opacity,
                          child: Text(
                            album.name,
                            style: TextStyle(
                              fontSize: 28.0,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 专辑信息区
                SliverToBoxAdapter(
                  child: _AlbumInfoSection(album: album, scheme: scheme),
                ),

                // 操作按钮区
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: Symbols.repeat,
                            label: "顺序播放",
                            onTap: () {
                              HapticFeedback.lightImpact();
                              PlayService.instance.playbackService.play(0, sortedAudios);
                            },
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: _ActionButton(
                            icon: Symbols.shuffle,
                            label: "随机播放",
                            onTap: () {
                              HapticFeedback.lightImpact();
                              PlayService.instance.playbackService.shuffleAndPlay(sortedAudios);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 歌曲列表
                SliverList.builder(
                  itemCount: sortedAudios.length,
                  itemBuilder: (context, index) {
                    return _AlbumAudioTile(
                      audio: sortedAudios[index],
                      audioIndex: index,
                      playlist: sortedAudios,
                    );
                  },
                ),

                const SliverPadding(padding: EdgeInsets.only(bottom: 96.0)),
              ],
            ),
          ),

          // 毛玻璃导航栏（透明背景 + 玻璃效果图标）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _scrollNotifier,
              builder: (context, scrollOffset, _) {
                // 导航栏背景透明度随滚动变化
                final bgOpacity = (scrollOffset / 100.0).clamp(0.0, 0.85);
                final navTitleOpacity = (scrollOffset / 100.0).clamp(0.0, 1.0);

                return Container(
                  height: statusBarHeight + navBarHeight,
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: bgOpacity),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      height: navBarHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        children: [
                          // 返回按钮（玻璃效果）
                          _GlassButton(
                            onTap: () => Navigator.pop(context),
                            child: Icon(Symbols.arrow_back, color: scheme.onSurface, size: 20.0),
                          ),
                          const SizedBox(width: 8.0),
                          // 折叠后标题
                          Expanded(
                            child: Opacity(
                              opacity: navTitleOpacity,
                              child: Text(
                                album.name,
                                style: TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // 更多按钮（玻璃效果）
                          _GlassButton(
                            onTap: () {},
                            child: Text("更多", style: TextStyle(color: scheme.onSurface)),
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
    );
  }
}

/// 玻璃效果按钮
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.onTap, required this.child, this.padding});
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4.0,
            offset: const Offset(0, 1.0),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20.0),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(8.0),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 专辑信息区
class _AlbumInfoSection extends StatelessWidget {
  const _AlbumInfoSection({required this.album, required this.scheme});
  final Album album;
  final ColorScheme scheme;

  String _formatTotalDuration(List<Audio> audios) {
    final totalSeconds = audios.fold<int>(0, (sum, audio) => sum + audio.duration);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes 分钟 ${seconds.toString().padLeft(2, '0')} 秒';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 专辑封面
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8.0,
                  offset: const Offset(0, 2.0),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: _CachedCoverImage(
                coverFuture: album.works.first.cover,
                width: 120.0,
                height: 120.0,
                scheme: scheme,
              ),
            ),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.name,
                  style: TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  album.name,
                  style: TextStyle(fontSize: 14.0, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4.0),
                Text(
                  '${album.works.length} 歌曲, ${_formatTotalDuration(album.works)}',
                  style: TextStyle(fontSize: 13.0, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 缓存封面图片（避免滚动时重新加载）
class _CachedCoverImage extends StatelessWidget {
  const _CachedCoverImage({
    required this.coverFuture,
    required this.width,
    required this.height,
    required this.scheme,
  });

  final Future<ImageProvider?> coverFuture;
  final double width;
  final double height;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider?>(
      future: coverFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            width: width,
            height: height,
            color: scheme.surfaceContainerHighest,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
          );
        }
        if (snapshot.data == null) {
          return Container(
            width: width,
            height: height,
            color: scheme.surfaceContainerHighest,
            child: Icon(Symbols.album, size: 48.0, color: scheme.onSurfaceVariant),
          );
        }
        return RepaintBoundary(
          child: Image(
            image: snapshot.data!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: width,
              height: height,
              color: scheme.surfaceContainerHighest,
              child: Icon(Symbols.album, size: 48.0, color: scheme.onSurfaceVariant),
            ),
          ),
        );
      },
    );
  }
}

/// 操作按钮组件
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.0),
        splashColor: scheme.primary.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20.0, color: scheme.onSurface),
              const SizedBox(width: 8.0),
              Text(label, style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.w500, color: scheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 专辑歌曲项
class _AlbumAudioTile extends StatelessWidget {
  const _AlbumAudioTile({required this.audio, required this.audioIndex, required this.playlist});
  final Audio audio;
  final int audioIndex;
  final List<Audio> playlist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = PlayService.instance.playbackService.nowPlaying == audio;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          PlayService.instance.playbackService.play(audioIndex, playlist);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isPlaying ? scheme.primaryContainer.withValues(alpha: 0.3) : null,
          ),
          child: Row(
            children: [
              // 封面缩略图（使用缓存）
              ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: RepaintBoundary(
                  child: _CachedCoverImage(
                    coverFuture: audio.cover,
                    width: 48.0,
                    height: 48.0,
                    scheme: scheme,
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
                          child: Text(audio.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15.0, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                  color: isPlaying ? scheme.primary : scheme.onSurface)),
                        ),
                        if (audio.isCloudAudio)
                          Padding(padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(Symbols.cloud, size: 14.0, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 2.0),
                    Text('${audio.artist} - ${audio.album}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.0, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_formatDuration(audio.duration), style: TextStyle(fontSize: 13.0, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2.0),
                  Text(audio.fileSize != null ? _formatFileSize(audio.fileSize!) : '',
                      style: TextStyle(fontSize: 11.0, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
