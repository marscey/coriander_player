import 'dart:io';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/entry.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/library/genre_service.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/platform_dependency_manager.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/metadata/scraper_orchestrator.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/recent_play_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart' as bass;
import 'package:coriander_player/src/rust/api/logger.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _exitApp() async {
  PlayService.instance.close();
  await savePlaylists();
  await saveLyricSources();
  await AppSettings.instance.saveSettings();
  await AppPreference.instance.save();
  if (PlatformHelper.isDesktop) {
    await HotkeysHelper.unregisterAll();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
  exit(0);
}

Future<void> _updateTrayMenu() async {
  final ps = PlayService.instance.playbackService;
  final isPlaying = ps.playerState == bass.PlayerState.playing;
  final hasAudio = ps.nowPlaying != null;

  await trayManager.setContextMenu(Menu(items: [
    MenuItem(
      key: 'toggle_window',
      label: '显示/隐藏窗口',
    ),
    MenuItem.separator(),
    MenuItem(
      key: 'play_pause',
      label: isPlaying ? '暂停' : '播放',
      disabled: !hasAudio,
    ),
    MenuItem(
      key: 'previous',
      label: '上一首',
      disabled: !hasAudio,
    ),
    MenuItem(
      key: 'next',
      label: '下一首',
      disabled: !hasAudio,
    ),
    MenuItem.separator(),
    MenuItem(
      key: 'exit_app',
      label: '退出',
    ),
  ]));
}

Future<void> initWindow() async {
  if (!PlatformHelper.isDesktop) return;

  await windowManager.ensureInitialized();

  try {
    if (PlatformHelper.isWindows) {
      await trayManager.setIcon('app_icon.ico');
    } else if (PlatformHelper.isMacOS) {
      await trayManager.setIcon('AppIcon');
    } else {
      await trayManager.setIcon('app_icon.png');
    }
  } catch (e) {
    LOGGER.e('Failed to set tray icon: $e');
  }

  await _updateTrayMenu();

  final windowOptions = WindowOptions(
    minimumSize: const Size(507, 507),
    size: AppSettings.instance.windowSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle:
        PlatformHelper.isMacOS ? TitleBarStyle.normal : TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });

  windowManager.addListener(_AppWindowListener());
  trayManager.addListener(_AppTrayListener());

  PlayService.instance.playbackService.addListener(_onPlaybackStateChanged);
}

void _onPlaybackStateChanged() {
  _updateTrayMenu();
}

class _AppWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    if (AppSettings.instance.closeToTray) {
      await windowManager.hide();
    } else {
      await _exitApp();
    }
  }
}

class _AppTrayListener implements TrayListener {
  @override
  void onTrayIconMouseDown() async {
    if (PlatformHelper.isWindows) {
      await _toggleWindow();
    } else {
      await trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    if (PlatformHelper.isWindows) {
      await trayManager.popUpContextMenu();
    } else {
      await _toggleWindow();
    }
  }

  Future<void> _toggleWindow() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final ps = PlayService.instance.playbackService;
    switch (menuItem.key) {
      case 'toggle_window':
        await _toggleWindow();
        break;
      case 'play_pause':
        if (ps.playerState == bass.PlayerState.playing) {
          ps.pause();
        } else {
          ps.start();
        }
        break;
      case 'previous':
        ps.lastAudio();
        break;
      case 'next':
        ps.nextAudio();
        break;
      case 'exit_app':
        await _exitApp();
        break;
    }
  }

  @override
  void onTrayIconMouseUp() {}
  @override
  void onTrayIconRightMouseUp() {}
}

Future<void> loadPrefFont() async {
  final settings = AppSettings.instance;
  if (settings.fontFamily != null) {
    try {
      final fontLoader = FontLoader(settings.fontFamily!);

      fontLoader.addFont(
        File(settings.fontPath!).readAsBytes().then((value) {
          return ByteData.sublistView(value);
        }),
      );
      await fontLoader.load();
      ThemeProvider.instance.changeFontFamily(settings.fontFamily!);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();

  await RustLib.init();

  initRustLogger().listen((msg) {
    LOGGER.i("[rs]: $msg");
  });

  if (PlatformHelper.isDesktop) {
    await HotkeysHelper.unregisterAll();
    HotkeysHelper.registerHotKeys();
  }

  await migrateAppData();

  final supportPath = (await getAppDataDir()).path;
  if (File(PlatformHelper.joinPaths([supportPath, "settings.json"]))
      .existsSync()) {
    await AppSettings.readFromJson();

    await CloudCacheManager.init();
    CloudCacheManager.instance
        .setMaxCacheSizeMB(AppSettings.instance.cloudCacheMaxSizeMB);

    await PlatformDependencyManager.instance.initialize();

    final dependencyManager = PlatformDependencyManager.instance;
    if (AppSettings.instance.playerEngineType != null &&
        !dependencyManager
            .isPlayerEngineSupported(AppSettings.instance.playerEngineType!)) {
      AppSettings.instance.playerEngineType =
          dependencyManager.getRecommendedPlayerEngine();
      await AppSettings.instance.saveSettings();
    }

    await loadPrefFont();
  }
  if (File(PlatformHelper.joinPaths([supportPath, "app_preference.json"]))
      .existsSync()) {
    await AppPreference.read();
  }
  final welcome = PlatformHelper.isMobile
      ? false
      : !File(PlatformHelper.joinPaths([supportPath, "index.json"]))
          .existsSync();

  await initWindow();

  await RecentPlayService.instance.load();

  await GenreService.instance.load();

  await ScraperOrchestrator.instance.initDefaults();

  await PlayService.instance.initialize();

  final cloudServiceManager = CloudServiceManager();

  runApp(App(welcome: welcome, cloudServiceManager: cloudServiceManager));
}
