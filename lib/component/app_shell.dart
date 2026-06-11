// ignore_for_file: camel_case_types

import 'package:coriander_player/component/mini_now_playing.dart';
import 'package:coriander_player/component/responsive_builder.dart';
import 'package:coriander_player/component/side_nav.dart';
import 'package:coriander_player/component/title_bar.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 所有 Tab 一级页面路径（mini player 在这些页面显示）
const List<String> _shellRootPages = [
  '/audios',
  '/recent',
  '/artists',
  '/albums',
  '/folders',
  '/cloud',
  '/playlists',
  '/search',
  '/settings',
];

/// 迷你播放器可见性通知器
/// AppShell 根据当前路由自动更新，MiniNowPlaying 监听此通知器
final ValueNotifier<bool> miniPlayerVisibleNotifier = ValueNotifier<bool>(true);

/// 侧边导航栏展开/折叠状态管理
/// 大屏/中屏模式下控制侧边导航栏的显示与隐藏
class SideNavController extends ChangeNotifier {
  static final SideNavController instance = SideNavController();

  bool _expanded = true;
  bool get expanded => _expanded;

  void toggle() {
    _expanded = !_expanded;
    notifyListeners();
  }

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 通过 GoRouterState.of(context) 注册依赖，路由变化时自动触发
    _updateVisibility();
  }

  void _updateVisibility() {
    final path = GoRouterState.of(context).uri.path;
    // 去除尾部斜杠进行比较
    final normalizedPath = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    miniPlayerVisibleNotifier.value = _shellRootPages.contains(normalizedPath);
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformHelper.isMobile) {
      return _AppShell_Mobile(navigationShell: widget.navigationShell);
    }
    return ResponsiveBuilder(
      builder: (context, screenType) {
        switch (screenType) {
          case ScreenType.small:
            return _AppShell_Small(navigationShell: widget.navigationShell);
          case ScreenType.medium:
          case ScreenType.large:
            return _AppShell_Large(navigationShell: widget.navigationShell);
        }
      },
    );
  }
}

class _AppShell_Small extends StatelessWidget {
  const _AppShell_Small({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(48.0),
        child: TitleBar(),
      ),
      drawer: SideNav(navigationShell: navigationShell),
      body: Stack(children: [navigationShell, const MiniNowPlaying()]),
    );
  }
}

class _AppShell_Large extends StatelessWidget {
  const _AppShell_Large({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(48.0),
        child: TitleBar(),
      ),
      body: ListenableBuilder(
        listenable: SideNavController.instance,
        builder: (context, _) {
          final expanded = SideNavController.instance.expanded;
          return Row(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.centerLeft,
                child: expanded
                    ? SideNav(navigationShell: navigationShell)
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(expanded ? 8.0 : 0),
                    ),
                    child: navigationShell,
                  ),
                  const MiniNowPlaying()
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppShell_Mobile extends StatelessWidget {
  const _AppShell_Mobile({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          navigationShell,
          const MiniNowPlaying(),
        ]),
      ),
      bottomNavigationBar: MobileBottomNav(navigationShell: navigationShell),
    );
  }
}
