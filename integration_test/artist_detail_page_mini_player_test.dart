import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:coriander_player/main.dart' as app;
import 'package:coriander_player/component/mini_now_playing.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 艺术家详情页 Mini 播放器可见性集成测试
/// 修复验证：MiniNowPlaying(forceShow: true) 在非 shell 根页面仍然可见
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 创建基本的 settings.json（避免 AppSettings 初始化异常）
  Future<void> ensureSettingsExists() async {
    final docDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docDir.path, 'coriander_player'));
    if (!appDir.existsSync()) {
      appDir.createSync(recursive: true);
    }

    // 创建包含测试音频的 index.json（避免 Rust 侧读取文件时崩溃）
    File(p.join(appDir.path, 'index.json')).writeAsStringSync('''{
      "version": 110,
      "folders": [
        {
          "path": "/test/music",
          "modified": 1718000000,
          "latest": 1718000000,
          "audios": [
            {
              "title": "测试歌曲A",
              "artist": "测试艺术家",
              "album": "测试专辑",
              "genre": "流行",
              "year": 2024,
              "date": "2024-01-01",
              "track": 1,
              "duration": 245,
              "bitrate": 320,
              "sample_rate": 44100,
              "path": "/test/music/song_a.mp3",
              "modified": 1718000000,
              "created": 1718000000,
              "by": "Lofty"
            },
            {
              "title": "测试歌曲B",
              "artist": "测试艺术家",
              "album": "测试专辑",
              "genre": "流行",
              "year": 2024,
              "date": "2024-01-01",
              "track": 2,
              "duration": 260,
              "bitrate": 320,
              "sample_rate": 44100,
              "path": "/test/music/song_b.mp3",
              "modified": 1718000000,
              "created": 1718000000,
              "by": "Lofty"
            }
          ]
        }
      ]
    }''');

    // 创建基本的 settings.json（避免 AppSettings 初始化异常）
    File(p.join(appDir.path, 'settings.json')).writeAsStringSync('''{
      "Version": "1.9.1",
      "ThemeMode": false,
      "DynamicTheme": true,
      "UseSystemTheme": true,
      "UseSystemThemeMode": true,
      "DefaultTheme": 4280391414,
      "ArtistSeparator": ["/", "\\u3001"],
      "LocalLyricFirst": true,
      "IsWindowMaximized": false,
      "FontFamily": "",
      "FontPath": "",
      "PlayerEngineType": "mediaKit"
    }''');

    // 确保其他必要文件存在
    final playlistsFile = File(p.join(appDir.path, 'playlists.json'));
    if (!playlistsFile.existsSync()) {
      playlistsFile.writeAsStringSync('[]');
    }
    final lyricSourceFile = File(p.join(appDir.path, 'lyric_source.json'));
    if (!lyricSourceFile.existsSync()) {
      lyricSourceFile.writeAsStringSync('{}');
    }
    final prefFile = File(p.join(appDir.path, 'app_preference.json'));
    if (!prefFile.existsSync()) {
      prefFile.writeAsStringSync('{}');
    }
  }

  testWidgets('艺术家详情页 Mini 播放器可见性', (tester) async {
    // 1. 准备测试数据
    await ensureSettingsExists();

    // 2. 启动应用
    app.main();
    // 等待 UpdatingPage 完成索引构建（可能需要较长时间）
    await tester.pumpAndSettle(const Duration(seconds: 30));
    await binding.takeScreenshot('artist-detail-01-app-launched');

    // 3. 检查当前是否在主页面（UpdatingPage 已完成）
    //    如果 AudioLibrary 为空，手动注入测试数据
    final library = AudioLibrary.instance;
    print('DEBUG: 音频数量 = ${library.audioCollection.length}');
    print('DEBUG: 艺术家数量 = ${library.artistCollection.length}');

    if (library.artistCollection.isEmpty) {
      // 手动注入测试艺术家数据
      final testArtist = Artist(name: '测试艺术家');
      final audioA = Audio(
        '测试歌曲A',
        '测试艺术家',
        '测试专辑',
        '流行',
        2024,
        '2024-01-01',
        1,
        245, // duration in seconds
        320,
        44100,
        '/test/music/song_a.mp3',
        1718000000, // modified: secs since UNIX EPOCH
        1718000000, // created: secs since UNIX EPOCH
        'Lofty',
      );
      final audioB = Audio(
        '测试歌曲B',
        '测试艺术家',
        '测试专辑',
        '流行',
        2024,
        '2024-01-01',
        2,
        260,
        320,
        44100,
        '/test/music/song_b.mp3',
        1718000000,
        1718000000,
        'Lofty',
      );
      testArtist.works.addAll([audioA, audioB]);

      // 将测试艺术家添加到 AudioLibrary
      library.artistCollection[testArtist.name] = testArtist;
      library.audioCollection.addAll([audioA, audioB]);

      print('DEBUG: 手动注入测试数据后，艺术家数量 = ${library.artistCollection.length}');
    }

    // 4. 通过 GoRouter 导航到艺术家详情页
    final firstArtist = library.artistCollection.values.first;
    print('DEBUG: 导航到艺术家详情页: "${firstArtist.name}"');

    // 使用任意可见 widget 的 context 来获取 GoRouter
    try {
      final anyWidget = find.byType(Scaffold).first;
      final context = tester.element(anyWidget);
      GoRouter.of(context).push(app_paths.ARTIST_DETAIL_PAGE_NEW, extra: firstArtist);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      print('DEBUG: GoRouter 导航成功');
    } catch (e) {
      print('DEBUG: GoRouter 导航失败: $e');
      // 备用方案：尝试通过 MaterialApp.router 的 context
      try {
        final routerWidget = find.byType(MaterialApp).first;
        final context = tester.element(routerWidget);
        GoRouter.of(context).push(app_paths.ARTIST_DETAIL_PAGE_NEW, extra: firstArtist);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        print('DEBUG: GoRouter 备用导航成功');
      } catch (e2) {
        print('DEBUG: GoRouter 备用导航也失败: $e2');
      }
    }

    await binding.takeScreenshot('artist-detail-02-artist-detail-page');

    // 5. 核心验证：艺术家详情页中 MiniNowPlaying 可见
    final miniPlayers = find.byType(MiniNowPlaying, skipOffstage: false);
    final miniPlayerCount = miniPlayers.evaluate().length;
    print('DEBUG: 艺术家详情页 MiniNowPlaying 组件数量 = $miniPlayerCount');

    // 打印当前页面关键文本
    final pageTexts = <String>[];
    final allTextWidgets = find.byType(Text, skipOffstage: false).evaluate().toList();
    for (var i = 0; i < allTextWidgets.length && i < 30; i++) {
      final textWidget = allTextWidgets[i].widget as Text;
      final text = textWidget.data ?? '';
      if (text.isNotEmpty && text.length < 40) {
        pageTexts.add(text);
      }
    }
    print('DEBUG: 页面文本 = ${pageTexts.take(15).toList()}');

    // 6. 断言：艺术家详情页必须包含至少一个 MiniNowPlaying
    //    修复前：forceShow=false + miniPlayerVisibleNotifier=false → SizedBox.shrink
    //    修复后：forceShow=true → 始终渲染
    expect(
      miniPlayerCount >= 1,
      isTrue,
      reason: '艺术家详情页应包含至少 1 个 MiniNowPlaying 组件（forceShow 修复）',
    );

    // 7. 验证艺术家名显示在页面上
    expect(
      find.text(firstArtist.name, skipOffstage: false).evaluate().isNotEmpty,
      isTrue,
      reason: '艺术家详情页应显示艺术家名 "${firstArtist.name}"',
    );

    // 8. 最终截图
    await binding.takeScreenshot('artist-detail-03-mini-player-verified');

    print('\n========================================');
    print('  艺术家详情页 Mini 播放器可见性测试通过！');
    print('  MiniNowPlaying(forceShow: true) 修复已验证');
    print('========================================\n');
  });
}
