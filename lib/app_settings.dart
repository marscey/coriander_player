import 'dart:convert';
import 'dart:io';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:flutter/material.dart';
import 'package:github/github.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

/// 把旧的 app data 目录（如果存在）移到新的目录
/// 只在新 app data 目录没有数据时进行
/// 从 C:\Users\$username\AppData\Roaming\com.example\coriander_player 移到 C:\Users\$username\Documents\coriander_player
Future<void> migrateAppData() async {
  try {
    final newAppDataDir = await getAppDataDir();
    if (newAppDataDir.listSync().isNotEmpty) return;

    final oldAppDataDir = await getApplicationSupportDirectory();

    if (oldAppDataDir.existsSync()) {
      final datas = oldAppDataDir.listSync();
      for (var item in datas) {
        final oldDataFile = File(item.path);
        oldDataFile.copySync(
          path.join(newAppDataDir.path, path.basename(item.path)),
        );
      }
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

Future<Directory> getAppDataDir() async {
  final dir = await getApplicationDocumentsDirectory();
  return Directory(path.join(dir.path, "coriander_player"))
      .create(recursive: true);
}

class AppSettings {
  static final github = GitHub();
  static const String version = "1.8.0";

  /// 主题模式：亮 / 暗
  ThemeMode themeMode = getWindowsThemeMode();

  /// 启动时 / 封面主题色不适合当主题时的主题
  int defaultTheme = getWindowsTheme();

  /// 跟随歌曲封面的动态主题
  bool dynamicTheme = true;

  /// 跟随系统主题色
  bool useSystemTheme = true;

  /// 跟随系统主题模式
  bool useSystemThemeMode = true;

  List artistSeparator = ["/", "、"];

  /// 歌词来源：true，本地优先；false，在线优先
  bool localLyricFirst = true;
  Size windowSize = const Size(1280, 756);
  bool isWindowMaximized = false;

  String? fontFamily;
  String? fontPath;

  // 播放器引擎类型
  PlayerEngineType? playerEngineType;

  /// iOS 蓝牙歌词：将歌词绘制到封面图上，通过 AVRCP 传给蓝牙设备
  bool bluetoothLyric = true;

  /// 关闭主窗口时最小化到托盘（true）或退出程序（false）
  bool closeToTray = true;

  /// 是否已提示过"已最小化到托盘"
  bool hasShownTrayTip = false;

  /// 云音频缓存容量上限（MB），-1 表示无限制，默认 2048MB (2GB)
  int cloudCacheMaxSizeMB = 2048;

  late String artistSplitPattern = artistSeparator.join("|");

  static final AppSettings _instance = AppSettings._();

  static AppSettings get instance => _instance;

  static ThemeMode getWindowsThemeMode() {
    if (PlatformHelper.isMacOS) {
      // macOS平台使用平台助手提供的方法获取系统主题模式
      return PlatformHelper.getSystemThemeMode();
    }

    final systemTheme = SystemTheme.getSystemTheme();

    final isDarkMode = (((5 * systemTheme.fore.$3) +
            (2 * systemTheme.fore.$2) +
            systemTheme.fore.$4) >
        (8 * 128));
    return isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  static int getWindowsTheme() {
    if (PlatformHelper.isMacOS) {
      // macOS平台使用平台助手提供的默认主题色
      return PlatformHelper.getDefaultSystemThemeColor();
    }

    final systemTheme = SystemTheme.getSystemTheme();
    return Color.fromARGB(
      systemTheme.accent.$1,
      systemTheme.accent.$2,
      systemTheme.accent.$3,
      systemTheme.accent.$4,
    ).value;
  }

  AppSettings._();

  static Future<void> _readFromJson_old(Map settingsMap) async {
    final ust = settingsMap["UseSystemTheme"];
    if (ust != null) {
      _instance.useSystemTheme = ust == 1 ? true : false;
    }

    final ustm = settingsMap["UseSystemThemeMode"];
    if (ustm != null) {
      _instance.useSystemThemeMode = ustm == 1 ? true : false;
    }

    if (!_instance.useSystemTheme) {
      _instance.defaultTheme = settingsMap["DefaultTheme"];
    }
    if (!_instance.useSystemThemeMode) {
      _instance.themeMode =
          settingsMap["ThemeMode"] == 0 ? ThemeMode.light : ThemeMode.dark;
    }

    _instance.dynamicTheme = settingsMap["DynamicTheme"] == 1 ? true : false;
    _instance.artistSeparator = settingsMap["ArtistSeparator"];
    _instance.artistSplitPattern = _instance.artistSeparator.join("|");

    final llf = settingsMap["LocalLyricFirst"];
    if (llf != null) {
      _instance.localLyricFirst = llf == 1 ? true : false;
    }

    final sizeStr = settingsMap["WindowSize"];
    if (sizeStr != null) {
      final sizeStrs = (sizeStr as String).split(",");
      _instance.windowSize = Size(double.tryParse(sizeStrs[0]) ?? 1280,
          double.tryParse(sizeStrs[1]) ?? 756);
    }

    final isMaximized = settingsMap["IsWindowMaximized"];
    if (isMaximized != null) {
      _instance.isWindowMaximized = isMaximized == 1;
    }
  }

  static Future<void> readFromJson() async {
    try {
      final supportPath = (await getAppDataDir()).path;
      final settingsPath =
          PlatformHelper.joinPaths([supportPath, "settings.json"]);

      final settingsStr = File(settingsPath).readAsStringSync();
      Map settingsMap = json.decode(settingsStr);

      if (settingsMap["Version"] == null) {
        return _readFromJson_old(settingsMap);
      }

      final ust = settingsMap["UseSystemTheme"];
      if (ust != null) {
        _instance.useSystemTheme = ust;
      }

      final ustm = settingsMap["UseSystemThemeMode"];
      if (ustm != null) {
        _instance.useSystemThemeMode = ustm;
      }

      if (!_instance.useSystemTheme) {
        _instance.defaultTheme = settingsMap["DefaultTheme"];
      }
      if (!_instance.useSystemThemeMode) {
        _instance.themeMode = (settingsMap["ThemeMode"] ?? false)
            ? ThemeMode.dark
            : ThemeMode.light;
      }

      final dt = settingsMap["DynamicTheme"];
      if (dt != null) {
        _instance.dynamicTheme = dt;
      }

      final as = settingsMap["ArtistSeparator"];
      if (as != null) {
        _instance.artistSeparator = as;
        _instance.artistSplitPattern = _instance.artistSeparator.join("|");
      }

      final llf = settingsMap["LocalLyricFirst"];
      if (llf != null) {
        _instance.localLyricFirst = llf;
      }

      final sizeStr = settingsMap["WindowSize"];
      if (sizeStr != null) {
        final sizeStrs = (sizeStr as String).split(",");
        _instance.windowSize = Size(double.tryParse(sizeStrs[0]) ?? 1280,
            double.tryParse(sizeStrs[1]) ?? 756);
      }

      final isMaximized = settingsMap["IsWindowMaximized"];
      if (isMaximized != null) {
        _instance.isWindowMaximized = isMaximized;
      }

      final ff = settingsMap["FontFamily"];
      final fp = settingsMap["FontPath"];
      if (ff != null) {
        _instance.fontFamily = ff;
        _instance.fontPath = fp;
      }

      // 读取播放器引擎类型配置
      final pet = settingsMap["PlayerEngineType"];
      if (pet != null) {
        try {
          _instance.playerEngineType = PlayerEngineType.values.byName(pet);
        } catch (e) {
          // 如果配置的值无效，保持默认值
        }
      }

      // 读取蓝牙歌词配置
      final bl = settingsMap["BluetoothLyric"];
      if (bl != null) {
        _instance.bluetoothLyric = bl;
      }

      // 读取关闭行为配置
      final ctt = settingsMap["CloseToTray"];
      if (ctt != null) {
        _instance.closeToTray = ctt;
      }

      final hst = settingsMap["HasShownTrayTip"];
      if (hst != null) {
        _instance.hasShownTrayTip = hst;
      }

      final ccms = settingsMap["CloudCacheMaxSizeMB"];
      if (ccms != null) {
        _instance.cloudCacheMaxSizeMB = ccms;
      }
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }

  Future<void> saveSettings() async {
    try {
      bool isMaximized = false;
      bool isFullScreen = false;
      Size currentSize = windowSize;

      if (PlatformHelper.isDesktop) {
        isMaximized = await windowManager.isMaximized();
        isFullScreen = await windowManager.isFullScreen();
        if (!isMaximized && !isFullScreen) {
          currentSize = await windowManager.getSize();
        }
      }

      final settingsMap = {
        "Version": version,
        "ThemeMode": themeMode == ThemeMode.dark,
        "DynamicTheme": dynamicTheme,
        "UseSystemTheme": useSystemTheme,
        "UseSystemThemeMode": useSystemThemeMode,
        "DefaultTheme": defaultTheme,
        "ArtistSeparator": artistSeparator,
        "LocalLyricFirst": localLyricFirst,
        "IsWindowMaximized": isMaximized,
        "FontFamily": fontFamily,
        "FontPath": fontPath,
        "PlayerEngineType": playerEngineType?.name,
        "BluetoothLyric": bluetoothLyric,
        "CloseToTray": closeToTray,
        "HasShownTrayTip": hasShownTrayTip,
        "CloudCacheMaxSizeMB": cloudCacheMaxSizeMB,
      };

      // 只有桌面端保存窗口尺寸
      if (PlatformHelper.isDesktop) {
        settingsMap["WindowSize"] =
            "${currentSize.width.toStringAsFixed(1)},${currentSize.height.toStringAsFixed(1)}";
      }

      final settingsStr = json.encode(settingsMap);
      final supportPath = (await getAppDataDir()).path;
      final settingsPath =
          PlatformHelper.joinPaths([supportPath, "settings.json"]);
      final output = await File(settingsPath).create(recursive: true);
      output.writeAsStringSync(settingsStr);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }
}
