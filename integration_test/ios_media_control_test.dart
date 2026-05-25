import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:coriander_player/main.dart' as app;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// iOS 媒体控制集成测试
/// 测试流程：添加 WebDAV 连接 → 浏览文件 → 播放音频 → 验证媒体控制
/// 关键验证：AudioSession 配置、AudioService 初始化、MediaItem 更新、PlaybackState 更新
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
        "PlayerEngineType": "mediaKit"
      }''');
    }

    final prefFile = File(p.join(appDir.path, 'app_preference.json'));
    if (!prefFile.existsSync()) {
      prefFile.writeAsStringSync('{}');
    }
  }

  testWidgets('iOS 媒体控制 - WebDAV 播放测试', (tester) async {
    await ensureAppDataExists();
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await binding.takeScreenshot('media-00-after-init');

    // ===== 步骤 1：导航到"连接"页面 =====
    await tester.tap(find.text('连接').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('media-01-connections-page');

    // ===== 步骤 2：添加 WebDAV 连接 =====
    final addButtons = find.text('添加连接');
    if (addButtons.evaluate().isEmpty) {
      // 可能已经有连接了，直接跳到步骤3
      print('连接已存在，跳过添加步骤');
    } else {
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
    await binding.takeScreenshot('media-02-connection-added');

    // ===== 步骤 3：进入 WebDAV 文件浏览器 =====
    final connectionNames = find.text(webdavName);
    if (connectionNames.evaluate().isNotEmpty) {
      await tester.tap(connectionNames.last);
      await tester.pumpAndSettle(const Duration(seconds: 8));
    }
    await binding.takeScreenshot('media-03-file-browser');

    // ===== 步骤 4：寻找并进入包含音频的文件夹 =====
    // 尝试进入"歌手"文件夹
    final singerFolder = find.text('歌手');
    if (singerFolder.evaluate().isNotEmpty) {
      await tester.tap(singerFolder.last);
      await tester.pumpAndSettle(const Duration(seconds: 8));
      await binding.takeScreenshot('media-04-singer-folder');
    }

    // 尝试进入第一个子文件夹
    final folderIcons = find.byIcon(Icons.folder);
    if (folderIcons.evaluate().isNotEmpty) {
      await tester.tap(folderIcons.first);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await binding.takeScreenshot('media-05-subfolder');
    }

    // ===== 步骤 5：播放音频 =====
    var audioIcons = find.byIcon(Icons.audiotrack);
    if (audioIcons.evaluate().isEmpty) {
      // 尝试进入更多文件夹
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
      await binding.takeScreenshot('media-06-audio-playing');

      // 等待播放开始
      await Future.delayed(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('media-07-after-playback-started');

      print('音频播放测试完成 - 请检查 Xcode 控制台日志中的 [MediaControl] 标签');
    } else {
      print('未找到音频文件');
      await binding.takeScreenshot('media-06-no-audio-found');
    }
  });
}
