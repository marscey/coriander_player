import 'dart:async';
import 'dart:ui';

import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/glass_theme/glass_controls.dart';
import 'package:coriander_player/glass_theme/app_dialog.dart';
import 'package:coriander_player/component/app_shell.dart';
import 'package:coriander_player/component/playlist_audio_item.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─── 最近搜索历史管理器 ──────────────────────────────────
class SearchHistoryManager {
  static const _kKey = 'search_history';
  static const _kMaxCount = 10;

  SearchHistoryManager._();
  static final SearchHistoryManager instance = SearchHistoryManager._();

  final history = ValueNotifier<List<String>>([]);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kKey) ?? [];
      history.value = list;
    } catch (_) {
      history.value = [];
    }
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final list = List<String>.from(history.value);
    list.remove(trimmed); // 去重
    list.insert(0, trimmed); // 最新的放在最前
    if (list.length > _kMaxCount) {
      list.removeRange(_kMaxCount, list.length);
    }
    history.value = list;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kKey, list);
    } catch (_) {}
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= history.value.length) return;
    final list = List<String>.from(history.value);
    list.removeAt(index);
    history.value = list;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kKey, list);
    } catch (_) {}
  }

  Future<void> clear() async {
    history.value = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    } catch (_) {}
  }
}

/// Glass 版 AppShell — 仅移动端
///
/// 严格照搬 artist_detail_page_v3.dart 的底部导航栏 + PlayBarPill 逻辑
class GlassAppShell extends StatefulWidget {
  const GlassAppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<GlassAppShell> createState() => _GlassAppShellState();
}

class _GlassAppShellState extends State<GlassAppShell> {
  // ─── 状态（完全照搬 Artist V3）──────────────────────────

  final FocusNode _searchFocusNode = FocusNode();
  bool _isMiniMode = false;
  bool _isSearching = false;
  bool _searchFieldFocused = false;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChange);
    SearchHistoryManager.instance.load();
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchFocusChange() {
    setState(() => _searchFieldFocused = _searchFocusNode.hasFocus);
  }

  /// 退出 mini 模式（完全照搬 Artist V3）
  void _dismissMiniMode() {
    setState(() {
      _isMiniMode = false;
      _isSearching = false;
      _searchFieldFocused = false;
    });
  }

  /// 监听子页面滚动 — 滚动超过 50px 进入 mini 模式，回到顶部退出
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      final mini = metrics.pixels > 50;
      if (mini != _isMiniMode) {
        setState(() => _isMiniMode = mini);
      }
    } else if (notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      if (metrics.pixels <= 0 && _isMiniMode) {
        setState(() => _isMiniMode = false);
      }
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSelectedTab();
    final path = GoRouterState.of(context).uri.path;
    final normalizedPath = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    miniPlayerVisibleNotifier.value = _shellRootPages.contains(normalizedPath);
  }

  void _updateSelectedTab() {
    final location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < _kTabPaths.length; i++) {
      if (location.startsWith(_kTabPaths[i])) {
        _selectedTab = i;
        return;
      }
    }
    _selectedTab = 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    // 检测是否在搜索结果页
    final location = GoRouterState.of(context).uri.toString();
    final isSearchResult = location.startsWith(app_paths.SEARCH_RESULT_PAGE);

    // ── 完全照搬 Artist V3 的精确尺寸 ──────────────
    final platform = Theme.of(context).platform;
    final isIOS =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final sysBottom = isIOS ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;

    const double expandedNavBarH = 40 + 2 * kBarPaddingV; // 72.0
    const double collapsedNavBarH = 60.0;
    const double pillGap = 14.0;

    final double activeNavBarH =
        _isSearching ? collapsedNavBarH : expandedNavBarH;
    final double aboveBarBottom = activeNavBarH + pillGap + sysBottom;
    final double miniBarBottom = kBarPaddingV + sysBottom;

    const double collapsedPillW = 50.0;
    final double miniPlayLeft = kBarPaddingH + collapsedPillW + 6.0;
    final double miniPlayRight = kBarPaddingH + collapsedPillW + 6.0;

    // 如果在搜索结果页：不显示 tab bar 和 mini player，也不提供底部搜索框
    // 搜索框由搜索结果页自己管理（避免嵌套路由的导航问题）
    if (isSearchResult) {
      return GlassScaffold(
        background: buildGlassBackground(scheme),
        settings: navButtonSettings(glassIsDark(context)),
        statusBarStyle: GlassStatusBarStyle.auto,
        edgeFade: false,
        edgeStyle: GlassScrollEdgeStyle.soft,
        bottomBarHeight: 0.0,
        resizeToAvoidBottomInset: false,
        bodyOverlays: const [],
        body: widget.navigationShell,
      );
    }

    // 正常 tab 页面：保留原有 GlassSearchableBottomBar + PlayBarPill
    return GlassScaffold(
      background: buildGlassBackground(scheme),
      settings: navButtonSettings(glassIsDark(context)),
      statusBarStyle: GlassStatusBarStyle.auto,
      edgeFade: false,
      edgeStyle: GlassScrollEdgeStyle.soft,
      bottomBarHeight: kBarHeight,
      resizeToAvoidBottomInset: false,

      // ── 底部玻璃导航栏（完全照搬 Artist V3）──────
      bottomBar: GlassSearchableBottomBar(
        isSearchActive: _isMiniMode || _isSearching,
        selectedIndex: _selectedTab,
        onTabSelected: (index) {
          if (index == _selectedTab && _isMiniMode) {
            _dismissMiniMode();
            return;
          }
          if (index < _kTabPaths.length) {
            // 切换 tab 时退出搜索模式
            if (_isSearching) {
              setState(() {
                _isSearching = false;
                _searchFieldFocused = false;
              });
            }
            // 底部导航 4 个 tab 与 StatefulShellBranch 的实际 index 映射
            // branch 0=音乐库, 1=歌单, 2=类别, 3=文件夹, 4=连接, 5=搜索, 6=设置
            // 底部导航 _kTabs 顺序：音乐库(0), 歌单(1), 类别(2), 连接(4)
            final branchIndex = _kTabBranchIndices[index];
            // Apple Music 风格 Tab 行为：
            // - 切换到不同 Tab：保留目标 Tab 的导航栈状态（goBranch 默认行为）
            // - 再次点击当前 Tab：回到该 Tab 的根页面（initialLocation: true）
            widget.navigationShell.goBranch(
              branchIndex,
              initialLocation:
                  branchIndex == widget.navigationShell.currentIndex,
            );
          }
        },
        barHeight: kBarHeight,
        searchBarHeight: 50.0,
        horizontalPadding: kBarPaddingH,
        verticalPadding: kBarPaddingV,
        spacing: kBarSpacing,
        selectedIconColor: scheme.primary,
        unselectedIconColor: scheme.onSurface.withValues(alpha: 0.9),
        indicatorColor: scheme.onSurface.withValues(alpha: 0.20),
        labelFontSize: 10,
        iconSize: 28,
        iconLabelSpacing: 0,
        quality: GlassQuality.premium,
        interactionBehavior: GlassInteractionBehavior.full,
        settings: tabBarSettings(isDark),
        searchConfig: GlassSearchBarConfig(
          focusNode: _searchFocusNode,
          autoFocusOnExpand: false,
          showsCancelButton: true,
          expandWhenActive: !_isMiniMode || _isSearching,
          hintText: '搜索歌曲、艺术家、专辑',
          onSearchToggle: (active) {
            if (active) {
              setState(() => _isSearching = true);
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
          onSubmitted: (query) {
            final trimmed = query.trim();
            if (trimmed.isEmpty) return;
            // 搜索框在 tab 页面：先退出搜索模式，再跳转到结果页
            setState(() {
              _isSearching = false;
              _searchFieldFocused = false;
            });
            // 记录历史 + 跳转
            SearchHistoryManager.instance.add(trimmed);
            context.push(
              app_paths.SEARCH_RESULT_PAGE,
              extra: UnionSearchResult.search(trimmed),
            );
          },
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

      // ── 播放条 Pill（完全照搬 Artist V3）──────────
      bodyOverlays: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          bottom: (_isMiniMode && !_isSearching)
              ? miniBarBottom
              : aboveBarBottom,
          left: (_isMiniMode && !_isSearching) ? miniPlayLeft : kBarPaddingH,
          right:
              (_isMiniMode && !_isSearching) ? miniPlayRight : kBarPaddingH,
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
                },
                onNavigateToNowPlaying: () {
                  if (_isMiniMode) _dismissMiniMode();
                  context.push(app_paths.NOW_PLAYING_PAGE);
                },
                isMiniMode: _isMiniMode && !_isSearching,
              ),
            ),
          ),
        ),
      ],

      body: GestureDetector(
        onTap: () {
          // 点击空白区域取消搜索框焦点
          if (_searchFieldFocused) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _isSearching
              ? _SearchBrowseView(
                  key: const ValueKey('search-browse'),
                  isFieldFocused: _searchFieldFocused,
                  onQueryTap: (query) {
                    // 点击历史搜索词：直接搜索
                    setState(() {
                      _isSearching = false;
                      _searchFieldFocused = false;
                    });
                    SearchHistoryManager.instance.add(query);
                    context.push(
                      app_paths.SEARCH_RESULT_PAGE,
                      extra: UnionSearchResult.search(query),
                    );
                  },
                  onClearHistory: () {
                    SearchHistoryManager.instance.clear();
                  },
                )
              : NotificationListener<ScrollNotification>(
                  key: const ValueKey('nav-shell'),
                  onNotification: _onScrollNotification,
                  child: widget.navigationShell,
                ),
        ),
      ),
    );
  }
}

// ─── 底部导航栏 Tab 定义 ─────────────────────────────────

const _kTabPaths = [
  app_paths.AUDIOS_PAGE,
  app_paths.PLAYLISTS_PAGE,
  app_paths.CATEGORIES_PAGE,
  app_paths.CLOUD_CONNECTIONS_PAGE,
];

/// 底部导航 4 个 tab 对应的 StatefulShellBranch 实际 index
/// entry.dart 中 branch 顺序：0=音乐库, 1=歌单, 2=类别, 3=文件夹, 4=连接, 5=搜索, 6=设置
/// 底部导航不含"文件夹/搜索/设置"，所以"连接"对应 branch 4
const _kTabBranchIndices = [0, 1, 2, 4];

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

/// 所有 Tab 一级页面路径（与 app_shell.dart 保持一致）
const List<String> _shellRootPages = [
  '/audios',
  '/categories',
  '/categories/artists',
  '/categories/albums',
  '/categories/genres',
  '/folders',
  '/cloud',
  '/playlists',
  '/playlists/detail',
  '/search',
];

// ─── 迷你播放条 Pill（完全照搬 Artist V3 的 _PlayBarPill）─────

class _PlayBarPill extends StatelessWidget {
  const _PlayBarPill({this.onTap, this.onNavigateToNowPlaying, this.isMiniMode = false});

  final VoidCallback? onTap;
  final VoidCallback? onNavigateToNowPlaying;
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
              height: kBarHeight,
              shape: const LiquidRoundedSuperellipse(borderRadius: kBarHeight / 2),
              settings: playBarPillSettings(isDark),
              child: _PlayBarContent(
                isMiniMode: isMiniMode,
                isPlaying: isPlaying,
                nowPlaying: nowPlaying,
                playlist: playlist,
                scheme: scheme,
                onNavigateToNowPlaying: onNavigateToNowPlaying,
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

/// 播放条内容 + 有色玻璃进度叠层
class _PlayBarContent extends StatefulWidget {
  const _PlayBarContent({
    required this.isMiniMode,
    required this.isPlaying,
    required this.nowPlaying,
    required this.playlist,
    required this.scheme,
    this.onNavigateToNowPlaying,
    required this.onOpenPlaylist,
    required this.onTogglePlay,
    required this.onSkip,
  });

  final bool isMiniMode;
  final bool isPlaying;
  final Audio? nowPlaying;
  final List<Audio> playlist;
  final ColorScheme scheme;
  final VoidCallback? onNavigateToNowPlaying;
  final VoidCallback onOpenPlaylist;
  final VoidCallback onTogglePlay;
  final VoidCallback onSkip;

  @override
  State<_PlayBarContent> createState() => _PlayBarContentState();
}

class _PlayBarContentState extends State<_PlayBarContent> {
  late StreamSubscription<double> _subscription;
  final _progress = ValueNotifier<double>(0.0);

  final playbackService = PlayService.instance.playbackService;

  // 歌词相关
  final lyricService = PlayService.instance.lyricService;
  String? _currentLyricText;
  StreamSubscription<int>? _lyricLineSub;

  @override
  void initState() {
    super.initState();
    _updateProgress();
    playbackService.addListener(_onPlaybackChanged);
    _subscription =
        PlayService.instance.playbackService.positionStream.listen((position) {
      _updateProgress();
    });
    // 监听歌词变化
    _lyricLineSub = lyricService.lyricLineStream.listen(_onLyricLineChanged);
  }

  void _onPlaybackChanged() {
    if (mounted) {
      _updateProgress();
      setState(() {});
    }
  }

  void _updateProgress() {
    final length = playbackService.displayLength;
    final position = playbackService.displayPosition;
    final newProgress = length > 0 ? (position / length).clamp(0.0, 1.0) : 0.0;
    _progress.value = newProgress;
  }

  @override
  void dispose() {
    playbackService.removeListener(_onPlaybackChanged);
    _subscription.cancel();
    _lyricLineSub?.cancel();
    super.dispose();
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

  /// 构建播放/暂停按钮，恢复播放加载期间显示 loading 并禁用点击
  Widget _buildPlayButton(ColorScheme scheme) {
    if (playbackService.isStartingFromRestored) {
      return SizedBox(
        width: 22,
        height: 22,
        child: AppSpinner(
          strokeWidth: 2.0,
          valueColor: AlwaysStoppedAnimation<Color>(scheme.onSurface),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onTogglePlay,
      child: Icon(
        widget.isPlaying
            ? CupertinoIcons.pause_fill
            : CupertinoIcons.play_arrow_solid,
        color: scheme.onSurface,
        size: 24,
      ),
    );
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
            if (progress > 0) _buildGlassTint(progress, tintAlpha),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // 封面 + 文字区域：点击跳转到正在播放页
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onNavigateToNowPlaying,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
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
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_currentLyricText != null && _currentLyricText!.isNotEmpty) ...[
                                  Text(
                                    _currentLyricText!,
                                    style: TextStyle(
                                      color: widget.scheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    widget.nowPlaying != null
                                        ? '${widget.nowPlaying!.title} - ${widget.nowPlaying!.artist}'
                                        : 'Enjoy music',
                                    style: TextStyle(
                                      color: widget.scheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ] else ...[
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
                                    widget.nowPlaying != null
                                        ? '${widget.nowPlaying!.artist}${widget.nowPlaying!.album.isNotEmpty ? ' - ${widget.nowPlaying!.album}' : ''}'
                                        : 'Enjoy music',
                                    style: TextStyle(
                                      color: widget.scheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.isMiniMode) ...[
                    _buildPlayButton(widget.scheme),
                  ] else ...[
                    GestureDetector(
                      onTap: widget.onOpenPlaylist,
                      child: Icon(
                        CupertinoIcons.music_note_list,
                        color: widget.scheme.onSurface.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildPlayButton(widget.scheme),
                    const SizedBox(width: 12),
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

  Widget _buildGlassTint(double progress, double tintAlpha) {
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

// ─── 搜索浏览视图（含最近搜索历史）───────────────────

class _SearchBrowseView extends StatelessWidget {
  const _SearchBrowseView({
    super.key,
    required this.isFieldFocused,
    required this.onQueryTap,
    required this.onClearHistory,
  });

  final bool isFieldFocused;
  final Function(String query) onQueryTap;
  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyboardH = MediaQuery.viewInsetsOf(context).bottom;

    return ValueListenableBuilder<List<String>>(
      valueListenable: SearchHistoryManager.instance.history,
      builder: (context, history, _) {
        final hasHistory = history.isNotEmpty;

        if (isFieldFocused && !hasHistory) {
          // 搜索框获得焦点但无历史：显示"无最近搜索"占位
          return SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboardH + 50),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.search,
                      size: 56,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "无最近搜索",
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "你的最近搜索将显示在这里",
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (isFieldFocused && hasHistory) {
          // 有历史 + 搜索框聚焦：显示历史搜索列表
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.paddingOf(context).top + 8),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        "最近搜索",
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onClearHistory,
                        child: Text(
                          "清除",
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, keyboardH + 200),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final query = history[index];
                      return _HistoryItem(
                        query: query,
                        onTap: () => onQueryTap(query),
                        onRemove: () =>
                            SearchHistoryManager.instance.removeAt(index),
                      );
                    },
                    childCount: history.length,
                  ),
                ),
              ),
            ],
          );
        }

        // 搜索栏展开但未聚焦：显示"搜索"标题 + 分类 + 最近搜索
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.paddingOf(context).top + 8),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 16, 20),
                child: Text(
                  "搜索",
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            // 最近搜索（有则显示）
            if (hasHistory) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        "最近搜索",
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onClearHistory,
                        child: Text(
                          "清除",
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final query = history[index];
                      return _HistoryItem(
                        query: query,
                        onTap: () => onQueryTap(query),
                        onRemove: () =>
                            SearchHistoryManager.instance.removeAt(index),
                      );
                    },
                    childCount: history.length,
                  ),
                ),
              ),
            ],
            // 搜索分类
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
                child: Text(
                  "搜索分类",
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 200),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.65,
                ),
                delegate: SliverChildListDelegate([
                  _SearchCategory(name: "歌曲", color: scheme.primary),
                  _SearchCategory(name: "艺术家", color: scheme.tertiary),
                  _SearchCategory(name: "专辑", color: scheme.secondary),
                  _SearchCategory(name: "流派", color: scheme.primaryContainer),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 单个历史搜索词条目
class _HistoryItem extends StatelessWidget {
  const _HistoryItem({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.clock,
                color: scheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  query,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onRemove,
                child: Icon(
                  CupertinoIcons.xmark,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchCategory extends StatelessWidget {
  const _SearchCategory({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: color,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(12),
        child: Text(
          name,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
