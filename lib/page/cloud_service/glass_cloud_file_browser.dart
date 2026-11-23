import 'dart:io';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/auto_scroll_text.dart';
import 'package:coriander_player/cloud_service/cloud_connection.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/cloud_service/webdav_service.dart' as webdav;
import 'package:coriander_player/cloud_service/cloud_utils.dart' as cloud_utils;
import 'package:coriander_player/cloud_service/cloud_audio_player.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/library/genre_service.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'cloud_file_browser.dart';

class GlassCloudFileBrowser extends StatefulWidget {
  final String connectionId;
  final String initialPath;
  final String? locateToPath;

  const GlassCloudFileBrowser({
    super.key,
    required this.connectionId,
    this.initialPath = '',
    this.locateToPath,
  });

  @override
  State<GlassCloudFileBrowser> createState() => _GlassCloudFileBrowserState();
}

class _GlassCloudFileBrowserState extends State<GlassCloudFileBrowser> {
  late String _currentPath;
  late Future<List<webdav.WebDavFile>> _filesFuture;
  List<webdav.WebDavFile> _currentFiles = [];
  final Set<String> _selectedFiles = {};
  bool _isSelectionMode = false;

  FileViewMode _viewMode = FileViewMode.list;
  FileSortBy _sortBy = FileSortBy.name;
  FileSortOrder _sortOrder = FileSortOrder.ascending;

  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final ScrollController _scrollController = ScrollController();
  final _scrollNotifier = ValueNotifier<double>(0.0);
  final _fadeStartNotifier = ValueNotifier<double>(30.0);
  final _fadeEndNotifier = ValueNotifier<double>(90.0);
  bool _hasScrolledToLocate = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadFiles();
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _scrollNotifier.dispose();
    _fadeStartNotifier.dispose();
    _fadeEndNotifier.dispose();
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  /// 退出多选模式
  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
  }

  /// 全选/取消全选（针对当前显示的文件）
  void _toggleSelectAll() {
    setState(() {
      if (_selectedFiles.isEmpty) {
        for (final f in _currentFiles) {
          _selectedFiles.add(f.path);
        }
      } else {
        _selectedFiles.clear();
      }
    });
  }

  /// 是否所有可选文件都已被选中
  bool get _isAllSelected {
    if (_currentFiles.isEmpty) return false;
    for (final f in _currentFiles) {
      if (!_selectedFiles.contains(f.path)) return false;
    }
    return true;
  }

  void _onSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus && _searchController.text.isEmpty && _isSearching) {
      setState(() {
        _isSearching = false;
      });
    }
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

  List<webdav.WebDavFile> _filterFiles(List<webdav.WebDavFile> files) {
    if (_searchQuery.isEmpty) return files;
    final query = _searchQuery.toLowerCase();
    return files.where((f) => f.name.toLowerCase().contains(query)).toList();
  }

  List<webdav.WebDavFile> _getDisplayFiles(List<webdav.WebDavFile> files) {
    return _sortFiles(_filterFiles(files));
  }

  void _locatePlayingFile() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || nowPlaying.connectionId != widget.connectionId) {
      return;
    }

    final playingPath = nowPlaying.path;
    final playingDir = playingPath.contains('/')
        ? playingPath.substring(0, playingPath.lastIndexOf('/'))
        : '';

    if (playingDir != _currentPath) {
      // Stack 模式：push 到正在播放的文件夹，并传入 locateToPath 自动滚动定位
      context.push(
        '${app_paths.CLOUD_BROWSER_PAGE}/${widget.connectionId}',
        extra: CloudBrowserArgs(playingDir, playingPath),
      );
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

    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxExtent = _scrollController.position.maxScrollExtent;
    double targetOffset;

    if (_viewMode == FileViewMode.list) {
      targetOffset = index * 60.0 - (viewportHeight / 2) + 30.0;
    } else {
      final row = (index / _getCrossAxisCount()).floor();
      targetOffset = row * 140.0 - (viewportHeight / 2) + 70.0;
    }

    _scrollController.animateTo(
      targetOffset.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  int _getCrossAxisCount() {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth / 130).floor().clamp(2, 10);
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
      targetOffset = index * 60.0 - (viewportHeight / 2) + 30.0;
    } else {
      final row = (index / _getCrossAxisCount()).floor();
      targetOffset = row * 140.0 - (viewportHeight / 2) + 70.0;
    }

    _scrollController.animateTo(
      targetOffset.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  double _glassThickness(double scrollPixels) {
    final p = (scrollPixels / 50).clamp(0.0, 1.0);
    final smooth = p * p * (3 - 2 * p);
    return 0.5 + smooth * 3.0;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _scrollNotifier.value = notification.metrics.pixels;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manager = context.watch<CloudServiceManager>();
    final connection = manager.getConnection(widget.connectionId);

    if (connection == null) {
      return const Center(child: Text('连接不存在'));
    }

    final folderName = _currentPath.isEmpty
        ? connection.displayName ?? connection.name
        : _currentPath.split('/').last;

    // 沉浸式状态栏：背景延伸到屏幕顶部，状态栏文字颜色适配主题
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Stack 模式：每个文件夹层级是独立路由，iOS 原生侧滑返回自动可用
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
          children: [
            Positioned.fill(child: buildGlassBackground(scheme)),
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: _ScrollOffsetScope(
                  scrollNotifier: _scrollNotifier,
                  fadeStartNotifier: _fadeStartNotifier,
                  fadeEndNotifier: _fadeEndNotifier,
                  child: FutureBuilder<List<webdav.WebDavFile>>(
                    future: _filesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                        child: CupertinoActivityIndicator(),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '错误: ${snapshot.error}',
                          style: TextStyle(color: scheme.onSurface),
                        ),
                      );
                    }
                    final files = snapshot.data ?? [];
                    _currentFiles = files;
                    if (widget.locateToPath != null &&
                        !_hasScrolledToLocate) {
                      _hasScrolledToLocate = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _scrollToPath(widget.locateToPath!);
                      });
                    }
                    return _buildContent(files, connection, folderName);
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _scrollNotifier,
              builder: (context, pixels, child) {
                final thickness = _glassThickness(pixels);
                return _buildFloatingPillNavBar(connection, scheme, thickness, pixels);
              },
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// 生成上级目录面包屑文本（不含当前目录）
  /// 初始状态胶囊只显示这个，避免与大标题重复
  String _buildParentBreadcrumbText(CloudConnection connection) {
    final rootName = connection.displayName ?? connection.name;
    if (_currentPath.isEmpty) return rootName;
    final segments = _currentPath.split('/');
    if (segments.length <= 1) {
      return rootName;
    }
    final parentSegments = segments.sublist(0, segments.length - 1);
    return '$rootName › ${parentSegments.join(' › ')}';
  }

  double _navCollapseProgress(double scrollPixels) {
    const start = 10.0;
    const end = 80.0;
    if (scrollPixels <= start) return 0.0;
    if (scrollPixels >= end) return 1.0;
    final t = (scrollPixels - start) / (end - start);
    return t * t * (3 - 2 * t);
  }

  /// 悬浮导航栏 — iOS 26 Liquid Glass 风格
  ///
  /// 布局结构：
  /// - 左侧：独立返回按钮
  /// - 中间：胶囊容器（滚动时从单行面包屑变为两行标题+面包屑）
  /// - 右侧：独立更多按钮
  ///
  /// 滚动动画：
  /// - progress=0（顶部）：胶囊单行，显示上级面包屑路径（不重复大标题）
  /// - progress=1（滚动后）：胶囊两行，当前目录标题淡入，面包屑变副标题
  Widget _buildFloatingPillNavBar(
      CloudConnection connection, ColorScheme scheme, double thickness, double scrollPixels) {
    final canPop = context.canPop();
    final folderName = _currentPath.isEmpty
        ? (connection.displayName ?? connection.name)
        : _currentPath.split('/').last;
    final parentPath = _buildParentBreadcrumbText(connection);

    final progress = _navCollapseProgress(scrollPixels);
    final topPadding = MediaQuery.of(context).padding.top;

    // 胶囊高度：46（单行） → 60（两行）
    final pillHeight = 46 + (60 - 46) * progress;

    // 胶囊 settings：统一走 searchPillSettings 预设
    final pillSettings =
        searchPillSettings(Theme.of(context).brightness == Brightness.dark);

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + 6.0,
        left: 12.0,
        right: 12.0,
      ),
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            // 左侧：返回按钮 / 多选模式下为退出多选按钮
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _isSelectionMode
                    ? GlassButton(
                        icon: const Icon(Icons.close, size: 20),
                        iconSize: 20,
                        width: 44,
                        height: 44,
                        useOwnLayer: true,
                        quality: GlassQuality.premium,
                        onTap: _exitSelectionMode,
                      )
                    : (canPop
                        ? GlassButton(
                            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                            iconSize: 18,
                            width: 44,
                            height: 44,
                            useOwnLayer: true,
                            quality: GlassQuality.premium,
                            onTap: () => context.pop(),
                          )
                        : const SizedBox(width: 44)),
              ),
            ),
            // 中间：胶囊标题区域
            // 使用 GlassButton.custom 与返回/更多按钮走相同渲染路径
            // 左右各留 52px（44按钮宽 + 8间距），避免玻璃边缘覆盖两侧按钮
            Positioned(
              left: 52.0,
              right: 52.0,
              top: 0,
              bottom: 0,
              child: Center(
                child: GlassButton.custom(
                  onTap: () {},
                  shape: const LiquidRoundedSuperellipse(borderRadius: 26),
                  useOwnLayer: true,
                  quality: GlassQuality.premium,
                  settings: pillSettings,
                  height: pillHeight,
                  stretch: 0.0,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 4.0 + 3.0 * progress,
                    ),
                    height: pillHeight,
                    child: _buildPillContent(scheme, progress, parentPath, folderName),
                  ),
                ),
              ),
            ),
            // 右侧：更多按钮
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildMoreMenu(scheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 胶囊内容：多选模式 / 搜索模式 / 正常标题模式
  Widget _buildPillContent(
      ColorScheme scheme, double progress, String parentPath, String folderName) {
    if (_isSelectionMode) {
      return _buildSelectionBarContent(scheme);
    }
    if (_isSearching) {
      return _buildSearchField(scheme);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // 初始状态：上级面包屑路径（单行，progress=0时显示）
        Align(
          alignment: Alignment.center,
          child: Opacity(
            opacity: 1.0 - progress,
            child: _MarqueeText(
              text: parentPath,
              style: TextStyle(
                fontSize: 15.0,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
        // 顶部：两行布局（progress=1时显示）
        Align(
          alignment: Alignment.topCenter,
          child: Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, (1 - progress) * 8),
              child: _MarqueeText(
                text: folderName,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
        if (parentPath.isNotEmpty && parentPath != folderName)
          Align(
            alignment: Alignment.bottomCenter,
            child: Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, (1 - progress) * -8),
                child: Text(
                  parentPath,
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(fontSize: 14, color: scheme.onSurface),
          cursorColor: scheme.primary,
          decoration: InputDecoration(
            hintText: '搜索文件...',
            hintStyle: TextStyle(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                      _searchFocusNode.requestFocus();
                    },
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 20,
              minHeight: 20,
            ),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
      ),
    );
  }

  /// 多选模式下的胶囊内容：显示已选数量 + 全选/取消按钮
  Widget _buildSelectionBarContent(ColorScheme scheme) {
    final count = _selectedFiles.length;
    final isAll = _isAllSelected;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            count == 0 ? '选择项目' : '已选 $count 项',
            style: TextStyle(
              fontSize: 15.0,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        GestureDetector(
          onTap: _toggleSelectAll,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAll ? Symbols.deselect : Symbols.select_all,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  isAll ? '取消' : '全选',
                  style: TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMoreMenu(ColorScheme scheme) {
    final items = _isSelectionMode
        ? _buildMultiSelectMenuItems(scheme)
        : _buildNormalMenuItems(scheme);
    return GlassMenu(
      menuWidth: 240,
      quality: navButtonQuality,
      triggerBuilder: (context, toggleMenu) => GlassButton(
        onTap: toggleMenu,
        icon: const Icon(Icons.more_horiz, size: 22),
        iconSize: 22,
        width: 44,
        height: 44,
        useOwnLayer: true,
        quality: GlassQuality.premium,
      ),
      items: items,
    );
  }

  /// 普通模式菜单项
  List<Widget> _buildNormalMenuItems(ColorScheme scheme) {
    return [
      GlassMenuItem(
        title: '定位到正在播放',
        icon: const Icon(Icons.my_location, size: 20),
        onTap: () => _locatePlayingFile(),
      ),
      GlassMenuDivider(
        color: scheme.outline.withValues(alpha: 0.5),
      ),
      GlassMenuItem(
        title: _viewMode == FileViewMode.list ? '网格视图' : '列表视图',
        icon: Icon(
          _viewMode == FileViewMode.list
              ? Symbols.grid_view
              : Symbols.list,
          size: 20,
        ),
        onTap: () {
          setState(() {
            _viewMode = _viewMode == FileViewMode.list
                ? FileViewMode.grid
                : FileViewMode.list;
          });
        },
      ),
      GlassMenuDivider(
        color: scheme.outline.withValues(alpha: 0.5),
      ),
      GlassMenuItem(
        title: '按名称',
        icon: Icon(Symbols.sort_by_alpha, size: 20),
        trailing: _sortBy == FileSortBy.name
            ? Icon(
                _sortOrder == FileSortOrder.ascending
                    ? CupertinoIcons.arrow_up
                    : CupertinoIcons.arrow_down,
                size: 14,
                color: scheme.primary,
              )
            : null,
        onTap: () => _applySort(FileSortBy.name),
      ),
      GlassMenuItem(
        title: '按大小',
        icon: Icon(Symbols.sort, size: 20),
        trailing: _sortBy == FileSortBy.size
            ? Icon(
                _sortOrder == FileSortOrder.ascending
                    ? CupertinoIcons.arrow_up
                    : CupertinoIcons.arrow_down,
                size: 14,
                color: scheme.primary,
              )
            : null,
        onTap: () => _applySort(FileSortBy.size),
      ),
      GlassMenuItem(
        title: '按修改时间',
        icon: Icon(Symbols.schedule, size: 20),
        trailing: _sortBy == FileSortBy.lastModified
            ? Icon(
                _sortOrder == FileSortOrder.ascending
                    ? CupertinoIcons.arrow_up
                    : CupertinoIcons.arrow_down,
                size: 14,
                color: scheme.primary,
              )
            : null,
        onTap: () => _applySort(FileSortBy.lastModified),
      ),
      GlassMenuItem(
        title: '按类型',
        icon: Icon(Symbols.category, size: 20),
        trailing: _sortBy == FileSortBy.type
            ? Icon(
                _sortOrder == FileSortOrder.ascending
                    ? CupertinoIcons.arrow_up
                    : CupertinoIcons.arrow_down,
                size: 14,
                color: scheme.primary,
              )
            : null,
        onTap: () => _applySort(FileSortBy.type),
      ),
      GlassMenuDivider(
        color: scheme.outline.withValues(alpha: 0.5),
      ),
      GlassMenuItem(
        title: '播放全部',
        icon: const Icon(Symbols.play_arrow, size: 20),
        onTap: () {
          final audioFiles =
              _currentFiles.where((f) => f.isAudioFile).toList();
          _playAll(audioFiles);
        },
      ),
      GlassMenuItem(
        title: '扫描到音乐库',
        icon: const Icon(Symbols.library_music, size: 20),
        onTap: () => _scanCurrentFolderToLibrary(),
      ),
      GlassMenuItem(
        title: '添加到播放列表',
        icon: const Icon(Symbols.playlist_add, size: 20),
        onTap: () {
          final allAudio = _currentFiles.where((f) => f.isAudioFile).toList();
          _addToPlaylist(allAudio);
        },
      ),
    ];
  }

  /// 多选模式菜单项：针对选中文件的操作
  List<Widget> _buildMultiSelectMenuItems(ColorScheme scheme) {
    final hasSelection = _selectedFiles.isNotEmpty;
    final selectedCount = _selectedFiles.length;
    return [
      GlassMenuItem(
        title: _isAllSelected ? '取消全选' : '全选',
        icon: Icon(
          _isAllSelected ? Symbols.deselect : Symbols.select_all,
          size: 20,
        ),
        onTap: _toggleSelectAll,
      ),
      GlassMenuDivider(
        color: scheme.outline.withValues(alpha: 0.5),
      ),
      GlassMenuItem(
        title: hasSelection
            ? '扫描 $selectedCount 项到音乐库'
            : '扫描当前目录到音乐库',
        icon: const Icon(Symbols.library_music, size: 20),
        onTap: hasSelection ? _addSelectedToLibrary : _scanCurrentFolderToLibrary,
      ),
      GlassMenuItem(
        title: hasSelection
            ? '添加 $selectedCount 项到播放列表'
            : '添加全部到播放列表',
        icon: const Icon(Symbols.playlist_add, size: 20),
        onTap: () {
          final files = _getSelectedFiles();
          _addToPlaylist(files);
        },
      ),
      GlassMenuDivider(
        color: scheme.outline.withValues(alpha: 0.5),
      ),
      GlassMenuItem(
        title: '退出多选',
        icon: const Icon(Icons.close, size: 20),
        onTap: _exitSelectionMode,
      ),
    ];
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

  Widget _buildContent(
      List<webdav.WebDavFile> files, CloudConnection connection, String folderName) {
    final filtered = _filterFiles(files);
    final sorted = _sortFiles(filtered);
    final audioFiles = files.where((f) => f.isAudioFile).toList();
    final audioCount = audioFiles.length;
    final folderCount = files.where((f) => f.isDirectory).length;
    // 只显示非零的部分，都为0则返回空字符串（不显示副标题）
    final parts = <String>[];
    if (folderCount > 0) parts.add('$folderCount 个文件夹');
    if (audioCount > 0) parts.add('$audioCount 首音频');
    final subtitle = parts.join(' · ');

    final scheme = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;
    // 顶部虚化高度 = 状态栏 + 胶囊导航栏(56) + 间距(6) + 缓冲(50)
    final topFadeHeight = topPad + 56 + 6 + 50;

    final fadeColor = scheme.secondaryContainer;
    // 自定义渐变遮罩替代 GlassScrollEdgeEffect
    // 使用与 GlassScrollEdgeStyle.soft 相同的曲线: alphas=[1.0,0.70,0.30,0.04,0.0], stops=[0.0,0.15,0.45,0.75,0.92]
    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: GlassPageHeader(
                title: folderName,
                subtitle: subtitle,
                actionButtons: [
                  _buildHeaderActionButton(
                    icon: CupertinoIcons.search,
                    label: '搜索',
                    scheme: scheme,
                    onTap: () {
                      setState(() {
                        _isSearching = true;
                        _searchFocusNode.requestFocus();
                      });
                    },
                  ),
                  _buildHeaderActionButton(
                    icon: CupertinoIcons.play_fill,
                    label: '播放全部',
                    scheme: scheme,
                    onTap: () => _playAll(audioFiles),
                  ),
                  _buildHeaderActionButton(
                    icon: Symbols.shuffle,
                    label: '随机播放',
                    scheme: scheme,
                    onTap: () => _shuffleAll(audioFiles),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 140.0),
              sliver: _viewMode == FileViewMode.grid
                  ? _buildGridView(sorted)
                  : _buildListView(sorted),
            ),
          ],
        ),
        // 顶部渐变遮罩（直接使用 scheme 颜色，确保主题变化时同步更新）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topFadeHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    fadeColor.withValues(alpha: fadeColor.a * 1.0),
                    fadeColor.withValues(alpha: fadeColor.a * 0.70),
                    fadeColor.withValues(alpha: fadeColor.a * 0.30),
                    fadeColor.withValues(alpha: fadeColor.a * 0.04),
                    fadeColor.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.15, 0.45, 0.75, 0.92],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderActionButton({
    required IconData icon,
    required String label,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: scheme.primary.withValues(alpha: 0.3),
        highlightColor: scheme.primary.withValues(alpha: 0.15),
        child: SizedBox(
          height: 45,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  void _playAll(List<webdav.WebDavFile> audioFiles) {
    if (audioFiles.isEmpty) return;
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) return;
    CloudAudioPlayer.playCloudFile(
      service: service,
      filePath: audioFiles.first.path,
      fileName: audioFiles.first.name,
      folderFiles: audioFiles,
      connectionId: widget.connectionId,
      onPlayStarted: () {},
    );
  }

  void _shuffleAll(List<webdav.WebDavFile> audioFiles) {
    if (audioFiles.isEmpty) return;
    final shuffled = List<webdav.WebDavFile>.from(audioFiles);
    shuffled.shuffle();
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) return;
    CloudAudioPlayer.playCloudFile(
      service: service,
      filePath: shuffled.first.path,
      fileName: shuffled.first.name,
      folderFiles: shuffled,
      connectionId: widget.connectionId,
      onPlayStarted: () {},
    );
    PlayService.instance.playbackService.useShuffle(true);
  }

  // ─── 列表视图 ──────────────────────────────────────────

  SliverList _buildListView(List<webdav.WebDavFile> files) {
    final audioFiles = files.where((f) => f.isAudioFile).toList();
    return SliverList.separated(
      itemCount: files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8.0),
      itemBuilder: (context, index) {
        return _buildListFileItem(files[index], index, audioFiles);
      },
    );
  }

  Widget _buildListFileItem(webdav.WebDavFile file, int index,
      List<webdav.WebDavFile> currentAudioFiles) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _selectedFiles.contains(file.path);
    final isOnPlayingPath = _isOnPlayingPath(file);
    final isPlayingAudio = isOnPlayingPath && !file.isDirectory;
    final nameColor = isPlayingAudio ? scheme.primary : scheme.onSurface;
    final subColor = isPlayingAudio ? scheme.primary : scheme.onSurfaceVariant;

    return InkWell(
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
          // Stack 模式：push 新路由进入子文件夹，原生侧滑返回自动可用
          context.push(
            '${app_paths.CLOUD_BROWSER_PAGE}/${widget.connectionId}',
            extra: CloudBrowserArgs(file.path),
          );
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: scheme.primary, width: 1.5)
              : null,
        ),
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.only(left: 6.0, right: 0.0),
            child: Row(
              children: [
                if (AppSettings.instance.showTrackIndex) ...[
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
                  const SizedBox(width: 4),
                ],
                PlayingIndicatorOverlay(
                  size: PlayingIndicatorSize.small,
                  isActivelyPlaying: isOnPlayingPath,
                  child: _buildListFileIcon(file, scheme),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AutoScrollText(
                        text: file.name,
                        style: TextStyle(fontSize: 15, color: nameColor, height: 1.2),
                        scrollSpeed: AppSettings.instance.marqueeSpeed,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Row(
                          children: [
                            if (file.isDirectory)
                              Text(
                                '文件夹',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subColor,
                                  height: 1.2,
                                ),
                              )
                            else
                              Text(
                                _formatFileSize(file.size),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subColor,
                                  height: 1.2,
                                ),
                              ),
                            const SizedBox(width: 10),
                            if (file.lastModified.toIso8601String() !=
                                '0001-01-01T00:00:00.000')
                              Text(
                                _formatDate(file.lastModified),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subColor,
                                  height: 1.2,
                                ),
                              ),
                          ],
                        ),
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
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  )
                else
                  _buildListMenuButton(file, currentAudioFiles, scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListFileIcon(webdav.WebDavFile file, ColorScheme scheme) {
    const iconSize = 40.0;
    if (file.isDirectory) {
      return _buildFolderCoverPlaceholder(scheme, size: iconSize);
    } else if (file.isAudioFile) {
      return _buildAudioCoverPlaceholder(scheme, size: iconSize);
    } else if (_isImageFile(file.name)) {
      return _buildImageThumbnail(file, size: iconSize, borderRadius: 10);
    } else {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: Icon(CupertinoIcons.doc, size: 32, color: scheme.onSurfaceVariant),
      );
    }
  }

  /// 音频文件占位封面 — 渐变背景 + 音符图标（与迷你播放器默认封面一致）
  Widget _buildAudioCoverPlaceholder(ColorScheme scheme, {double size = 28}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: 0.8),
              scheme.primary.withValues(alpha: 0.4),
            ],
          ),
        ),
        child: Icon(
          Symbols.music_note,
          color: scheme.onPrimary.withValues(alpha: 0.85),
          size: size * 0.6,
        ),
      ),
    );
  }

  /// 文件夹占位封面 — 渐变背景 + 文件夹图标（与音频图标风格统一）
  Widget _buildFolderCoverPlaceholder(ColorScheme scheme, {double size = 28}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: 0.8),
              scheme.primary.withValues(alpha: 0.4),
            ],
          ),
        ),
        child: Icon(
          CupertinoIcons.folder_fill,
          color: scheme.onPrimary.withValues(alpha: 0.85),
          size: size * 0.6,
        ),
      ),
    );
  }

  Widget _buildListMenuButton(webdav.WebDavFile file,
      List<webdav.WebDavFile> currentAudioFiles, ColorScheme scheme) {
    return GlassMenu(
      menuWidth: 200,
      quality: GlassQuality.standard,
      triggerBuilder: (context, toggleMenu) => IconButton(
        onPressed: toggleMenu,
        icon: const Icon(Icons.more_vert, size: 20),
        iconSize: 20,
        padding: const EdgeInsets.only(left: 4, right: 0, top: 6, bottom: 6),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        color: scheme.onSurfaceVariant,
      ),
      items: [
        if (file.isAudioFile)
          GlassMenuItem(
            title: '播放',
            icon: const Icon(Symbols.play_arrow, size: 20),
            onTap: () => _playAudio(file, currentAudioFiles),
          ),
        if (file.isAudioFile)
          GlassMenuItem(
            title: '添加到播放列表',
            icon: const Icon(Symbols.playlist_add, size: 20),
            onTap: () => _addToPlaylist([file]),
          ),
        if (file.isAudioFile)
          GlassMenuItem(
            title: '添加到音乐库',
            icon: const Icon(Symbols.library_add, size: 20),
            onTap: () => _addAudioToLibrary(file),
          ),
        if (_isImageFile(file.name))
          GlassMenuItem(
            title: '预览图片',
            icon: const Icon(Symbols.image, size: 20),
            onTap: () => _previewImage(file),
          ),
        if (file.isDirectory)
          GlassMenuItem(
            title: '扫描到音乐库',
            icon: const Icon(Symbols.library_music, size: 20),
            onTap: () => _scanFolderToLibrary(file),
          ),
        GlassMenuItem(
          title: '下载',
          icon: const Icon(Symbols.download, size: 20),
          onTap: () => _downloadFile(file),
        ),
      ],
    );
  }

  // ─── 网格视图 ──────────────────────────────────────────

  SliverPadding _buildGridView(List<webdav.WebDavFile> files) {
    final audioFiles = files.where((f) => f.isAudioFile).toList();
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getCrossAxisCount(),
          crossAxisSpacing: 8.0,
          mainAxisSpacing: 8.0,
          childAspectRatio: 0.8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return _buildGridFileItem(files[index], audioFiles);
          },
          childCount: files.length,
        ),
      ),
    );
  }

  Widget _buildGridFileItem(
      webdav.WebDavFile file, List<webdav.WebDavFile> currentAudioFiles) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _selectedFiles.contains(file.path);
    final isOnPlayingPath = _isOnPlayingPath(file);

    return InkWell(
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
          // Stack 模式：push 新路由进入子文件夹
          context.push(
            '${app_paths.CLOUD_BROWSER_PAGE}/${widget.connectionId}',
            extra: CloudBrowserArgs(file.path),
          );
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: scheme.primary, width: 1.5)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: PlayingIndicatorOverlay(
                    size: PlayingIndicatorSize.large,
                    isActivelyPlaying: isOnPlayingPath,
                    child: _buildGridFileIcon(file, scheme),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                file.name,
                style: TextStyle(fontSize: 12, color: scheme.onSurface),
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

  Widget _buildGridFileIcon(webdav.WebDavFile file, ColorScheme scheme) {
    if (file.isDirectory) {
      return _buildFolderCoverPlaceholder(scheme, size: 64);
    } else if (file.isAudioFile) {
      return _buildAudioCoverPlaceholder(scheme, size: 64);
    } else if (_isImageFile(file.name)) {
      return _buildImageThumbnail(file, size: 80, borderRadius: 8);
    } else {
      return Icon(CupertinoIcons.doc, size: 48, color: scheme.onSurfaceVariant);
    }
  }

  // ─── 图片缩略图 ────────────────────────────────────────

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
        child: Icon(Icons.image, size: size * 0.5, color: scheme.onSurfaceVariant),
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
                child: CupertinoActivityIndicator(
                  radius: 10,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── 业务逻辑方法 ─────────────────────────────────────

  void _previewImage(webdav.WebDavFile file) {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) return;
    final imageUrl = service.getFileUrl(file.path);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
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
                      child: CupertinoActivityIndicator(),
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

  Future<void> _playAudio(webdav.WebDavFile file,
      List<webdav.WebDavFile> currentAudioFiles) async {
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
          onPlayStarted: () {},
        );
      } catch (e) {
        if (!mounted) return;
      }
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
    if (audioFiles.isEmpty) return;
    try {
      final manager = context.read<CloudServiceManager>();
      final service = manager.getService(widget.connectionId);
      if (service == null) return;
      await CloudAudioPlayer.addCloudFilesToPlaylist(
        service: service,
        files: audioFiles,
        connectionId: widget.connectionId,
        onProgress: (count) {},
      );
    } catch (_) {}
  }

  Future<void> _scanFolderToLibrary(webdav.WebDavFile folder) async {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) return;
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
    if (service == null) return;
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
    if (service == null) return;
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
    if (audioFiles.isEmpty) return;
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service == null) return;
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
      if (service == null) return;
      final downloadDir = await cloud_utils.getDownloadDir();
      final localPath = path.join(downloadDir, file.name);
      final bytes = await service.downloadFile(file.path);
      final localFile = File(localPath);
      await localFile.writeAsBytes(bytes);
      if (!mounted) return;
    } catch (_) {}
  }
}

// ─── 辅助组件 ──────────────────────────────────────────

/// 超长文本滚动展示（marquee），短文本正常显示
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    required this.text,
    required this.style,
    this.enabled = true,
    this.speed = 40.0,
  });

  final String text;
  final TextStyle style;
  final bool enabled;
  final double speed;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 12000),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style || oldWidget.enabled != widget.enabled || oldWidget.speed != widget.speed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
  }

  void _checkOverflow() {
    final ctx = context;
    if (!mounted) return;
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final available = ctx.size?.width ?? 0;
    final needs = widget.enabled && tp.width > available + 1;
    if (needs != _needsScroll) {
      setState(() => _needsScroll = needs);
      if (needs) {
        // 根据速度调整动画时长：速度越快，时长越短
        final baseDuration = 12000.0;
        final adjustedDuration = baseDuration * (40.0 / widget.speed);
        _ctrl.duration = Duration(milliseconds: adjustedDuration.round());
        _ctrl.repeat();
      } else {
        _ctrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final textWidth = tp.width;
    final gap = 40.0;
    return ClipRect(
      child: SizedBox(
        height: widget.style.fontSize != null
            ? widget.style.fontSize! * 1.4
            : null,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final shift = (textWidth + gap) * t;
            return Transform.translate(
              offset: Offset(-shift, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.text, style: widget.style, maxLines: 1),
                  SizedBox(width: gap),
                  Text(widget.text, style: widget.style, maxLines: 1),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── InheritedWidget：共享滚动偏移量 ─────────────────

class _ScrollOffsetScope extends InheritedWidget {
  const _ScrollOffsetScope({
    required this.scrollNotifier,
    required this.fadeStartNotifier,
    required this.fadeEndNotifier,
    required super.child,
  });

  final ValueNotifier<double> scrollNotifier;
  final ValueNotifier<double> fadeStartNotifier;
  final ValueNotifier<double> fadeEndNotifier;

  static _ScrollOffsetScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_ScrollOffsetScope>();
    assert(scope != null,
        'GlassPageHeader must be used inside _ScrollOffsetScope');
    return scope!;
  }

  @override
  bool updateShouldNotify(_ScrollOffsetScope oldWidget) =>
      scrollNotifier != oldWidget.scrollNotifier ||
      fadeStartNotifier != oldWidget.fadeStartNotifier ||
      fadeEndNotifier != oldWidget.fadeEndNotifier;
}

// ─── ValueListenableBuilder3 ─────────────────────────

class ValueListenableBuilder3<A, B, C> extends StatelessWidget {
  const ValueListenableBuilder3({
    super.key,
    required this.scrollNotifier,
    required this.fadeStartNotifier,
    required this.fadeEndNotifier,
    required this.builder,
    this.child,
  });

  final ValueNotifier<A> scrollNotifier;
  final ValueNotifier<B> fadeStartNotifier;
  final ValueNotifier<C> fadeEndNotifier;
  final Widget Function(BuildContext context, A a, B b, C c, Widget? child)
      builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: scrollNotifier,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: fadeStartNotifier,
          builder: (context, b, _) {
            return ValueListenableBuilder<C>(
              valueListenable: fadeEndNotifier,
              builder: (context, c, _) => builder(context, a, b, c, child),
            );
          },
        );
      },
    );
  }
}

// ─── GlassPageHeader ──────────────────────────────────

class GlassPageHeader extends StatefulWidget {
  const GlassPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionButtons,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actionButtons;

  @override
  State<GlassPageHeader> createState() => _GlassPageHeaderState();
}

class _GlassPageHeaderState extends State<GlassPageHeader> {
  final _titleAreaKey = GlobalKey();
  double? _measuredTitleHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measureTitleHeight);
  }

  @override
  void didUpdateWidget(covariant GlassPageHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.subtitle != widget.subtitle) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _measureTitleHeight(null));
    }
  }

  void _measureTitleHeight(Duration? _) {
    final context = _titleAreaKey.currentContext;
    if (context == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final height = box.size.height;
    if (height <= 0 || height == _measuredTitleHeight) return;

    setState(() {
      _measuredTitleHeight = height;
    });

    const gapBetweenNavBarAndTitle = 8.0;
    final fadeStart = gapBetweenNavBarAndTitle;
    final fadeEnd = gapBetweenNavBarAndTitle + height;

    final scope = _ScrollOffsetScope.of(this.context);
    scope.fadeStartNotifier.value = fadeStart;
    scope.fadeEndNotifier.value = fadeEnd;
  }

  double _progress(double offset, double start, double end) {
    if (end <= start) return offset >= end ? 1.0 : 0.0;
    return ((offset - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusBarH = MediaQuery.of(context).padding.top;
    const navBarH = 56.0; // 胶囊导航栏容器高度

    final scope = _ScrollOffsetScope.of(context);
    final scrollNotifier = scope.scrollNotifier;

    return ValueListenableBuilder3<double, double, double>(
      scrollNotifier: scrollNotifier,
      fadeStartNotifier: scope.fadeStartNotifier,
      fadeEndNotifier: scope.fadeEndNotifier,
      builder: (context, offset, fadeStart, fadeEnd, _) {
        final progress = _progress(offset, fadeStart, fadeEnd);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: statusBarH + navBarH + 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Opacity(
                opacity: 1.0 - progress,
                child: Column(
                  key: _titleAreaKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MarqueeText(
                      text: widget.title,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                      enabled: AppSettings.instance.marqueeEnabled,
                      speed: AppSettings.instance.marqueeSpeed,
                    ),
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (widget.actionButtons != null && widget.actionButtons!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (int i = 0; i < widget.actionButtons!.length; i++) ...[
                            Expanded(child: widget.actionButtons![i]),
                            if (i < widget.actionButtons!.length - 1)
                              const SizedBox(width: 14),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── 对话框 ───────────────────────────────────────────

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
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      settings: sheetSettings(scheme.brightness == Brightness.dark),
      margin: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '扫描: ${widget.folderName}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  if (!_done) const CupertinoActivityIndicator(),
                  if (!_done) const SizedBox(height: 12),
                  Text(
                    _status,
                    style: TextStyle(color: scheme.onSurface),
                    textAlign: TextAlign.center,
                  ),
                  if (_count > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '已发现 $_count 首音频',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_done ? '完成' : '取消'),
              ),
            ),
          ],
        ),
      ),
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
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      settings: sheetSettings(scheme.brightness == Brightness.dark),
      margin: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '添加到音乐库',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  if (!_done) const CupertinoActivityIndicator(),
                  if (!_done) const SizedBox(height: 12),
                  Text(
                    _status,
                    style: TextStyle(color: scheme.onSurface),
                    textAlign: TextAlign.center,
                  ),
                  if (_count > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '已添加 $_count 首',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_done ? '完成' : '取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
