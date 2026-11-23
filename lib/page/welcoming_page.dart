import 'dart:async';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/build_index_state_view.dart';
import 'package:coriander_player/glass_theme/glass_dialog.dart';
import 'package:coriander_player/page/glass_page_scaffold.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/genre_service.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

class WelcomingPage extends StatelessWidget {
  const WelcomingPage({super.key});

  /// 跳过引导：写入空索引（代表“已初始化”），直接进入主界面
  ///
  /// 引导不是强制流程：用户可以不扫描、稍后在设置里添加文件夹。
  Future<void> _skip(BuildContext context) async {
    try {
      final dir = await getAppDataDir();
      final indexFile =
          File(PlatformHelper.joinPaths([dir.path, "index.json"]));
      if (!indexFile.existsSync()) {
        indexFile.writeAsStringSync('{"folders":[],"version":110}');
      }
      await AudioLibrary.initFromIndex();
      await GenreService.instance.refresh();
      LOGGER.i("[welcome] 用户跳过引导，进入空音乐库");
    } catch (err, trace) {
      LOGGER.e("[welcome] 跳过引导失败: $err", stackTrace: trace);
    }
    if (!context.mounted) return;
    context.go(app_paths.START_PAGES[AppPreference.instance.startPage]);
  }

  @override
  Widget build(BuildContext context) {
    final useGlass = AppPreference.instance.glassActive;
    final scheme = Theme.of(context).colorScheme;

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "你的音乐放在哪些文件夹呢？",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "软件会扫描这些文件夹（包括所有子文件夹）下的音乐并建立索引。",
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        Text(
          "也可以先跳过，之后在设置中随时添加。",
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 16),
        FolderSelectorView(
          useGlass: useGlass,
          onSkip: () => _skip(context),
        ),
      ],
    );

    if (useGlass) {
      return GlassPageScaffold(
        title: "欢迎使用",
        showBackButton: false,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 120.0),
          child: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(48.0),
        child: _TitleBar(),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48.0),
        child: Center(child: content),
      ),
    );
  }
}

class FolderSelectorView extends StatefulWidget {
  const FolderSelectorView(
      {super.key, this.useGlass = false, required this.onSkip});

  final bool useGlass;
  final VoidCallback onSkip;

  @override
  State<FolderSelectorView> createState() => _FolderSelectorViewState();
}

class _FolderSelectorViewState extends State<FolderSelectorView> {
  bool selecting = true;
  final List<String> folders = [];
  final applicationSupportDirectory = getAppDataDir();

  Widget _primaryButton({
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    if (widget.useGlass) {
      return GlassDialogButton(
        label: label,
        onTap: onTap,
        primary: primary,
      );
    }
    return primary
        ? FilledButton(onPressed: onTap, child: Text(label))
        : OutlinedButton(onPressed: onTap, child: Text(label));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400.0, maxHeight: 400.0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: selecting
            ? folderSelector(scheme)
            : FutureBuilder(
                future: applicationSupportDirectory,
                builder: (context, snapshot) {
                  if (snapshot.data == null) {
                    return const Center(
                      child: Text("Fail to get app data dir."),
                    );
                  }

                  return BuildIndexStateView(
                    indexPath: snapshot.data!,
                    folders: folders,
                    whenIndexBuilt: () async {
                      await Future.wait([
                        AppSettings.instance.saveSettings(),
                        AudioLibrary.initFromIndex(),
                      ]);
                      await GenreService.instance.refresh();
                      if (context.mounted) {
                        context.go(app_paths.AUDIOS_PAGE);
                      }
                    },
                  );
                },
              ),
      ),
    );
  }

  // 平台特定的文件夹选择函数
  Future<String?> pickSingleFolder() async {
    if (PlatformHelper.isWindows) {
      LOGGER.d("[welcome] 准备调用 DirectoryPicker");
      final dirPicker = DirectoryPicker();
      dirPicker.title = "选择文件夹";
      LOGGER.d("[welcome] 调用 getDirectory()");
      final dir = dirPicker.getDirectory();
      return dir?.path;
    } else {
      // 非Windows平台使用file_picker
      LOGGER.d("[welcome] 准备调用 FilePicker");
      final result = await FilePicker.platform.getDirectoryPath();
      LOGGER.d("[welcome] 调用 getDirectoryPath()");
      return result;
    }
  }

  Widget folderSelector(ColorScheme scheme) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _primaryButton(
              label: "添加文件夹",
              onTap: () async {
                LOGGER.d("[welcome] 点击添加文件夹");
                final path = await pickSingleFolder();
                if (path == null) return;
                setState(() {
                  folders.add(path);
                });
              },
            ),
            const SizedBox(width: 12.0),
            _primaryButton(
              label: "扫描",
              primary: true,
              // 没有选择任何文件夹时不允许扫描，避免空扫描把应用卡在异常状态
              onTap: folders.isEmpty
                  ? null
                  : () {
                      setState(() {
                        selecting = false;
                      });
                    },
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        TextButton(
          onPressed: widget.onSkip,
          child: const Text("跳过，稍后设置"),
        ),
        const SizedBox(height: 8.0),
        Flexible(
          child: ListView.builder(
            itemCount: folders.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(folders[i]),
              trailing: IconButton(
                tooltip: "移除",
                onPressed: () {
                  setState(() {
                    folders.removeAt(i);
                  });
                },
                color: scheme.error,
                icon: const Icon(Symbols.delete),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    if (PlatformHelper.isMobile) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return DragToMoveArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Image.asset("app_icon.ico", width: 24, height: 24),
                  ),
                  Text(
                    "Coriander Player",
                    style: TextStyle(color: scheme.onSurface, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8.0),
            const _WindowControlls(),
          ],
        ),
      ),
    );
  }
}

class _WindowControlls extends StatefulWidget {
  const _WindowControlls();

  @override
  State<_WindowControlls> createState() => __WindowControllsState();
}

class __WindowControllsState extends State<_WindowControlls>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    if (PlatformHelper.isDesktop) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (PlatformHelper.isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() {});
  }

  @override
  void onWindowUnmaximize() {
    setState(() {});
  }

  @override
  void onWindowRestore() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformHelper.isMobile) return const SizedBox.shrink();

    return Wrap(
      spacing: 8.0,
      children: [
        IconButton(
          tooltip: "最小化",
          onPressed: windowManager.minimize,
          icon: const Icon(Symbols.remove),
        ),
        FutureBuilder(
          future: windowManager.isMaximized(),
          builder: (context, snapshot) {
            final isMaximized = snapshot.data ?? false;
            return IconButton(
              tooltip: isMaximized ? "还原" : "最大化",
              onPressed: isMaximized
                  ? windowManager.unmaximize
                  : windowManager.maximize,
              icon: Icon(
                isMaximized ? Symbols.fullscreen_exit : Symbols.fullscreen,
              ),
            );
          },
        ),
        IconButton(
          tooltip: "关闭",
          onPressed: () async {
            // 保存状态
            await savePlaylists();
            await saveLyricSources();
            await AppSettings.instance.saveSettings();
            await AppPreference.instance.save();

            // 清理资源
            PlayService.instance.close();
            await HotkeysHelper.unregisterAll();

            // 完全退出
            await windowManager.setPreventClose(false);
            await windowManager.close();
            exit(0);
          },
          icon: const Icon(Symbols.close),
        ),
      ],
    );
  }
}
