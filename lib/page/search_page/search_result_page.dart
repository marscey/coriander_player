import 'dart:ui';

import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/album_tile.dart';
import 'package:coriander_player/component/artist_tile.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─── 搜索历史管理器（与 glass_app_shell.dart 保持一致）───
class _SearchHistoryManager {
  static const _kKey = 'search_history';
  static const _kMaxCount = 10;

  _SearchHistoryManager._();
  static final _SearchHistoryManager instance = _SearchHistoryManager._();

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = List<String>.from(prefs.getStringList(_kKey) ?? []);
      list.remove(trimmed);
      list.insert(0, trimmed);
      if (list.length > _kMaxCount) {
        list.removeRange(_kMaxCount, list.length);
      }
      await prefs.setStringList(_kKey, list);
    } catch (_) {}
  }
}

class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key, required this.searchResult});

  final UnionSearchResult searchResult;

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  late final searchResult = ValueNotifier(widget.searchResult);
  late final searchBarController = TextEditingController(
    text: widget.searchResult.query,
  );

  @override
  void didUpdateWidget(covariant SearchResultPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchResult.query != oldWidget.searchResult.query) {
      searchResult.value = widget.searchResult;
      searchBarController.text = widget.searchResult.query;
    }
  }

  @override
  void dispose() {
    searchBarController.dispose();
    super.dispose();
  }

  /// 在本页内执行搜索，直接更新本地状态，不走 GoRouter 导航
  void _performLocalSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _SearchHistoryManager.instance.add(trimmed);

    if (searchBarController.text != trimmed) {
      searchBarController.text = trimmed;
    }
    searchResult.value = UnionSearchResult.search(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final useGlass = AppPreference.instance.glassActive &&
        (Theme.of(context).platform == TargetPlatform.iOS ||
            Theme.of(context).platform == TargetPlatform.android);

    if (useGlass) {
      return _GlassSearchResultPage(
        searchResult: searchResult,
        searchBarController: searchBarController,
        onSubmitted: _performLocalSearch,
      );
    }
    return _MaterialSearchResultPage(
      searchResult: searchResult,
      searchBarController: searchBarController,
    );
  }
}

// ────────────────────────────────────────────────────
// Material 风格（桌面）
// ────────────────────────────────────────────────────

class _MaterialSearchResultPage extends StatelessWidget {
  const _MaterialSearchResultPage({
    required this.searchResult,
    required this.searchBarController,
  });

  final ValueNotifier<UnionSearchResult> searchResult;
  final TextEditingController searchBarController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: DefaultTabController(
          length: 4,
          child: Column(
            children: [
              Row(
                children: [
                  if (context.canPop())
                    IconButton(
                      tooltip: "返回",
                      onPressed: () => context.pop(),
                      icon: const Icon(Symbols.arrow_back),
                    ),
                  Expanded(
                    child: TextField(
                      controller: searchBarController,
                      decoration: InputDecoration(
                        suffixIcon: const Padding(
                          padding: EdgeInsets.only(right: 12.0),
                          child: Icon(Symbols.search),
                        ),
                        hintText: "搜索歌曲、艺术家、专辑",
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (String query) {
                        searchResult.value = UnionSearchResult.search(query);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              Material(
                type: MaterialType.transparency,
                child: TabBar(
                  tabs: _SearchResultFilter.values
                      .map((filter) => Tab(text: filter.name))
                      .toList(),
                ),
              ),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: ValueListenableBuilder(
                    valueListenable: searchResult,
                    builder: (context, value, _) => TabBarView(
                      children: _buildContent(value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(UnionSearchResult result) => [
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.all,
          useGlass: false,
        ),
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.music,
          useGlass: false,
        ),
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.artist,
          useGlass: false,
        ),
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.album,
          useGlass: false,
        ),
      ];
}

// ────────────────────────────────────────────────────
// Glass 风格（移动端）
// ────────────────────────────────────────────────────

class _GlassSearchResultPage extends StatelessWidget {
  const _GlassSearchResultPage({
    required this.searchResult,
    required this.searchBarController,
    required this.onSubmitted,
  });

  final ValueNotifier<UnionSearchResult> searchResult;
  final TextEditingController searchBarController;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final sysBottom =
        (Theme.of(context).platform == TargetPlatform.iOS ||
                Theme.of(context).platform == TargetPlatform.macOS)
            ? 0.0
            : MediaQuery.viewPaddingOf(context).bottom;
    const searchBarHeight = 50.0;
    final searchBarTotal = searchBarHeight + sysBottom + 12.0;

    return ValueListenableBuilder<UnionSearchResult>(
      valueListenable: searchResult,
      builder: (context, result, _) {
        final totalCount =
            result.audios.length + result.artists.length + result.album.length;

        return GlassScaffold(
          backgroundColor: Colors.transparent,
          edgeFade: false,
          appBarHeight: 56.0,
          bottomBarHeight: searchBarTotal,
          resizeToAvoidBottomInset: true,
          appBar: GlassAppBar(
            buttonSettings: navButtonSettings,
            preferredSize: const Size.fromHeight(56.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            leading: GlassButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              iconSize: 20,
              width: 44,
              height: 44,
              useOwnLayer: true,
              onTap: () {
                if (GoRouter.of(context).canPop()) {
                  context.pop();
                }
              },
            ),
            title: Text(
              result.query,
              style: const TextStyle(
                fontSize: 17.0,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          bottomBar: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, sysBottom + 12),
            child: _BottomSearchBar(
              controller: searchBarController,
              onSubmitted: onSubmitted,
              isDark: isDark,
            ),
          ),
          body: _SearchResultScrollContent(
            result: result,
            totalCount: totalCount,
            scheme: scheme,
          ),
        );
      },
    );
  }
}

/// 搜索结果页底部的搜索输入框：与 GlassSearchableBottomBar 的 SearchPill 完全一致
class _BottomSearchBar extends StatelessWidget {
  const _BottomSearchBar({
    required this.controller,
    required this.onSubmitted,
    required this.isDark,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = scheme.onSurfaceVariant;
    final textColor = scheme.onSurface;

    return GlassContainer(
      settings: LiquidGlassSettings(
        glassColor:
            isDark ? const Color(0xCC1C1C1E) : const Color(0xCCF2F2F7),
        thickness: 30,
        blur: 3,
        lightIntensity: 0.6,
        chromaticAberration: 0.3,
        refractiveIndex: 1.59,
        saturation: 0.7,
        ambientStrength: 1,
        lightAngle: kAppleLightAngle,
      ),
      shape: const LiquidRoundedSuperellipse(borderRadius: 32.0),
      width: double.infinity,
      height: 50,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final hasText = value.text.isNotEmpty;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.search, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoTextField(
                    controller: controller,
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    onSubmitted: onSubmitted,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                    placeholder: '搜索歌曲、艺术家、专辑',
                    placeholderStyle: TextStyle(
                      color: iconColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                    padding: EdgeInsets.zero,
                    decoration: null,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: hasText
                      ? GestureDetector(
                          key: const ValueKey('clear'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => controller.clear(),
                          child: Icon(
                            CupertinoIcons.clear_circled_solid,
                            color: iconColor,
                            size: 18,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 搜索结果页的滚动内容：大标题 + 小标题 → TabBar → TabBarView
class _SearchResultScrollContent extends StatelessWidget {
  const _SearchResultScrollContent({
    required this.result,
    required this.totalCount,
    required this.scheme,
  });

  final UnionSearchResult result;
  final int totalCount;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final statusBarH = MediaQuery.paddingOf(context).top;
    const appBarH = 56.0;
    // 内容从 appBar 下方 12px 处开始，避免被导航栏遮挡
    final topPadding = statusBarH + appBarH + 12;

    return DefaultTabController(
      length: 4,
      child: NestedScrollView(
        floatHeaderSlivers: false,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // 大标题 + 小标题（从导航栏下方开始，有 padding）
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, topPadding, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "“${result.query}”",
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "共 $totalCount 条结果",
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // TabBar：sticky 固定
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(scheme: scheme),
          ),
        ],
        body: TabBarView(
          children: [
            _SearchResultPageBody(
              result: result,
              filter: _SearchResultFilter.all,
              useGlass: true,
            ),
            _SearchResultPageBody(
              result: result,
              filter: _SearchResultFilter.music,
              useGlass: true,
            ),
            _SearchResultPageBody(
              result: result,
              filter: _SearchResultFilter.artist,
              useGlass: true,
            ),
            _SearchResultPageBody(
              result: result,
              filter: _SearchResultFilter.album,
              useGlass: true,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sticky TabBar：固定在顶部，滚动时保持可见 ─
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  _StickyTabBarDelegate({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // 滚动后，给 TabBar 加一个柔和的背景和底部边框，与导航栏衔接
    final scrolled = shrinkOffset > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scrolled
            ? scheme.surface.withValues(alpha: 0.65)
            : Colors.transparent,
        border: scrolled
            ? Border(
                bottom: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              )
            : null,
      ),
      // TabBar 需要 Material ancestor 才能正确处理点击动画
      child: Material(
        type: MaterialType.transparency,
        child: TabBar(
          labelColor: scheme.onSurface,
          unselectedLabelColor: scheme.onSurfaceVariant,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          indicator: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(vertical: 2),
          tabs: _SearchResultFilter.values
              .map((filter) => Tab(text: filter.name))
              .toList(),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 48.0;

  @override
  double get minExtent => 48.0;

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) =>
      scheme != oldDelegate.scheme;
}

// ────────────────────────────────────────────────────
// 过滤类型
// ────────────────────────────────────────────────────

enum _SearchResultFilter {
  all("所有"),
  music("音乐"),
  artist("艺术家"),
  album("专辑");

  const _SearchResultFilter(this.name);
  final String name;
}

// ────────────────────────────────────────────────────
// 结果页 Body
// ────────────────────────────────────────────────────

class _SearchResultPageBody extends StatelessWidget {
  const _SearchResultPageBody({
    required this.result,
    required this.filter,
    required this.useGlass,
  });

  final UnionSearchResult result;
  final _SearchResultFilter filter;
  final bool useGlass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    List<Widget> slivers = [];
    switch (filter) {
      case _SearchResultFilter.all:
        if (result.audios.isNotEmpty) {
          slivers.addAll(_buildMusicSection(scheme));
        }
        if (result.artists.isNotEmpty) {
          slivers.addAll(_buildArtistSection(scheme));
        }
        if (result.album.isNotEmpty) {
          slivers.addAll(_buildAlbumSection(scheme));
        }
        break;
      case _SearchResultFilter.music:
        slivers.addAll(_buildMusicSection(scheme));
        break;
      case _SearchResultFilter.artist:
        slivers.addAll(_buildArtistSection(scheme));
        break;
      case _SearchResultFilter.album:
        slivers.addAll(_buildAlbumSection(scheme));
        break;
    }
    if (slivers.isEmpty) {
      slivers.add(_buildEmptyState(scheme));
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 200)));
    return CustomScrollView(slivers: slivers);
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.search_off_rounded,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              "没有找到相关结果",
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSectionHeader(
      ColorScheme scheme, String title, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          "$title（$count）",
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMusicSection(ColorScheme scheme) {
    return [
      _buildSectionHeader(scheme, "歌曲", result.audios.length),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: result.audios.length,
          itemBuilder: (context, i) {
            final item = result.audios[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AudioTile(
                audioIndex: 0,
                playlist: [item],
                action: IconButton(
                  onPressed: () {
                    context.push(app_paths.AUDIOS_PAGE, extra: item);
                  },
                  icon: Icon(
                    Symbols.location_on,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildArtistSection(ColorScheme scheme) {
    return [
      _buildSectionHeader(scheme, "艺术家", result.artists.length),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: result.artists.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ArtistTile(artist: result.artists[i]),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAlbumSection(ColorScheme scheme) {
    return [
      _buildSectionHeader(scheme, "专辑", result.album.length),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: result.album.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AlbumTile(album: result.album[i]),
          ),
        ),
      ),
    ];
  }
}
