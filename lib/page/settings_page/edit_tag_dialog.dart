import 'dart:typed_data';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_scraper.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/metadata/scraper_orchestrator.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 编辑音频标签对话框
///
/// 统一的元数据编辑与刮削入口：
/// - 手动编辑所有标签字段（标题/艺术家/专辑/轨道号/年份/流派）
/// - 在线搜索元数据+封面（同一搜索源）
/// - 搜索结果点击后回显到标签栏，不直接应用
/// - 显示当前封面（嵌入或缓存）
/// - 点击"应用并保存"才写入文件
///
/// 可通过 [autoSearch] 参数直接进入搜索模式（替代独立的刮削弹窗）
class EditTagDialog extends StatefulWidget {
  final Audio audio;

  /// 是否自动进入搜索模式（用于"刮削元数据"菜单入口）
  final bool autoSearch;

  const EditTagDialog(
      {super.key, required this.audio, this.autoSearch = false});

  @override
  State<EditTagDialog> createState() => _EditTagDialogState();
}

class _EditTagDialogState extends State<EditTagDialog> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _trackController;
  late TextEditingController _yearController;
  late TextEditingController _genreController;

  bool _isSearching = false;
  bool _isSaving = false;
  bool _isLoadingCover = false;
  List<ScrapeResult> _searchResults = [];
  String? _searchError;

  ScrapeResult? _selectedResult;

  Uint8List? _currentCoverData;
  Uint8List? _selectedCoverData;
  String? _selectedCoverMimeType;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.audio.title);
    _artistController = TextEditingController(text: widget.audio.artist);
    _albumController = TextEditingController(text: widget.audio.album);
    _trackController = TextEditingController(
      text: widget.audio.track > 0 ? widget.audio.track.toString() : '',
    );
    _yearController = TextEditingController();
    _genreController = TextEditingController();

    _loadCurrentCover();

    if (widget.autoSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchOnline());
    }
  }

  Future<void> _loadCurrentCover() async {
    setState(() => _isLoadingCover = true);
    try {
      final audioId =
          await MetadataService.instance.computeAudioId(widget.audio);

      Uint8List? coverBytes;

      // 内嵌封面始终最优先
      // 云音频：有本地缓存文件时从缓存文件读内嵌，无缓存文件跳过
      if (!widget.audio.isCloudAudio) {
        coverBytes = await getPictureFromPath(
          path: widget.audio.path,
          width: 400,
          height: 400,
        );
      } else {
        final cachedPath =
            CloudCacheManager.instance.getCachedFilePath(widget.audio.path);
        if (cachedPath != null) {
          coverBytes = await getPictureFromPath(
            path: cachedPath,
            width: 400,
            height: 400,
          );
        }
      }

      // 内嵌封面不存在时，从缓存获取
      if (coverBytes == null && audioId != null) {
        final cached = await MediaCache.instance.getCover(audioId);
        if (cached != null) {
          coverBytes = cached.$1;
        }
      }

      if (audioId != null) {
        final record = await MetadataStore.instance.getMetadata(audioId);
        if (record != null) {
          if (record.year != null && _yearController.text.isEmpty) {
            _yearController.text = record.year.toString();
          }
          if (record.genre != null && _genreController.text.isEmpty) {
            _genreController.text = record.genre!;
          }
        }
      }

      if (coverBytes != null && mounted) {
        setState(() {
          _currentCoverData = coverBytes;
          _selectedCoverData = coverBytes;
        });
      }
    } catch (e) {
      LOGGER.w("[EditTagDialog] Failed to load current cover: $e");
    } finally {
      if (mounted) setState(() => _isLoadingCover = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _trackController.dispose();
    _yearController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = PlatformHelper.isMobile;

    if (isMobile) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          leading: IconButton.filledTonal(
            icon: const Icon(Symbols.arrow_back, size: 20.0),
            onPressed: () => Navigator.pop(context, false),
            style: IconButton.styleFrom(
              minimumSize: const Size(40, 40),
              backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            ),
          ),
          title: Text(widget.autoSearch ? "刮削元数据" : "编辑标签"),
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _saveTags,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("保存"),
            ),
          ],
        ),
        body: Column(
          children: [
            // 固定标签编辑区（不滚动）
            _buildMobileTagSection(scheme),
            // 搜索按钮 + 提示文字（固定行）
            _buildSearchBarRow(scheme),
            // 搜索结果（可滚动）
            Expanded(
              child: _buildSearchResultsList(scheme),
            ),
          ],
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: SizedBox(
        width: 640.0,
        height: 720.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(scheme),
              const SizedBox(height: 16.0),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTagFields(scheme),
                    ),
                    const SizedBox(width: 16.0),
                    Expanded(
                      flex: 2,
                      child: _buildCoverSection(scheme),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              _buildFooter(scheme),
            ],
          ),
        ),
      ),
    );
  }

  /// 移动端固定标签编辑区：封面左对齐 + 标签字段右对齐
  Widget _buildMobileTagSection(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面图片（左对齐，点击可查看大图）
          GestureDetector(
            onTap: _selectedCoverData != null
                ? () => _showCoverPreview(context, scheme)
                : null,
            child: Semantics(
              identifier: "cover_image",
              button: true,
              child: SizedBox(
                width: 96.0,
                height: 96.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: _buildCoverPreview(scheme),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12.0),
          // 标签字段（右侧紧凑排列）
          Expanded(
            child: Column(
              children: [
                _buildCompactField(_titleController, "标题", scheme,
                    icon: Symbols.music_note),
                const SizedBox(height: 6.0),
                _buildCompactField(_artistController, "艺术家", scheme,
                    icon: Symbols.person),
                const SizedBox(height: 6.0),
                _buildCompactField(_albumController, "专辑", scheme,
                    icon: Symbols.album),
                const SizedBox(height: 6.0),
                // 轨道号 / 年份 / 流派 三列紧凑行
                Row(
                  children: [
                    Expanded(
                      child: _buildCompactField(
                        _trackController,
                        "#",
                        scheme,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: _buildCompactField(
                        _yearController,
                        "年份",
                        scheme,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: _buildCompactField(
                        _genreController,
                        "流派",
                        scheme,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑输入框（移动端专用，高度更小）
  Widget _buildCompactField(
    TextEditingController controller,
    String label,
    ColorScheme scheme, {
    TextInputType? keyboardType,
    IconData? icon,
  }) {
    return SizedBox(
      height: 40.0,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null
              ? Padding(
                  padding: const EdgeInsets.only(left: 8.0, right: 4.0),
                  child: Icon(icon, size: 14.0),
                )
              : null,
          prefixIconConstraints:
              const BoxConstraints(minWidth: 28.0, minHeight: 0),
          labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        ),
      ),
    );
  }

  /// 搜索按钮 + 提示文字同一行
  Widget _buildSearchBarRow(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Row(
        children: [
          // 在线搜索按钮（缩小）
          SizedBox(
            height: 32.0,
            child: FilledButton.tonalIcon(
              onPressed: _isSearching ? null : _searchOnline,
              icon: _isSearching
                  ? const SizedBox(
                      width: 14.0,
                      height: 14.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    )
                  : const Icon(Symbols.search, size: 16.0),
              label: const Text("在线搜索", style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          // 提示文字
          Expanded(
            child: Text(
              "搜索结果点击回显到标签栏",
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索结果列表（可滚动区域）
  Widget _buildSearchResultsList(ColorScheme scheme) {
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _searchError!,
            style: TextStyle(color: scheme.error, fontSize: 13.0),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.search,
                size: 32.0,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 8.0),
              Text(
                _isSearching ? "搜索中..." : "点击「在线搜索」查找元数据",
                style: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 13.0,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildResultItem(_searchResults[index], scheme);
      },
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Row(
      children: [
        Icon(Symbols.edit, color: scheme.primary),
        const SizedBox(width: 8.0),
        Text(
          widget.autoSearch ? "刮削元数据" : "编辑标签",
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTagFields(ColorScheme scheme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(_titleController, "标题", scheme,
              icon: Symbols.music_note),
          const SizedBox(height: 8.0),
          _buildTextField(_artistController, "艺术家", scheme,
              icon: Symbols.person),
          const SizedBox(height: 8.0),
          _buildTextField(_albumController, "专辑", scheme, icon: Symbols.album),
          const SizedBox(height: 8.0),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  _trackController,
                  "轨道号",
                  scheme,
                  keyboardType: TextInputType.number,
                  icon: Symbols.numbers,
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: _buildTextField(
                  _yearController,
                  "年份",
                  scheme,
                  keyboardType: TextInputType.number,
                  icon: Symbols.calendar_today,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          _buildTextField(_genreController, "流派", scheme, icon: Symbols.genres),
          const SizedBox(height: 12.0),
          FilledButton.icon(
            onPressed: _isSearching ? null : _searchOnline,
            icon: _isSearching
                ? const SizedBox(
                    width: 16.0,
                    height: 16.0,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.0, color: Colors.white),
                  )
                : const Icon(Symbols.search, size: 18.0),
            label: const Text("在线搜索"),
          ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Text(
                _searchError!,
                style: TextStyle(color: scheme.error, fontSize: 13.0),
              ),
            ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 12.0),
            Text(
              "搜索结果（点击回显到标签栏）",
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13.0,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8.0),
            ..._searchResults
                .take(8)
                .map((result) => _buildResultItem(result, scheme)),
          ],
        ],
      ),
    );
  }

  Widget _buildCoverSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SizedBox(
            width: 140,
            height: 140,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: _buildCoverPreview(scheme),
            ),
          ),
        ),
        if (_selectedCoverData != null &&
            _selectedCoverData != _currentCoverData)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              "封面已更新（来自搜索结果）",
              style: TextStyle(color: scheme.primary, fontSize: 11.0),
            ),
          ),
      ],
    );
  }

  Widget _buildCoverPreview(ColorScheme scheme) {
    if (_isLoadingCover) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.0));
    }

    if (_selectedCoverData != null) {
      return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Image.memory(
            _selectedCoverData!,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Symbols.album,
            size: 32.0,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 4.0),
          Text(
            "暂无封面",
            style: TextStyle(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 11.0,
            ),
          ),
        ],
      ),
    );
  }

  /// 点击查看封面大图
  void _showCoverPreview(BuildContext context, ColorScheme scheme) {
    if (_selectedCoverData == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16.0),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.memory(
                _selectedCoverData!,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    ColorScheme scheme, {
    TextInputType? keyboardType,
    IconData? icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 18.0) : null,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
      ),
    );
  }

  Widget _buildResultItem(ScrapeResult result, ColorScheme scheme) {
    final isSelected = _selectedResult == result;

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      color:
          isSelected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
        title: Text(
          result.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13.0,
            color: isSelected ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
        ),
        subtitle: Text(
          [
            result.artist ?? '',
            if (result.album != null) result.album,
            if (result.year != null) '${result.year}',
          ].join(' - '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.0,
            color: isSelected
                ? scheme.onPrimaryContainer.withValues(alpha: 0.7)
                : scheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Text(
                result.source,
                style:
                    TextStyle(fontSize: 10.0, color: scheme.onSurfaceVariant),
              ),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Icon(Symbols.check_circle,
                    color: scheme.primary, size: 16.0),
              ),
          ],
        ),
        onTap: () => _applyResultToFields(result),
      ),
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("取消"),
        ),
        const SizedBox(width: 8.0),
        FilledButton.icon(
          onPressed: _isSaving ? null : _saveTags,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.0, color: Colors.white),
                )
              : const Icon(Symbols.save, size: 18.0),
          label: const Text("应用并保存"),
        ),
      ],
    );
  }

  /// 在线搜索元数据+封面
  Future<void> _searchOnline() async {
    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResults = [];
      _selectedResult = null;
    });

    try {
      final results = await ScraperOrchestrator.instance.search(
        _titleController.text,
        artist:
            _artistController.text.isNotEmpty ? _artistController.text : null,
        album: _albumController.text.isNotEmpty ? _albumController.text : null,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
          if (results.isEmpty) {
            _searchError = '未找到匹配结果';
          }
        });
      }
    } catch (e) {
      LOGGER.e("[EditTagDialog] Search failed: $e");
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchError = '搜索失败: $e';
        });
      }
    }
  }

  /// 将搜索结果回显到标签栏
  Future<void> _applyResultToFields(ScrapeResult result) async {
    setState(() => _selectedResult = result);

    _titleController.text = result.title ?? _titleController.text;
    _artistController.text = result.artist ?? _artistController.text;
    _albumController.text = result.album ?? _albumController.text;
    if (result.track != null) {
      _trackController.text = result.track.toString();
    }
    if (result.year != null) {
      _yearController.text = result.year.toString();
    }
    if (result.genre != null) {
      _genreController.text = result.genre!;
    }

    // 自动获取封面
    try {
      final scraper = ScraperOrchestrator.instance.getScraper(result.source);
      if (scraper != null) {
        final coverData = await scraper.fetchCover(result);
        if (coverData != null && mounted) {
          setState(() {
            _selectedCoverData = coverData;
            _selectedCoverMimeType = 'image/jpeg';
          });
        }
      }
    } catch (e) {
      LOGGER.w("[EditTagDialog] Failed to fetch cover for result: $e");
    }
  }

  /// 保存标签到文件
  Future<void> _saveTags() async {
    setState(() => _isSaving = true);

    try {
      final audio = widget.audio;
      final path = audio.path;
      int? track;
      int? year;

      if (_trackController.text.isNotEmpty) {
        track = int.tryParse(_trackController.text);
      }
      if (_yearController.text.isNotEmpty) {
        year = int.tryParse(_yearController.text);
      }

      // 本地音频：写入文件 + 缓存；云音频：仅写入缓存
      if (!audio.isCloudAudio) {
        await MetadataService.instance.writeTags(
          path: path,
          title: _titleController.text,
          artist: _artistController.text,
          album: _albumController.text,
          track: track,
          year: year,
          genre:
              _genreController.text.isNotEmpty ? _genreController.text : null,
        );

        if (_selectedCoverData != null &&
            _selectedCoverData != _currentCoverData) {
          await MetadataService.instance.writeCover(
            path: path,
            coverData: _selectedCoverData!,
            mimeType: _selectedCoverMimeType ?? 'image/jpeg',
          );
        }
      } else {
        // 云音频：如果有本地缓存文件，写入缓存文件的内嵌标签
        final cachedPath = CloudCacheManager.instance.getCachedFilePath(path);
        if (cachedPath != null) {
          try {
            await MetadataService.instance.writeTags(
              path: cachedPath,
              title: _titleController.text,
              artist: _artistController.text,
              album: _albumController.text,
              track: track,
              year: year,
              genre: _genreController.text.isNotEmpty
                  ? _genreController.text
                  : null,
            );
            if (_selectedCoverData != null &&
                _selectedCoverData != _currentCoverData) {
              await MetadataService.instance.writeCover(
                path: cachedPath,
                coverData: _selectedCoverData!,
                mimeType: _selectedCoverMimeType ?? 'image/jpeg',
              );
            }
          } catch (e) {
            LOGGER.w(
                "[EditTagDialog] Failed to write tags to cloud cache file: $e");
          }
        }
      }

      // 统一写入缓存（本地音频和云音频都需要）
      final audioId = await MetadataService.instance.computeAudioId(audio);
      if (audioId != null) {
        await MetadataStore.instance.upsertMetadata(MetadataRecord(
          audioId: audioId,
          filePath: path,
          title: _titleController.text,
          artist: _artistController.text,
          album: _albumController.text,
          track: track,
          year: year,
          genre:
              _genreController.text.isNotEmpty ? _genreController.text : null,
          scraperSource: _selectedResult?.source,
          scrapedAt: _selectedResult != null ? DateTime.now() : null,
        ));

        if (_selectedCoverData != null &&
            _selectedCoverData != _currentCoverData) {
          await MediaCache.instance.saveCover(
            audioId,
            _selectedCoverData!,
            mimeType: _selectedCoverMimeType ?? 'image/jpeg',
          );
        }
      }

      audio.title = _titleController.text;
      audio.artist = _artistController.text;
      audio.album = _albumController.text;
      audio.splitedArtists = audio.artist.split(
        RegExp(AppSettings.instance.artistSplitPattern),
      );
      if (track != null) audio.track = track;
      audio.clearCoverCache();
      AudioLibrary.instance.notifyUpdated();
      PlayService.instance.playbackService.refreshNowPlaying();

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      LOGGER.e("[EditTagDialog] Save failed: $e");
      if (mounted) {
        setState(() {
          _isSaving = false;
          _searchError = '保存失败: $e';
        });
      }
    }
  }
}
