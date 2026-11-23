import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/app_shell.dart';
import 'package:coriander_player/component/glass_app_shell.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/page/albums_page.dart';
import 'package:coriander_player/page/album_detail_page_new.dart';
import 'package:coriander_player/page/artist_detail_page_v3.dart';
import 'package:coriander_player/page/artists_page.dart';
import 'package:coriander_player/page/audio_detail_page.dart';
import 'package:coriander_player/page/glass_audio_detail_page.dart';
import 'package:coriander_player/page/audios_page.dart';
import 'package:coriander_player/page/categories_page.dart';
import 'package:coriander_player/page/cloud_service/cloud_connections_page.dart';
import 'package:coriander_player/page/cloud_service/cloud_file_browser.dart';
import 'package:coriander_player/page/cloud_service/glass_cloud_file_browser.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/page/folder_detail_page.dart';
import 'package:coriander_player/page/folders_page.dart';
import 'package:coriander_player/page/genres_page.dart';
import 'package:coriander_player/page/now_playing_page/page.dart';
import 'package:coriander_player/page/playlist_detail_page.dart';
import 'package:coriander_player/page/playlists_page.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:coriander_player/page/search_page/search_result_page.dart';
import 'package:coriander_player/page/settings_page/create_issue.dart';
import 'package:coriander_player/page/settings_page/page.dart';
import 'package:coriander_player/page/updating_page.dart';
import 'package:coriander_player/page/welcoming_page.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

// ─── 移动端导航转场页面 ──────────────────────────────────

/// Tab 一级页面 — 无转场动画（即时切换）
class _NoTransitionPage<T> extends CustomTransitionPage<T> {
  _NoTransitionPage({required super.child})
      : super(
          transitionsBuilder: _transitionsBuilder,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );

  static Widget _transitionsBuilder(
          _, __, ___, Widget child) =>
      child;
}

/// 移动端模态转场 — 从底部滑入（NowPlaying 等模态覆盖场景）
class _MobileModalPage<T> extends CustomTransitionPage<T> {
  _MobileModalPage({required super.child, super.maintainState})
      : super(
          transitionsBuilder: _transitionsBuilder,
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 350),
        );

  static Widget _transitionsBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slideIn = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.fastOutSlowIn,
    ));

    return SlideTransition(
      position: slideIn,
      child: child,
    );
  }
}

/// 根据平台选择合适的页面类型
///
/// - 移动端：CupertinoPage（支持 iOS 左滑手势返回 + 原生右滑入转场）
/// - 桌面端：MaterialPage
Page<dynamic> _platformPage({required Widget child, bool maintainState = true}) {
  if (PlatformHelper.isMobile) {
    return CupertinoPage(child: child, maintainState: maintainState);
  }
  return MaterialPage(child: child, maintainState: maintainState);
}

/// Tab 一级页面 — 无转场动画
Page<dynamic> _tabRootPage({required Widget child}) {
  if (PlatformHelper.isMobile) {
    return _NoTransitionPage(child: child);
  }
  return MaterialPage(child: child);
}

class Entry extends StatelessWidget {
  Entry({super.key, required this.welcome, required this.cloudServiceManager});
  final bool welcome;
  final CloudServiceManager cloudServiceManager;

  ThemeData fromSchemeAndFontFamily({
    required ColorScheme colorScheme,
    String? fontFamily,
  }) {
    final bool isDark = colorScheme.brightness == Brightness.dark;

    // For surfaces that use primary color in light themes and surface color in dark
    final Color primarySurfaceColor =
        isDark ? colorScheme.surface : colorScheme.primary;
    final Color onPrimarySurfaceColor =
        isDark ? colorScheme.onSurface : colorScheme.onPrimary;

    return ThemeData(
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      brightness: colorScheme.brightness,
      primaryColor: primarySurfaceColor,
      canvasColor: colorScheme.surface,
      scaffoldBackgroundColor: colorScheme.surface,
      cardColor: colorScheme.surface,
      dividerColor: colorScheme.onSurface.withOpacity(0.12),
      indicatorColor: onPrimarySurfaceColor,
      applyElevationOverlayColor: isDark,
      useMaterial3: true,
      dialogTheme: DialogThemeData(backgroundColor: colorScheme.surface),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ThemeProvider.instance),
        ChangeNotifierProvider.value(value: cloudServiceManager),
      ],
      builder: (context, _) {
        final theme = Provider.of<ThemeProvider>(context);
        return MaterialApp.router(
          scaffoldMessengerKey: SCAFFOLD_MESSAGER,
          debugShowCheckedModeBanner: false,
          theme: fromSchemeAndFontFamily(
            fontFamily: theme.fontFamily,
            colorScheme: theme.lightScheme,
          ),
          darkTheme: fromSchemeAndFontFamily(
            fontFamily: theme.fontFamily,
            colorScheme: theme.darkScheme,
          ),
          themeMode: theme.themeMode,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: supportedLocales,
          routerConfig: config,
        );
      },
    );
  }

  late final GoRouter config = GoRouter(
    navigatorKey: ROUTER_KEY,
    initialLocation:
        welcome ? app_paths.WELCOMING_PAGE : app_paths.UPDATING_DIALOG,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // 根据 Liquid Glass 开关选择不同的 Shell
          if (AppPreference.instance.liquidGlassEnabled && PlatformHelper.isMobile) {
            return GlassAppShell(navigationShell: navigationShell);
          }
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // 0: 音乐库
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.AUDIOS_PAGE,
              pageBuilder: (context, state) {
                if (state.extra != null) {
                  return _tabRootPage(
                      child: AudiosPage(locateTo: state.extra as Audio));
                }
                return _tabRootPage(child: const AudiosPage());
              },
              routes: [
                GoRoute(
                  path: "detail",
                  pageBuilder: (context, state) => _platformPage(
                    child: (AppPreference.instance.liquidGlassEnabled &&
                            PlatformHelper.isMobile)
                        ? GlassAudioDetailPage(audio: state.extra as Audio)
                        : AudioDetailPage(audio: state.extra as Audio),
                  ),
                ),
              ],
            ),
          ]),
          // 1: 歌单
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.PLAYLISTS_PAGE,
              pageBuilder: (context, state) =>
                  _tabRootPage(child: const PlaylistsPage()),
              routes: [
                GoRoute(
                  path: "detail",
                  pageBuilder: (context, state) {
                    final playlist = state.extra as Playlist;
                    return _platformPage(
                        child: PlaylistDetailPage(playlist: playlist));
                  },
                ),
              ],
            ),
          ]),
          // 2: 类别
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.CATEGORIES_PAGE,
              pageBuilder: (context, state) =>
                  _tabRootPage(child: const CategoriesPage()),
              routes: [
                GoRoute(
                  path: "artists",
                  pageBuilder: (context, state) =>
                      _platformPage(child: const ArtistsPage()),
                  routes: [
                    GoRoute(
                      path: "detail",
                      pageBuilder: (context, state) => _platformPage(
                        child: ArtistDetailPageV3(
                            artist: state.extra as Artist),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: "albums",
                  pageBuilder: (context, state) =>
                      _platformPage(child: const AlbumsPage()),
                  routes: [
                    GoRoute(
                      path: "detail",
                      pageBuilder: (context, state) => _platformPage(
                        child:
                            AlbumDetailPageNew(album: state.extra as Album),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: "genres",
                  pageBuilder: (context, state) =>
                      _platformPage(child: const GenresPage()),
                  routes: [
                    GoRoute(
                      path: "detail",
                      pageBuilder: (context, state) => _platformPage(
                        child: GenreDetailPage(genre: state.extra as Genre),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          // 3: 本地
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.FOLDERS_PAGE,
              pageBuilder: (context, state) =>
                  _tabRootPage(child: const FoldersPage()),
              routes: [
                GoRoute(
                  path: "detail",
                  pageBuilder: (context, state) {
                    final args = state.extra as FolderDetailArgs;
                    return _platformPage(
                      child: FolderDetailPage(
                          folder: args.folder,
                          locateToPath: args.locateToPath),
                    );
                  },
                ),
              ],
            ),
          ]),
          // 4: 连接
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.CLOUD_CONNECTIONS_PAGE,
              pageBuilder: (context, state) =>
                  _tabRootPage(child: const CloudConnectionsPage()),
              routes: [
                GoRoute(
                  path: "browser/:connectionId",
                  pageBuilder: (context, state) {
                    final connectionId =
                        state.pathParameters['connectionId']!;
                    final args = state.extra as CloudBrowserArgs?;
                    final useGlass = AppPreference.instance.liquidGlassEnabled
                        && PlatformHelper.isMobile;
                    return _platformPage(
                      child: useGlass
                          ? GlassCloudFileBrowser(
                              connectionId: connectionId,
                              initialPath: args?.initialPath ?? '',
                              locateToPath: args?.locateToPath,
                            )
                          : CloudFileBrowser(
                              connectionId: connectionId,
                              initialPath: args?.initialPath ?? '',
                              locateToPath: args?.locateToPath,
                            ),
                    );
                  },
                ),
              ],
            ),
          ]),
          // 5: 搜索
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.SEARCH_PAGE,
              pageBuilder: (context, state) =>
                  _tabRootPage(child: const SearchPage()),
              routes: [
                GoRoute(
                  path: "result",
                  pageBuilder: (context, state) {
                    final result = state.extra as UnionSearchResult;
                    return _platformPage(
                        child: SearchResultPage(searchResult: result));
                  },
                ),
              ],
            ),
          ]),
        ],
      ),

      /// settings page — 顶级路由（不嵌套在 shell 内，无底部导航栏和迷你播放器）
      GoRoute(
        path: app_paths.SETTINGS_PAGE,
        pageBuilder: (context, state) =>
            _platformPage(child: const SettingsPage()),
        routes: [
          GoRoute(
            path: "issue",
            pageBuilder: (context, state) =>
                _platformPage(child: const SettingsIssuePage()),
          ),
        ],
      ),

      /// now playing page — 模态底部滑入
      GoRoute(
        path: app_paths.NOW_PLAYING_PAGE,
        pageBuilder: (context, state) => _MobileModalPage(
          maintainState: false,
          child: const NowPlayingPage(),
        ),
      ),

      /// album detail page (top-level route) — 右侧推入
      GoRoute(
        path: app_paths.ALBUM_DETAIL_PAGE_NEW,
        pageBuilder: (context, state) => _platformPage(
          child: AlbumDetailPageNew(album: state.extra as Album),
        ),
      ),

      /// welcoming page
      GoRoute(
        path: app_paths.WELCOMING_PAGE,
        pageBuilder: (context, state) =>
            _platformPage(child: const WelcomingPage()),
      ),

      /// updating dialog
      GoRoute(
        path: app_paths.UPDATING_DIALOG,
        pageBuilder: (context, state) =>
            _platformPage(child: const UpdatingPage()),
      ),
    ],
  );

  final supportedLocales = const [
    Locale.fromSubtags(languageCode: 'zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale.fromSubtags(
        languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
    Locale.fromSubtags(
        languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
    Locale.fromSubtags(
        languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK'),
    Locale("en", "US"),
  ];
}

class App extends StatefulWidget {
  const App(
      {super.key, required this.welcome, required this.cloudServiceManager});
  final bool welcome;
  final CloudServiceManager cloudServiceManager;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    if (PlatformHelper.isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initSystemTray();
    }
  }

  @override
  void dispose() {
    if (PlatformHelper.isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      trayManager.destroy();
    }
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    String iconPath;
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      iconPath = p.join(exeDir, 'data', 'flutter_assets', 'app_icon.ico');
    } else if (Platform.isMacOS) {
      iconPath = 'app_icon.ico';
    } else {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      iconPath = p.join(exeDir, 'data', 'flutter_assets', 'app_icon.ico');
    }

    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('Coriander Player');

    Menu menu = Menu(items: [
      MenuItem(key: 'show_window', label: '显示主窗口'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: '退出'),
    ]);
    await trayManager.setContextMenu(menu);
  }

  @override
  void onWindowClose() async {
    try {
      await windowManager.hide();
    } catch (e) {
      await windowManager.minimize();
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Entry(
      welcome: widget.welcome,
      cloudServiceManager: widget.cloudServiceManager,
    );
  }
}
