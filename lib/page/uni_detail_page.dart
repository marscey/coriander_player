import 'dart:ui';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// `ArtistDetailPage`, `AlbumDetailPage` 页面的主要组件。
///
/// `P`: 第一内容；`S`: 第二内容（主要）；`T`: 第三内容
///
/// 例如：对于 `ArtistDetailPage` 来说，
/// `P` 是 `Artist` 类，`S` 是 `Audio` 类，`T` 是 `Album` 类
///
/// `multiSelectController` 可以使页面进入多选状态。如果它不为空，则 `multiSelectViewActions` 也不可为空
class UniDetailPage<P, S, T> extends StatefulWidget {
  const UniDetailPage({
    super.key,
    required this.pref,
    required this.primaryContent,
    required this.primaryPic,
    required this.backgroundPic,
    required this.picShape,
    required this.title,
    required this.subtitle,
    required this.secondaryContent,
    required this.secondaryContentBuilder,
    required this.tertiaryContentTitle,
    required this.tertiaryContent,
    required this.tertiaryContentBuilder,
    required this.enableShufflePlay,
    required this.enableSortMethod,
    required this.enableSortOrder,
    required this.enableSecondaryContentViewSwitch,
    this.sortMethods,
    this.multiSelectController,
    this.multiSelectViewActions,
  });

  final PagePreference pref;

  final P primaryContent;

  /// 用来展示内容图片，较高清
  final Future<ImageProvider?> primaryPic;

  /// 当作毛玻璃的背景，较模糊
  final Future<ImageProvider?> backgroundPic;

  final PicShape picShape;

  final String title;
  final String subtitle;

  final List<S> secondaryContent;
  final ContentBuilder<S> secondaryContentBuilder;

  final String tertiaryContentTitle;
  final List<T> tertiaryContent;
  final ContentBuilder<T> tertiaryContentBuilder;

  final bool enableShufflePlay;
  final bool enableSortMethod;
  final bool enableSortOrder;
  final bool enableSecondaryContentViewSwitch;

  final List<SortMethodDesc<S>>? sortMethods;

  final MultiSelectController<S>? multiSelectController;
  final List<Widget>? multiSelectViewActions;

  @override
  State<UniDetailPage<P, S, T>> createState() => _UniDetailPageState<P, S, T>();
}

class _UniDetailPageState<P, S, T> extends State<UniDetailPage<P, S, T>> {
  late SortMethodDesc<S>? currSortMethod =
      widget.sortMethods?[widget.pref.sortMethod];
  late SortOrder currSortOrder = widget.pref.sortOrder;
  late ContentView currContentView = widget.pref.contentView;

  /// 已解析的全屏沉浸式背景图
  ImageProvider? _resolvedBackgroundPic;

  /// 保存进入页面前的状态栏样式，用于 dispose 时恢复
  late Brightness _savedIconBrightness;
  late Brightness _savedStatusBarBrightness;
  bool _statusBarInitialized = false;

  /// 滚动控制器：用于大标题淡出 + 顶栏标题淡入
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollNotifier = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    currSortMethod?.method(widget.secondaryContent, currSortOrder);
    _scrollController.addListener(_onScroll);

    // 解析背景图 Future，完成后触发重建以显示沉浸式背景
    widget.backgroundPic.then((pic) {
      if (mounted && pic != null) {
        setState(() {
          _resolvedBackgroundPic = pic;
        });
      }
    });
  }

  /// 上一次触发 setState 时的状态栏区域标识（true=顶部模糊区）
  bool _lastWasTopArea = true;

  void _onScroll() {
    _scrollNotifier.value = _scrollController.offset;
    // 仅在跨越阈值时触发 build 重建以更新 AnnotatedRegion 状态栏样式
    final isTopAreaNow = _scrollController.offset < 100.0;
    if (isTopAreaNow != _lastWasTopArea) {
      _lastWasTopArea = isTopAreaNow;
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Theme.of(context) 只能在这里调用（initState 之后）
    if (!_statusBarInitialized) {
      _statusBarInitialized = true;
      final brightness = Theme.of(context).brightness;
      _savedIconBrightness =
          brightness == Brightness.dark ? Brightness.light : Brightness.dark;
      _savedStatusBarBrightness = brightness;
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: brightness,
      ));
    }
  }

  @override
  void didUpdateWidget(covariant UniDetailPage<P, S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    currSortMethod?.method(widget.secondaryContent, currSortOrder);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollNotifier.dispose();
    // 恢复进入页面前的状态栏样式
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _savedIconBrightness,
      statusBarBrightness: _savedStatusBarBrightness,
    ));
    super.dispose();
  }

  void setSortMethod(SortMethodDesc<S> sortMethod) {
    setState(() {
      currSortMethod = sortMethod;
      widget.pref.sortMethod = widget.sortMethods?.indexOf(sortMethod) ?? 0;
      currSortMethod?.method(widget.secondaryContent, currSortOrder);
    });
  }

  void setSortOrder(SortOrder sortOrder) {
    setState(() {
      currSortOrder = sortOrder;
      widget.pref.sortOrder = sortOrder;
      currSortMethod?.method(widget.secondaryContent, currSortOrder);
    });
  }

  void setContentView(ContentView contentView) {
    setState(() {
      currContentView = contentView;
      widget.pref.contentView = contentView;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 将操作按钮分为两组：
    //   playActions: 随机播放/顺序播放（放置在封面正下方）
    //   utilityActions: 排序、视图切换等（放置在歌曲列表上方）
    final List<Widget> playActions = [];
    final List<Widget> utilityActions = [];
    if (widget.enableShufflePlay) {
      playActions.add(SequentialPlay<S>(contentList: widget.secondaryContent));
      playActions.add(ShufflePlay<S>(contentList: widget.secondaryContent));
    }
    if (widget.enableSortMethod) {
      utilityActions.add(SortMethodComboBox<S>(
        sortMethods: widget.sortMethods!,
        contentList: widget.secondaryContent,
        currSortMethod: currSortMethod!,
        setSortMethod: setSortMethod,
      ));
    }
    if (widget.enableSortOrder) {
      utilityActions.add(SortOrderSwitch<S>(
        sortOrder: currSortOrder,
        setSortOrder: setSortOrder,
      ));
    }
    if (widget.enableSecondaryContentViewSwitch) {
      utilityActions.add(ContentViewSwitch<S>(
        contentView: currContentView,
        setContentView: setContentView,
      ));
    }

    // 滚动联动状态栏：顶部模糊区域用浅色图标，滚动后 surface 区域用深色图标
    final scrollOffset = _scrollNotifier.value;
    final isTopArea = scrollOffset < 100.0;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _resolvedBackgroundPic != null && isTopArea
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: _resolvedBackgroundPic != null && isTopArea
          ? Brightness.dark
          : Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: widget.multiSelectController == null
          ? result(null, playActions, utilityActions, scheme)
          : ListenableBuilder(
              listenable: widget.multiSelectController!,
              builder: (context, _) => result(
                widget.multiSelectController!,
                playActions,
                utilityActions,
                scheme,
              ),
            ),
    );
  }

  Widget result(
      MultiSelectController<S>? multiSelectController,
      List<Widget> playActions,
      List<Widget> utilityActions,
      ColorScheme scheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const topBarHeight = 56.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 底色兜底：使用 secondaryContainer 而非 surface，
        // 避免浅色主题下首帧（背景图未加载）时状态栏区域过亮造成闪烁
        ColoredBox(color: scheme.secondaryContainer),
        // 沉浸式背景层（参照正在播放页风格）
        if (_resolvedBackgroundPic != null) ...[
          // 全屏封面图
          Image(
            image: _resolvedBackgroundPic!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          // 主题渐变遮罩：secondaryContainer → surface
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.secondaryContainer.withValues(alpha: 0.5),
                  scheme.secondaryContainer.withValues(alpha: 0.85),
                  scheme.surface.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // 暗色渐变遮罩
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.05),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
          // 高斯模糊（sigma=120）
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ],

        // 滚动内容（移除顶部安全区内边距，内容延伸到状态栏后）
        Positioned.fill(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // 顶部留白：为状态栏 + 自定义顶栏预留空间
                SliverToBoxAdapter(
                  child: SizedBox(height: statusBarHeight + topBarHeight + 4.0),
                ),

                // 大标题（滚动时淡出）
                SliverToBoxAdapter(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scrollNotifier,
                    builder: (context, offset, _) {
                      final opacity = (1.0 - offset / 80.0).clamp(0.0, 1.0);
                      return Opacity(
                        opacity: opacity,
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: isMobile ? 28.0 : 32.0,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 专辑信息区（封面 + 详情 + 播放按钮组）
                SliverToBoxAdapter(
                  child: _AlbumInfoSection(
                    pic: widget.primaryPic,
                    backgroundPic: widget.backgroundPic,
                    picShape: widget.picShape,
                    subtitle: widget.subtitle,
                    playActions: playActions,
                    multiSelectController: multiSelectController,
                    multiSelectViewActions: widget.multiSelectViewActions,
                    isMobile: isMobile,
                  ),
                ),

                // 工具栏（排序/视图切换等），仅在有工具按钮时显示
                if (utilityActions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: utilityActions,
                      ),
                    ),
                  ),

                // 歌曲列表（左右边距与专辑封面对齐：12px）
                switch (currContentView) {
                  ContentView.list => SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      sliver: SliverFixedExtentList.builder(
                        itemExtent: isMobile ? 64 : 72,
                        itemCount: widget.secondaryContent.length,
                        itemBuilder: (context, i) =>
                            widget.secondaryContentBuilder(
                          context,
                          widget.secondaryContent[i],
                          i,
                          multiSelectController,
                        ),
                      ),
                    ),
                  ContentView.table => SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      sliver: SliverGrid.builder(
                        gridDelegate: gridDelegate,
                        itemCount: widget.secondaryContent.length,
                        itemBuilder: (context, i) =>
                            widget.secondaryContentBuilder(
                          context,
                          widget.secondaryContent[i],
                          i,
                          multiSelectController,
                        ),
                      ),
                    ),
                },

                // 三级内容标题
                if (widget.tertiaryContent.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                      child: Text(
                        widget.tertiaryContentTitle,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // 三级内容列表
                SliverList.builder(
                  itemCount: widget.tertiaryContent.length,
                  itemBuilder: (context, i) => widget.tertiaryContentBuilder(
                    context,
                    widget.tertiaryContent[i],
                    i,
                    null,
                  ),
                ),

                // 底部安全间距
                const SliverPadding(padding: EdgeInsets.only(bottom: 96.0)),
              ],
            ),
          ),
        ),

        // 自定义顶栏（参照正在播放页 Positioned 方式，完全沉浸式）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              height: topBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                children: [
                  if (context.canPop())
                    IconButton.filledTonal(
                      tooltip: "返回",
                      onPressed: () => context.pop(),
                      icon: const Icon(Symbols.arrow_back, size: 20.0),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        backgroundColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  Expanded(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _scrollNotifier,
                      builder: (context, offset, _) {
                        // 大标题滚动超过阈值时显示顶栏标题
                        final showTitle = offset > 60.0;
                        return AnimatedOpacity(
                          opacity: showTitle ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18.0,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: "更多",
                    icon: const Icon(Symbols.more_vert, size: 22.0),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),

        // 字母索引（仅移动端显示，默认隐藏，滚动后浮现）
        if (isMobile && widget.secondaryContent.isNotEmpty)
          Positioned(
            right: 4.0,
            top: 100.0,
            bottom: 100.0,
            child: _AlphabetIndex(
              items: widget.secondaryContent
                  .whereType<Audio>()
                  .map((a) => a.title)
                  .toList(),
              scrollController: _scrollController,
            ),
          ),
      ],
    );
  }
}

enum PicShape { oval, rrect }

/// 专辑信息区组件（封面 + 详情 + 播放按钮组）
class _AlbumInfoSection extends StatelessWidget {
  const _AlbumInfoSection({
    required this.pic,
    required this.backgroundPic,
    required this.picShape,
    required this.subtitle,
    required this.playActions,
    this.multiSelectController,
    this.multiSelectViewActions,
    required this.isMobile,
  });

  final Future<ImageProvider?> pic;
  final Future<ImageProvider?> backgroundPic;
  final PicShape picShape;
  final String subtitle;
  final List<Widget> playActions;
  final MultiSelectController? multiSelectController;
  final List<Widget>? multiSelectViewActions;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final picSize = isMobile ? 120.0 : 180.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 毛玻璃背景
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: isMobile ? 150.0 : 180.0,
            child: FutureBuilder(
              future: backgroundPic,
              builder: (context, snapshot) {
                if (snapshot.data == null) return const SizedBox.shrink();
                return Image(
                  image: snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                );
              },
            ),
          ),
          // 暗色遮罩
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: isMobile ? 150.0 : 180.0,
            child: switch (brightness) {
              Brightness.dark => const ColoredBox(color: Colors.black38),
              Brightness.light => const ColoredBox(color: Colors.white30),
            },
          ),
          // 模糊效果
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: isMobile ? 150.0 : 180.0,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          // 信息内容
          Padding(
            padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
            child: Column(
              children: [
                // 封面 + 详情信息
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面
                    SizedBox(
                      width: picSize,
                      height: picSize,
                      child: FutureBuilder(
                        future: pic,
                        builder: (context, snapshot) {
                          final placeholder = Icon(
                            Symbols.broken_image,
                            size: picSize,
                            color: scheme.onSurface,
                          );
                          return switch (snapshot.connectionState) {
                            ConnectionState.done => snapshot.data == null
                                ? placeholder
                                : switch (picShape) {
                                    PicShape.oval => ClipOval(
                                        child: Image(
                                          image: snapshot.data!,
                                          width: picSize,
                                          height: picSize,
                                          errorBuilder: (_, __, ___) =>
                                              placeholder,
                                        ),
                                      ),
                                    PicShape.rrect => ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8.0),
                                        child: Image(
                                          image: snapshot.data!,
                                          width: picSize,
                                          height: picSize,
                                          errorBuilder: (_, __, ___) =>
                                              placeholder,
                                        ),
                                      ),
                                  },
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
                    SizedBox(width: isMobile ? 12.0 : 16.0),
                    // 详情信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13.0,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 播放按钮组（独立行，居中显示在封面正下方）
                if (playActions.isNotEmpty) ...[
                  SizedBox(height: isMobile ? 10.0 : 14.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: multiSelectController == null
                        ? playActions
                        : multiSelectController!.enableMultiSelectView
                            ? multiSelectViewActions ?? []
                            : playActions,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 字母索引组件（支持滚动浮现动画 + 触摸跳转）
class _AlphabetIndex extends StatefulWidget {
  const _AlphabetIndex({
    required this.items,
    required this.scrollController,
  });

  final List<String> items;
  final ScrollController scrollController;

  @override
  State<_AlphabetIndex> createState() => _AlphabetIndexState();
}

class _AlphabetIndexState extends State<_AlphabetIndex>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  /// 是否已触发过显示（用户开始滚动后保持显示）
  bool _hasBeenVisible = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // 监听滚动：首次滚动时浮现字母索引
    widget.scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_hasBeenVisible && widget.scrollController.offset > 20.0) {
      _hasBeenVisible = true;
      _animationController.forward();
    }
  }

  /// 跳转到指定字母对应的列表位置
  void _scrollToLetter(int itemIndex) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final itemExtent = isMobile ? 64.0 : 72.0;
    final offset = itemIndex * itemExtent;
    widget.scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letters = _getLetters();

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) => Opacity(
        opacity: _opacityAnimation.value,
        child: child,
      ),
      child: Container(
        width: 24.0,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: letters.map((letter) {
            final index = widget.items.indexWhere(
              (item) => item.toUpperCase().startsWith(letter),
            );
            final isActive = index != -1;

            return GestureDetector(
              onTap: isActive ? () => _scrollToLetter(index) : null,
              child: Container(
                width: 20.0,
                height: 20.0,
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? scheme.onSurface
                        : scheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<String> _getLetters() {
    return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('').toList();
  }
}
