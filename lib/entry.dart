import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/component/app_shell.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/page/album_detail_page_new.dart';
import 'package:coriander_player/page/albums_page.dart';
import 'package:coriander_player/page/artist_detail_page.dart';
import 'package:coriander_player/page/artists_page.dart';
import 'package:coriander_player/page/audio_detail_page.dart';
import 'package:coriander_player/page/audios_page.dart';
import 'package:coriander_player/page/cloud_service/cloud_connections_page.dart';
import 'package:coriander_player/page/cloud_service/cloud_file_browser.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/page/folder_detail_page.dart';
import 'package:coriander_player/page/folders_page.dart';
import 'package:coriander_player/page/now_playing_page/page.dart';
import 'package:coriander_player/page/playlist_detail_page.dart';
import 'package:coriander_player/page/playlists_page.dart';
import 'package:coriander_player/page/recent_plays_page.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:coriander_player/page/search_page/search_result_page.dart';
import 'package:coriander_player/page/settings_page/create_issue.dart';
import 'package:coriander_player/page/settings_page/page.dart';
import 'package:coriander_player/page/updating_page.dart';
import 'package:coriander_player/page/welcoming_page.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class SlideTransitionPage<T> extends CustomTransitionPage<T> {
  const SlideTransitionPage({
    required super.child,
    super.name,
    super.arguments,
    super.restorationId,
    super.key,
  }) : super(
          transitionsBuilder: _transitionsBuilder,
          transitionDuration: const Duration(milliseconds: 150),
          reverseTransitionDuration: const Duration(milliseconds: 150),
        );

  static Widget _transitionsBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final tween = Tween(
      begin: const Offset(0, 0.10),
      end: const Offset(0, 0),
    );

    return SlideTransition(
      position: tween.animate(
        CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn),
      ),
      child: child,
    );
  }
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
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.AUDIOS_PAGE,
              pageBuilder: (context, state) {
                if (state.extra != null) {
                  return SlideTransitionPage(
                      child: AudiosPage(locateTo: state.extra as Audio));
                }
                return const SlideTransitionPage(child: AudiosPage());
              },
              routes: [
                GoRoute(
                  path: "detail",
                  builder: (context, state) =>
                      AudioDetailPage(audio: state.extra as Audio),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.RECENT_PLAYS_PAGE,
              pageBuilder: (context, state) => const SlideTransitionPage(
                child: RecentPlaysPage(),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.ARTISTS_PAGE,
              pageBuilder: (context, state) => const SlideTransitionPage(
                child: ArtistsPage(),
              ),
              routes: [
                GoRoute(
                  path: "detail",
                  builder: (context, state) =>
                      ArtistDetailPage(artist: state.extra as Artist),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.ALBUMS_PAGE,
              pageBuilder: (context, state) => const SlideTransitionPage(
                child: AlbumsPage(),
              ),
              routes: [
                GoRoute(
                  path: "detail",
                  builder: (context, state) =>
                      AlbumDetailPageNew(album: state.extra as Album),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.FOLDERS_PAGE,
              pageBuilder: (context, state) => const SlideTransitionPage(
                child: FoldersPage(),
              ),
              routes: [
                GoRoute(
                  path: "detail",
                  builder: (context, state) {
                    final args = state.extra as FolderDetailArgs;
                    return FolderDetailPage(
                        folder: args.folder, locateToPath: args.locateToPath);
                  },
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.CLOUD_CONNECTIONS_PAGE,
              pageBuilder: (context, state) => const SlideTransitionPage(
                child: CloudConnectionsPage(),
              ),
              routes: [
                GoRoute(
                  path: "browser/:connectionId",
                  builder: (context, state) {
                    final connectionId = state.pathParameters['connectionId']!;
                    final args = state.extra as CloudBrowserArgs?;
                    return CloudFileBrowser(
                      connectionId: connectionId,
                      initialPath: args?.initialPath ?? '',
                      locateToPath: args?.locateToPath,
                    );
                  },
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.PLAYLISTS_PAGE,
              pageBuilder: (context, state) => const SlideTransitionPage(
                child: PlaylistsPage(),
              ),
              routes: [
                GoRoute(
                  path: "detail",
                  builder: (context, state) {
                    final playlist = state.extra as Playlist;
                    return PlaylistDetailPage(playlist: playlist);
                  },
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.SEARCH_PAGE,
              pageBuilder: (context, state) => const SlideTransitionPage(
                child: SearchPage(),
              ),
              routes: [
                GoRoute(
                  path: "result",
                  builder: (context, state) {
                    final result = state.extra as UnionSearchResult;
                    return SearchResultPage(searchResult: result);
                  },
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: app_paths.SETTINGS_PAGE,
              pageBuilder: (context, state) => const SlideTransitionPage(
                child: SettingsPage(),
              ),
              routes: [
                GoRoute(
                  path: "issue",
                  builder: (context, state) => const SettingsIssuePage(),
                ),
              ],
            ),
          ]),
        ],
      ),

      /// now playing page
      GoRoute(
        path: app_paths.NOW_PLAYING_PAGE,
        pageBuilder: (context, state) => CustomTransitionPage(
          maintainState: false,
          transitionsBuilder: (context, animation, _, child) {
            final tween = Tween(
              begin: const Offset(0, 1),
              end: const Offset(0, 0),
            );

            return SlideTransition(
              position: tween.animate(
                CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn),
              ),
              child: child,
            );
          },
          child: const NowPlayingPage(),
        ),
      ),

      /// welcoming page
      GoRoute(
        path: app_paths.WELCOMING_PAGE,
        pageBuilder: (context, state) => const SlideTransitionPage(
          child: WelcomingPage(),
        ),
      ),

      /// updating dialog
      GoRoute(
        path: app_paths.UPDATING_DIALOG,
        pageBuilder: (context, state) => const SlideTransitionPage(
          child: UpdatingPage(),
        ),
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
