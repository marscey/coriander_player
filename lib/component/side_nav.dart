// ignore_for_file: camel_case_types

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/responsive_builder.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class DestinationDesc {
  final IconData icon;
  final String label;
  final String desPath;
  DestinationDesc(this.icon, this.label, this.desPath);
}

/// 导航项与 StatefulShellRoute 分支的对应关系
/// 分支顺序必须与 entry.dart 中 StatefulShellRoute.indexedStack 的 branches 顺序一致
final destinations = <DestinationDesc>[
  DestinationDesc(Symbols.library_music, "音乐库", app_paths.AUDIOS_PAGE),
  DestinationDesc(Symbols.history, "最近播放", app_paths.RECENT_PLAYS_PAGE),
  DestinationDesc(Symbols.artist, "艺术家", app_paths.ARTISTS_PAGE),
  DestinationDesc(Symbols.album, "专辑", app_paths.ALBUMS_PAGE),
  DestinationDesc(Symbols.folder, "本地", app_paths.FOLDERS_PAGE),
  DestinationDesc(Symbols.cloud, "连接", app_paths.CLOUD_CONNECTIONS_PAGE),
  DestinationDesc(Symbols.list, "歌单", app_paths.PLAYLISTS_PAGE),
  DestinationDesc(Symbols.search, "搜索", app_paths.SEARCH_PAGE),
  DestinationDesc(Symbols.settings, "设置", app_paths.SETTINGS_PAGE),
];

class SideNav extends StatelessWidget {
  const SideNav({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).uri.toString();
    int selected = destinations.indexWhere(
      (desc) => location.startsWith(desc.desPath),
    );

    void onDestinationSelected(int value) {
      if (value == selected) return;

      final targetDesc = destinations[value];
      final index = app_paths.START_PAGES.indexOf(targetDesc.desPath);
      if (index != -1) AppPreference.instance.startPage = index;

      // 使用 StatefulNavigationShell.goBranch 切换分支，保留各分支路由栈
      navigationShell.goBranch(
        value,
        initialLocation: value == navigationShell.currentIndex,
      );

      var scaffold = Scaffold.of(context);
      if (scaffold.hasDrawer) scaffold.closeDrawer();
    }

    return ResponsiveBuilder(
      builder: (context, screenType) {
        switch (screenType) {
          case ScreenType.small:
          case ScreenType.large:
            return NavigationDrawer(
              backgroundColor: scheme.surfaceContainer,
              selectedIndex: selected,
              onDestinationSelected: onDestinationSelected,
              children: List.generate(
                destinations.length,
                (i) => NavigationDrawerDestination(
                  icon: Icon(destinations[i].icon),
                  label: Text(destinations[i].label),
                ),
              ),
            );
          case ScreenType.medium:
            return NavigationRail(
              backgroundColor: scheme.surfaceContainer,
              selectedIndex: selected,
              onDestinationSelected: onDestinationSelected,
              destinations: List.generate(
                destinations.length,
                (i) => NavigationRailDestination(
                  icon: Icon(destinations[i].icon),
                  label: Text(destinations[i].label),
                ),
              ),
            );
        }
      },
    );
  }
}

/// 移动端底部导航栏的导航项
/// key: 显示在底部导航栏中的项 index (0-4)
/// value: 对应 StatefulShellRoute 的分支 index
const _mobileNavBranchMapping = [0, 1, 5, 7, 8];

/// 移动端底部导航栏显示的5个导航项
final _mobileDestinations = <DestinationDesc>[
  destinations[0], // 音乐库
  destinations[1], // 最近播放
  destinations[5], // 连接
  destinations[7], // 搜索
  destinations[8], // 设置
];

/// Maestro 自动化测试用的语义标识符
const _mobileTabIds = ['tab_library', 'tab_recent', 'tab_cloud', 'tab_search', 'tab_settings'];

class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).uri.toString();

    // 找到当前路由对应的 destinations index
    int selectedInDestinations = destinations.indexWhere(
      (desc) => location.startsWith(desc.desPath),
    );

    // 映射到底部导航栏的 index
    int selectedInMobile = _mobileNavBranchMapping.indexOf(selectedInDestinations);
    if (selectedInMobile == -1) selectedInMobile = 0;

    void onDestinationSelected(int mobileIndex) {
      if (mobileIndex == selectedInMobile) return;
      final branchIndex = _mobileNavBranchMapping[mobileIndex];
      navigationShell.goBranch(
        branchIndex,
        initialLocation: branchIndex == navigationShell.currentIndex,
      );
    }

    return NavigationBar(
      backgroundColor: scheme.surfaceContainer,
      selectedIndex: selectedInMobile,
      onDestinationSelected: onDestinationSelected,
      destinations: List.generate(
        _mobileDestinations.length,
        (i) => NavigationDestination(
          key: ValueKey('nav-tab-$i'),
          icon: Semantics(
            identifier: _mobileTabIds[i],
            child: Icon(_mobileDestinations[i].icon),
          ),
          label: _mobileDestinations[i].label,
        ),
      ),
    );
  }
}
