import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UI visual test - capture all tabs', (tester) async {
    // 等待 app 启动
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // 截图: 音乐库 (默认 tab)
    await binding.takeScreenshot('tab-01-music-library');
    print('Screenshot: tab-01-music-library');

    // 通过 Semantic label 找到并点击各个 tab
    // Flutter NavigationBar 的标签在 accessibility tree 中
    // 使用 find.text 找到标签文字
    final tabLabels = ['最近播放', '连接', '搜索', '设置'];
    final tabScreenshots = [
      'tab-02-recent-plays',
      'tab-03-cloud',
      'tab-04-search',
      'tab-05-settings',
    ];

    for (int i = 0; i < tabLabels.length; i++) {
      // 找到标签文字并点击
      final label = find.text(tabLabels[i]).first;
      if (label.evaluate().isNotEmpty) {
        await tester.tap(label);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await binding.takeScreenshot(tabScreenshots[i]);
        print('Screenshot: ${tabScreenshots[i]}');
      } else {
        print('Warning: Could not find tab "${tabLabels[i]}"');
      }
    }

    print('All screenshots taken!');
  });
}
