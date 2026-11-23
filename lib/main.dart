import 'dart:io';
import 'dart:ui';

import 'package:coriander_player/app_storage.dart';
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
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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
    } else {
      // macOS / Linux 托盘走 Flutter asset（tray_manager 用 rootBundle 读图）
      await trayManager.setIcon('assets/tray/app_icon.png');
    }
  } catch (e) {
    LOGGER.w('托盘图标设置失败（不影响主功能）: $e');
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

/// 安装全局错误钩子：未捕获异常写入运行日志，便于事后排查
void _installErrorHandlers() {
  FlutterError.onError = (details) {
    LOGGER.e('[flutter] ${details.exceptionAsString()}',
        stackTrace: details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    LOGGER.e('[async] $error', stackTrace: stack);
    return true;
  };
}

/// 启动阶段单步容错：某一步失败只记录日志，不阻断后续启动
Future<T?> _guardValue<T>(String name, Future<T> Function() action) async {
  try {
    return await action();
  } catch (err, trace) {
    LOGGER.e('[init] $name 失败: $err', stackTrace: trace);
    return null;
  }
}

Future<void> _guard(String name, Future<void> Function() action) async {
  await _guardValue<dynamic>(name, action);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 日志必须最先初始化：此后任何一步失败都能落到日志文件
  await DebugLogger.instance.init();
  _installErrorHandlers();
  LOGGER.i('[init] app start, platform=${Platform.operatingSystem}');

  // 预热 Liquid Glass shader，消除首次渲染白闪
  await _guard('预热 Liquid Glass', LiquidGlassWidgets.initialize);

  MediaKit.ensureInitialized();

  await _guard('初始化 Rust 库', RustLib.init);

  initRustLogger().listen((msg) {
    LOGGER.i("[rs]: $msg");
  });

  if (PlatformHelper.isDesktop) {
    await _guard('注册全局快捷键', () async {
      await HotkeysHelper.unregisterAll();
      HotkeysHelper.registerHotKeys();
    });
  }

  await _guard('迁移旧数据目录', migrateAppData);

  final appDataDir = await _guardValue('读取数据目录', getAppDataDir);
  final supportPath = appDataDir?.path;
  LOGGER.i('[init] app data dir: ${supportPath ?? "<unavailable>"}');

  if (supportPath != null &&
      File(PlatformHelper.joinPaths([supportPath, "settings.json"]))
          .existsSync()) {
    await _guard('读取设置', AppSettings.readFromJson);

    await _guard('初始化云缓存', CloudCacheManager.init);
    CloudCacheManager.instance
        .setMaxCacheSizeMB(AppSettings.instance.cloudCacheMaxSizeMB);

    await _guard('初始化平台依赖', PlatformDependencyManager.instance.initialize);

    final dependencyManager = PlatformDependencyManager.instance;
    if (AppSettings.instance.playerEngineType != null &&
        !dependencyManager
            .isPlayerEngineSupported(AppSettings.instance.playerEngineType!)) {
      AppSettings.instance.playerEngineType =
          dependencyManager.getRecommendedPlayerEngine();
      await _guard('保存设置', AppSettings.instance.saveSettings);
    }

    await _guard('加载自定义字体', loadPrefFont);
  }
  if (supportPath != null &&
      File(PlatformHelper.joinPaths([supportPath, "app_preference.json"]))
          .existsSync()) {
    await _guard('读取偏好', AppPreference.read);
  }
  final welcome = PlatformHelper.isMobile
      ? false
      : supportPath != null &&
          !File(PlatformHelper.joinPaths([supportPath, "index.json"]))
              .existsSync();

  await _guard('初始化窗口', initWindow);

  await _guard('加载最近播放', RecentPlayService.instance.load);

  // GenreService 需要在 AudioLibrary 初始化之后加载
  // 但 AudioLibrary.initFromIndex() 在用户选择文件夹后才调用
  // 所以先初始化 GenreService（此时为空），后续在 AudioLibrary 初始化后刷新
  await _guard('加载流派', GenreService.instance.load);

  await _guard('初始化刮削器', ScraperOrchestrator.instance.initDefaults);

  await _guard('初始化播放服务', PlayService.instance.initialize);

  final cloudServiceManager = CloudServiceManager();

  LOGGER.i('[init] bootstrap done, launching UI (welcome=$welcome)');
  runApp(LiquidGlassWidgets.wrap(
    child: App(welcome: welcome, cloudServiceManager: cloudServiceManager),
  ));
}
