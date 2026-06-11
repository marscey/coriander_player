import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/settings_page/artist_separator_editor.dart';
import 'package:coriander_player/page/settings_page/cache_settings.dart';
import 'package:coriander_player/page/settings_page/check_update.dart';
import 'package:coriander_player/page/settings_page/create_issue.dart';
import 'package:coriander_player/page/settings_page/other_settings.dart';
import 'package:coriander_player/page/settings_page/player_engine_selector.dart';
import 'package:coriander_player/page/settings_page/scraper_settings.dart';
import 'package:coriander_player/page/settings_page/theme_settings.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
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

    return PageScaffold(
      title: "设置",
      actions: const [],
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96.0),
        children: [
          const _SectionHeader(title: "音乐库"),
          const AudioLibraryEditor(),
          const SizedBox(height: 8.0),
          const _SectionHeader(title: "缓存"),
          const CacheManagementSettings(),
          const SizedBox(height: 8.0),
          const _SectionHeader(title: "歌词"),
          const DefaultLyricSourceControl(),
          const SizedBox(height: 12.0),
          const BluetoothLyricSwitch(),
          const SizedBox(height: 8.0),
          const _SectionHeader(title: "元数据"),
          const ScraperSettings(),
          const SizedBox(height: 8.0),
          const _SectionHeader(title: "外观"),
          const DynamicThemeSwitch(),
          const SizedBox(height: 12.0),
          const UseSystemThemeSwitch(),
          const SizedBox(height: 12.0),
          const ThemeSelector(),
          const SizedBox(height: 12.0),
          const UseSystemThemeModeSwitch(),
          const SizedBox(height: 12.0),
          const ThemeModeControl(),
          const SizedBox(height: 12.0),
          const SelectFontCombobox(),
          const SizedBox(height: 8.0),
          const _SectionHeader(title: "高级"),
          const CloseBehaviorControl(),
          const SizedBox(height: 12.0),
          const ArtistSeparatorEditor(),
          const SizedBox(height: 12.0),
          const ShowTrackIndexSwitch(),
          const SizedBox(height: 12.0),
          const PlayerEngineSelector(),
          if (showTestConfig) ...[
            const SizedBox(height: 8.0),
            const _SectionHeader(title: "测试配置"),
            const AutoTestConfigSwitch(),
          ],
          const SizedBox(height: 8.0),
          const _SectionHeader(title: "关于"),
          const CreateIssueTile(),
          const SizedBox(height: 12.0),
          const CheckForUpdate(),
        ],
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
