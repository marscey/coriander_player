import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'dart:io' as io;

enum LocalSortBy {
  name,
  size,
  lastModified,
  type,
}

enum LocalSortOrder {
  ascending,
  descending,
}

enum LocalViewMode {
  list,
  grid,
}

/// 本地文件/文件夹条目
class _LocalEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime lastModified;
  final Audio? audio; // 如果是音频文件，关联的 Audio 对象

  _LocalEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    required this.lastModified,
    this.audio,
  });

  bool get isAudioFile => audio != null;

  String get extension => p.extension(name).toLowerCase();
}

/// 文件夹详情页参数包装类
class FolderDetailArgs {
  final AudioFolder folder;
  final String? locateToPath;
  FolderDetailArgs(this.folder, [this.locateToPath]);
}

class FolderDetailPage extends StatefulWidget {
  final AudioFolder folder;
  final String? locateToPath;
  const FolderDetailPage({super.key, required this.folder, this.locateToPath});

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  late String _rootPath;
  late String _currentPath;
  List<_LocalEntry> _entries = [];
  bool _isLoading = true;

  LocalViewMode _viewMode = LocalViewMode.list;
  LocalSortBy _sortBy = LocalSortBy.name;
  LocalSortOrder _sortOrder = LocalSortOrder.ascending;

  // 搜索
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 滚动控制
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _rootPath = widget.folder.path;
    _currentPath = _rootPath;
    _loadEntries();
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  bool _isOnPlayingPath(_LocalEntry entry) {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || nowPlaying.isCloudAudio) return false;
    final playingPath = nowPlaying.path;
    if (entry.isDirectory) {
      return playingPath.startsWith('${entry.path}/') ||
          playingPath == entry.path;
    } else {
      return playingPath == entry.path;
    }
  }

  void _loadEntries() {
    setState(() => _isLoading = true);
    final entries = <_LocalEntry>[];
    final audioMap = <String, Audio>{};

    // 构建当前文件夹及其子文件夹的音频映射
    for (final folder in AudioLibrary.instance.folders) {
      for (final audio in folder.audios) {
        audioMap[audio.path] = audio;
      }
    }

    try {
      final dir = io.Directory(_currentPath);
      if (dir.existsSync()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          final name = p.basename(entity.path);
          // 跳过隐藏文件
          if (name.startsWith('.')) continue;

          if (entity is io.Directory) {
            entries.add(_LocalEntry(
              name: name,
              path: entity.path,
              isDirectory: true,
              lastModified: DateTime.now(),
            ));
          } else if (entity is io.File) {
            final audio = audioMap[entity.path];
            entries.add(_LocalEntry(
              name: name,
              path: entity.path,
              isDirectory: false,
              size: entity.lengthSync(),
              lastModified: entity.lastModifiedSync(),
              audio: audio,
            ));
          }
        }
      }
    } catch (e) {
      // 权限不足等错误，忽略
    }

    setState(() {
      _entries = entries;
      _isLoading = false;
    });

    // 如果有定位目标，延迟滚动
    if (widget.locateToPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToPath(widget.locateToPath!);
      });
    }
  }

  List<_LocalEntry> _sortEntries(List<_LocalEntry> entries) {
    final sorted = List<_LocalEntry>.from(entries);
    final compare = _sortOrder == LocalSortOrder.ascending ? 1 : -1;

    sorted.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      int result;
      switch (_sortBy) {
        case LocalSortBy.name:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case LocalSortBy.size:
          result = a.size.compareTo(b.size);
          break;
        case LocalSortBy.lastModified:
          result = a.lastModified.compareTo(b.lastModified);
          break;
        case LocalSortBy.type:
          result = a.extension.compareTo(b.extension);
          break;
      }
      return result * compare;
    });
    return sorted;
  }

  List<_LocalEntry> _filterEntries(List<_LocalEntry> entries) {
    if (_searchQuery.isEmpty) return entries;
    final query = _searchQuery.toLowerCase();
    return entries.where((e) => e.name.toLowerCase().contains(query)).toList();
  }

  List<_LocalEntry> _getDisplayEntries() {
    return _sortEntries(_filterEntries(_entries));
  }

  void _locatePlayingFile() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || nowPlaying.isCloudAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未在播放本地音频')),
      );
      return;
    }

    final playingPath = nowPlaying.path;
    final playingDir = playingPath.contains('/')
        ? playingPath.substring(0, playingPath.lastIndexOf('/'))
        : '';

    if (playingDir != _currentPath) {
      setState(() {
        _currentPath = playingDir;
        _searchQuery = '';
        _searchController.clear();
        _isSearching = false;
        _loadEntries();
      });
      // 等UI重建后滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToPlayingFile();
      });
    } else {
      _scrollToPlayingFile();
    }
  }

  void _scrollToPlayingFile() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null) return;

    final displayEntries = _getDisplayEntries();
    final index = displayEntries.indexWhere((e) => e.path == nowPlaying.path);
    if (index == -1) return;

    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxExtent = _scrollController.position.maxScrollExtent;
    double targetOffset;

    if (_viewMode == LocalViewMode.list) {
      // 将目标项居中显示在视口中
      targetOffset = index * 64.0 - (viewportHeight / 2) + 32.0;
    } else {
      final row = (index / _getCrossAxisCount()).floor();
      targetOffset = row * 98.0 - (viewportHeight / 2) + 49.0;
    }

    _scrollController.animateTo(
      targetOffset.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToPath(String filePath) {
    final displayEntries = _getDisplayEntries();
    final index = displayEntries.indexWhere((e) => e.path == filePath);
    if (index == -1) return;
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxExtent = _scrollController.position.maxScrollExtent;
    double targetOffset;

    if (_viewMode == LocalViewMode.list) {
      targetOffset = index * 64.0 - (viewportHeight / 2) + 32.0;
    } else {
      final row = (index / _getCrossAxisCount()).floor();
      targetOffset = row * 98.0 - (viewportHeight / 2) + 49.0;
    }

    _scrollController.animateTo(
      targetOffset.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  int _getCrossAxisCount() {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth / 160).floor().clamp(2, 10);
  }

  List<Audio> _getAudioFiles(List<_LocalEntry> entries) {
    return entries.where((e) => e.isAudioFile).map((e) => e.audio!).toList();
  }

  void _playAudio(_LocalEntry entry, List<Audio> playlist) {
    if (entry.audio == null) return;
    final index = playlist.indexOf(entry.audio!);
    if (index >= 0) {
      PlayService.instance.playbackService.play(index, playlist);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildBreadcrumb(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final filtered = _filterEntries(_entries);
    final sorted = _sortEntries(filtered);
    if (_viewMode == LocalViewMode.grid) {
      return _buildGridView(sorted);
    }
    return _buildListView(sorted);
  }

  // ==================== 网格视图 ====================

  Widget _buildGridView(List<_LocalEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final minCellWidth = PlatformHelper.isMobile ? 110.0 : 160.0;
        final crossAxisCount =
            (screenWidth / minCellWidth).floor().clamp(2, 10);
        const crossAxisSpacing = 8.0;
        const runSpacing = 8.0;
        const padding = 8.0;
        final availableWidth =
            screenWidth - padding * 2 - crossAxisSpacing * (crossAxisCount - 1);
        final cellWidth = availableWidth / crossAxisCount;

        return Scrollbar(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(padding),
            child: Wrap(
              spacing: crossAxisSpacing,
              runSpacing: runSpacing,
              children: entries.map((entry) {
                return SizedBox(
                  width: cellWidth,
                  child: _buildGridItem(entry),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // ==================== 列表视图 ====================

  Widget _buildListView(List<_LocalEntry> entries) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return _buildListItem(entries[index], index);
      },
    );
  }

  // ==================== 网格项 ====================

  Widget _buildGridItem(_LocalEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final isOnPlayingPath = _isOnPlayingPath(entry);
    final isPlayingAudio = isOnPlayingPath && !entry.isDirectory;
    final nameColor = isPlayingAudio ? scheme.primary : scheme.onSurface;

    return GestureDetector(
      onTap: () => _handleEntryTap(entry),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 55,
                height: 55,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: PlayingIndicatorOverlay(
                        size: PlayingIndicatorSize.large,
                        isActivelyPlaying: isOnPlayingPath,
                        child: _buildGridIcon(entry),
                      ),
                    ),
                    Positioned(
                      right: -12,
                      bottom: -10,
                      child: _buildLocalGridMenuButton(entry),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                entry.name,
                style: TextStyle(fontSize: 13, color: nameColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalGridMenuButton(_LocalEntry entry) {
    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        iconSize: 18,
        icon: const Icon(Icons.more_horiz),
        tooltip: '更多',
        itemBuilder: (context) => [
          if (entry.isAudioFile)
            const PopupMenuItem(value: 'play', child: Text('播放')),
          if (entry.isDirectory)
            const PopupMenuItem(
                value: 'scan_folder_to_library', child: Text('扫描到音乐库')),
        ],
        onSelected: (value) => _handleLocalFileAction(entry, value),
      ),
    );
  }

  Widget _buildGridIcon(_LocalEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    if (entry.isDirectory) {
      return Icon(Icons.folder, size: 48, color: scheme.onSurfaceVariant);
    } else if (entry.isAudioFile) {
      return Icon(Icons.audiotrack, size: 48, color: scheme.onSurfaceVariant);
    } else if (_isImageFile(entry.name)) {
      return _buildLocalImageThumbnail(entry, size: 48);
    } else {
      return Icon(Icons.insert_drive_file,
          size: 48, color: scheme.onSurfaceVariant);
    }
  }

  // ==================== 列表项 ====================

  Widget _buildListItem(_LocalEntry entry, int index) {
    final scheme = Theme.of(context).colorScheme;
    final isOnPlayingPath = _isOnPlayingPath(entry);
    final isPlayingAudio = isOnPlayingPath && !entry.isDirectory;
    final nameColor = isPlayingAudio ? scheme.primary : scheme.onSurface;
    final subColor = isPlayingAudio ? scheme.primary : scheme.onSurfaceVariant;

    return GestureDetector(
      onTap: () => _handleEntryTap(entry),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // 序号
              SizedBox(
                width: 28.0,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 12),
              PlayingIndicatorOverlay(
                size: PlayingIndicatorSize.small,
                isActivelyPlaying: isOnPlayingPath,
                child: _buildListIcon(entry),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.name,
                      style: TextStyle(fontSize: 16, color: nameColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!entry.isDirectory)
                      Text(
                        _formatFileSize(entry.size),
                        style: TextStyle(
                          fontSize: 13,
                          color: subColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListIcon(_LocalEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    if (entry.isDirectory) {
      return Icon(Icons.folder, size: 24, color: scheme.onSurfaceVariant);
    } else if (entry.isAudioFile) {
      return Icon(Icons.audiotrack, size: 24, color: scheme.onSurfaceVariant);
    } else if (_isImageFile(entry.name)) {
      return _buildLocalImageThumbnail(entry, size: 48);
    } else {
      return Icon(Icons.insert_drive_file,
          size: 24, color: scheme.onSurfaceVariant);
    }
  }

  // ==================== 本地图片缩略图 ====================

  Widget _buildLocalImageThumbnail(_LocalEntry entry, {double size = 48}) {
    final scheme = Theme.of(context).colorScheme;
    final file = io.File(entry.path);
    if (!file.existsSync()) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child:
            Icon(Icons.image, size: size * 0.5, color: scheme.onSurfaceVariant),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(Icons.broken_image,
              size: size * 0.5, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  // ==================== 面包屑导航栏 ====================

  Widget _buildBreadcrumb() {
    final scheme = Theme.of(context).colorScheme;
    final rootName = _rootPath.split('/').last;

    // 构建面包屑段：从根目录名开始，不显示父级路径
    final segments = <_BreadcrumbSegment>[];
    // 第一段 = 根目录名称（如 "music"）
    final isAtRoot = _currentPath == _rootPath;
    segments.add(_BreadcrumbSegment(
      name: rootName,
      path: _rootPath,
      isLast: isAtRoot,
    ));

    if (!isAtRoot) {
      // 根目录之后的子路径段
      final relativePath = _currentPath.substring(_rootPath.length + 1);
      final parts = relativePath.split('/').where((p) => p.isNotEmpty).toList();
      for (int i = 0; i < parts.length; i++) {
        final segmentPath = '$_rootPath/${parts.sublist(0, i + 1).join('/')}';
        segments.add(_BreadcrumbSegment(
          name: parts[i],
          path: segmentPath,
          isLast: i == parts.length - 1,
        ));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: isAtRoot ? '返回文件夹列表' : '返回上一级',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              if (isAtRoot) {
                context.pop();
              } else {
                setState(() {
                  _currentPath = _getParentPath(_currentPath);
                  _loadEntries();
                });
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _isSearching
                ? TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: '搜索文件...',
                      hintStyle: TextStyle(
                          fontSize: 14, color: scheme.onSurfaceVariant),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    style: TextStyle(fontSize: 14, color: scheme.onSurface),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: segments.map((seg) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (seg != segments.first)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Icon(Icons.chevron_right,
                                    size: 16, color: scheme.onSurfaceVariant),
                              ),
                            _buildBreadcrumbItem(seg, scheme),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
          // 搜索按钮
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, size: 20),
            tooltip: _isSearching ? '关闭搜索' : '搜索',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _searchFocusNode.requestFocus();
                }
              });
            },
          ),
          // 播放定位按钮
          IconButton(
            icon: const Icon(Icons.my_location, size: 20),
            tooltip: '定位播放文件',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _locatePlayingFile(),
          ),
          // 三点菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: '更多',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onSelected: (value) => _handleMenuAction(value),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'toggle_view',
                child: ListTile(
                  leading: Icon(_viewMode == LocalViewMode.list
                      ? Icons.grid_view
                      : Icons.view_list),
                  title:
                      Text(_viewMode == LocalViewMode.list ? '网格视图' : '列表视图'),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'sort_name',
                child: ListTile(
                  leading: Icon(Icons.sort_by_alpha,
                      color:
                          _sortBy == LocalSortBy.name ? scheme.primary : null),
                  title: const Text('按名称'),
                  trailing: _buildSortOrderIcon(LocalSortBy.name),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              PopupMenuItem<String>(
                value: 'sort_size',
                child: ListTile(
                  leading: Icon(Icons.sort,
                      color:
                          _sortBy == LocalSortBy.size ? scheme.primary : null),
                  title: const Text('按大小'),
                  trailing: _buildSortOrderIcon(LocalSortBy.size),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              PopupMenuItem<String>(
                value: 'sort_lastModified',
                child: ListTile(
                  leading: Icon(Icons.access_time,
                      color: _sortBy == LocalSortBy.lastModified
                          ? scheme.primary
                          : null),
                  title: const Text('按修改时间'),
                  trailing: _buildSortOrderIcon(LocalSortBy.lastModified),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              PopupMenuItem<String>(
                value: 'sort_type',
                child: ListTile(
                  leading: Icon(Icons.category,
                      color:
                          _sortBy == LocalSortBy.type ? scheme.primary : null),
                  title: const Text('按类型'),
                  trailing: _buildSortOrderIcon(LocalSortBy.type),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget? _buildSortOrderIcon(LocalSortBy sortBy) {
    if (_sortBy != sortBy) return null;
    return Icon(
      _sortOrder == LocalSortOrder.ascending
          ? Icons.arrow_upward
          : Icons.arrow_downward,
      size: 16,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _buildBreadcrumbItem(_BreadcrumbSegment seg, ColorScheme scheme) {
    if (seg.isLast) {
      return Text(
        seg.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          fontSize: 14,
        ),
      );
    }
    return InkWell(
      onTap: () {
        setState(() {
          _currentPath = seg.path;
          _loadEntries();
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Text(seg.name,
            style: TextStyle(color: scheme.primary, fontSize: 14)),
      ),
    );
  }

  // ==================== 事件处理 ====================

  void _handleEntryTap(_LocalEntry entry) {
    if (entry.isDirectory) {
      setState(() {
        _currentPath = entry.path;
        _loadEntries();
      });
    } else if (entry.isAudioFile) {
      final audioFiles = _getAudioFiles(_entries);
      _playAudio(entry, audioFiles);
    } else if (_isImageFile(entry.name)) {
      _previewLocalImage(entry);
    }
  }

  void _handleLocalFileAction(_LocalEntry entry, String action) {
    switch (action) {
      case 'play':
        _playAudio(entry, _getAudioFiles(_entries));
        break;
      case 'add_to_library':
        if (entry.isAudioFile) {
          showTextOnSnackBar('请通过音乐库管理添加');
        }
        break;
      case 'scan_folder_to_library':
        if (entry.isDirectory) {
          showTextOnSnackBar('请通过音乐库扫描添加');
        }
        break;
    }
  }

  void _handleMenuAction(String value) {
    switch (value) {
      case 'toggle_view':
        setState(() {
          _viewMode = _viewMode == LocalViewMode.list
              ? LocalViewMode.grid
              : LocalViewMode.list;
        });
        break;
      case 'sort_name':
        _applySort(LocalSortBy.name);
        break;
      case 'sort_size':
        _applySort(LocalSortBy.size);
        break;
      case 'sort_lastModified':
        _applySort(LocalSortBy.lastModified);
        break;
      case 'sort_type':
        _applySort(LocalSortBy.type);
        break;
    }
  }

  void _applySort(LocalSortBy sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortOrder = _sortOrder == LocalSortOrder.ascending
            ? LocalSortOrder.descending
            : LocalSortOrder.ascending;
      } else {
        _sortBy = sortBy;
        _sortOrder = LocalSortOrder.ascending;
      }
    });
  }

  void _previewLocalImage(_LocalEntry entry) {
    final file = io.File(entry.path);
    if (!file.existsSync()) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(entry.name),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Text('图片加载失败')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 工具方法 ====================

  bool _isImageFile(String name) {
    final imageExtensions = {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.svg',
      '.ico'
    };
    return imageExtensions.contains(p.extension(name).toLowerCase());
  }

  String _getParentPath(String currentPath) {
    if (currentPath == _rootPath) return _rootPath;
    final parts = currentPath.split('/');
    if (parts.length <= 2) return _rootPath;
    final parent = parts.sublist(0, parts.length - 1).join('/');
    // 确保不返回到根目录之上
    if (parent.length < _rootPath.length || !parent.startsWith(_rootPath)) {
      return _rootPath;
    }
    return parent;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _BreadcrumbSegment {
  final String name;
  final String path;
  final bool isLast;

  _BreadcrumbSegment({
    required this.name,
    required this.path,
    required this.isLast,
  });
}
