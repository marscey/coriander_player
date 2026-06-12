import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../../cloud_service/cloud_connection.dart';
import '../../cloud_service/cloud_service_manager.dart';
import '../../cloud_service/webdav_service.dart' as webdav;
import '../../cloud_service/cloud_utils.dart' as cloud_utils;
import '../../play_service/play_service.dart';
import '../../platform_helper.dart';
import 'dart:io';
import '../../cloud_service/cloud_audio_player.dart';
import '../../library/genre_service.dart';
import 'package:coriander_player/component/playing_indicator.dart';

enum FileSortBy {
  name,
  size,
  lastModified,
  type,
}

enum FileSortOrder {
  ascending,
  descending,
}

enum FileViewMode {
  list,
  grid,
}

class CloudBrowserArgs {
  final String initialPath;
  final String? locateToPath;
  CloudBrowserArgs(this.initialPath, [this.locateToPath]);
}

class CloudFileBrowser extends StatefulWidget {
  final String connectionId;
  final String initialPath;
  final String? locateToPath;

  const CloudFileBrowser({
    super.key,
    required this.connectionId,
    this.initialPath = '',
    this.locateToPath,
  });

  @override
  State<CloudFileBrowser> createState() => _CloudFileBrowserState();
}

class _CloudFileBrowserState extends State<CloudFileBrowser> {
  late String _currentPath;
  late Future<List<webdav.WebDavFile>> _filesFuture;
  List<webdav.WebDavFile> _currentFiles = [];
  final Set<String> _selectedFiles = {};
  final Set<String> _hoveredPaths = {};
  bool _isSelectionMode = false;

  FileViewMode _viewMode = FileViewMode.list;
  FileSortBy _sortBy = FileSortBy.name;
  FileSortOrder _sortOrder = FileSortOrder.ascending;

  // 搜索
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 滚动控制（用于定位播放文件）
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToLocate = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadFiles();
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

  bool _isOnPlayingPath(webdav.WebDavFile file) {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || nowPlaying.connectionId != widget.connectionId) {
      return false;
    }
    final playingPath = nowPlaying.path;
    if (file.isDirectory) {
      return playingPath.startsWith('${file.path}/') ||
          playingPath == file.path;
    } else {
      return playingPath == file.path;
    }
  }

  void _loadFiles() {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service != null) {
      setState(() {
        _filesFuture = service.listFiles(_currentPath);
      });
    }
  }

  List<webdav.WebDavFile> _sortFiles(List<webdav.WebDavFile> files) {
    final sorted = List<webdav.WebDavFile>.from(files);
    final compare = _sortOrder == FileSortOrder.ascending ? 1 : -1;

    sorted.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      int result;
      switch (_sortBy) {
        case FileSortBy.name:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case FileSortBy.size:
          result = a.size.compareTo(b.size);
          break;
        case FileSortBy.lastModified:
          result = a.lastModified.compareTo(b.lastModified);
          break;
        case FileSortBy.type:
          final extA = path.extension(a.name).toLowerCase();
          final extB = path.extension(b.name).toLowerCase();
          result = extA.compareTo(extB);
          break;
      }
      return result * compare;
    });
    return sorted;
  }

  /// 搜索过滤
  List<webdav.WebDavFile> _filterFiles(List<webdav.WebDavFile> files) {
    if (_searchQuery.isEmpty) return files;
    final query = _searchQuery.toLowerCase();
    return files.where((f) => f.name.toLowerCase().contains(query)).toList();
  }

  List<webdav.WebDavFile> _getDisplayFiles(List<webdav.WebDavFile> files) {
    return _sortFiles(_filterFiles(files));
  }

  /// 定位到当前播放的文件
  void _locatePlayingFile() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || nowPlaying.connectionId != widget.connectionId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未在播放云音频')),
      );
      return;
    }

    final playingPath = nowPlaying.path;
    // 如果播放文件不在当前目录，先导航到其父目录
    final playingDir = playingPath.contains('/')
        ? playingPath.substring(0, playingPath.lastIndexOf('/'))
        : '';

    if (playingDir != _currentPath) {
      setState(() {
        _currentPath = playingDir;
        _searchQuery = '';
        _searchController.clear();
        _loadFiles();
      });
      // 等文件加载后再滚动
      _filesFuture.then((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToPlayingFile();
        });
      });
    } else {
      _scrollToPlayingFile();
    }
  }

  void _scrollToPlayingFile() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null) return;

    final displayFiles = _getDisplayFiles(_currentFiles);
    final index = displayFiles.indexWhere((f) => f.path == nowPlaying.path);
    if (index == -1) return;

    // 检查 ScrollController 是否已附加
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxExtent = _scrollController.position.maxScrollExtent;
    double targetOffset;

    if (_viewMode == FileViewMode.list) {
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

  int _getCrossAxisCount() {
    // 与 _buildGridView 中的计算一致
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth / 160).floor().clamp(2, 10);
  }

  void _scrollToPath(String filePath) {
    final displayFiles = _getDisplayFiles(_currentFiles);
    final index = displayFiles.indexWhere((f) => f.path == filePath);
    if (index == -1) return;
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxExtent = _scrollController.position.maxScrollExtent;
    double targetOffset;

    if (_viewMode == FileViewMode.list) {
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

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<CloudServiceManager>();
    final connection = manager.getConnection(widget.connectionId);

    if (connection == null) {
      return const Center(child: Text('连接不存在'));
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildBreadcrumb(connection),
            Expanded(
              child: FutureBuilder<List<webdav.WebDavFile>>(
            future: _filesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('错误: ${snapshot.error}'));
              }
              final files = snapshot.data ?? [];
              _currentFiles = files;
              // 如果有定位目标，在首次加载后滚动
              if (widget.locateToPath != null && !_hasScrolledToLocate) {
                _hasScrolledToLocate = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _scrollToPath(widget.locateToPath!);
                });
              }
              return _buildContent(files);
            },
          ),
        ),
      ],
    ),
    ),
    );
  }

  Widget _buildContent(List<webdav.WebDavFile> files) {
    final filtered = _filterFiles(files);
    final sorted = _sortFiles(filtered);
    if (_viewMode == FileViewMode.grid) {
      return _buildGridView(sorted);
    }
    return _buildListView(sorted);
  }

  // ==================== 网格视图 ====================

  Widget _buildGridView(List<webdav.WebDavFile> files) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final minCellWidth = PlatformHelper.isMobile ? 110.0 : 160.0;
        final crossAxisCount =
            (screenWidth / minCellWidth).floor().clamp(2, 10);
        final crossAxisSpacing = 8.0;
        final runSpacing = 8.0;
        final padding = 8.0;
        final availableWidth =
            screenWidth - padding * 2 - crossAxisSpacing * (crossAxisCount - 1);
        final cellWidth = availableWidth / crossAxisCount;

        return Scrollbar(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.all(padding),
            child: Wrap(
              spacing: crossAxisSpacing,
              runSpacing: runSpacing,
              children: files.map((file) {
                final audioFiles = files.where((f) => f.isAudioFile).toList();
                return SizedBox(
                  width: cellWidth,
                  child: _buildGridItem(file, audioFiles),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // ==================== 列表视图 ====================

  Widget _buildListView(List<webdav.WebDavFile> files) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: files.length,
      itemBuilder: (context, index) {
        final audioFiles = files.where((f) => f.isAudioFile).toList();
        return _buildFileItem(files[index], index, audioFiles);
      },
    );
  }

  // ==================== 网格项 ====================

  Widget _buildGridItem(
      webdav.WebDavFile file, List<webdav.WebDavFile> currentAudioFiles) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _selectedFiles.contains(file.path);
    final isHovered = _hoveredPaths.contains(file.path);
    final isOnPlayingPath = _isOnPlayingPath(file);
    final isPlayingAudio = isOnPlayingPath && !file.isDirectory;
    final nameColor = isPlayingAudio ? scheme.primary : scheme.onSurface;

    Color bgColor = Colors.transparent;
    if (isSelected) {
      bgColor = scheme.secondaryContainer;
    } else if (isHovered) {
      bgColor = scheme.surfaceContainerHighest.withValues(alpha: 0.15);
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8.0),
      clipBehavior: Clip.none,
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            setState(() {
              if (isSelected) {
                _selectedFiles.remove(file.path);
              } else {
                _selectedFiles.add(file.path);
              }
            });
          } else if (file.isDirectory) {
            setState(() {
              _currentPath = file.path;
              _loadFiles();
            });
          } else if (file.isAudioFile) {
            _playAudio(file, currentAudioFiles);
          } else if (_isImageFile(file.name)) {
            _previewImage(file);
          }
        },
        onLongPress: () {
          if (!_isSelectionMode) {
            setState(() {
              _isSelectionMode = true;
              _selectedFiles.add(file.path);
            });
          }
        },
        onHover: (hovering) {
          setState(() {
            if (hovering) {
              _hoveredPaths.add(file.path);
            } else {
              _hoveredPaths.remove(file.path);
            }
          });
        },
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          padding: const EdgeInsets.all(8),
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
                        child: _buildGridFileIcon(file, isOnPlayingPath),
                      ),
                    ),
                    if (_isSelectionMode)
                      Positioned(
                        top: -2,
                        left: -2,
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedFiles.add(file.path);
                                } else {
                                  _selectedFiles.remove(file.path);
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    if (!_isSelectionMode)
                      Positioned(
                        right: -12,
                        bottom: -10,
                        child: _buildGridMenuButton(file, currentAudioFiles),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                file.name,
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

  /// 网格视图的文件图标
  Widget _buildGridFileIcon(webdav.WebDavFile file, bool isOnPlayingPath) {
    final scheme = Theme.of(context).colorScheme;
    if (file.isDirectory) {
      return Icon(Icons.folder, size: 48, color: scheme.onSurfaceVariant);
    } else if (file.isAudioFile) {
      return Icon(Icons.audiotrack, size: 48, color: scheme.onSurfaceVariant);
    } else if (_isImageFile(file.name)) {
      return _buildImageThumbnail(file, size: 100, borderRadius: 8);
    } else {
      return Icon(Icons.insert_drive_file,
          size: 48, color: scheme.onSurfaceVariant);
    }
  }

  Widget _buildGridMenuButton(
      webdav.WebDavFile file, List<webdav.WebDavFile> currentAudioFiles) {
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
          if (file.isAudioFile)
            const PopupMenuItem(value: 'play', child: Text('播放')),
          if (file.isAudioFile)
            const PopupMenuItem(
                value: 'add_to_playlist', child: Text('添加到播放列表')),
          if (file.isAudioFile)
            const PopupMenuItem(value: 'add_to_library', child: Text('添加到音乐库')),
          if (_isImageFile(file.name))
            const PopupMenuItem(value: 'preview', child: Text('预览图片')),
          if (file.isDirectory)
            const PopupMenuItem(
                value: 'scan_folder_to_library', child: Text('扫描到音乐库')),
          const PopupMenuItem(value: 'download', child: Text('下载')),
        ],
        onSelected: (value) =>
            _handleFileAction(file, value, currentAudioFiles),
      ),
    );
  }

  // ==================== 列表项 ====================

  Widget _buildFileItem(webdav.WebDavFile file, int index,
      List<webdav.WebDavFile> currentAudioFiles) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _selectedFiles.contains(file.path);
    final isHovered = _hoveredPaths.contains(file.path);
    final isOnPlayingPath = _isOnPlayingPath(file);
    final isPlayingAudio = isOnPlayingPath && !file.isDirectory;
    final nameColor = isPlayingAudio ? scheme.primary : scheme.onSurface;
    final subColor = isPlayingAudio ? scheme.primary : scheme.onSurfaceVariant;

    Color bgColor = Colors.transparent;
    if (isSelected) {
      bgColor = scheme.secondaryContainer;
    } else if (isHovered) {
      bgColor = scheme.surfaceContainerHighest.withValues(alpha: 0.15);
    }

    return Material(
      color: bgColor,
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            setState(() {
              if (isSelected) {
                _selectedFiles.remove(file.path);
              } else {
                _selectedFiles.add(file.path);
              }
            });
          } else if (file.isDirectory) {
            setState(() {
              _currentPath = file.path;
              _loadFiles();
            });
          } else if (file.isAudioFile) {
            _playAudio(file, currentAudioFiles);
          } else if (_isImageFile(file.name)) {
            _previewImage(file);
          }
        },
        onLongPress: () {
          if (!_isSelectionMode) {
            setState(() {
              _isSelectionMode = true;
              _selectedFiles.add(file.path);
            });
          }
        },
        onHover: (hovering) {
          setState(() {
            if (hovering) {
              _hoveredPaths.add(file.path);
            } else {
              _hoveredPaths.remove(file.path);
            }
          });
        },
        mouseCursor: SystemMouseCursors.click,
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
                child: _buildListFileIcon(file),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      file.name,
                      style: TextStyle(fontSize: 16, color: nameColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!file.isDirectory)
                      Row(
                        children: [
                          Text(
                            _formatFileSize(file.size),
                            style: TextStyle(
                              fontSize: 13,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (file.lastModified.toIso8601String() !=
                              '0001-01-01T00:00:00.000')
                            Text(
                              _formatDate(file.lastModified),
                              style: TextStyle(
                                fontSize: 13,
                                color: subColor,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              if (_isSelectionMode)
                Checkbox(
                  value: isSelected,
                  onChanged: (selected) {
                    setState(() {
                      if (selected == true) {
                        _selectedFiles.add(file.path);
                      } else {
                        _selectedFiles.remove(file.path);
                      }
                    });
                  },
                )
              else
                _buildListMenuButton(file, currentAudioFiles),
            ],
          ),
        ),
      ),
    );
  }

  /// 列表视图的文件图标
  Widget _buildListFileIcon(webdav.WebDavFile file) {
    final scheme = Theme.of(context).colorScheme;
    if (file.isDirectory) {
      return Icon(Icons.folder, size: 24, color: scheme.onSurfaceVariant);
    } else if (file.isAudioFile) {
      return Icon(Icons.audiotrack, size: 24, color: scheme.onSurfaceVariant);
    } else if (_isImageFile(file.name)) {
      return _buildImageThumbnail(file, size: 48, borderRadius: 8);
    } else {
      return Icon(Icons.insert_drive_file,
          size: 24, color: scheme.onSurfaceVariant);
    }
  }

  // ==================== 列表视图的菜单按钮（行最右侧） ====================

  Widget _buildListMenuButton(
      webdav.WebDavFile file, List<webdav.WebDavFile> currentAudioFiles) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      iconSize: 20,
      icon: const Icon(Icons.more_vert),
      tooltip: '更多',
      itemBuilder: (context) => [
        if (file.isAudioFile)
          const PopupMenuItem(value: 'play', child: Text('播放')),
        if (file.isAudioFile)
          const PopupMenuItem(value: 'add_to_playlist', child: Text('添加到播放列表')),
        if (file.isAudioFile)
          const PopupMenuItem(value: 'add_to_library', child: Text('添加到音乐库')),
        if (_isImageFile(file.name))
          const PopupMenuItem(value: 'preview', child: Text('预览图片')),
        if (file.isDirectory)
          const PopupMenuItem(
              value: 'scan_folder_to_library', child: Text('扫描到音乐库')),
        const PopupMenuItem(value: 'download', child: Text('下载')),
      ],
      onSelected: (value) => _handleFileAction(file, value, currentAudioFiles),
    );
  }

  // ==================== 图片缩略图 ====================

  Widget _buildImageThumbnail(webdav.WebDavFile file,
      {double size = 100, double borderRadius = 8}) {
    final scheme = Theme.of(context).colorScheme;
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child:
            Icon(Icons.image, size: size * 0.5, color: scheme.onSurfaceVariant),
      );
    }
    final imageUrl = service.getFileUrl(file.path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        imageUrl,
        headers: service.getAuthHeaders(),
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Icon(Icons.broken_image,
              size: size * 0.5, color: scheme.onSurfaceVariant),
        ),
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== 面包屑导航栏 ====================

  Widget _buildBreadcrumb(CloudConnection connection) {
    final scheme = Theme.of(context).colorScheme;
    final connectionName = connection.displayName ?? connection.name;

    final segments = <_BreadcrumbSegment>[];
    segments.add(_BreadcrumbSegment(
      name: connectionName,
      path: '',
      isLast: _currentPath.isEmpty,
    ));

    if (_currentPath.isNotEmpty) {
      final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
      for (int i = 0; i < parts.length; i++) {
        final segmentPath = parts.sublist(0, i + 1).join('/');
        segments.add(_BreadcrumbSegment(
          name: parts[i],
          path: segmentPath,
          isLast: i == parts.length - 1,
        ));
      }
    }

    return Container(
      padding: const EdgeInsets.only(left: 4.0, right: 8.0, top: 4.0, bottom: 4.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: _currentPath.isEmpty ? '返回连接列表' : '返回上一级',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              if (_currentPath.isEmpty) {
                context.pop();
              } else {
                setState(() {
                  _currentPath = _getParentPath(_currentPath);
                  _loadFiles();
                });
              }
            },
          ),
          const SizedBox(width: 4),
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
                      setState(() {
                        _searchQuery = value;
                      });
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
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
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
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              size: 20,
            ),
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
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: '取消选择',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedFiles.clear();
                });
              },
            ),
          // 三点菜单（整合视图切换、排序、操作）
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: '更多',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onSelected: (value) => _handleBreadcrumbMenuAction(value),
            itemBuilder: (context) => [
              // 视图切换
              PopupMenuItem<String>(
                value: 'toggle_view',
                child: ListTile(
                  leading: Icon(_viewMode == FileViewMode.list
                      ? Icons.grid_view
                      : Icons.view_list),
                  title: Text(_viewMode == FileViewMode.list ? '网格视图' : '列表视图'),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              const PopupMenuDivider(),
              // 排序选项
              PopupMenuItem<String>(
                value: 'sort_name',
                child: ListTile(
                  leading: Icon(Icons.sort_by_alpha,
                      color:
                          _sortBy == FileSortBy.name ? scheme.primary : null),
                  title: const Text('按名称'),
                  trailing: _buildSortOrderIcon(FileSortBy.name),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              PopupMenuItem<String>(
                value: 'sort_size',
                child: ListTile(
                  leading: Icon(Icons.sort,
                      color:
                          _sortBy == FileSortBy.size ? scheme.primary : null),
                  title: const Text('按大小'),
                  trailing: _buildSortOrderIcon(FileSortBy.size),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              PopupMenuItem<String>(
                value: 'sort_lastModified',
                child: ListTile(
                  leading: Icon(Icons.access_time,
                      color: _sortBy == FileSortBy.lastModified
                          ? scheme.primary
                          : null),
                  title: const Text('按修改时间'),
                  trailing: _buildSortOrderIcon(FileSortBy.lastModified),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              PopupMenuItem<String>(
                value: 'sort_type',
                child: ListTile(
                  leading: Icon(Icons.category,
                      color:
                          _sortBy == FileSortBy.type ? scheme.primary : null),
                  title: const Text('按类型'),
                  trailing: _buildSortOrderIcon(FileSortBy.type),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              const PopupMenuDivider(),
              // 操作选项
              const PopupMenuItem<String>(
                value: 'scan_to_library',
                child: ListTile(
                  leading: Icon(Icons.library_music),
                  title: Text('扫描到音乐库'),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'add_to_playlist',
                child: ListTile(
                  leading: Icon(Icons.playlist_add),
                  title: Text('添加到播放列表'),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
              if (_isSelectionMode)
                const PopupMenuItem<String>(
                  value: 'add_selected_to_library',
                  child: ListTile(
                    leading: Icon(Icons.library_add),
                    title: Text('添加选中到音乐库'),
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

  /// 排序方向指示图标
  Widget? _buildSortOrderIcon(FileSortBy sortBy) {
    if (_sortBy != sortBy) return null;
    return Icon(
      _sortOrder == FileSortOrder.ascending
          ? Icons.arrow_upward
          : Icons.arrow_downward,
      size: 16,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  /// 面包屑菜单操作处理
  void _handleBreadcrumbMenuAction(String value) {
    switch (value) {
      case 'toggle_view':
        setState(() {
          _viewMode = _viewMode == FileViewMode.list
              ? FileViewMode.grid
              : FileViewMode.list;
        });
        break;
      case 'sort_name':
        _applySort(FileSortBy.name);
        break;
      case 'sort_size':
        _applySort(FileSortBy.size);
        break;
      case 'sort_lastModified':
        _applySort(FileSortBy.lastModified);
        break;
      case 'sort_type':
        _applySort(FileSortBy.type);
        break;
      case 'scan_to_library':
        _scanCurrentFolderToLibrary();
        break;
      case 'add_to_playlist':
        final selectedFiles = _getSelectedFiles();
        _addToPlaylist(selectedFiles);
        break;
      case 'add_selected_to_library':
        _addSelectedToLibrary();
        break;
    }
  }

  void _applySort(FileSortBy sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortOrder = _sortOrder == FileSortOrder.ascending
            ? FileSortOrder.descending
            : FileSortOrder.ascending;
      } else {
        _sortBy = sortBy;
        _sortOrder = FileSortOrder.ascending;
      }
    });
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
          _loadFiles();
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Text(
          seg.name,
          style: TextStyle(color: scheme.primary, fontSize: 14),
        ),
      ),
    );
  }

  // ==================== 业务逻辑方法 ====================

  void _previewImage(webdav.WebDavFile file) {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) return;
    final imageUrl = service.getFileUrl(file.path);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(file.name),
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
                child: Image.network(
                  imageUrl,
                  headers: service.getAuthHeaders(),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Text('图片加载失败')),
                  loadingBuilder: (_, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    final ext = path.extension(name).toLowerCase();
    return imageExtensions.contains(ext);
  }

  String _getParentPath(String currentPath) {
    final parts = currentPath.split('/');
    if (parts.length <= 1) return '';
    return parts.sublist(0, parts.length - 1).join('/');
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _playAudio(
      webdav.WebDavFile file, List<webdav.WebDavFile> currentAudioFiles) async {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service != null) {
      try {
        await CloudAudioPlayer.playCloudFile(
          service: service,
          filePath: file.path,
          fileName: file.name,
          folderFiles: currentAudioFiles,
          connectionId: widget.connectionId,
          onPlayStarted: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      '开始播放: ${file.name}（共 ${currentAudioFiles.length} 首）')),
            );
          },
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _handleFileAction(webdav.WebDavFile file, String action,
      List<webdav.WebDavFile> currentAudioFiles) async {
    switch (action) {
      case 'play':
        _playAudio(file, currentAudioFiles);
        break;
      case 'add_to_playlist':
        _addToPlaylist([file]);
        break;
      case 'add_to_library':
        _addAudioToLibrary(file);
        break;
      case 'scan_folder_to_library':
        _scanFolderToLibrary(file);
        break;
      case 'download':
        _downloadFile(file);
        break;
      case 'preview':
        _previewImage(file);
        break;
    }
  }

  List<webdav.WebDavFile> _getSelectedFiles() {
    if (_isSelectionMode && _selectedFiles.isNotEmpty) {
      return _currentFiles
          .where((f) => _selectedFiles.contains(f.path))
          .toList();
    }
    return _currentFiles.where((f) => f.isAudioFile).toList();
  }

  Future<void> _addToPlaylist(List<webdav.WebDavFile> files) async {
    final audioFiles = files.where((f) => f.isAudioFile).toList();
    if (audioFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择音频文件')),
      );
      return;
    }
    try {
      final manager = context.read<CloudServiceManager>();
      final service = manager.getService(widget.connectionId);
      if (service == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法连接到云服务')),
        );
        return;
      }
      await CloudAudioPlayer.addCloudFilesToPlaylist(
        service: service,
        files: audioFiles,
        connectionId: widget.connectionId,
        onProgress: (count) {
          if (count == audioFiles.length) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已添加到播放列表: $count 个文件')),
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加到播放列表失败: ${e.toString()}')),
      );
    }
  }

  Future<void> _scanFolderToLibrary(webdav.WebDavFile folder) async {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法连接到云服务')),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ScanToLibraryDialog(
        service: service,
        folderPath: folder.path,
        folderName: folder.name,
        connectionId: widget.connectionId,
      ),
    );
  }

  Future<void> _scanCurrentFolderToLibrary() async {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法连接到云服务')),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ScanToLibraryDialog(
        service: service,
        folderPath: _currentPath,
        folderName: _currentPath.isEmpty ? '根目录' : _currentPath.split('/').last,
        connectionId: widget.connectionId,
      ),
    );
  }

  Future<void> _addAudioToLibrary(webdav.WebDavFile file) async {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法连接到云服务')),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddToLibraryDialog(
        service: service,
        files: [file],
        connectionId: widget.connectionId,
      ),
    );
  }

  Future<void> _addSelectedToLibrary() async {
    final selectedFiles = _getSelectedFiles();
    final audioFiles = selectedFiles.where((f) => f.isAudioFile).toList();
    if (audioFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择音频文件')),
      );
      return;
    }
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法连接到云服务')),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddToLibraryDialog(
        service: service,
        files: audioFiles,
        connectionId: widget.connectionId,
      ),
    );
  }

  Future<void> _downloadFile(webdav.WebDavFile file) async {
    try {
      final manager = context.read<CloudServiceManager>();
      final service = manager.getService(widget.connectionId);
      if (service == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法连接到云服务')),
        );
        return;
      }
      final downloadDir = await getDownloadDir();
      final localPath = path.join(downloadDir, file.name);
      final bytes = await service.downloadFile(file.path);
      final localFile = File(localPath);
      await localFile.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载完成: ${file.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: ${e.toString()}')),
      );
    }
  }

  Future<String> getDownloadDir() async {
    return cloud_utils.getDownloadDir();
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

class _ScanToLibraryDialog extends StatefulWidget {
  final webdav.WebDavService service;
  final String folderPath;
  final String folderName;
  final String? connectionId;

  const _ScanToLibraryDialog({
    required this.service,
    required this.folderPath,
    required this.folderName,
    this.connectionId,
  });

  @override
  State<_ScanToLibraryDialog> createState() => _ScanToLibraryDialogState();
}

class _ScanToLibraryDialogState extends State<_ScanToLibraryDialog> {
  String _status = '准备扫描...';
  int _count = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    try {
      await CloudAudioPlayer.addCloudFolderToLibrary(
        service: widget.service,
        folderPath: widget.folderPath,
        connectionId: widget.connectionId,
        onProgress: (count) {
          if (mounted) setState(() => _count = count);
        },
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      await GenreService.instance.refresh();
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '扫描失败: $e';
          _done = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('扫描: ${widget.folderName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_done) const CircularProgressIndicator(),
          if (!_done) const SizedBox(height: 16),
          Text(_status),
          if (_count > 0) Text('已发现 $_count 首音频'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_done ? '完成' : '取消'),
        ),
      ],
    );
  }
}

class _AddToLibraryDialog extends StatefulWidget {
  final webdav.WebDavService service;
  final List<webdav.WebDavFile> files;
  final String? connectionId;

  const _AddToLibraryDialog({
    required this.service,
    required this.files,
    this.connectionId,
  });

  @override
  State<_AddToLibraryDialog> createState() => _AddToLibraryDialogState();
}

class _AddToLibraryDialogState extends State<_AddToLibraryDialog> {
  String _status = '准备添加...';
  int _count = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _startAdd();
  }

  Future<void> _startAdd() async {
    try {
      await CloudAudioPlayer.addCloudFilesToLibrary(
        service: widget.service,
        files: widget.files,
        connectionId: widget.connectionId,
        onProgress: (count) {
          if (mounted) setState(() => _count = count);
        },
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      await GenreService.instance.refresh();
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '添加失败: $e';
          _done = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加到音乐库'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_done) const CircularProgressIndicator(),
          if (!_done) const SizedBox(height: 16),
          Text(_status),
          if (_count > 0) Text('已添加 $_count 首音频'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_done ? '完成' : '取消'),
        ),
      ],
    );
  }
}
