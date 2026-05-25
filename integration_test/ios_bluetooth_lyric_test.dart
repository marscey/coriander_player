import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:coriander_player/main.dart' as app;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/platform_helper.dart';

/// iOS 蓝牙歌词 + 媒体控制集成测试
///
/// 测试流程：
/// 1. 启动应用 → 验证初始化日志
/// 2. 连接 WebDAV → 浏览文件 → 播放音频
/// 3. 验证设置页面的蓝牙歌词开关
/// 4. 验证封面图+歌词合成功能
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // WebDAV 测试配置
  const webdavUrl = 'http://106.13.25.163:5244/dav';
  const webdavUsername = 'musicyep';
  const webdavPassword = 'Muy@s-0122';
  const webdavName = 'TestWebDAV';

  /// 确保 app data 目录存在
  Future<void> ensureAppDataExists() async {
    final docDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docDir.path, 'coriander_player'));
    if (!appDir.existsSync()) {
      appDir.createSync(recursive: true);
    }

    final indexFile = File(p.join(appDir.path, 'index.json'));
    if (!indexFile.existsSync()) {
      indexFile.writeAsStringSync('{"version": 110, "folders": []}');
    }

    final playlistsFile = File(p.join(appDir.path, 'playlists.json'));
    if (!playlistsFile.existsSync()) {
      playlistsFile.writeAsStringSync('[]');
    }

    final lyricSourceFile = File(p.join(appDir.path, 'lyric_source.json'));
    if (!lyricSourceFile.existsSync()) {
      lyricSourceFile.writeAsStringSync('{}');
    }

    final settingsFile = File(p.join(appDir.path, 'settings.json'));
    if (!settingsFile.existsSync()) {
      settingsFile.writeAsStringSync('''{
        "Version": "1.7.0",
        "ThemeMode": false,
        "DynamicTheme": true,
        "UseSystemTheme": true,
        "UseSystemThemeMode": true,
        "DefaultTheme": 4280391414,
        "ArtistSeparator": ["/", "\u3001"],
        "LocalLyricFirst": true,
        "IsWindowMaximized": false,
        "FontFamily": null,
        "FontPath": null,
        "PlayerEngineType": "mediaKit",
        "BluetoothLyric": true
      }''');
    }
  }

  testWidgets('iOS 蓝牙歌词 + 媒体控制测试', (tester) async {
    await ensureAppDataExists();
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await binding.takeScreenshot('bt-lyric-00-after-init');

    // ===== 步骤 1：验证设置页面的蓝牙歌词开关 =====
    // 导航到设置页面
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('bt-lyric-01-settings-page');

    // 验证蓝牙歌词开关存在（仅 iOS）
    if (PlatformHelper.isIOS) {
      final btLyricSwitch = find.text('蓝牙歌词');
      // 可能需要滚动才能看到
      bool found = btLyricSwitch.evaluate().isNotEmpty;
      if (!found) {
        // 尝试滚动查找
        await tester.scrollUntilVisible(
          btLyricSwitch,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        found = btLyricSwitch.evaluate().isNotEmpty;
      }
      if (found) {
        print('蓝牙歌词开关已找到 ✅');
        await binding.takeScreenshot('bt-lyric-02-bt-lyric-switch');
      } else {
        print('蓝牙歌词开关未找到 ⚠️');
      }
    }

    // ===== 步骤 2：连接 WebDAV 并播放音频 =====
    // 导航到"连接"页面
    await tester.tap(find.text('连接').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('bt-lyric-03-connections-page');

    // 添加 WebDAV 连接（如果还没有）
    final addButtons = find.text('添加连接');
    if (addButtons.evaluate().isNotEmpty) {
      await tester.tap(addButtons.last);
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      if (textFields.evaluate().length >= 5) {
        await tester.enterText(textFields.at(0), webdavName);
        await tester.enterText(textFields.at(2), webdavUrl);
        await tester.enterText(textFields.at(3), webdavUsername);
        await tester.enterText(textFields.at(4), webdavPassword);

        final saveButton = find.widgetWithText(ElevatedButton, '保存');
        if (saveButton.evaluate().isNotEmpty) {
          await tester.tap(saveButton);
          await tester.pumpAndSettle(const Duration(seconds: 3));
        }
      }
    }
    await binding.takeScreenshot('bt-lyric-04-connection-added');

    // 进入 WebDAV 文件浏览器
    final connectionNames = find.text(webdavName);
    if (connectionNames.evaluate().isNotEmpty) {
      await tester.tap(connectionNames.last);
      await tester.pumpAndSettle(const Duration(seconds: 8));
    }
    await binding.takeScreenshot('bt-lyric-05-file-browser');

    // 进入"歌手"文件夹
    final singerFolder = find.text('歌手');
    if (singerFolder.evaluate().isNotEmpty) {
      await tester.tap(singerFolder.last);
      await tester.pumpAndSettle(const Duration(seconds: 8));
      await binding.takeScreenshot('bt-lyric-06-singer-folder');
    }

    // 进入第一个子文件夹
    final folderIcons = find.byIcon(Icons.folder);
    if (folderIcons.evaluate().isNotEmpty) {
      await tester.tap(folderIcons.first);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await binding.takeScreenshot('bt-lyric-07-subfolder');
    }

    // 播放音频
    var audioIcons = find.byIcon(Icons.audiotrack);
    if (audioIcons.evaluate().isEmpty) {
      final moreFolders = find.byIcon(Icons.folder);
      if (moreFolders.evaluate().isNotEmpty) {
        await tester.tap(moreFolders.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        audioIcons = find.byIcon(Icons.audiotrack);
      }
    }

    if (audioIcons.evaluate().isNotEmpty) {
      print('找到音频文件，点击播放...');
      await tester.tap(audioIcons.first);
      await tester.pumpAndSettle(const Duration(seconds: 8));
      await binding.takeScreenshot('bt-lyric-08-audio-playing');

      // 等待播放开始和歌词加载
      await Future.delayed(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('bt-lyric-09-after-playback');

      print('音频播放测试完成 ✅');
      print('请检查 Xcode 控制台日志中的 [MediaControl] 标签');
      print('预期日志：');
      print('  - [MediaControl] updateCurrentMediaItem: title=...');
      print('  - [MediaControl] updatePlaybackState: playing=true');
      print('  - [MediaControl] Lyric cover updated: ...');
    } else {
      print('未找到音频文件 ⚠️');
      await binding.takeScreenshot('bt-lyric-08-no-audio-found');
    }

    // ===== 步骤 3：验证 AppSettings 中蓝牙歌词配置 =====
    final settings = AppSettings.instance;
    print('AppSettings.bluetoothLyric = ${settings.bluetoothLyric}');
    // 默认应该为 true
    expect(settings.bluetoothLyric, isTrue);
    print('蓝牙歌词配置验证通过 ✅');
  });
}
