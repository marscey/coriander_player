// ignore_for_file: camel_case_types

import 'package:coriander_player/component/mini_now_playing.dart';
import 'package:coriander_player/component/responsive_builder.dart';
import 'package:coriander_player/component/side_nav.dart';
import 'package:coriander_player/component/title_bar.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    if (PlatformHelper.isMobile) {
      return _AppShell_Mobile(navigationShell: navigationShell);
    }
    return ResponsiveBuilder(
      builder: (context, screenType) {
        switch (screenType) {
          case ScreenType.small:
            return _AppShell_Small(navigationShell: navigationShell);
          case ScreenType.medium:
          case ScreenType.large:
            return _AppShell_Large(navigationShell: navigationShell);
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
      body: Row(
        children: [
          SideNav(navigationShell: navigationShell),
          Expanded(
            child: Stack(children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8.0),
                ),
                child: navigationShell,
              ),
              const MiniNowPlaying()
            ]),
          ),
        ],
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
