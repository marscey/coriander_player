import 'dart:ui';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/page/glass_page_scaffold.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 歌单详情页 — iOS 26 Liquid Glass 风格（Mode 6: Fade Header）
///
/// 参考 AlbumDetailPageNew 与 ArtistDetailPageV3 实现：
/// - 沉浸式背景：歌单第一首歌封面（如有）blur + 渐变暗化
/// - GlassPageScaffold 提供导航栏 + 滚动驱动标题
/// - GlassCard 信息区 + GlassButtonGroup 播放按钮
/// - 下滑关闭手势
class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlist});

  final Playlist playlist;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage>
    with TickerProviderStateMixin {
  // ─── 状态 ───────────────────────────────────────────

  ImageProvider? _resolvedCover;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollNotifier = ValueNotifier(0.0);

  // 下滑关闭手势
  double _dragOffsetY = 0.0;
  AnimationController? _dismissAnimCtrl;

  // 排序与视图
  late List<SortMethodDesc<Audio>> sortMethods;
  late SortMethodDesc<Audio>? currSortMethod;
  late SortOrder currSortOrder;
  late ContentView currContentView;
  late List<Audio> sortedAudios;
  late MultiSelectController<Audio> multiSelectController;

  // ─── 生命周期 ───────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initSortAndView();
    _loadCover();

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
    _dismissAnimCtrl?.dispose();
    super.dispose();
  }

  void _onScroll() {
    _scrollNotifier.value = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
  }

  Future<void> _loadCover() async {
    final audios = widget.playlist.audios.values.toList();
    if (audios.isEmpty) return;
    // 使用第一首歌的封面作为歌单封面
    final cover = await audios.first.cover;
    if (mounted && cover != null) {
      setState(() => _resolvedCover = cover);
    }
  }

  void _initSortAndView() {
    sortMethods = [
      SortMethodDesc(
        icon: Symbols.title,
        name: "标题",
        method: (list, order) {
          switch (order) {
            case SortOrder.ascending:
              list.sort((a, b) => a.title.localeCompareTo(b.title));
            case SortOrder.decending:
              list.sort((a, b) => b.title.localeCompareTo(a.title));
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
            case SortOrder.decending:
              list.sort((a, b) => b.artist.localeCompareTo(a.artist));
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
            case SortOrder.decending:
              list.sort((a, b) => b.album.localeCompareTo(a.album));
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
            case SortOrder.decending:
              list.sort((a, b) => b.created.compareTo(a.created));
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
            case SortOrder.decending:
              list.sort((a, b) => b.modified.compareTo(a.modified));
          }
        },
      ),
    ];

    sortedAudios = List<Audio>.from(widget.playlist.audios.values);
    multiSelectController = MultiSelectController<Audio>();

    final pref = AppPreference.instance.playlistDetailPagePref;
    currSortMethod = sortMethods[pref.sortMethod];
    currSortOrder = pref.sortOrder;
    currContentView = pref.contentView;
    currSortMethod?.method(sortedAudios, currSortOrder);
  }

  void setSortMethod(SortMethodDesc<Audio> sortMethod) {
    setState(() {
      currSortMethod = sortMethod;
      AppPreference.instance.playlistDetailPagePref.sortMethod =
          sortMethods.indexOf(sortMethod);
    });
    currSortMethod?.method(sortedAudios, currSortOrder);
  }

  void setSortOrder(SortOrder sortOrder) {
    setState(() {
      currSortOrder = sortOrder;
      AppPreference.instance.playlistDetailPagePref.sortOrder = sortOrder;
    });
    currSortMethod?.method(sortedAudios, currSortOrder);
  }

  void setContentView(ContentView contentView) {
    setState(() {
      currContentView = contentView;
      AppPreference.instance.playlistDetailPagePref.contentView = contentView;
    });
  }

  // ─── 下滑关闭手势 ───────────────────────────────────

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_scrollController.hasClients) return;
    if (_scrollController.offset <= 0 && details.delta.dy > 0) {
      setState(() => _dragOffsetY += details.delta.dy);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffsetY > 150 ||
        (details.velocity.pixelsPerSecond.dy > 500 && _dragOffsetY > 0)) {
      context.pop();
    } else if (_dragOffsetY > 0) {
      _dismissAnimCtrl?.dispose();
      _dismissAnimCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
      )..addListener(() {
          setState(() {
            _dragOffsetY = _dragOffsetY * (1.0 - _dismissAnimCtrl!.value);
          });
        });
      _dismissAnimCtrl!.forward(from: 0.0);
    }
  }

  // ─── GlassMenu 菜单项 ───────────────────────────────

  bool get _isRecentBuiltin =>
      widget.playlist.isBuiltIn && widget.playlist.builtInId == 'recent';

  List<Widget> get _menuItems => [
        if (!_isRecentBuiltin) ...[
          GlassMenuItem(
            title: '添加歌曲',
            icon: const Icon(CupertinoIcons.plus, size: 20),
            onTap: () => _showAddAudioSheet(context),
          ),
          const GlassMenuDivider(),
        ],
        const GlassMenuLabel(title: '排序方式'),
        ...sortMethods.map((sm) => GlassMenuItem(
              title: sm.name,
              icon: Icon(sm.icon, size: 20),
              trailing: sm.name == currSortMethod?.name
                  ? const Icon(CupertinoIcons.checkmark_alt, size: 16)
                  : null,
              onTap: () => setSortMethod(sm),
            )),
        const GlassMenuDivider(),
        GlassMenuItem(
          title: currSortOrder == SortOrder.ascending ? '升序' : '降序',
          icon: Icon(
            currSortOrder == SortOrder.ascending
                ? Symbols.arrow_upward
                : Symbols.arrow_downward,
            size: 20,
          ),
          onTap: () => setSortOrder(
            currSortOrder == SortOrder.ascending
                ? SortOrder.decending
                : SortOrder.ascending,
          ),
        ),
        const GlassMenuDivider(),
        GlassMenuItem(
          title: currContentView == ContentView.list ? '列表视图' : '表格视图',
          icon: Icon(
            currContentView == ContentView.list ? Symbols.list : Symbols.table,
            size: 20,
          ),
          onTap: () => setContentView(
            currContentView == ContentView.list
                ? ContentView.table
                : ContentView.list,
          ),
        ),
      ];

  // ─── 构建 ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GlassPageScaffold(
      title: widget.playlist.name,
      showBackButton: true,
      menuItems: _menuItems,
      customBackground: _buildBackground(),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: _buildScrollContent(),
      ),
    );
  }

  // ─── ① 沉浸式背景 ──────────────────────────────────

  Widget _buildBackground() {
    final scheme = Theme.of(context).colorScheme;

    if (_resolvedCover != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          buildGlassBackground(scheme),
          // 歌单封面（取第一首歌）作为背景
          Positioned.fill(
            child: Image(
              image: _resolvedCover!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          // 渐变暗化层（与 Album V3 / Artist V3 一致）
          Positioned.fill(
            child: DecoratedBox(
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
          ),
          Positioned.fill(
            child: DecoratedBox(
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
          ),
          // 模糊滤镜（与 Album V3 / Artist V3 一致：sigma 140）
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 140, sigmaY: 140),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ],
      );
    }

    return buildGlassBackground(scheme);
  }

  // ─── ② 滚动内容 ────────────────────────────────────

  Widget _buildScrollContent() {
    final scheme = Theme.of(context).colorScheme;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const navBarHeight = 56.0;

    return Transform.translate(
      offset: Offset(0, _dragOffsetY),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // 顶部留白
          SliverToBoxAdapter(
            child: SizedBox(height: statusBarHeight + navBarHeight + 4.0),
          ),

          // 大标题（快速淡出：offset 0→70）
          SliverToBoxAdapter(
            child: ValueListenableBuilder<double>(
              valueListenable: _scrollNotifier,
              builder: (context, offset, _) {
                final progress = (offset / 70.0).clamp(0.0, 1.0);
                return Opacity(
                  opacity: 1.0 - progress,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
                    child: Text(
                      widget.playlist.name,
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

          // 歌单信息区（GlassCard）
          SliverToBoxAdapter(child: _buildPlaylistInfo(scheme)),

          // 播放按钮组（GlassButtonGroup，与 Album V3 一致）
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: SizedBox(
                width: double.infinity,
                child: GlassButtonGroup(
                  showDividers: true,
                  borderRadius: 22.0,
                  useOwnLayer: true,
                  settings: buttonGroupSettings,
                  children: [
                    Expanded(
                      child: GlassButton.custom(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          PlayService.instance.playbackService.shuffle.value =
                              false;
                          PlayService.instance.playbackService
                              .play(0, sortedAudios);
                        },
                        style: GlassButtonStyle.transparent,
                        height: 48,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.play_arrow_solid, size: 18),
                            SizedBox(width: 6),
                            Text('顺序播放',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: GlassButton.custom(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          PlayService.instance.playbackService.shuffle.value =
                              true;
                          PlayService.instance.playbackService
                              .play(0, sortedAudios);
                        },
                        style: GlassButtonStyle.transparent,
                        height: 48,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.shuffle, size: 18),
                            SizedBox(width: 6),
                            Text('随机播放',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 曲目列表
          switch (currContentView) {
            ContentView.list => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                sliver: SliverList.separated(
                  itemCount: sortedAudios.length,
                  separatorBuilder: (context, i) =>
                      const SizedBox(height: 6.0),
                  itemBuilder: (context, i) =>
                      multiSelectController.enableMultiSelectView
                          ? _buildMultiSelectTile(i, scheme)
                          : AudioTile(
                              audioIndex: i,
                              playlist: sortedAudios,
                              multiSelectController: multiSelectController,
                            ),
                ),
              ),
            ContentView.table => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 72.0,
                    crossAxisSpacing: 8.0,
                    mainAxisSpacing: 4.0,
                  ),
                  itemCount: sortedAudios.length,
                  itemBuilder: (context, i) =>
                      multiSelectController.enableMultiSelectView
                          ? _buildMultiSelectTile(i, scheme)
                          : AudioTile(
                              audioIndex: i,
                              playlist: sortedAudios,
                              multiSelectController: multiSelectController,
                            ),
                ),
              ),
          },

          // 底部间距（留给 Shell 的底部导航栏 + 播放条）
          const SliverPadding(padding: EdgeInsets.only(bottom: 140.0)),
        ],
      ),
    );
  }

  // ─── 添加歌曲到歌单 ────────────────────────────────

  void _showAddAudioSheet(BuildContext context) {
    final allAudios = AudioLibrary.instance.audioCollection.toList();
    final existingPaths = widget.playlist.audios.keys.toSet();
    final selected = <Audio>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.4, 0.8, 0.95],
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // 拖动条
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // 标题栏
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        '选择要添加的歌曲',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      if (selected.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            for (final audio in selected) {
                              PlaylistManager.instance
                                  .addAudioToPlaylist(widget.playlist, audio);
                            }
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('已添加 ${selected.length} 首歌曲'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Text('确认添加'),
                        )
                      else
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('取消'),
                        ),
                    ],
                  ),
                ),
                // 歌曲列表
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: allAudios.length,
                    itemBuilder: (context, i) {
                      final audio = allAudios[i];
                      final alreadyIn = existingPaths.contains(audio.path);
                      final isSelected = selected.contains(audio);

                      return ListTile(
                        leading: Checkbox(
                          value: isSelected || alreadyIn,
                          onChanged: alreadyIn
                              ? null
                              : (v) {
                                  if (v == true) {
                                    selected.add(audio);
                                  } else {
                                    selected.remove(audio);
                                  }
                                  setSheetState(() {});
                                },
                        ),
                        title: Text(
                          audio.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${audio.artist ?? ""} · ${audio.album ?? ""}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        enabled: !alreadyIn,
                        trailing: alreadyIn
                            ? Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                size: 20,
                                color:
                                    Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: alreadyIn
                            ? null
                            : () {
                                if (selected.contains(audio)) {
                                  selected.remove(audio);
                                } else {
                                  selected.add(audio);
                                }
                                setSheetState(() {});
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 歌单信息区（GlassCard，与 Album V3 风格一致）───

  Widget _buildPlaylistInfo(ColorScheme scheme) {
    final audiosList = widget.playlist.audios.values.toList();
    final showRemove = !_isRecentBuiltin;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GlassCard(
        padding: const EdgeInsets.all(16.0),
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        settings: navButtonSettings,
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 歌单封面（取第一首歌的封面）
                SizedBox(
                  width: 96.0,
                  height: 96.0,
                  child: FutureBuilder<ImageProvider?>(
                    future: audiosList.isEmpty
                        ? Future.value(null)
                        : audiosList.first.cover,
                    builder: (context, snapshot) {
                      final placeholder = Icon(
                        Symbols.queue_music,
                        size: 48.0,
                        color: scheme.onSurface,
                      );
                      return switch (snapshot.connectionState) {
                        ConnectionState.done => snapshot.data == null
                            ? Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12.0),
                                  color: scheme.surfaceContainerHighest,
                                ),
                                child: placeholder,
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12.0),
                                child: Image(
                                  image: snapshot.data!,
                                  width: 96.0,
                                  height: 96.0,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12.0),
                                      color: scheme.surfaceContainerHighest,
                                    ),
                                    child: placeholder,
                                  ),
                                ),
                              ),
                        _ => Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              color: scheme.onSurface,
                            ),
                          ),
                      };
                    },
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.playlist.name,
                        style: TextStyle(
                          fontSize: 15.0,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6.0),
                      Text(
                        _playlistTypeLabel,
                        style: TextStyle(
                          fontSize: 13.0,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        '${audiosList.length} 首乐曲',
                        style: TextStyle(
                          fontSize: 13.0,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (multiSelectController.enableMultiSelectView)
              Padding(
                padding: const EdgeInsets.only(top: 14.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showRemove)
                      Padding(
                        padding: const EdgeInsets.only(right: 10.0),
                        child: _buildMultiSelectAction(
                          icon: Symbols.delete_forever,
                          label: '移除选中',
                          scheme: scheme,
                          onTap: () {
                            PlaylistManager.instance.removeAudiosFromPlaylist(
                              widget.playlist,
                              multiSelectController.selected,
                            );
                            setState(() {});
                            multiSelectController
                                .useMultiSelectView(false);
                          },
                          isDestructive: true,
                        ),
                      ),
                    AddAllToPlaylist(
                        multiSelectController: multiSelectController),
                    const SizedBox(width: 10.0),
                    MultiSelectSelectOrClearAll(
                      multiSelectController: multiSelectController,
                      contentList: sortedAudios,
                    ),
                    const SizedBox(width: 10.0),
                    MultiSelectExit(multiSelectController: multiSelectController),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String get _playlistTypeLabel {
    if (widget.playlist.isBuiltIn) {
      switch (widget.playlist.builtInId) {
        case 'favorites':
          return '我的最爱 · 内置歌单';
        case 'recent':
          return '最近播放 · 动态更新';
        default:
          return '内置歌单';
      }
    }
    return '自建歌单';
  }

  Widget _buildMultiSelectAction({
    required IconData icon,
    required String label,
    required ColorScheme scheme,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final bgColor =
        isDestructive ? scheme.error : scheme.surfaceContainerHighest;
    final fgColor = isDestructive ? scheme.onError : scheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(
            color: scheme.onSurface.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fgColor),
            const SizedBox(width: 4.0),
            Text(
              label,
              style: TextStyle(fontSize: 13.0, color: fgColor),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 多选模式 AudioTile ─────────────────────────────

  Widget _buildMultiSelectTile(int i, ColorScheme scheme) {
    final audio = sortedAudios[i];
    final isSelected = multiSelectController.selected.contains(audio);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: InkWell(
        onTap: () {
          if (isSelected) {
            multiSelectController.unselect(audio);
          } else {
            multiSelectController.selectAtIndex(audio, i);
          }
        },
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.4),
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (val) {
                  if (val == true) {
                    multiSelectController.selectAtIndex(audio, i);
                  } else {
                    multiSelectController.unselect(audio);
                  }
                },
              ),
              const SizedBox(width: 4.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      audio.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      audio.subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.0,
                        color: scheme.onSurface.withValues(alpha: 0.7),
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
  }
}
