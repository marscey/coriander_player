import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/glass_theme/glass_controls.dart';
import 'package:coriander_player/glass_theme/app_dialog.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/metadata/scraper_orchestrator.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/glass_theme/glass_dialog.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' hide GlassDialog;
import 'package:material_symbols_icons/symbols.dart';

/// 刮削设置组件
///
/// 管理刮削源的启用/禁用、优先级和 API 地址配置。
class ScraperSettings extends StatelessWidget {
  const ScraperSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "刮削设置",
      action: FilledButton.icon(
        icon: const Icon(Symbols.tune),
        label: const Text("刮削设置"),
        onPressed: () {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const ScraperSettingsDialog(),
          );
        },
      ),
    );
  }
}

/// 刮削设置对话框
class ScraperSettingsDialog extends StatefulWidget {
  const ScraperSettingsDialog({super.key});

  @override
  State<ScraperSettingsDialog> createState() => _ScraperSettingsDialogState();
}

class _ScraperSettingsDialogState extends State<ScraperSettingsDialog> {
  List<ScraperConfig> _configs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final configs = await MetadataStore.instance.getScraperConfigs();
    if (mounted) {
      setState(() {
        _configs = configs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;

    if (useGlass) {
      return GlassDialog(
        title: "刮削源设置",
        width: PlatformHelper.isMobile ? null : 420.0,
        height: PlatformHelper.isMobile
            ? MediaQuery.of(context).size.height * 0.7
            : 450.0,
        actions: [
          GlassDialogButton(
            label: "关闭",
            onTap: () => Navigator.pop(context),
          ),
        ],
        child: _isLoading
            ? const Center(child: AppSpinner())
            : ListView.builder(
                itemCount: _configs.length,
                itemBuilder: (context, index) {
                  final config = _configs[index];
                  return _buildScraperTile(config, scheme, useGlass);
                },
              ),
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: SizedBox(
        width: PlatformHelper.isMobile ? double.infinity : 420.0,
        height: PlatformHelper.isMobile ? MediaQuery.of(context).size.height * 0.7 : 450.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  "刮削源设置",
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 刮削源列表
              Expanded(
                child: _isLoading
                    ? const Center(child: AppSpinner())
                    : ListView.builder(
                        itemCount: _configs.length,
                        itemBuilder: (context, index) {
                          final config = _configs[index];
                          return _buildScraperTile(config, scheme, useGlass);
                        },
                      ),
              ),
              // 底部按钮
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("关闭"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScraperTile(
      ScraperConfig config, ColorScheme scheme, bool useGlass) {
    if (useGlass) {
      // Glass 风格：用 GlassContainer（listTileSettings）包裹自定义布局
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: GlassContainer(
          useOwnLayer: true,
          shape: const LiquidRoundedSuperellipse(borderRadius: 12),
          settings: listTileSettings(scheme.brightness == Brightness.dark),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                // 左侧：名称 + 优先级 + API 地址
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              config.name,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 14.0,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Text(
                            '优先级: ${config.priority}',
                            style: TextStyle(
                              fontSize: 12.0,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (config.apiBase != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            config.apiBase!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.0,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 右侧：编辑按钮 + 开关
                // API 地址编辑按钮（仅 MusicBrainz 等有 apiBase 的源）
                if (config.type == 'musicbrainz')
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: GlassButton(
                      icon: const Icon(Symbols.edit, size: 18.0),
                      iconSize: 18.0,
                      width: 36,
                      height: 36,
                      useOwnLayer: true,
                      onTap: () => _editApiBase(config),
                    ),
                  ),
                const SizedBox(width: 4.0),
                // 启用/禁用开关（保留 Material Switch，项目无 GlassSwitch）
                AppSwitch(
                  value: config.enabled,
                  onChanged: (value) async {
                    await MetadataStore.instance.toggleScraper(config.id, value);
                    // 重新注册刮削源
                    await ScraperOrchestrator.instance.initDefaults();
                    _loadConfigs();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Material 风格（保持原样）
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Text(config.name),
          const SizedBox(width: 8.0),
          Text(
            '优先级: ${config.priority}',
            style: TextStyle(fontSize: 12.0, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: config.apiBase != null
          ? Text(
              config.apiBase!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.0, color: scheme.outline),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // API 地址编辑按钮（仅 MusicBrainz 等有 apiBase 的源）
          if (config.type == 'musicbrainz')
            IconButton(
              icon: const Icon(Symbols.edit, size: 18.0),
              tooltip: "修改 API 地址",
              onPressed: () => _editApiBase(config),
            ),
          // 启用/禁用开关
          AppSwitch(
            value: config.enabled,
            onChanged: (value) async {
              await MetadataStore.instance.toggleScraper(config.id, value);
              // 重新注册刮削源
              await ScraperOrchestrator.instance.initDefaults();
              _loadConfigs();
            },
          ),
        ],
      ),
    );
  }

  /// 编辑 API 地址
  Future<void> _editApiBase(ScraperConfig config) async {
    final controller = TextEditingController(text: config.apiBase ?? '');
    final useGlass = AppPreference.instance.glassActive;
    final scheme = Theme.of(context).colorScheme;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => useGlass
          ? GlassDialog(
              title: "修改 API 地址",
              actions: [
                GlassDialogButton(
                  label: "取消",
                  onTap: () => Navigator.pop(context),
                ),
                GlassDialogButton(
                  label: "确定",
                  primary: true,
                  onTap: () => Navigator.pop(context, controller.text),
                ),
              ],
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: "API 地址",
                  hintText: "https://musicbrainz.org/ws/2",
                  filled: true,
                  fillColor: scheme.surface.withValues(alpha: 0.3),
                  border: const OutlineInputBorder(),
                ),
              ),
            )
          : AdaptiveDialog(
              title: const Text("修改 API 地址"),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "API 地址",
                  hintText: "https://musicbrainz.org/ws/2",
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("取消"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text("确定"),
                ),
              ],
            ),
    );

    if (result != null) {
      await MetadataStore.instance.updateScraperApiBase(
        config.id,
        result.isEmpty ? null : result,
      );
      // 重新注册刮削源
      await ScraperOrchestrator.instance.initDefaults();
      _loadConfigs();
    }
  }
}
