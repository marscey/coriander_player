import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:coriander_player/main.dart' as app;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// iOS 移动端适配集成测试
/// 验证：底部导航栏、Mini播放器、桌面端UI隐藏、导航切换
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 确保 app data 目录存在，并创建必要的空数据文件
  Future<void> ensureAppDataExists() async {
    final docDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docDir.path, 'coriander_player'));
    if (!appDir.existsSync()) {
      appDir.createSync(recursive: true);
    }

    // 创建空的 index.json（版本 110，无文件夹）
    final indexFile = File(p.join(appDir.path, 'index.json'));
    if (!indexFile.existsSync()) {
      indexFile.writeAsStringSync('{"version": 110, "folders": []}');
    }

    // 创建空的 playlists.json（数组格式）
    final playlistsFile = File(p.join(appDir.path, 'playlists.json'));
    if (!playlistsFile.existsSync()) {
      playlistsFile.writeAsStringSync('[]');
    }

    // 创建空的 lyric_source.json
    final lyricSourceFile = File(p.join(appDir.path, 'lyric_source.json'));
    if (!lyricSourceFile.existsSync()) {
      lyricSourceFile.writeAsStringSync('{}');
    }

    // 创建基本的 settings.json（使用 MediaKit 引擎）
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

    // 创建空的 app_preference.json
    final prefFile = File(p.join(appDir.path, 'app_preference.json'));
    if (!prefFile.existsSync()) {
      prefFile.writeAsStringSync('{}');
    }
  }

  testWidgets('iOS 移动端完整适配测试', (tester) async {
    // 准备测试数据
    await ensureAppDataExists();

    app.main();

    // 等待应用初始化和索引更新完成，然后进入主页面
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // 先截图看当前页面状态
    await binding.takeScreenshot('00-after-init');

    // #1 应用启动后应显示音乐库页面
    // 使用 findsWidgets 因为"音乐库"可能出现在导航栏和页面标题中
    expect(find.text('音乐库'), findsWidgets, reason: '应显示"音乐库"');

    // #2 底部导航栏存在
    final navBarFinder = find.byType(NavigationBar);
    expect(navBarFinder, findsOneWidget, reason: '移动端应使用NavigationBar作为底部导航');

    // #3 底部导航栏有5个正确项
    final navBar = tester.widget<NavigationBar>(navBarFinder);
    final labels = navBar.destinations
        .map((d) => (d as NavigationDestination).label)
        .toList();
    expect(labels, containsAll(['音乐库', '最近播放', '连接', '搜索', '设置']));
    expect(labels, isNot(contains('本地')), reason: '"本地"不应出现在底部导航栏中');

    await binding.takeScreenshot('01-initial-launch');

    // #4 不显示桌面端窗口控制按钮
    expect(find.text('全屏'), findsNothing, reason: '移动端不应显示全屏按钮');
    expect(find.text('最小化'), findsNothing, reason: '移动端不应显示最小化按钮');
    expect(find.text('关闭'), findsNothing, reason: '移动端不应显示关闭按钮');

    // #5 Mini 播放器可见
    expect(find.text('Coriander Player'), findsOneWidget,
        reason: 'Mini播放器应显示应用名称');

    // #6 导航切换 - 最近播放
    await tester.tap(find.text('最近播放').last);
    await tester.pumpAndSettle();
    expect(find.text('最近播放'), findsWidgets);
    await binding.takeScreenshot('02-nav-recent-plays');

    // #7 导航切换 - 连接（云服务）
    await tester.tap(find.text('连接').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // 云服务页面可能显示"云服务连接"标题或"暂无云服务连接"空状态
    final hasCloudTitle = find.text('云服务连接').evaluate().isNotEmpty ||
        find.text('暂无云服务连接').evaluate().isNotEmpty;
    expect(hasCloudTitle, isTrue, reason: '点击"连接"应跳转到云服务连接页面');
    await binding.takeScreenshot('03-nav-cloud-connection');

    // #8 导航切换 - 搜索
    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    expect(find.text('搜索'), findsWidgets);
    await binding.takeScreenshot('04-nav-search');

    // #9 导航切换 - 设置
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    await binding.takeScreenshot('05-nav-settings');

    // #10 回到音乐库最终验证
    await tester.tap(find.text('音乐库').first);
    await tester.pumpAndSettle();
    expect(find.text('音乐库'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Coriander Player'), findsOneWidget);
    await binding.takeScreenshot('10-final-full-layout');
  });
}
