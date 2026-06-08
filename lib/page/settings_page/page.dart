import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/settings_page/artist_separator_editor.dart';
import 'package:coriander_player/page/settings_page/cache_settings.dart';
import 'package:coriander_player/page/settings_page/check_update.dart';
import 'package:coriander_player/page/settings_page/create_issue.dart';
import 'package:coriander_player/page/settings_page/other_settings.dart';
import 'package:coriander_player/page/settings_page/player_engine_selector.dart';
import 'package:coriander_player/page/settings_page/scraper_settings.dart';
import 'package:coriander_player/page/settings_page/theme_settings.dart';
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
