import 'dart:ui';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/glass_page_scaffold.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 专辑详情页 — iOS 26 Liquid Glass 风格（Mode 6: Fade Header）
///
/// 参考 ArtistDetailPageV3 实现：
/// - 沉浸式背景：专辑封面 blur + 渐变暗化
/// - GlassPageScaffold 提供导航栏 + 滚动驱动标题
/// - GlassCard 信息区 + GlassButtonGroup 播放按钮
/// - 下滑关闭手势
class AlbumDetailPageNew extends StatefulWidget {
  const AlbumDetailPageNew({super.key, required this.album});

  final Album album;

  @override
  State<AlbumDetailPageNew> createState() => _AlbumDetailPageNewState();
}

class _AlbumDetailPageNewState extends State<AlbumDetailPageNew>
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
    if (widget.album.works.isEmpty) return;
    final cover = await widget.album.works.first.cover;
    if (mounted && cover != null) {
      setState(() => _resolvedCover = cover);
    }
  }

  void _initSortAndView() {
    sortMethods = [
      SortMethodDesc(
        icon: Symbols.numbers,
        name: "音轨",
        method: (list, order) {
          switch (order) {
            case SortOrder.ascending:
              list.sort((a, b) => a.track.compareTo(b.track));
            case SortOrder.decending:
              list.sort((a, b) => b.track.compareTo(a.track));
          }
        },
      ),
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
    ];

    sortedAudios = List<Audio>.from(widget.album.works);
    multiSelectController = MultiSelectController<Audio>();

    final pref = AppPreference.instance.albumDetailPagePref;
    currSortMethod = sortMethods[pref.sortMethod];
    currSortOrder = pref.sortOrder;
    currContentView = pref.contentView;
    currSortMethod?.method(sortedAudios, currSortOrder);
  }

  void setSortMethod(SortMethodDesc<Audio> sortMethod) {
    setState(() {
      currSortMethod = sortMethod;
      AppPreference.instance.albumDetailPagePref.sortMethod =
          sortMethods.indexOf(sortMethod);
    });
    currSortMethod?.method(sortedAudios, currSortOrder);
  }

  void setSortOrder(SortOrder sortOrder) {
    setState(() {
      currSortOrder = sortOrder;
      AppPreference.instance.albumDetailPagePref.sortOrder = sortOrder;
    });
    currSortMethod?.method(sortedAudios, currSortOrder);
  }

  void setContentView(ContentView contentView) {
    setState(() {
      currContentView = contentView;
      AppPreference.instance.albumDetailPagePref.contentView = contentView;
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

  List<Widget> get _menuItems => [
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
      title: widget.album.name,
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
          // 专辑封面作为背景
          Positioned.fill(
            child: Image(
              image: _resolvedCover!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          // 渐变暗化层（与 Artist V3 一致）
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
          // 模糊滤镜（与 Artist V3 一致：sigma 140）
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
                    padding:
                        const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
                    child: Text(
                      widget.album.name,
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

          // 专辑信息区（GlassCard）
          SliverToBoxAdapter(child: _buildAlbumInfo(scheme)),

          // 播放按钮组（GlassButtonGroup，与 Artist V3 一致）
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16.0, vertical: 14.0),
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
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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

  // ─── 专辑信息区（GlassCard，与 Artist V3 风格一致）───

  Widget _buildAlbumInfo(ColorScheme scheme) {
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
                // 专辑封面
                SizedBox(
                  width: 96.0,
                  height: 96.0,
                  child: FutureBuilder<ImageProvider?>(
                    future: widget.album.works.isEmpty
                        ? Future.value(null)
                        : widget.album.works.first.cover,
                    builder: (context, snapshot) {
                      final placeholder = Icon(
                        Symbols.album,
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
                        widget.album.name,
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
                        '${widget.album.works.length} 首作品',
                        style: TextStyle(
                          fontSize: 13.0,
                          color: scheme.onSurface.withValues(alpha: 0.65),
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
                    AddAllToPlaylist(
                        multiSelectController: multiSelectController),
                    const SizedBox(width: 10.0),
                    MultiSelectSelectOrClearAll(
                      multiSelectController: multiSelectController,
                      contentList: sortedAudios,
                    ),
                    const SizedBox(width: 10.0),
                    MultiSelectExit(
                        multiSelectController: multiSelectController),
                  ],
                ),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
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
