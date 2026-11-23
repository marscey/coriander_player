import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/glass_theme/glass_dialog.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/genre_service.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    hide GlassDialog;
import 'package:material_symbols_icons/symbols.dart';

class ArtistSeparatorEditor extends StatelessWidget {
  const ArtistSeparatorEditor({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "自定义艺术家分隔符",
      action: FilledButton.icon(
        icon: const Icon(Symbols.edit),
        label: const Text("管理艺术家分隔符"),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const _ArtistSeparatorEditDialog(),
          );
        },
      ),
    );
  }
}

class _ArtistSeparatorEditDialog extends StatefulWidget {
  const _ArtistSeparatorEditDialog();

  @override
  State<_ArtistSeparatorEditDialog> createState() =>
      __ArtistSeparatorEditDialogState();
}

class __ArtistSeparatorEditDialogState
    extends State<_ArtistSeparatorEditDialog> {
  final appSettings = AppSettings.instance;
  late List<String> separators = List.from(appSettings.artistSeparator);
  Map<String, Widget> children = {};
  final currEditController = TextEditingController();
  bool editing = false;
  // 在 initState 前即可读取，用于决定列表项使用 glass 还是 material 风格
  final bool _useGlass = AppPreference.instance.glassActive;

  /// 构建已有分隔符列表项（glass / material 双风格）
  Widget _buildSeparatorItem(String item) {
    if (_useGlass) {
      return GlassContainer(
        settings: listTileSettings(glassIsDark(context)),
        shape: const LiquidRoundedSuperellipse(borderRadius: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(item)),
              GlassButton(
                icon: const Icon(Symbols.remove, size: 18),
                iconSize: 18,
                width: 36,
                height: 36,
                useOwnLayer: true,
                onTap: () {
                  separators.remove(item);
                  setState(() {
                    children.remove(item);
                  });
                },
              ),
            ],
          ),
        ),
      );
    }
    return ListTile(
      title: Text(item),
      trailing: IconButton(
        onPressed: () {
          separators.remove(item);
          setState(() {
            children.remove(item);
          });
        },
        icon: const Icon(Symbols.remove),
      ),
    );
  }

  /// 构建新增分隔符输入项（glass / material 双风格）
  Widget _buildEditingItem() {
    if (_useGlass) {
      final scheme = Theme.of(context).colorScheme;
      return GlassContainer(
        settings: listTileSettings(glassIsDark(context)),
        shape: const LiquidRoundedSuperellipse(borderRadius: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: HotkeysHelper.onFocusChanges,
                  child: TextField(
                    controller: currEditController,
                    autofocus: true,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: scheme.surface.withValues(alpha: 0.3),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10.0, vertical: 10.0),
                    ),
                    onSubmitted: (value) {
                      _addArtistSeparator();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              GlassButton(
                icon: const Icon(Symbols.done, size: 18),
                iconSize: 18,
                width: 36,
                height: 36,
                useOwnLayer: true,
                onTap: _addArtistSeparator,
              ),
            ],
          ),
        ),
      );
    }
    return ListTile(
      title: Focus(
        onFocusChange: HotkeysHelper.onFocusChanges,
        child: TextField(
          controller: currEditController,
          autofocus: true,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              onPressed: _addArtistSeparator,
              icon: const Icon(Symbols.done),
            ),
          ),
          onSubmitted: (value) {
            _addArtistSeparator();
          },
        ),
      ),
    );
  }

  void _addArtistSeparator() {
    if (currEditController.text.isEmpty) return;
    final newSeparator = currEditController.text;
    setState(
      () {
        children.remove("");
        children[newSeparator] = _buildSeparatorItem(newSeparator);
        editing = false;
      },
    );
  }

  @override
  void initState() {
    super.initState();
    for (var item in separators) {
      children[item] = _buildSeparatorItem(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;

    if (useGlass) {
      return GlassDialog(
        title: "管理艺术家分隔符",
        width: 350.0,
        height: 350.0,
        actions: [
          GlassDialogButton(
            label: "新增",
            onTap: () {
              setState(() {
                editing = true;
                children[""] = _buildEditingItem();
              });
            },
          ),
          GlassDialogButton(
            label: "取消",
            onTap: () => Navigator.pop(context),
          ),
          GlassDialogButton(
            label: "确定",
            primary: true,
            onTap: editing
                ? null
                : () async {
                    appSettings.artistSeparator = children.keys.toList();
                    appSettings.artistSplitPattern =
                        appSettings.artistSeparator.join("|");
                    await appSettings.saveSettings();
                    await AudioLibrary.initFromIndex();
                    await GenreService.instance.refresh();
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
          ),
        ],
        child: ListView.separated(
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8.0),
          itemBuilder: (context, index) =>
              children.values.elementAt(index),
        ),
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: SizedBox(
        width: 350.0,
        height: 350.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  "管理艺术家分隔符",
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView(children: children.values.toList()),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        editing = true;
                        children[""] = ListTile(
                          title: Focus(
                            onFocusChange: HotkeysHelper.onFocusChanges,
                            child: TextField(
                              controller: currEditController,
                              autofocus: true,
                              decoration: InputDecoration(
                                suffixIcon: IconButton(
                                  onPressed: _addArtistSeparator,
                                  icon: const Icon(Symbols.done),
                                ),
                              ),
                              onSubmitted: (value) {
                                _addArtistSeparator();
                              },
                            ),
                          ),
                        );
                      });
                    },
                    child: const Text("新增"),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: editing
                        ? null
                        : () async {
                            appSettings.artistSeparator =
                                children.keys.toList();
                            appSettings.artistSplitPattern =
                                appSettings.artistSeparator.join("|");
                            await appSettings.saveSettings();
                            await AudioLibrary.initFromIndex();
                            await GenreService.instance.refresh();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                    child: const Text("确定"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
