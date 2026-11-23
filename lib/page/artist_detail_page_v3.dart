import 'dart:async';
import 'dart:ui';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/glass_theme/glass_controls.dart';
import 'package:coriander_player/glass_theme/app_dialog.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/component/playlist_audio_item.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 艺术家详情页 v3 — iOS 26 Liquid Glass 风格

// 顶层常量（严格按 Apple Music Demo）
const double _kPaddingH = 20.0;
const double _kPaddingV = 16.0;
const double _kBarH = 64.0; // GlassSearchableBottomBar barHeight
const double _kSpacing = 8.0; // Tab 间距

// ★ 底部导航栏图标（CupertinoIcons + Symbols 混用，与项目风格一致）
final _kTabs = [
  GlassBottomBarTab(
    label: '音乐库',
    icon: Icon(Symbols.library_music),
    activeIcon: Icon(Symbols.library_music_rounded),
  ),
  GlassBottomBarTab(
    label: '歌单',
    icon: Icon(CupertinoIcons.music_note_list),
    activeIcon: Icon(CupertinoIcons.music_note_list),
  ),
  GlassBottomBarTab(
    label: '类别',
    icon: Icon(CupertinoIcons.square_grid_2x2),
    activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
  ),
  GlassBottomBarTab(
    label: '连接',
    icon: Icon(CupertinoIcons.cloud),
    activeIcon: Icon(CupertinoIcons.cloud_fill),
  ),
];

///
/// Pattern 2 + Pattern 4 导航栏模式（nav_bar_patterns_demo）：
/// - GlassScaffold + GlassAppBar（内置隔离 + 按钮设置继承）
/// - topEdgeFade / bottomEdgeFade（GlassScrollEdgeEffect 5-stop 曲线自然淡出）
/// - 大标题在内容中淡出 + inline 标题在 AppBar 中淡入
/// - 不加手动 BackdropFilter — 交由 GlassScrollEdgeEffect 处理
class ArtistDetailPageV3 extends StatefulWidget {
  const ArtistDetailPageV3({super.key, required this.artist});

  final Artist artist;

  @override
  State<ArtistDetailPageV3> createState() => _ArtistDetailPageV3State();
}

class _ArtistDetailPageV3State extends State<ArtistDetailPageV3>
    with TickerProviderStateMixin {
  // ─── 状态 ───────────────────────────────────────────

  ImageProvider? _resolvedBackgroundPic;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollNotifier = ValueNotifier(0.0);

  // ★ 完全照搬 Apple Music Demo 的状态管理
  final FocusNode _searchFocusNode = FocusNode();
  bool _isMiniMode = false;
  bool _isSearching = false;
  bool _searchFieldFocused = false;
  final int _selectedTab = 0;

  // 下滑关闭手势
  double _dragOffsetY = 0.0;
  AnimationController? _dismissAnimCtrl;

  // 排序与视图
  late List<SortMethodDesc<Audio>> sortMethods;
  late SortMethodDesc<Audio>? currSortMethod;
  late SortOrder currSortOrder;
  late ContentView currContentView;
  late List<Audio> secondaryContent;
  late MultiSelectController<Audio> multiSelectController;

  // ─── 玻璃效果参数（参考 showcase/ShowcaseGlassTheme + 底部导航栏 + 迷你播放器）───

  // ─── 生命周期 ───────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onSearchFocusChange);
    _initSortAndView();
    _loadBackground();
  }

  void _onSearchFocusChange() {
    setState(() => _searchFieldFocused = _searchFocusNode.hasFocus);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _dismissAnimCtrl?.dispose();
    super.dispose();
  }

  void _onScroll() {
    _scrollNotifier.value = _scrollController.offset;
    final mini = _scrollController.hasClients && _scrollController.offset > 50;
    if (mini == _isMiniMode) return;
    setState(() => _isMiniMode = mini);
  }

  /// 退出 mini 模式（完全照搬 Apple Music Demo）
  void _dismissMiniMode() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutQuart,
      );
    }
    setState(() {
      _isMiniMode = false;
      _isSearching = false;
      _searchFieldFocused = false;
    });
  }

  Future<void> _loadBackground() async {
    final pic = await widget.artist.picture;
    if (mounted && pic != null) {
      setState(() => _resolvedBackgroundPic = pic);
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

    secondaryContent = List<Audio>.from(widget.artist.works);
    multiSelectController = MultiSelectController<Audio>();

    final pref = AppPreference.instance.artistDetailPagePref;
    currSortMethod = sortMethods[pref.sortMethod];
    currSortOrder = pref.sortOrder;
    currContentView = pref.contentView;
    currSortMethod?.method(secondaryContent, currSortOrder);
  }

  void setSortMethod(SortMethodDesc<Audio> sortMethod) {
    setState(() {
      currSortMethod = sortMethod;
      AppPreference.instance.artistDetailPagePref.sortMethod =
          sortMethods.indexOf(sortMethod);
    });
    currSortMethod?.method(secondaryContent, currSortOrder);
  }

  void setSortOrder(SortOrder sortOrder) {
    setState(() {
      currSortOrder = sortOrder;
      AppPreference.instance.artistDetailPagePref.sortOrder = sortOrder;
    });
    currSortMethod?.method(secondaryContent, currSortOrder);
  }

  void setContentView(ContentView contentView) {
    setState(() {
      currContentView = contentView;
      AppPreference.instance.artistDetailPagePref.contentView = contentView;
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

  // ─── 构建 ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // ── 完全照搬 Apple Music Demo 的精确尺寸 ──────────────
    final platform = Theme.of(context).platform;
    final isIOS =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final sysBottom = isIOS ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;

    const double expandedNavBarH = 40 + 2 * _kPaddingV; // 72.0
    const double collapsedNavBarH = 60.0;
    const double pillGap = 14.0;

    final double activeNavBarH =
        _isSearching ? collapsedNavBarH : expandedNavBarH;
    final double aboveBarBottom = activeNavBarH + pillGap + sysBottom;
    final double miniBarBottom = _kPaddingV + sysBottom;
    final double contentPad = aboveBarBottom + 50.0 + 8.0;

    const double collapsedPillW = 50.0;
    final double miniPlayLeft = _kPaddingH + collapsedPillW + 6.0;
    final double miniPlayRight = _kPaddingH + collapsedPillW + 6.0;

    return GlassScaffold(
      background: _buildBackground(),
      settings: navButtonSettings(glassIsDark(context)),
      statusBarStyle: GlassStatusBarStyle.auto,
      // 注意：不设 topEdgeFade/bottomEdgeFade。
      // edgeFade 的白色淡出在背景图未加载时会产生明显白色条带（见分析报告 v2）。
      // 如需边缘淡化效果，在 _buildBackground() 中手动添加暗色渐变。
      edgeStyle: GlassScrollEdgeStyle.soft,
      appBarHeight: 56.0,
      bottomBarHeight: _kBarH,

      // ── 顶部导航栏（Pattern 2: inline 标题滚动淡入）──
      appBar: GlassAppBar(
        preferredSize: const Size.fromHeight(56.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        buttonSettings: navButtonSettings(glassIsDark(context)),
        leading: GlassButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20),
          iconSize: 20,
          width: 44,
          height: 44,
          useOwnLayer: true,
          onTap: () => context.pop(),
        ),
        title: ValueListenableBuilder<double>(
          valueListenable: _scrollNotifier,
          builder: (context, offset, _) {
            final titleOpacity = ((offset - 50.0) / 70.0).clamp(0.0, 1.0);
            return Opacity(
              opacity: titleOpacity,
              child: Text(
                widget.artist.name,
                style: const TextStyle(
                  fontSize: 17.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
        actions: [
          GlassMenu(
            menuWidth: 220,
            quality: navButtonQuality,
            triggerBuilder: (context, toggleMenu) => GlassButton(
              onTap: toggleMenu,
              icon: Icon(Icons.more_horiz, size: 22),
              iconSize: 22,
              width: 44,
              height: 44,
              useOwnLayer: true,
            ),
            items: [
              const GlassMenuLabel(title: '排序方式'),
              ...sortMethods.map((sm) => GlassMenuItem(
                    title: sm.name,
                    icon: Icon(sm.icon, size: 20),
                    trailing: sm.name == currSortMethod?.name
                        ? Icon(CupertinoIcons.checkmark_alt, size: 16)
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
                title: currContentView == ContentView.list
                    ? '列表视图'
                    : '表格视图',
                icon: Icon(
                  currContentView == ContentView.list
                      ? Symbols.list
                      : Symbols.table,
                  size: 20,
                ),
                onTap: () => setContentView(
                  currContentView == ContentView.list
                      ? ContentView.table
                      : ContentView.list,
                ),
              ),
            ],
          ),
        ],
      ),

      // ── 底部玻璃导航栏 ──────────────────────────────
      bottomBar: GlassSearchableBottomBar(
        isSearchActive: _isMiniMode || _isSearching,
        selectedIndex: _selectedTab,
        onTabSelected: (index) {
          if (index == _selectedTab && _isMiniMode) {
            _dismissMiniMode();
            return;
          }
          const routes = [
            app_paths.AUDIOS_PAGE,
            app_paths.PLAYLISTS_PAGE,
            app_paths.CATEGORIES_PAGE,
            app_paths.CLOUD_CONNECTIONS_PAGE,
          ];
          if (index < routes.length) {
            context.go(routes[index]);
          }
        },
        barHeight: _kBarH,
        searchBarHeight: 50.0,
        horizontalPadding: _kPaddingH,
        verticalPadding: _kPaddingV,
        spacing: _kSpacing,
        selectedIconColor: scheme.primary,
        unselectedIconColor: scheme.onSurface.withValues(alpha: 0.9),
        indicatorColor: scheme.onSurface.withValues(alpha: 0.20),
        labelFontSize: 10,
        iconSize: 28,
        iconLabelSpacing: 0,
        quality: GlassQuality.premium,
        interactionBehavior: GlassInteractionBehavior.full,
        settings: tabBarSettings(glassIsDark(context)),
        searchConfig: GlassSearchBarConfig(
          focusNode: _searchFocusNode,
          autoFocusOnExpand: false,
          showsCancelButton: true,
          expandWhenActive: !_isMiniMode || _isSearching,
          hintText: '搜索',
          onSearchToggle: (active) {
            if (active) {
              context.go(app_paths.SEARCH_PAGE);
            } else {
              setState(() {
                _isSearching = false;
                _searchFieldFocused = false;
              });
              if (_isMiniMode) {
                _dismissMiniMode();
              }
            }
          },
          onSearchFocusChanged: (focused) =>
              setState(() => _searchFieldFocused = focused),
          searchIconColor: scheme.onSurface.withValues(alpha: 0.9),
          textInputAction: TextInputAction.search,
          collapsedLogoBuilder: (context) {
            final tab = _kTabs[_selectedTab];
            final iconColor = _isMiniMode && !_isSearching
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.9);
            return Center(
              child: IconTheme(
                data: IconThemeData(color: iconColor, size: 28),
                child: tab.activeIcon ?? tab.icon,
              ),
            );
          },
        ),
        tabs: _kTabs,
      ),

      // ── 播放条 Pill ─────────────────────────────────
      bodyOverlays: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          bottom: (_isMiniMode && !_isSearching)
              ? miniBarBottom
              : aboveBarBottom,
          left: (_isMiniMode && !_isSearching) ? miniPlayLeft : _kPaddingH,
          right:
              (_isMiniMode && !_isSearching) ? miniPlayRight : _kPaddingH,
          height: 50.0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            opacity: _searchFieldFocused ? 0.0 : 1.0,
            child: IgnorePointer(
              ignoring: _searchFieldFocused,
              child: _PlayBarPill(
                onTap: () {
                  if (_isMiniMode) _dismissMiniMode();
                  context.push(app_paths.NOW_PLAYING_PAGE);
                },
                isMiniMode: _isMiniMode && !_isSearching,
              ),
            ),
          ),
        ),
      ],

      // ── 滚动内容 ────────────────────────────────────
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: _buildScrollContent(bottomPad: contentPad),
      ),
    );
  }

  // ─── ① 沉浸式背景 ──────────────────────────────────

  Widget _buildBackground() {
    final scheme = Theme.of(context).colorScheme;

    // 有背景图片：在共享渐变背景基础上叠加图片 + 模糊
    if (_resolvedBackgroundPic != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // 1) 共享基础背景（确保无图片时也有正确视觉）
          buildGlassBackground(scheme),
          // 2) 图片层
          Positioned.fill(
            child: Image(
              image: _resolvedBackgroundPic!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          // 3) 多层渐变遮罩（与 Artist V3 原逻辑一致）
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
          // 4) 深度模糊
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 140, sigmaY: 140),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ],
      );
    }

    // 无背景图片：直接使用共享渐变背景
    return buildGlassBackground(scheme);
  }

  // ─── ② 滚动内容 ────────────────────────────────────

  Widget _buildScrollContent({required double bottomPad}) {
    final scheme = Theme.of(context).colorScheme;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const navBarHeight = 56.0;

    return Transform.translate(
      offset: Offset(0, _dragOffsetY),
      child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // 顶部留白（导航栏高度）
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
                        widget.artist.name,
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

            // 艺术家信息区
            SliverToBoxAdapter(child: _buildArtistInfo(scheme)),

            // 播放按钮组
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
                    settings: navButtonSettings(glassIsDark(context)),
                    children: [
                      Expanded(
                        child: GlassButton.custom(
                          onTap: () {
                            PlayService.instance.playbackService.shuffle.value =
                                false;
                            PlayService.instance.playbackService
                                .play(0, secondaryContent);
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
                            PlayService.instance.playbackService.shuffle.value =
                                true;
                            PlayService.instance.playbackService
                                .play(0, secondaryContent);
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
                  sliver: SliverFixedExtentList.builder(
                    itemExtent: 64,
                    itemCount: secondaryContent.length,
                    itemBuilder: (context, i) =>
                        multiSelectController.enableMultiSelectView
                            ? _buildMultiSelectTile(i, scheme)
                            : AudioTile(
                                audioIndex: i,
                                playlist: secondaryContent,
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
                    itemCount: secondaryContent.length,
                    itemBuilder: (context, i) =>
                        multiSelectController.enableMultiSelectView
                            ? _buildMultiSelectTile(i, scheme)
                            : AudioTile(
                                audioIndex: i,
                                playlist: secondaryContent,
                                multiSelectController: multiSelectController,
                              ),
                  ),
                ),
            },

            // 专辑列表标题
            if (widget.artist.albumsMap.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: Text(
                    "专辑",
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // 专辑列表
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              sliver: SliverList.separated(
                itemCount: widget.artist.albumsMap.values.length,
                separatorBuilder: (_, i) => const SizedBox(height: 6.0),
                itemBuilder: (context, i) {
                  final album = widget.artist.albumsMap.values.elementAt(i);
                  return _AlbumTile(
                    album: album,
                    scheme: scheme,
                    onTap: () => context.push(app_paths.ALBUM_DETAIL_PAGE_NEW,
                        extra: album),
                  );
                },
              ),
            ),

            // 底部间距（导航栏 + 播放条）
            SliverPadding(padding: EdgeInsets.only(bottom: bottomPad)),
          ],
        ),
      );
  }

  // ─── 艺术家信息区 ───────────────────────────────────

  Widget _buildArtistInfo(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GlassCard(
        padding: const EdgeInsets.all(16.0),
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        settings: navButtonSettings(glassIsDark(context)),
        child: Column(
          children: [
            // 头像 + 信息
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 96.0,
                  height: 96.0,
                  child: FutureBuilder(
                    future: widget.artist.picture,
                    builder: (context, snapshot) {
                      final placeholder = Icon(
                        Symbols.broken_image,
                        size: 48.0,
                        color: scheme.onSurface,
                      );
                      return switch (snapshot.connectionState) {
                        ConnectionState.done => snapshot.data == null
                            ? Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scheme.surfaceContainerHighest,
                                ),
                                child: placeholder,
                              )
                            : ClipOval(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.15),
                                      width: 2.0,
                                    ),
                                  ),
                                  child: Image(
                                    image: snapshot.data!,
                                    width: 96.0,
                                    height: 96.0,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => placeholder,
                                  ),
                                ),
                              ),
                        _ => Center(
                            child: AppSpinner(
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
                        "${widget.artist.works.length} 首作品",
                        style: TextStyle(
                          fontSize: 15.0,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6.0),
                      Text(
                        "${widget.artist.albumsMap.length} 张专辑",
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
            // 多选模式按钮组
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
                      contentList: secondaryContent,
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
    final audio = secondaryContent[i];
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
              AppCheckbox(
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

// ─── 迷你播放条 Pill（完全照搬 Apple Music Demo 的 _PlayBarPill）─────

class _PlayBarPill extends StatelessWidget {
  const _PlayBarPill({this.onTap, this.isMiniMode = false});

  final VoidCallback? onTap;
  final bool isMiniMode;

  void _showPlaylistBottomSheet(BuildContext context) {
    final playbackService = PlayService.instance.playbackService;
    showAdaptiveSheet(
      context: context,
      useRootNavigator: true,
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
                  LocatePlayingButton(
                    hasPlayingAudio: playbackService.nowPlaying != null,
                    onLocate: () {
                      final index = playbackService.playlistIndex;
                      if (!scrollController.hasClients) return;
                      final viewportHeight =
                          scrollController.position.viewportDimension;
                      final targetOffset =
                          index * 56.0 - (viewportHeight / 2) + 28.0;
                      final maxExtent =
                          scrollController.position.maxScrollExtent;
                      scrollController.animateTo(
                        targetOffset.clamp(0.0, maxExtent),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.fastOutSlowIn,
                      );
                    },
                  ),
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
                      return PlaylistAudioItem(
                        audio: item,
                        index: index,
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

  /// 默认封面占位符 — 渐变背景 + 音符图标
  static Widget _buildDefaultCover(ColorScheme scheme) {
    return Container(
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
        size: 20,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final playbackService = PlayService.instance.playbackService;

    return ValueListenableBuilder<List<Audio>>(
      valueListenable: playbackService.playlist,
      builder: (context, playlist, __) {
        final nowPlaying = playbackService.nowPlaying;

        return StreamBuilder<PlayerState>(
          stream: playbackService.playerStateStream,
          initialData: playbackService.playerState,
          builder: (context, stateSnapshot) {
            final isPlaying = stateSnapshot.data == PlayerState.playing;

            return GlassButton.custom(
              onTap: onTap ?? () {},
              quality: GlassQuality.premium,
              useOwnLayer: true,
              width: double.infinity,
              height: _kBarH,
              shape: const LiquidRoundedSuperellipse(borderRadius: _kBarH / 2),
              settings: playBarPillSettings(isDark),
              child: _PlayBarContent(
                isMiniMode: isMiniMode,
                isPlaying: isPlaying,
                nowPlaying: nowPlaying,
                playlist: playlist,
                scheme: scheme,
                onOpenPlaylist: () => _showPlaylistBottomSheet(context),
                onTogglePlay: () {
                  if (isPlaying) {
                    playbackService.pause();
                  } else {
                    playbackService.start();
                  }
                },
                onSkip: () {
                  final idx = playbackService.playlistIndex;
                  if (idx < playlist.length - 1) {
                    playbackService.play(idx + 1, playlist);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

// ─── 专辑列表项 ────────────────────────────────────────

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.album,
    required this.scheme,
    required this.onTap,
  });

  final Album album;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                album.name,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8.0),
            Icon(Symbols.chevron_right, size: 18.0, color: scheme.onSurface),
          ],
        ),
      ),
    );
  }
}

/// 播放条内容 + 有色玻璃进度叠层
///
/// 设计思路（与主界面 RectangleProgressIndicator 一致的方向，但放在玻璃内部）：
/// - Stack 底层：进度渐变色（模拟"有色玻璃"区域）
/// - Stack 顶层：封面 + 标题 + 按钮（原有内容）
/// - 进度色用主题 primary 色，带纵向渐变（上亮下暗）模拟光线折射
/// - 仅在进度 > 0 时绘制，避免零宽度闪烁
class _PlayBarContent extends StatefulWidget {
  const _PlayBarContent({
    required this.isMiniMode,
    required this.isPlaying,
    required this.nowPlaying,
    required this.playlist,
    required this.scheme,
    required this.onOpenPlaylist,
    required this.onTogglePlay,
    required this.onSkip,
  });

  final bool isMiniMode;
  final bool isPlaying;
  final Audio? nowPlaying;
  final List<Audio> playlist;
  final ColorScheme scheme;
  final VoidCallback onOpenPlaylist;
  final VoidCallback onTogglePlay;
  final VoidCallback onSkip;

  @override
  State<_PlayBarContent> createState() => _PlayBarContentState();
}

class _PlayBarContentState extends State<_PlayBarContent> {
  late StreamSubscription<double> _subscription;
  final _progress = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _subscription =
        PlayService.instance.playbackService.positionStream.listen((position) {
      final length = PlayService.instance.playbackService.length;
      _progress.value = length > 0 ? (position / length).clamp(0.0, 1.0) : 0.0;
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.scheme.brightness == Brightness.dark;
    final tintAlpha = isDark ? 0.22 : 0.18;

    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, progress, _) {
        return Stack(
          children: [
            // 底层：有色玻璃进度区域（模拟 iOS 有色玻璃）
            if (progress > 0) _buildGlassTint(progress, tintAlpha, isDark),
            // 顶层：内容（封面 + 标题 + 按钮）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // 专辑封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: FutureBuilder(
                        future: widget.nowPlaying?.cover,
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data != null) {
                            return Image(
                              image: snapshot.data!,
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _PlayBarPill._buildDefaultCover(
                                      widget.scheme),
                            );
                          }
                          return _PlayBarPill._buildDefaultCover(widget.scheme);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 标题 + 艺术家
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.nowPlaying?.title ?? 'Coriander Player',
                          style: TextStyle(
                            color: widget.scheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.nowPlaying?.artist ?? 'Enjoy music',
                          style: TextStyle(
                            color:
                                widget.scheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // mini mode：只显示播放/暂停按钮
                  if (widget.isMiniMode) ...[
                    GestureDetector(
                      onTap: widget.onTogglePlay,
                      child: Icon(
                        widget.isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_arrow_solid,
                        color: widget.scheme.onSurface,
                        size: 24,
                      ),
                    ),
                  ] else ...[
                    // 播放列表
                    GestureDetector(
                      onTap: widget.onOpenPlaylist,
                      child: Icon(
                        CupertinoIcons.music_note_list,
                        color: widget.scheme.onSurface.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 播放/暂停
                    GestureDetector(
                      onTap: widget.onTogglePlay,
                      child: Icon(
                        widget.isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_arrow_solid,
                        color: widget.scheme.onSurface,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 下一首
                    GestureDetector(
                      onTap: widget.onSkip,
                      child: Icon(
                        CupertinoIcons.forward_end_fill,
                        color: widget.scheme.onSurface.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGlassTint(double progress, double tintAlpha, bool isDark) {
    final baseColor = widget.scheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tintWidth = constraints.maxWidth * progress;
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: tintWidth,
            height: constraints.maxHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  baseColor.withValues(alpha: tintAlpha + 0.04),
                  baseColor.withValues(alpha: tintAlpha),
                  baseColor.withValues(alpha: tintAlpha - 0.02),
                ],
              ),
            ),
            // 在右侧添加一条极细的高光，模拟玻璃边缘
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 1.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      baseColor.withValues(alpha: 0.0),
                      baseColor.withValues(alpha: 0.25),
                      baseColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
