import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

// ─── InheritedWidget：共享滚动偏移量 + 动态淡入淡出阈值 ─

/// 让 GlassPageScaffold 的滚动偏移量和动态阈值被子树中的 GlassPageHeader 读取
class _ScrollOffsetScope extends InheritedWidget {
  const _ScrollOffsetScope({
    required this.scrollNotifier,
    required this.fadeStartNotifier,
    required this.fadeEndNotifier,
    required super.child,
  });

  final ValueNotifier<double> scrollNotifier;
  final ValueNotifier<double> fadeStartNotifier; // 大标题开始淡出 / 小标题开始淡入的 offset
  final ValueNotifier<double> fadeEndNotifier;   // 大标题完全消失 / 小标题完全显示的 offset

  static _ScrollOffsetScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_ScrollOffsetScope>();
    assert(
        scope != null, 'GlassPageHeader must be used inside GlassPageScaffold');
    return scope!;
  }

  @override
  bool updateShouldNotify(_ScrollOffsetScope oldWidget) =>
      scrollNotifier != oldWidget.scrollNotifier ||
      fadeStartNotifier != oldWidget.fadeStartNotifier ||
      fadeEndNotifier != oldWidget.fadeEndNotifier;
}

// ─── GlassPageScaffold ──────────────────────────────────

/// 统一的 Glass 版页面骨架
///
/// 导航栏采用 Stack 胶囊布局（与云服务文件预览页一致）：
/// - 左侧：返回按钮 / 多选模式下为退出多选按钮
/// - 中间：胶囊标题（滚动时从单行变两行）/ 多选模式下为选择栏
/// - 右侧：更多按钮（GlassMenu）
///
/// 通过 [_ScrollOffsetScope] 将滚动偏移量共享给子树中的 [GlassPageHeader]。
class GlassPageScaffold extends StatefulWidget {
  const GlassPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.menuItems = const [],
    required this.body,
    this.showBackButton = true,
    this.showCloseButton = false,
    this.showSettingsButton = false,
    this.actions = const [],
    this.customBackground,
    // 多选模式参数
    this.isSelectionMode = false,
    this.selectionCount = 0,
    this.isAllSelected = false,
    this.onExitSelection,
    this.onToggleSelectAll,
  });

  final String title;
  final String? subtitle;
  final List<Widget> menuItems;
  final Widget body;
  final bool showBackButton;
  final bool showCloseButton;
  final bool showSettingsButton;
  final List<Widget> actions;
  final Widget? customBackground;

  // 多选模式
  final bool isSelectionMode;
  final int selectionCount;
  final bool isAllSelected;
  final VoidCallback? onExitSelection;
  final VoidCallback? onToggleSelectAll;

  @override
  State<GlassPageScaffold> createState() => _GlassPageScaffoldState();
}

class _GlassPageScaffoldState extends State<GlassPageScaffold> {
  final _scrollNotifier = ValueNotifier<double>(0.0);
  final _fadeStartNotifier = ValueNotifier<double>(30.0);
  final _fadeEndNotifier = ValueNotifier<double>(90.0);

  @override
  void dispose() {
    _scrollNotifier.dispose();
    _fadeStartNotifier.dispose();
    _fadeEndNotifier.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _scrollNotifier.value = notification.metrics.pixels;
    }
    return false;
  }

  double _progress(double offset, double start, double end) {
    if (end <= start) return offset >= end ? 1.0 : 0.0;
    return ((offset - start) / (end - start)).clamp(0.0, 1.0);
  }

  double _navCollapseProgress(double scrollPixels) {
    const start = 10.0;
    const end = 80.0;
    if (scrollPixels <= start) return 0.0;
    if (scrollPixels >= end) return 1.0;
    final t = (scrollPixels - start) / (end - start);
    return t * t * (3 - 2 * t);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canPop = widget.showBackButton && context.canPop();

    // 构建完整菜单项：settingsButton 转为菜单项 + 用户 menuItems
    final allMenuItems = <Widget>[];
    if (widget.showSettingsButton && !widget.isSelectionMode) {
      allMenuItems.add(GlassMenuItem(
        title: '设置',
        icon: const Icon(Symbols.settings, size: 20),
        onTap: () => context.push(app_paths.SETTINGS_PAGE),
      ));
      if (widget.menuItems.isNotEmpty) {
        allMenuItems.add(
          GlassMenuDivider(color: scheme.outline.withValues(alpha: 0.5)),
        );
      }
    }
    allMenuItems.addAll(widget.menuItems);

    // 胶囊 settings：基于 navButtonSettings，glassColor 稍微更透
    final pillSettings = navButtonSettings.copyWith(
      glassColor: navButtonSettings.glassColor.withValues(alpha: 0.12),
    );

    final hasLeading = widget.isSelectionMode
        ? true
        : (widget.showCloseButton || (widget.showBackButton && canPop));

    final hasTrailing = allMenuItems.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.customBackground ?? buildGlassBackground(scheme),
          ),
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: _ScrollOffsetScope(
                scrollNotifier: _scrollNotifier,
                fadeStartNotifier: _fadeStartNotifier,
                fadeEndNotifier: _fadeEndNotifier,
                child: widget.body,
              ),
            ),
          ),
          // 悬浮胶囊导航栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _scrollNotifier,
              builder: (context, pixels, child) {
                return _buildFloatingPillNavBar(
                  scheme,
                  pillSettings,
                  allMenuItems,
                  hasLeading,
                  hasTrailing,
                  pixels,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 悬浮胶囊导航栏 — Stack 布局（与云服务文件预览页一致）
  Widget _buildFloatingPillNavBar(
    ColorScheme scheme,
    LiquidGlassSettings pillSettings,
    List<Widget> menuItems,
    bool hasLeading,
    bool hasTrailing,
    double scrollPixels,
  ) {
    final canPop = widget.showBackButton && context.canPop();
    final progress = _navCollapseProgress(scrollPixels);
    final topPadding = MediaQuery.of(context).padding.top;
    final pillHeight = 46 + (60 - 46) * progress;

    // 左侧 leading：多选模式为退出按钮，否则为返回/关闭按钮
    final Widget? leadingButton;
    if (widget.isSelectionMode) {
      leadingButton = GlassButton(
        icon: const Icon(Icons.close, size: 20),
        iconSize: 20,
        width: 44,
        height: 44,
        useOwnLayer: true,
        quality: navButtonQuality,
        onTap: widget.onExitSelection ?? () {},
      );
    } else if (widget.showCloseButton) {
      leadingButton = GlassButton(
        icon: const Icon(CupertinoIcons.xmark, size: 20),
        iconSize: 20,
        width: 44,
        height: 44,
        useOwnLayer: true,
        quality: navButtonQuality,
        onTap: () {
          if (context.canPop()) context.pop();
        },
      );
    } else if (widget.showBackButton && canPop) {
      leadingButton = GlassButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        iconSize: 18,
        width: 44,
        height: 44,
        useOwnLayer: true,
        quality: navButtonQuality,
        onTap: () {
          if (context.canPop()) context.pop();
        },
      );
    } else {
      leadingButton = null;
    }

    // 右侧 trailing：更多菜单
    final Widget? trailingButton = hasTrailing
        ? GlassMenu(
            menuWidth: 240,
            quality: navButtonQuality,
            triggerBuilder: (context, toggleMenu) => GlassButton(
              onTap: toggleMenu,
              icon: const Icon(Icons.more_horiz, size: 22),
              iconSize: 22,
              width: 44,
              height: 44,
              useOwnLayer: true,
              quality: navButtonQuality,
            ),
            items: menuItems,
          )
        : null;

    // 计算中间胶囊的左右偏移
    final leftOffset = hasLeading ? 52.0 : 6.0;
    final rightOffset = hasTrailing ? 52.0 : 6.0;

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + 6.0,
        left: 12.0,
        right: 12.0,
      ),
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            // 左侧：返回/关闭/退出多选按钮
            if (leadingButton != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(child: leadingButton),
              ),
            // 中间：胶囊
            Positioned(
              left: leftOffset,
              right: rightOffset,
              top: 0,
              bottom: 0,
              child: Center(
                child: GlassButton.custom(
                  onTap: () {},
                  shape: const LiquidRoundedSuperellipse(borderRadius: 26),
                  useOwnLayer: true,
                  quality: navButtonQuality,
                  settings: pillSettings,
                  height: pillHeight,
                  stretch: 0.0,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 4.0 + 3.0 * progress,
                    ),
                    height: pillHeight,
                    child: widget.isSelectionMode
                        ? _buildSelectionBarContent(scheme)
                        : _buildPillContent(
                            scheme, progress, widget.subtitle, widget.title),
                  ),
                ),
              ),
            ),
            // 右侧：更多按钮
            if (trailingButton != null)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(child: trailingButton),
              ),
          ],
        ),
      ),
    );
  }

  /// 多选模式下的胶囊内容
  Widget _buildSelectionBarContent(ColorScheme scheme) {
    final count = widget.selectionCount;
    final isAll = widget.isAllSelected;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            count == 0 ? '选择项目' : '已选 $count 项',
            style: TextStyle(
              fontSize: 15.0,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        GestureDetector(
          onTap: widget.onToggleSelectAll,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAll ? Symbols.deselect : Symbols.select_all,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  isAll ? '取消' : '全选',
                  style: TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 正常模式下的胶囊内容：单行副标题 → 两行标题+副标题
  Widget _buildPillContent(
      ColorScheme scheme, double progress, String? subtitle, String title) {
    // 如果没有副标题，只显示标题
    if (subtitle == null || subtitle.isEmpty) {
      return Center(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 15.0,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 初始状态：副标题（单行，progress=0时显示）
        Align(
          alignment: Alignment.center,
          child: Opacity(
            opacity: 1.0 - progress,
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 15.0,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // 顶部：标题（progress=1时淡入）
        Align(
          alignment: Alignment.topCenter,
          child: Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, (1 - progress) * 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        // 底部：副标题（progress=1时淡入）
        Align(
          alignment: Alignment.bottomCenter,
          child: Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, (1 - progress) * -8),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── ValueListenableBuilder3：同时监听三个 ValueNotifier ──

class ValueListenableBuilder3<A, B, C> extends StatelessWidget {
  const ValueListenableBuilder3({
    super.key,
    required this.scrollNotifier,
    required this.fadeStartNotifier,
    required this.fadeEndNotifier,
    required this.builder,
    this.child,
  });

  final ValueNotifier<A> scrollNotifier;
  final ValueNotifier<B> fadeStartNotifier;
  final ValueNotifier<C> fadeEndNotifier;
  final Widget Function(BuildContext context, A a, B b, C c, Widget? child)
      builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: scrollNotifier,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: fadeStartNotifier,
          builder: (context, b, _) {
            return ValueListenableBuilder<C>(
              valueListenable: fadeEndNotifier,
              builder: (context, c, _) => builder(context, a, b, c, child),
            );
          },
        );
      },
    );
  }
}

// ─── GlassPageHeader ────────────────────────────────────

/// 大标题渐隐组件（配合 GlassPageScaffold 使用）
class GlassPageHeader extends StatefulWidget {
  const GlassPageHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  State<GlassPageHeader> createState() => _GlassPageHeaderState();
}

class _GlassPageHeaderState extends State<GlassPageHeader> {
  final _titleAreaKey = GlobalKey();
  double? _measuredTitleHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measureTitleHeight);
  }

  @override
  void didUpdateWidget(covariant GlassPageHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.subtitle != widget.subtitle) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _measureTitleHeight(null));
    }
  }

  void _measureTitleHeight(Duration? _) {
    final context = _titleAreaKey.currentContext;
    if (context == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final height = box.size.height;
    if (height <= 0 || height == _measuredTitleHeight) return;

    setState(() {
      _measuredTitleHeight = height;
    });

    const gapBetweenNavBarAndTitle = 8.0;
    final fadeStart = gapBetweenNavBarAndTitle;
    final fadeEnd = gapBetweenNavBarAndTitle + height;

    final scope = _ScrollOffsetScope.of(this.context);
    scope.fadeStartNotifier.value = fadeStart;
    scope.fadeEndNotifier.value = fadeEnd;
  }

  double _progress(double offset, double start, double end) {
    if (end <= start) return offset >= end ? 1.0 : 0.0;
    return ((offset - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusBarH = MediaQuery.of(context).padding.top;
    const navBarH = 56.0;

    final scope = _ScrollOffsetScope.of(context);
    final scrollNotifier = scope.scrollNotifier;

    return ValueListenableBuilder3<double, double, double>(
      scrollNotifier: scrollNotifier,
      fadeStartNotifier: scope.fadeStartNotifier,
      fadeEndNotifier: scope.fadeEndNotifier,
      builder: (context, offset, fadeStart, fadeEnd, _) {
        final progress = _progress(offset, fadeStart, fadeEnd);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: statusBarH + navBarH + 4.0),
            Container(
              key: _titleAreaKey,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                    opacity: 1.0 - progress,
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 28.0,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  if (widget.subtitle != null)
                    Opacity(
                      opacity: 1.0 - progress,
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
                        child: Text(
                          widget.subtitle!,
                          style: TextStyle(
                            fontSize: 14.0,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
