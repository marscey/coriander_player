import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/build_index_state_view.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/genre_service.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class CloseBehaviorControl extends StatefulWidget {
  const CloseBehaviorControl({super.key});

  @override
  State<CloseBehaviorControl> createState() => _CloseBehaviorControlState();
}

class _CloseBehaviorControlState extends State<CloseBehaviorControl> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    if (!PlatformHelper.isDesktop) return const SizedBox.shrink();

    return SettingsTile(
      description: "关闭主窗口时",
      action: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<bool>(
            value: true,
            icon: Icon(Symbols.minimize),
            label: Text("最小化到托盘"),
          ),
          ButtonSegment<bool>(
            value: false,
            icon: Icon(Symbols.close),
            label: Text("退出程序"),
          ),
        ],
        selected: {settings.closeToTray},
        onSelectionChanged: (newSelection) async {
          if (newSelection.first == settings.closeToTray) return;

          setState(() {
            settings.closeToTray = newSelection.first;
          });
          await settings.saveSettings();
        },
      ),
    );
  }
}

class DefaultLyricSourceControl extends StatefulWidget {
  const DefaultLyricSourceControl({super.key});

  @override
  State<DefaultLyricSourceControl> createState() =>
      _DefaultLyricSourceControlState();
}

class _DefaultLyricSourceControlState extends State<DefaultLyricSourceControl> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "首选歌词来源",
      action: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<bool>(
            value: true,
            icon: Icon(Symbols.cloud_off),
            label: Text("本地"),
          ),
          ButtonSegment<bool>(
            value: false,
            icon: Icon(Symbols.cloud),
            label: Text("在线"),
          ),
        ],
        selected: {settings.localLyricFirst},
        onSelectionChanged: (newSelection) async {
          if (newSelection.first == settings.localLyricFirst) return;

          setState(() {
            settings.localLyricFirst = newSelection.first;
          });
          await settings.saveSettings();
        },
      ),
    );
  }
}

class AudioLibraryEditor extends StatelessWidget {
  const AudioLibraryEditor({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "文件夹管理",
      action: FilledButton.icon(
        icon: const Icon(Symbols.folder),
        label: const Text("文件夹管理"),
        onPressed: () {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const AudioLibraryEditorDialog(),
          );
        },
      ),
    );
  }
}

class AudioLibraryEditorDialog extends StatefulWidget {
  const AudioLibraryEditorDialog({super.key});

  @override
  State<AudioLibraryEditorDialog> createState() =>
      _AudioLibraryEditorDialogState();
}

class _AudioLibraryEditorDialogState extends State<AudioLibraryEditorDialog> {
  final folders = List.generate(
    AudioLibrary.instance.folders.length,
    (i) => AudioLibrary.instance.folders[i].path,
  );

  final applicationSupportDirectory = getAppDataDir();

  bool editing = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: SizedBox(
        height: 450.0,
        width: 450.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  "管理文件夹",
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: editing
                      ? ListView.builder(
                          itemCount: folders.length,
                          itemBuilder: (context, i) => ListTile(
                            title: Text(folders[i], maxLines: 1),
                            trailing: IconButton(
                              tooltip: "移除",
                              color: scheme.error,
                              onPressed: () {
                                setState(() {
                                  folders.removeAt(i);
                                });
                              },
                              icon: const Icon(Symbols.delete),
                            ),
                          ),
                        )
                      : FutureBuilder(
                          future: applicationSupportDirectory,
                          builder: (context, snapshot) {
                            if (snapshot.data == null) {
                              return const Center(
                                child: Text("Fail to get app data dir."),
                              );
                            }

                            return Center(
                              child: BuildIndexStateView(
                                indexPath: snapshot.data!,
                                folders: folders,
                                whenIndexBuilt: () async {
                                  await Future.wait([
                                    AudioLibrary.initFromIndex(),
                                    readPlaylists(),
                                    readLyricSources(),
                                  ]);
                                  await GenreService.instance.refresh();
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      if (PlatformHelper.isWindows) {
                        final dirPicker = DirectoryPicker();
                        dirPicker.title = "选择文件夹";

                        final dir = dirPicker.getDirectory();
                        if (dir == null) return;

                        setState(() {
                          folders.add(dir.path);
                        });
                      } else {
                        final dir =
                            await FilePicker.platform.getDirectoryPath();
                        if (dir == null) return;

                        setState(() {
                          folders.add(dir);
                        });
                      }
                    },
                    child: const Text("添加"),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        editing = false;
                      });
                    },
                    child: const Text("确定"),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

/// 蓝牙歌词开关
/// 将歌词显示在锁屏/蓝牙设备的歌曲名称位置
class BluetoothLyricSwitch extends StatefulWidget {
  const BluetoothLyricSwitch({super.key});

  @override
  State<BluetoothLyricSwitch> createState() => _BluetoothLyricSwitchState();
}

class _BluetoothLyricSwitchState extends State<BluetoothLyricSwitch> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    if (!PlatformHelper.isIOS && !PlatformHelper.isMacOS) {
      return const SizedBox.shrink();
    }

    return SettingsTile(
      description: "蓝牙歌词",
      subtitle: "在锁屏和蓝牙设备歌曲名称处显示当前歌词",
      action: Switch(
        value: settings.bluetoothLyric,
        onChanged: (value) async {
          setState(() {
            settings.bluetoothLyric = value;
          });
          PlayService.instance.playbackService.setBluetoothLyricEnabled(value);
          await settings.saveSettings();
        },
      ),
    );
  }
}

class ShowTrackIndexSwitch extends StatefulWidget {
  const ShowTrackIndexSwitch({super.key});

  @override
  State<ShowTrackIndexSwitch> createState() => _ShowTrackIndexSwitchState();
}

class _ShowTrackIndexSwitchState extends State<ShowTrackIndexSwitch> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "显示序号",
      action: Switch(
        value: settings.showTrackIndex,
        onChanged: (value) async {
          setState(() {
            settings.showTrackIndex = value;
          });
          await settings.saveSettings();
        },
      ),
    );
  }
}
