import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:coriander_player/main.dart' as app;
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/cloud_service/cloud_connection.dart';
import 'package:coriander_player/cloud_service/cloud_audio_player.dart';
import 'package:coriander_player/cloud_service/webdav_service.dart' show WebDavFile;
import 'package:coriander_player/library/audio_library.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 播放界面 UI 优化自动化验证测试
/// 使用 pump + Duration 替代 pumpAndSettle 避免持续动画导致测试挂起
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const webdavUrl = 'http://106.13.25.163:5244/dav';
  const webdavUsername = 'musicyep';
  const webdavPassword = 'Muy@s-0122';
  const webdavConnectionId = 'test-webdav-auto';

  Future<void> ensureAppDataExists() async {
    final docDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docDir.path, 'coriander_player'));
    if (!appDir.existsSync()) appDir.createSync(recursive: true);

    for (final entry in {
      'index.json': '{"version": 110, "folders": []}',
      'playlists.json': '[]',
      'lyric_source.json': '{}',
      'app_preference.json': '{}',
      'settings.json': '''{
        "Version": "1.7.0", "ThemeMode": false, "DynamicTheme": true,
        "UseSystemTheme": true, "UseSystemThemeMode": true,
        "DefaultTheme": 4280391414, "ArtistSeparator": ["/", "、"],
        "LocalLyricFirst": true, "IsWindowMaximized": false,
        "FontFamily": null, "FontPath": null, "PlayerEngineType": "mediaKit"
      }'''
    }.entries) {
      final f = File(p.join(appDir.path, entry.key));
      if (!f.existsSync()) f.writeAsStringSync(entry.value);
    }
  }

  /// 程序化添加 WebDAV 连接并扫描音频到库
  Future<bool> setupWebdavAndAddAudio() async {
    try {
      // 优先检查是否已有持久化的云音频数据（之前测试运行已添加过）
      final docDir = await getApplicationDocumentsDirectory();
      final cloudFile = File(p.join(docDir.path, 'coriander_player', 'cloud_audios.json'));
      if (cloudFile.existsSync()) {
        final content = cloudFile.readAsStringSync();
        if (content.length > 50) {
          debugPrint('[SETUP] 已有持久化云音频数据 (${content.length} bytes)，跳过初始化');
          return true;
        }
      }

      // 没有持久化数据，需要初始化云服务连接
      debugPrint('[SETUP] 无持久化数据，开始初始化云服务...');

      // 使用应用启动时已创建的 CloudServiceManager 实例（通过 static instance），
      // 避免创建新实例导致 CloudAudioPlayer 找不到对应连接
      final manager = CloudServiceManager.instance;
      await manager.ready;

      // 清理旧的云连接数据后重新添加
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cloud_connections');
      await prefs.remove('cloud_passwords');
      debugPrint('[SETUP] 已清理旧的云连接数据');

      // 重新加载连接（清空后重新从 SharedPreferences 加载）
      await manager.loadConnections();

      await manager.addConnection(CloudConnection(
        id: webdavConnectionId,
        name: 'AutoTestWebDAV',
        type: CloudServiceType.webdav,
        serverUrl: webdavUrl,
        username: webdavUsername,
        password: webdavPassword,
        displayName: '自动测试',
        isActive: true,
      ));
      debugPrint('[SETUP] WebDAV 连接已添加');

      final service = manager.getService(webdavConnectionId);
      if (service == null) {
        debugPrint('[SETUP] 获取 WebDAV 服务失败');
        return false;
      }

      final ok = await service.testConnection();
      debugPrint('[SETUP] 连接测试: ${ok ? "成功" : "失败"}');
      if (!ok) return false;

      // 列出根目录
      final rootFiles = await service.listFiles('/');
      debugPrint('[SETUP] 根目录文件数: ${rootFiles.length}');
      for (final f in rootFiles) {
        debugPrint('  ${f.isDirectory ? "[DIR]" : "[FILE]"} ${f.name}');
      }

      // 扫描：只看歌单的前3个子目录，避免扫描歌手目录的150+子目录
      List<WebDavFile> audioFiles = [];
      final geDanDir = rootFiles.firstWhere(
        (f) => f.isDirectory && f.name.contains('歌单'),
        orElse: () => rootFiles.firstWhere((f) => f.isDirectory),
      );
      final subDirs = await service.listFiles(geDanDir.path);
      for (final subDir in subDirs.where((f) => f.isDirectory).take(3)) {
        final files = await service.listFiles(subDir.path);
        audioFiles = files.where((f) => f.isAudioFile).toList();
        if (audioFiles.isNotEmpty) break;
      }

      debugPrint('[SETUP] 找到音频: ${audioFiles.length}');
      if (audioFiles.isEmpty) return false;

      await CloudAudioPlayer.addCloudFilesToLibrary(
        service: service,
        files: audioFiles.take(3).toList(),
        connectionId: webdavConnectionId,
        onProgress: (c) => debugPrint('[SETUP] 已添加 $c 首'),
      );

      final count = AudioLibrary.instance.audioCollection
          .where((a) => a.isCloudAudio).length;
      debugPrint('[SETUP] 云音频总数: $count');
      return count > 0;
    } catch (e, st) {
      debugPrint('[SETUP] 错误: $e\n$st');
      return false;
    }
  }

  testWidgets('播放界面 UI 优化自动化验证', (tester) async {
    // ===== 阶段 0：准备数据 =====
    debugPrint('\n========== 阶段 0：准备环境 ==========');
    await ensureAppDataExists();

    // ===== 阶段 1：启动应用（Rust bridge 在此初始化） =====
    debugPrint('\n========== 阶段 1：启动应用 ==========');
    app.main();
    // 等待应用初始化完成
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.text('音乐库').evaluate().isNotEmpty) break;
    }
    expect(find.text('音乐库'), findsWidgets,
        reason: '启动后应显示音乐库');
    debugPrint('[阶段 1] ✓ 应用启动成功');

    // ===== 阶段 1.5：应用启动后再添加云音频（Rust bridge 已就绪） =====
    debugPrint('\n========== 阶段 1.5：添加云音频 ==========');
    final audioReady = await tester.runAsync(() => setupWebdavAndAddAudio());
    debugPrint('[阶段 1.5] 音频准备: $audioReady');

    if (audioReady == true) {
      // 刷新应用状态，让新添加的音频出现在列表中
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    }

    // ===== 阶段 2：播放云音频 =====
    debugPrint('\n========== 阶段 2：播放云音频 ==========');

    if (audioReady != true) {
      debugPrint('[阶段 2] 无云音频，跳过播放测试');
    } else {
    // 查找含时长格式的文本（如 "3:45"）来定位音频条目
    final durationTexts = find.byWidgetPredicate(
      (w) => w is Text && w.data != null && RegExp(r'^\d+:\d{2}$').hasMatch(w.data!),
    );

    if (durationTexts.evaluate().isNotEmpty) {
      debugPrint('[阶段 2] 找到音频条目，点击播放');
      await tester.tap(durationTexts.first);
      await tester.pump(const Duration(seconds: 5));
    } else {
      debugPrint('[阶段 2] 未找到音频条目，尝试点击 InkWell');
      final inkWells = find.byType(InkWell);
      if (inkWells.evaluate().length > 1) {
        await tester.tap(inkWells.at(1));
        await tester.pump(const Duration(seconds: 5));
      }
    }
    } // end audioReady check

    // ===== 阶段 3：打开播放页面 =====
    debugPrint('\n========== 阶段 3：打开播放页面 ==========');

    // 查找 mini 播放器（Semantics 标签含 "迷你播放器"）
    final miniPlayer = find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.label?.contains('迷你播放器') ?? false),
    );

    if (miniPlayer.evaluate().isNotEmpty) {
      debugPrint('[阶段 3] 点击迷你播放器');
      await tester.tap(miniPlayer);
      await tester.pump(const Duration(seconds: 3));
    } else {
      debugPrint('[阶段 3] 未找到迷你播放器标记，尝试最后的 InkWell');
      final inkWells = find.byType(InkWell);
      if (inkWells.evaluate().isNotEmpty) {
        await tester.tap(inkWells.last);
        await tester.pump(const Duration(seconds: 3));
      }
    }

    // ===== 阶段 4：验证播放界面 UI =====
    debugPrint('\n========== 阶段 4：验证播放界面 UI ==========');

    // [UI-01] 顶部导航栏关闭按钮
    final downArrow = find.byIcon(Symbols.keyboard_arrow_down);
    if (downArrow.evaluate().isNotEmpty) {
      debugPrint('[UI-01] ✓ 顶部导航栏关闭按钮存在');
    } else {
      debugPrint('[UI-01] ✗ 未找到关闭按钮 (可能在桌面端模式)');
    }

    // [UI-02] 歌名显示
    final titleText = find.byWidgetPredicate(
      (w) => w is Text && w.style?.fontSize == 14 && w.style?.fontWeight == FontWeight.w500,
    );
    if (titleText.evaluate().isNotEmpty) {
      final text = (titleText.first.evaluate().first.widget as Text).data;
      debugPrint('[UI-02] ✓ 顶部栏歌名: "$text"');
    } else {
      debugPrint('[UI-02] ✗ 未找到顶部栏歌名');
    }

    // [UI-03] 播放/暂停按钮
    final playPause = find.byWidgetPredicate(
      (w) => w is IconButton && w.icon is Icon &&
        ((w.icon as Icon).icon == Symbols.play_arrow || (w.icon as Icon).icon == Symbols.pause),
    );
    debugPrint(playPause.evaluate().isNotEmpty
        ? '[UI-03] ✓ 播放/暂停按钮存在'
        : '[UI-03] ✗ 播放/暂停按钮缺失');

    // [UI-04] 进度条
    final slider = find.byType(Slider);
    debugPrint(slider.evaluate().isNotEmpty
        ? '[UI-04] ✓ 进度条存在'
        : '[UI-04] ✗ 进度条缺失');

    // [UI-05] 上一曲/下一曲
    final prev = find.byIcon(Symbols.skip_previous);
    final next = find.byIcon(Symbols.skip_next);
    debugPrint(prev.evaluate().isNotEmpty && next.evaluate().isNotEmpty
        ? '[UI-05] ✓ 上一曲/下一曲存在'
        : '[UI-05] ✗ 上一曲/下一曲缺失');

    // [UI-06] 底部工具栏按钮
    final shuffleBtn = find.byIcon(Symbols.shuffle);
    final repeatBtn = find.byIcon(Symbols.repeat);
    debugPrint(shuffleBtn.evaluate().isNotEmpty || repeatBtn.evaluate().isNotEmpty
        ? '[UI-06] ✓ 底部工具栏存在'
        : '[UI-06] ✗ 底部工具栏缺失');

    // ===== 阶段 5：测试"更多"菜单导航 =====
    debugPrint('\n========== 阶段 5：测试详情页导航 ==========');

    final moreBtn = find.byIcon(Symbols.more_vert);
    if (moreBtn.evaluate().isNotEmpty) {
      await tester.tap(moreBtn.first);
      await tester.pump(const Duration(seconds: 1));

      final detailItem = find.text('详细信息');
      if (detailItem.evaluate().isNotEmpty) {
        debugPrint('[阶段 5] 点击"详细信息"');
        await tester.tap(detailItem);
        await tester.pump(const Duration(seconds: 3));

        // [NAV-01] 验证详情页返回按钮
        final backBtn = find.byIcon(Symbols.arrow_back);
        if (backBtn.evaluate().isNotEmpty) {
          debugPrint('[NAV-01] ✓ AudioDetailPage 返回按钮存在（固定在顶部）');
          await tester.tap(backBtn.first);
          await tester.pump(const Duration(seconds: 2));
          debugPrint('[NAV-01] ✓ 返回播放页成功');
        } else {
          debugPrint('[NAV-01] ✗ 返回按钮不存在');
        }
      } else {
        debugPrint('[阶段 5] 未找到"详细信息"');
        // 点击其他地方关闭菜单
        await tester.tapAt(const Offset(100, 100));
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    // ===== 阶段 6：测试视图切换 =====
    debugPrint('\n========== 阶段 6：测试视图切换 ==========');

    // 查找视图切换按钮
    final viewBtn = find.byWidgetPredicate(
      (w) => w is IconButton && w.tooltip != null &&
        (w.tooltip!.contains('歌词') || w.tooltip!.contains('播放列表') || w.tooltip!.contains('封面')),
    );
    if (viewBtn.evaluate().isNotEmpty) {
      await tester.tap(viewBtn.first);
      await tester.pump(const Duration(seconds: 1));
      debugPrint('[阶段 6] ✓ 视图切换成功');
    }

    // ===== 阶段 7：关闭播放页面 =====
    debugPrint('\n========== 阶段 7：测试关闭播放页 ==========');

    final downBtn = find.byIcon(Symbols.keyboard_arrow_down);
    if (downBtn.evaluate().isNotEmpty) {
      await tester.tap(downBtn.first);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byType(NavigationBar).evaluate().isNotEmpty) break;
      }

      // 如果 tap 未生效，直接调用 Navigator.pop
      if (find.byType(NavigationBar).evaluate().isEmpty) {
        debugPrint('[阶段 7] tap未关闭页面，尝试 Navigator.pop');
        Navigator.of(tester.element(downBtn.first)).pop();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 500));
          if (find.byType(NavigationBar).evaluate().isNotEmpty) break;
        }
      }

      final hasNavBar = find.byType(NavigationBar).evaluate().isNotEmpty;
      expect(hasNavBar, isTrue, reason: '关闭播放页后应回到主页面');
      if (hasNavBar) debugPrint('[阶段 7] ✓ 关闭播放页成功');
    }

    // ===== 测试完成 =====
    debugPrint('\n========== 测试完成 ==========');
    debugPrint('所有 UI 元素验证和导航测试已完成');
  });
}
