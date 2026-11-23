import 'dart:io';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/glass_theme/app_dialog.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/glass_page_scaffold.dart';
import 'package:coriander_player/page/settings_page/artist_separator_editor.dart';
import 'package:coriander_player/page/settings_page/cache_settings.dart';
import 'package:coriander_player/page/settings_page/check_update.dart';
import 'package:coriander_player/page/settings_page/create_issue.dart';
import 'package:coriander_player/page/settings_page/other_settings.dart';
import 'package:coriander_player/page/settings_page/player_engine_selector.dart';
import 'package:coriander_player/page/settings_page/scraper_settings.dart';
import 'package:coriander_player/page/settings_page/theme_settings.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;

    return Padding(
      padding: useGlass
          ? const EdgeInsets.fromLTRB(4.0, 16.0, 4.0, 6.0)
          : const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: useGlass ? 12.0 : 13.0,
          fontWeight: FontWeight.w700,
          color: useGlass
              ? scheme.onSurface.withValues(alpha: 0.5)
              : scheme.primary,
          letterSpacing: useGlass ? 1.0 : 0.5,
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final showTestConfig = PlatformHelper.isMobile && kDebugMode;
    final useGlass = AppPreference.instance.glassActive;

    final settingItems = <Widget>[
      // 移动端不提供本地文件夹管理（iOS/Android 无「音乐库目录」概念），
      // 连标题一起隐藏，避免出现空分组。
      if (!PlatformHelper.isMobile) ...[
        const _SectionHeader(title: "音乐库"),
        const SettingsGroup(
          children: [
            AudioLibraryEditor(),
          ],
        ),
        const SizedBox(height: 8.0),
      ],
      const _SectionHeader(title: "缓存"),
      const CacheManagementSettings(),
      const SizedBox(height: 8.0),
      const _SectionHeader(title: "歌词"),
      const SettingsGroup(
        children: [
          DefaultLyricSourceControl(),
          BluetoothLyricSwitch(),
        ],
      ),
      const SizedBox(height: 8.0),
      const _SectionHeader(title: "元数据"),
      const SettingsGroup(
        children: [
          ScraperSettings(),
        ],
      ),
      const SizedBox(height: 8.0),
      const _SectionHeader(title: "外观"),
      const SettingsGroup(
        children: [
          DynamicThemeSwitch(),
          UseSystemThemeSwitch(),
          ThemeSelector(),
          UseSystemThemeModeSwitch(),
          ThemeModeControl(),
          SelectFontCombobox(),
          LiquidGlassSwitch(),
        ],
      ),
      const SizedBox(height: 8.0),
      const _SectionHeader(title: "高级"),
      const SettingsGroup(
        children: [
          CloseBehaviorControl(),
          ArtistSeparatorEditor(),
          ShowTrackIndexSwitch(),
          MarqueeSpeedControl(),
          MarqueeEnabledSwitch(),
          PlayerEngineSelector(),
        ],
      ),
      if (showTestConfig) ...[
        const SizedBox(height: 8.0),
        const _SectionHeader(title: "测试配置"),
        const SettingsGroup(
          children: [
            AutoTestConfigSwitch(),
          ],
        ),
      ],
      const SizedBox(height: 8.0),
      const _SectionHeader(title: "关于"),
      const SettingsGroup(
        children: [
          CreateIssueTile(),
          CheckForUpdate(),
        ],
      ),
      const SizedBox(height: 8.0),
      const _SectionHeader(title: "调试"),
      const SettingsGroup(
        children: [
          DebugLogTile(),
        ],
      ),
    ];

    if (useGlass) {
      return GlassPageScaffold(
        title: "设置",
        menuItems: const [],
        showBackButton: true,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: GlassPageHeader(title: "设置"),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 140.0),
              sliver: SliverList.builder(
                itemCount: settingItems.length,
                itemBuilder: (context, i) => settingItems[i],
              ),
            ),
          ],
        ),
      );
    }

    return PageScaffold(
      title: "设置",
      actions: const [],
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96.0),
        children: settingItems,
      ),
    );
  }
}

/// 测试配置开关（仅移动端 debug 模式可见）
class AutoTestConfigSwitch extends StatefulWidget {
  const AutoTestConfigSwitch({super.key});

  @override
  State<AutoTestConfigSwitch> createState() => _AutoTestConfigSwitchState();
}

class _AutoTestConfigSwitchState extends State<AutoTestConfigSwitch> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "自动配置测试云服务和导入音频",
      action: Switch(
        value: settings.autoTestConfig,
        onChanged: (value) async {
          setState(() {
            settings.autoTestConfig = value;
          });
          await settings.saveSettings();
        },
      ),
    );
  }
}

/// Liquid Glass 界面开关（重启后生效）
class LiquidGlassSwitch extends StatefulWidget {
  const LiquidGlassSwitch({super.key});

  @override
  State<LiquidGlassSwitch> createState() => _LiquidGlassSwitchState();
}

class _LiquidGlassSwitchState extends State<LiquidGlassSwitch> {
  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "启用 Glass 界面风格",
      subtitle: "启用后需重启应用生效",
      action: Switch(
        value: AppPreference.instance.liquidGlassEnabled,
        onChanged: (value) async {
          setState(() {
            AppPreference.instance.liquidGlassEnabled = value;
          });
          await AppPreference.instance.save();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请重启应用以应用 Liquid Glass 界面设置'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );
  }
}

/// 调试日志查看
class DebugLogTile extends StatelessWidget {
  const DebugLogTile({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        String logs;
        try {
          logs = await DebugLogger.instance.readLogs();
        } catch (e) {
          logs = '读取日志失败: $e';
        }
        if (!context.mounted) return;
        showAdaptiveSheet(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => _DebugLogSheet(logs: logs),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Text(
              '查看运行日志',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
              ),
            ),
            const Spacer(),
            Icon(Icons.bug_report, size: 20, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _DebugLogSheet extends StatelessWidget {
  final String logs;
  const _DebugLogSheet({required this.logs});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('调试日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await DebugLogger.instance.clear();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  child: const Text('清除'),
                ),
                TextButton(
                  onPressed: () async {
                    final path = await DebugLogger.instance.logsPath();
                    if (path == null) return;
                    if (PlatformHelper.isMacOS) {
                      await Process.run('open', [path]);
                    } else if (PlatformHelper.isWindows) {
                      await Process.run('explorer', [path]);
                    } else if (PlatformHelper.isLinux) {
                      await Process.run('xdg-open', [path]);
                    }
                  },
                  child: const Text('打开目录'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text('暂无日志'))
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: logs
                        .split('\n')
                        .where((l) => l.trim().isNotEmpty)
                        .map((l) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: SelectableText(
                                l,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: l.contains('MISS') || l.contains('error')
                                      ? Colors.red
                                      : l.contains('HIT')
                                          ? Colors.green
                                          : scheme.onSurface,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
