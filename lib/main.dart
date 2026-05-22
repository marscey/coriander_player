import 'dart:io';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/entry.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/platform_dependency_manager.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/recent_play_service.dart';
import 'package:coriander_player/src/rust/api/logger.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initWindow() async {
  await windowManager.ensureInitialized();

  // 设置系统托盘图标
  try {
    await trayManager.setIcon('app_icon.ico');
  } catch (e) {
    LOGGER.e('Failed to set tray icon: $e');
  }

  // 设置系统托盘菜单项
  await trayManager.setContextMenu(Menu(
    items: [
      MenuItem(
        key: 'show_window',
        label: '显示窗口',
      ),
      MenuItem(
        key: 'exit_app',
        label: '退出应用',
      ),
    ],
  ));

  // macOS平台的窗口设置
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

    // macOS平台特有的设置
    if (PlatformHelper.isMacOS) {
      // 启用macOS上的窗口全尺寸内容视图
      // 注释掉不存在的方法调用
      // await windowManager.setFullSizeContentView(true);
    }
  });

  // 监听窗口关闭事件
  windowManager.addListener(MyWindowListener());

  // 监听系统托盘点击事件
  trayManager.addListener(_TrayManagerListener());
}

// 自定义窗口监听器
class MyWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    try {
      await windowManager.hide();
    } catch (e) {
      try {
        await windowManager.setPreventClose(true);
        await windowManager.hide();
      } catch (e2) {
        await windowManager.minimize();
      }
    }
  }

  // 其他未使用的回调方法
  @override
  void onWindowFocus() {}
  @override
  void onWindowBlur() {}
  @override
  void onWindowMaximize() {}
  @override
  void onWindowUnmaximize() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowRestore() {}
  @override
  void onWindowResize() {}
  @override
  void onWindowMove() {}
  @override
  void onWindowEnterFullScreen() {}
  @override
  void onWindowLeaveFullScreen() {}
}

// 系统托盘监听器
class _TrayManagerListener implements TrayListener {
  @override
  void onTrayIconMouseDown() async {
    // 点击托盘图标显示窗口
    await windowManager.show();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await windowManager.show();
        break;
      case 'exit_app':
        // 退出应用前的清理工作
        PlayService.instance.close();
        await savePlaylists();
        await saveLyricSources();
        await AppSettings.instance.saveSettings();
        await AppPreference.instance.save();
        await HotkeysHelper.unregisterAll();
        await windowManager.setPreventClose(false);
        await windowManager.close();
        exit(0);
        break;
    }
  }

  // 其他未使用的回调方法
  @override
  void onTrayIconMouseUp() {}
  @override
  void onTrayIconRightMouseDown() {}
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

  // 初始化MediaKit播放器
  MediaKit.ensureInitialized();

  await RustLib.init();

  initRustLogger().listen((msg) {
    LOGGER.i("[rs]: $msg");
  });

  // For hot reload, `unregisterAll()` needs to be called.
  await HotkeysHelper.unregisterAll();
  HotkeysHelper.registerHotKeys();

  await migrateAppData();

  final supportPath = (await getAppDataDir()).path;
  if (File(PlatformHelper.joinPaths([supportPath, "settings.json"]))
      .existsSync()) {
    await AppSettings.readFromJson();

    await CloudCacheManager.init();

    // 初始化平台特定依赖管理
    await PlatformDependencyManager.instance.initialize();

    // 确保设置的播放器引擎受当前平台支持
    final dependencyManager = PlatformDependencyManager.instance;
    if (AppSettings.instance.playerEngineType != null &&
        !dependencyManager
            .isPlayerEngineSupported(AppSettings.instance.playerEngineType!)) {
      // 如果当前设置的引擎不支持，则使用推荐的引擎
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
  final welcome =
      !File(PlatformHelper.joinPaths([supportPath, "index.json"])).existsSync();

  await initWindow();

  // 初始化最近播放服务
  await RecentPlayService.instance.load();

  final cloudServiceManager = CloudServiceManager();

  runApp(App(welcome: welcome, cloudServiceManager: cloudServiceManager));
}
