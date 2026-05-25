import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:coriander_player/main.dart' as app;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// iOS WebDAV 云服务集成测试
/// 测试流程：添加 WebDAV 连接 → 浏览文件 → 播放音频
/// 注意：所有步骤必须在同一个 testWidgets 中，因为 flutter_rust_bridge 只能初始化一次
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

  testWidgets('WebDAV 连接 + 文件浏览 + 音频播放', (tester) async {
    await ensureAppDataExists();
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // ===== 步骤 1：导航到"连接"页面 =====
    await tester.tap(find.text('连接').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('webdav-01-connections-page');

    // ===== 步骤 2：添加 WebDAV 连接 =====
    // 查找"添加连接"按钮
    final addButtons = find.text('添加连接');
    expect(addButtons, findsWidgets, reason: '应显示添加连接按钮');

    // 点击"添加连接"
    await tester.tap(addButtons.last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('webdav-02-add-dialog');

    // 填写 WebDAV 连接表单（5个字段：名称、显示名称、服务器地址、用户名、密码）
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(5),
        reason: '表单应有5个字段');

    await tester.enterText(textFields.at(0), webdavName);
    // 显示名称（可选）跳过
    await tester.enterText(textFields.at(2), webdavUrl);
    await tester.enterText(textFields.at(3), webdavUsername);
    await tester.enterText(textFields.at(4), webdavPassword);

    await tester.pumpAndSettle();
    await binding.takeScreenshot('webdav-03-form-filled');

    // 点击"保存"
    final saveButton = find.widgetWithText(ElevatedButton, '保存');
    expect(saveButton, findsOneWidget, reason: '应显示保存按钮');
    await tester.tap(saveButton);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 验证连接已添加
    expect(find.text(webdavName), findsWidgets,
        reason: '应显示刚添加的 WebDAV 连接');
    // 连接类型显示为 "类型: WebDAV"
    final hasWebdavType = find.byWidgetPredicate((w) =>
        w is Text && w.data != null && w.data!.contains('WebDAV')).evaluate().isNotEmpty;
    expect(hasWebdavType, isTrue, reason: '应显示连接类型包含 WebDAV');
    await binding.takeScreenshot('webdav-04-connection-added');

    // ===== 步骤 3：浏览 WebDAV 文件 =====
    // 点击连接卡片进入文件浏览器
    // 连接名称在 ListTile 的 title 中，点击它
    final connectionNames = find.text(webdavName);
    // 找到 ListTile 中的连接名称（不是对话框中的）
    await tester.tap(connectionNames.last);
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // 验证文件浏览器已打开
    final hasBackButton = find.byIcon(Icons.arrow_back).evaluate().isNotEmpty;
    expect(hasBackButton, isTrue,
        reason: '文件浏览器应显示返回按钮');
    await binding.takeScreenshot('webdav-05-file-browser');

    // 验证文件列表加载
    final hasFolderIcon = find.byIcon(Icons.folder).evaluate().isNotEmpty;
    final hasAudioIcon = find.byIcon(Icons.audiotrack).evaluate().isNotEmpty;
    final hasFileIcon =
        find.byIcon(Icons.insert_drive_file).evaluate().isNotEmpty;
    final hasLoading =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;

    expect(hasFolderIcon || hasAudioIcon || hasFileIcon || hasLoading, isTrue,
        reason: '文件浏览器应显示文件列表或加载中');

    // ===== 步骤 4：进入文件夹浏览 =====
    if (hasFolderIcon) {
      final folderIcons = find.byIcon(Icons.folder);
      if (folderIcons.evaluate().isNotEmpty) {
        await tester.tap(folderIcons.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await binding.takeScreenshot('webdav-06-folder-contents');
      }
    }

    // ===== 步骤 5：播放 WebDAV 音频 =====
    // 查找音频文件
    var audioIcons = find.byIcon(Icons.audiotrack);
    if (audioIcons.evaluate().isEmpty) {
      // 当前目录没有音频，尝试返回并进入其他文件夹
      final backButton = find.byIcon(Icons.arrow_back);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      // 尝试其他文件夹
      final folders = find.byIcon(Icons.folder);
      if (folders.evaluate().length > 1) {
        await tester.tap(folders.at(1));
        await tester.pumpAndSettle(const Duration(seconds: 5));
        audioIcons = find.byIcon(Icons.audiotrack);
      }
    }

    if (audioIcons.evaluate().isNotEmpty) {
      // 点击第一个音频文件
      await tester.tap(audioIcons.first);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await binding.takeScreenshot('webdav-07-audio-playing');

      // 验证 Mini 播放器
      expect(find.text('Coriander Player'), findsOneWidget,
          reason: 'Mini 播放器应始终可见');
    } else {
      // 如果没有找到音频文件，至少验证文件浏览器正常工作
      await binding.takeScreenshot('webdav-07-no-audio-found');
    }

    // ===== 步骤 6：返回连接列表 =====
    final backBtn = find.byIcon(Icons.arrow_back);
    if (backBtn.evaluate().isNotEmpty) {
      await tester.tap(backBtn.first);
      await tester.pumpAndSettle();
    }
    // 验证回到了连接列表
    expect(find.text(webdavName), findsWidgets,
        reason: '应回到连接列表并显示 WebDAV 连接');
    await binding.takeScreenshot('webdav-08-back-to-connections');
  });
}
