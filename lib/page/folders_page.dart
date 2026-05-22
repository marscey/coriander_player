import 'package:coriander_player/component/build_index_state_view.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/page/folder_detail_page.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  List<String> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  void _loadFolders() {
    setState(() {
      _folders = AudioLibrary.instance.folders.map((f) => f.path).toList();
      _isLoading = false;
    });
  }

  /// 判断当前文件夹是否包含正在播放的音频
  bool _isFolderPlaying(AudioFolder folder) {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || nowPlaying.isCloudAudio) return false;
    final playingPath = nowPlaying.path;
    // 播放文件的路径是否以此文件夹路径为前缀
    return playingPath.startsWith('${folder.path}/') ||
        playingPath == folder.path;
  }

  bool get _hasPlayingLocalAudio {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    return nowPlaying != null && !nowPlaying.isCloudAudio;
  }

  void _locatePlayingFolder() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || nowPlaying.isCloudAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未在播放本地音频')),
      );
      return;
    }

    // 找到包含播放文件的文件夹
    final playingPath = nowPlaying.path;
    AudioFolder? targetFolder;
    for (final folder in AudioLibrary.instance.folders) {
      if (playingPath.startsWith('${folder.path}/') ||
          playingPath == folder.path) {
        targetFolder = folder;
        break;
      }
    }

    if (targetFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('播放文件不在任何已配置的文件夹中')),
      );
      return;
    }

    context.push('/folders/detail',
        extra: FolderDetailArgs(targetFolder, playingPath));
  }

  Future<void> _addFolder() async {
    final dirPicker = DirectoryPicker();
    dirPicker.title = "选择音乐文件夹";
    final dir = dirPicker.getDirectory();
    if (dir == null) return;

    final path = dir.path;
    if (_folders.contains(path)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件夹已存在: ${p.basename(path)}')),
      );
      return;
    }

    setState(() {
      _folders.add(path);
    });
  }

  void _removeFolder(String path) {
    setState(() {
      _folders.remove(path);
    });
  }

  Future<void> _saveAndRebuild() async {
    final appDataDir = await getAppDataDir();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: SizedBox(
          height: 450.0,
          width: 450.0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: BuildIndexStateView(
              indexPath: appDataDir,
              folders: _folders,
              whenIndexBuilt: () async {
                await Future.wait([
                  AudioLibrary.initFromIndex(),
                  readPlaylists(),
                  readLyricSources(),
                ]);
                if (!mounted) return;
                Navigator.pop(ctx);
                _loadFolders();
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contentList = AudioLibrary.instance.folders;

    return Column(
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            children: [
              Text(
                "文件夹",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${contentList.length} 个文件夹",
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // 播放定位按钮（仅当有本地音频播放时显示）
              if (_hasPlayingLocalAudio)
                IconButton(
                  icon: const Icon(Icons.my_location, size: 20),
                  tooltip: "定位播放文件",
                  onPressed: _locatePlayingFolder,
                ),
              // 添加文件夹按钮
              IconButton(
                icon: Icon(Symbols.add, size: 20),
                tooltip: "添加文件夹",
                onPressed: _addFolder,
              ),
              // 保存并重建索引按钮
              IconButton(
                icon: const Icon(Symbols.save, size: 20),
                tooltip: "保存并重建索引",
                onPressed: _saveAndRebuild,
              ),
            ],
          ),
        ),

        // 文件夹列表
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : contentList.isEmpty
                  ? _buildEmptyState()
                  : _buildFolderList(),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.folder_open,
              size: 64, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            "暂无音乐文件夹",
            style: TextStyle(
              fontSize: 16,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Symbols.add, size: 18),
            label: const Text("添加文件夹"),
            onPressed: _addFolder,
          ),
        ],
      ),
    );
  }

  Widget _buildFolderList() {
    final contentList = AudioLibrary.instance.folders;
    final scheme = Theme.of(context).colorScheme;

    return ListView.builder(
      itemCount: contentList.length,
      itemBuilder: (context, index) {
        final folder = contentList[index];
        final folderName = p.basename(folder.path);
        final audioCount = folder.audios.length;
        final isPlaying = _isFolderPlaying(folder);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push(
              '/folders/detail',
              extra: FolderDetailArgs(folder),
            ),
            mouseCursor: SystemMouseCursors.click,
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  PlayingIndicatorOverlay(
                    size: PlayingIndicatorSize.medium,
                    isActivelyPlaying: isPlaying,
                    child: Icon(Icons.folder, size: 32, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Tooltip(
                          message: folder.path,
                          child: Text(
                            folderName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "$audioCount 首歌曲 · ${DateTime.fromMillisecondsSinceEpoch(folder.modified * 1000).toString().substring(0, 19)}",
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // 删除按钮
                  IconButton(
                    icon: Icon(Symbols.delete,
                        size: 18, color: scheme.error.withValues(alpha: 0.7)),
                    tooltip: "移除",
                    onPressed: () => _confirmRemoveFolder(folder.path),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmRemoveFolder(String path) {
    final folderName = p.basename(path);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除文件夹'),
        content: Text('确定要移除文件夹「$folderName」吗？\n\n这不会删除磁盘上的文件，只是从音乐库中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeFolder(path);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }
}
