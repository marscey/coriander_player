import 'dart:io';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/glass_theme/glass_dialog.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' hide GlassDialog;
import 'package:material_symbols_icons/symbols.dart';

/// 缓存类型枚举
enum CacheType {
  cloudAudio('云音频缓存', Symbols.cloud),
  lyric('歌词缓存', Symbols.lyrics),
  cover('封面缓存', Symbols.image);

  final String label;
  final IconData icon;

  const CacheType(this.label, this.icon);
}

/// 缓存管理设置项
///
/// 点击后弹出对话框进行缓存管理
class CacheManagementSettings extends StatelessWidget {
  const CacheManagementSettings({super.key});

  /// 加载所有缓存信息
  static Future<(Map<CacheType, int>, Map<CacheType, int>)> loadCacheInfo() async {
    final sizes = <CacheType, int>{};
    final counts = <CacheType, int>{};

    // 云音频缓存
    sizes[CacheType.cloudAudio] = await CloudCacheManager.instance.getCacheSize();
    counts[CacheType.cloudAudio] = await CloudCacheManager.instance.getCacheFileCount();

    // 歌词缓存
    final lyricsDir = await MediaCache.instance.lyricsDir;
    final lyricInfo = _getDirInfo(lyricsDir);
    sizes[CacheType.lyric] = lyricInfo.$1;
    counts[CacheType.lyric] = lyricInfo.$2;

    // 封面缓存
    final coversDir = await MediaCache.instance.coversDir;
    final coverInfo = _getDirInfo(coversDir);
    sizes[CacheType.cover] = coverInfo.$1;
    counts[CacheType.cover] = coverInfo.$2;

    return (sizes, counts);
  }

  static (int, int) _getDirInfo(Directory dir) {
    if (!dir.existsSync()) return (0, 0);
    int totalSize = 0;
    int count = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        try {
          totalSize += entity.lengthSync();
          count++;
        } catch (_) {}
      }
    }
    return (totalSize, count);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "缓存管理",
      action: FilledButton.icon(
        icon: const Icon(Symbols.tune),
        label: const Text("缓存设置"),
        onPressed: () async {
          // 加载缓存信息
          final (cacheSizes, cacheCounts) = await loadCacheInfo();

          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => _CacheDetailDialog(
                cacheSizes: cacheSizes,
                cacheCounts: cacheCounts,
              ),
            );
          }
        },
      ),
    );
  }
}

class _CacheDetailDialog extends StatefulWidget {
  final Map<CacheType, int> cacheSizes;
  final Map<CacheType, int> cacheCounts;

  const _CacheDetailDialog({
    required this.cacheSizes,
    required this.cacheCounts,
  });

  @override
  State<_CacheDetailDialog> createState() => _CacheDetailDialogState();
}

class _CacheDetailDialogState extends State<_CacheDetailDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _clearing = false;

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _refresh() async {
    final (cacheSizes, cacheCounts) = await CacheManagementSettings.loadCacheInfo();
    setState(() {
      // Update widget.cacheSizes and widget.cacheCounts indirectly by reloading
    });
    // Close and reopen to show updated data
    Navigator.pop(context);
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _CacheDetailDialog(
          cacheSizes: cacheSizes,
          cacheCounts: cacheCounts,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;

    if (useGlass) {
      return GlassDialog(
        titleWidget: Row(
          children: [
            Icon(Symbols.storage, color: scheme.primary),
            const SizedBox(width: 8.0),
            Text(
              "缓存管理",
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        width: 520.0,
        height: 480.0,
        actions: [
          if (_clearing)
            const SizedBox(
              width: 20.0,
              height: 20.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          GlassDialogButton(
            label: "关闭",
            onTap: () => Navigator.pop(context),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Symbols.cloud, size: 18.0), text: "云音频"),
                Tab(icon: Icon(Symbols.lyrics, size: 18.0), text: "歌词"),
                Tab(icon: Icon(Symbols.image, size: 18.0), text: "封面"),
              ],
            ),
            const SizedBox(height: 12.0),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCloudAudioTab(scheme, useGlass),
                  _buildLyricTab(scheme, useGlass),
                  _buildCoverTab(scheme, useGlass),
                ],
              ),
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
        width: 520.0,
        height: 480.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Symbols.storage, color: scheme.primary),
                  const SizedBox(width: 8.0),
                  Text(
                    "缓存管理",
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),

              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Symbols.cloud, size: 18.0), text: "云音频"),
                  Tab(icon: Icon(Symbols.lyrics, size: 18.0), text: "歌词"),
                  Tab(icon: Icon(Symbols.image, size: 18.0), text: "封面"),
                ],
              ),
              const SizedBox(height: 12.0),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCloudAudioTab(scheme, useGlass),
                    _buildLyricTab(scheme, useGlass),
                    _buildCoverTab(scheme, useGlass),
                  ],
                ),
              ),

              const SizedBox(height: 16.0),

              // 底部操作
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_clearing)
                    const SizedBox(
                      width: 20.0,
                      height: 20.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    ),
                  const SizedBox(width: 8.0),
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

  Widget _buildCloudAudioTab(ColorScheme scheme, bool useGlass) {
    final size = widget.cacheSizes[CacheType.cloudAudio] ?? 0;
    final count = widget.cacheCounts[CacheType.cloudAudio] ?? 0;
    final cache = CloudCacheManager.instance;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow("缓存目录", cache.cacheDir, scheme),
          const SizedBox(height: 8.0),
          _buildInfoRow("文件数量", "$count 个", scheme),
          const SizedBox(height: 8.0),
          _buildInfoRow("占用空间", _formatSize(size), scheme),
          const SizedBox(height: 12.0),

          _buildCacheLimitSelector(scheme, size, useGlass),
          const SizedBox(height: 16.0),

          Row(
            children: [
              Expanded(
                child: useGlass
                    ? _buildGlassActionButton(
                        scheme,
                        icon: Symbols.delete,
                        label: '清空缓存',
                        expand: true,
                        onPressed: count == 0 || _clearing
                            ? null
                            : () async {
                                setState(() => _clearing = true);
                                await CloudCacheManager.instance.clearCache();
                                await _refresh();
                                if (mounted) setState(() => _clearing = false);
                              },
                      )
                    : OutlinedButton.icon(
                        icon: const Icon(Symbols.delete, size: 18.0),
                        label: const Text('清空缓存'),
                        onPressed: count == 0 || _clearing ? null : () async {
                          setState(() => _clearing = true);
                          await CloudCacheManager.instance.clearCache();
                          await _refresh();
                          if (mounted) setState(() => _clearing = false);
                        },
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          if (PlatformHelper.isDesktop)
            Row(
              children: [
                Expanded(
                  child: useGlass
                      ? _buildGlassActionButton(
                          scheme,
                          icon: Symbols.folder_open,
                          label: '更改目录',
                          expand: true,
                          onPressed: _clearing ? null : _changeCloudCacheDir,
                        )
                      : OutlinedButton.icon(
                          icon: const Icon(Symbols.folder_open, size: 18.0),
                          label: const Text('更改目录'),
                          onPressed: _clearing ? null : _changeCloudCacheDir,
                        ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: useGlass
                      ? _buildGlassActionButton(
                          scheme,
                          icon: Symbols.folder_open,
                          label: '打开目录',
                          expand: true,
                          onPressed: () => _openDirectory(cache.cacheDir),
                        )
                      : OutlinedButton.icon(
                          icon: const Icon(Symbols.folder_open, size: 18.0),
                          label: const Text('打开目录'),
                          onPressed: () => _openDirectory(cache.cacheDir),
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLyricTab(ColorScheme scheme, bool useGlass) {
    final size = widget.cacheSizes[CacheType.lyric] ?? 0;
    final count = widget.cacheCounts[CacheType.lyric] ?? 0;

    return FutureBuilder<Directory>(
      future: MediaCache.instance.lyricsDir,
      builder: (context, snapshot) {
        final dirPath = snapshot.data?.path ?? '';
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow("缓存目录", dirPath, scheme),
              const SizedBox(height: 8.0),
              _buildInfoRow("文件数量", "$count 个", scheme),
              const SizedBox(height: 8.0),
              _buildInfoRow("占用空间", _formatSize(size), scheme),
              const SizedBox(height: 16.0),

              useGlass
                  ? _buildGlassActionButton(
                      scheme,
                      icon: Symbols.delete,
                      label: '清空歌词缓存',
                      onPressed: count == 0 || _clearing
                          ? null
                          : () async {
                              setState(() => _clearing = true);
                              final dir = await MediaCache.instance.lyricsDir;
                              if (dir.existsSync()) {
                                await dir.delete(recursive: true);
                                dir.createSync(recursive: true);
                              }
                              await _refresh();
                              if (mounted) setState(() => _clearing = false);
                            },
                    )
                  : OutlinedButton.icon(
                      icon: const Icon(Symbols.delete, size: 18.0),
                      label: const Text('清空歌词缓存'),
                      onPressed: count == 0 || _clearing ? null : () async {
                        setState(() => _clearing = true);
                        final dir = await MediaCache.instance.lyricsDir;
                        if (dir.existsSync()) {
                          await dir.delete(recursive: true);
                          dir.createSync(recursive: true);
                        }
                        await _refresh();
                        if (mounted) setState(() => _clearing = false);
                      },
                    ),
              const SizedBox(height: 8.0),
              if (PlatformHelper.isDesktop)
                useGlass
                    ? _buildGlassActionButton(
                        scheme,
                        icon: Symbols.folder_open,
                        label: '打开目录',
                        onPressed: () => _openDirectory(dirPath),
                      )
                    : OutlinedButton.icon(
                        icon: const Icon(Symbols.folder_open, size: 18.0),
                        label: const Text('打开目录'),
                        onPressed: () => _openDirectory(dirPath),
                      ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoverTab(ColorScheme scheme, bool useGlass) {
    final size = widget.cacheSizes[CacheType.cover] ?? 0;
    final count = widget.cacheCounts[CacheType.cover] ?? 0;

    return FutureBuilder<Directory>(
      future: MediaCache.instance.coversDir,
      builder: (context, snapshot) {
        final dirPath = snapshot.data?.path ?? '';
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow("缓存目录", dirPath, scheme),
              const SizedBox(height: 8.0),
              _buildInfoRow("文件数量", "$count 个", scheme),
              const SizedBox(height: 8.0),
              _buildInfoRow("占用空间", _formatSize(size), scheme),
              const SizedBox(height: 16.0),

              useGlass
                  ? _buildGlassActionButton(
                      scheme,
                      icon: Symbols.delete,
                      label: '清空封面缓存',
                      onPressed: count == 0 || _clearing
                          ? null
                          : () async {
                              setState(() => _clearing = true);
                              final dir = await MediaCache.instance.coversDir;
                              if (dir.existsSync()) {
                                await dir.delete(recursive: true);
                                dir.createSync(recursive: true);
                              }
                              await _refresh();
                              if (mounted) setState(() => _clearing = false);
                            },
                    )
                  : OutlinedButton.icon(
                      icon: const Icon(Symbols.delete, size: 18.0),
                      label: const Text('清空封面缓存'),
                      onPressed: count == 0 || _clearing ? null : () async {
                        setState(() => _clearing = true);
                        final dir = await MediaCache.instance.coversDir;
                        if (dir.existsSync()) {
                          await dir.delete(recursive: true);
                          dir.createSync(recursive: true);
                        }
                        await _refresh();
                        if (mounted) setState(() => _clearing = false);
                      },
                    ),
              const SizedBox(height: 8.0),
              if (PlatformHelper.isDesktop)
                useGlass
                    ? _buildGlassActionButton(
                        scheme,
                        icon: Symbols.folder_open,
                        label: '打开目录',
                        onPressed: () => _openDirectory(dirPath),
                      )
                    : OutlinedButton.icon(
                        icon: const Icon(Symbols.folder_open, size: 18.0),
                        label: const Text('打开目录'),
                        onPressed: () => _openDirectory(dirPath),
                      ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCacheLimitSelector(ColorScheme scheme, int currentSize, bool useGlass) {
    final settings = AppSettings.instance;
    final currentLimitMB = settings.cloudCacheMaxSizeMB;

    const options = [
      (512, '512 MB'),
      (1024, '1 GB'),
      (2048, '2 GB'),
      (4096, '4 GB'),
      (8192, '8 GB'),
      (-1, '无限制'),
    ];

    final usagePercent = currentLimitMB > 0 && currentSize > 0
        ? (currentSize / (currentLimitMB * 1024 * 1024) * 100).clamp(0, 100)
        : 0.0;

    // glass 分支：使用 GlassContainer + GlassButton.custom 模拟 ChoiceChip
    if (useGlass) {
      return GlassContainer(
        useOwnLayer: true,
        shape: const LiquidRoundedSuperellipse(borderRadius: 12),
        settings: cardSettings,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Symbols.database, size: 16.0, color: scheme.primary),
                  const SizedBox(width: 8.0),
                  Text(
                    '缓存容量上限',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    currentLimitMB == -1
                        ? '无限制'
                        : _formatSize(currentLimitMB * 1024 * 1024),
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (currentLimitMB > 0) ...[
                const SizedBox(height: 8.0),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: LinearProgressIndicator(
                    value: usagePercent / 100,
                    backgroundColor: scheme.surfaceContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      usagePercent > 90
                          ? scheme.error
                          : usagePercent > 70
                              ? scheme.tertiary
                              : scheme.primary,
                    ),
                    minHeight: 6.0,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  '已使用 ${_formatSize(currentSize)} (${usagePercent.toStringAsFixed(0)}%)',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.0,
                  ),
                ),
              ],
              const SizedBox(height: 10.0),
              Wrap(
                spacing: 6.0,
                runSpacing: 6.0,
                children: options.map((opt) {
                  final isSelected = currentLimitMB == opt.$1;
                  final textColor =
                      isSelected ? scheme.onPrimary : scheme.onSurface;
                  return GlassButton.custom(
                    onTap: _clearing
                        ? () {}
                        : () async {
                            setState(() => _clearing = true);
                            settings.cloudCacheMaxSizeMB = opt.$1;
                            CloudCacheManager.instance
                                .setMaxCacheSizeMB(opt.$1);
                            await settings.saveSettings();
                            await CloudCacheManager.instance.evictIfNeeded();
                            await _refresh();
                            if (mounted) setState(() => _clearing = false);
                          },
                    enabled: !_clearing,
                    style: isSelected
                        ? GlassButtonStyle.filled
                        : GlassButtonStyle.transparent,
                    shape: const LiquidRoundedSuperellipse(borderRadius: 10),
                    height: 32,
                    useOwnLayer: isSelected,
                    settings: isSelected
                        ? cardSettings.copyWith(
                            glassColor: scheme.primary.withValues(alpha: 0.7),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Text(
                        opt.$2,
                        style: TextStyle(
                          fontSize: 12.0,
                          color: textColor,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    // material 分支：保持原有实色背景与 ChoiceChip
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.database, size: 16.0, color: scheme.primary),
              const SizedBox(width: 8.0),
              Text(
                '缓存容量上限',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                currentLimitMB == -1
                    ? '无限制'
                    : _formatSize(currentLimitMB * 1024 * 1024),
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (currentLimitMB > 0) ...[
            const SizedBox(height: 8.0),
            ClipRRect(
              borderRadius: BorderRadius.circular(4.0),
              child: LinearProgressIndicator(
                value: usagePercent / 100,
                backgroundColor: scheme.surfaceContainer,
                valueColor: AlwaysStoppedAnimation<Color>(
                  usagePercent > 90
                      ? scheme.error
                      : usagePercent > 70
                          ? scheme.tertiary
                          : scheme.primary,
                ),
                minHeight: 6.0,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              '已使用 ${_formatSize(currentSize)} (${usagePercent.toStringAsFixed(0)}%)',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11.0,
              ),
            ),
          ],
          const SizedBox(height: 10.0),
          Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            children: options.map((opt) {
              final isSelected = currentLimitMB == opt.$1;
              return ChoiceChip(
                label: Text(opt.$2),
                selected: isSelected,
                onSelected: _clearing
                    ? null
                    : (_) async {
                        setState(() => _clearing = true);
                        settings.cloudCacheMaxSizeMB = opt.$1;
                        CloudCacheManager.instance.setMaxCacheSizeMB(opt.$1);
                        await settings.saveSettings();
                        await CloudCacheManager.instance.evictIfNeeded();
                        await _refresh();
                        if (mounted) setState(() => _clearing = false);
                      },
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: 12.0,
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Glass 风格操作按钮（替代 OutlinedButton.icon）
  ///
  /// 使用 [GlassButton.custom] + [GlassButtonStyle.transparent] 承载图标 + 文字，
  /// 适配 [Expanded] 撑满（[expand] = true）或按内容自适应宽度。
  Widget _buildGlassActionButton(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool expand = false,
  }) {
    final isDisabled = onPressed == null;
    final textColor = isDisabled
        ? scheme.onSurface.withValues(alpha: 0.4)
        : scheme.onSurface;
    return GlassButton.custom(
      onTap: onPressed ?? () {},
      enabled: !isDisabled,
      style: GlassButtonStyle.transparent,
      shape: const LiquidRoundedSuperellipse(borderRadius: 12),
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, size: 18.0, color: textColor),
            const SizedBox(width: 6.0),
            Text(
              label,
              style: TextStyle(color: textColor, fontSize: 14.0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72.0,
          child: Text(
            label,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.0),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: scheme.onSurface, fontSize: 13.0),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 更改云音频缓存目录（跨平台）
  Future<void> _changeCloudCacheDir() async {
    if (PlatformHelper.isDesktop) {
      // 桌面端使用 file_picker
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择云音频缓存目录',
      );
      if (result != null) {
        setState(() => _clearing = true);
        await CloudCacheManager.instance.setCacheDirAndPersist(result);
        await _refresh();
        if (mounted) setState(() => _clearing = false);
      }
    } else {
      // 移动端暂不支持更改目录
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('移动端暂不支持更改缓存目录')),
        );
      }
    }
  }

  /// 打开目录（跨平台）
  void _openDirectory(String path) {
    if (!PlatformHelper.isDesktop) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移动端暂不支持打开目录')),
      );
      return;
    }

    try {
      if (PlatformHelper.isMacOS) {
        Process.run('open', [path]);
      } else if (PlatformHelper.isWindows) {
        Process.run('explorer', [path]);
      } else if (PlatformHelper.isLinux) {
        Process.run('xdg-open', [path]);
      }
    } catch (e) {
      LOGGER.e("[CacheSettings] Failed to open directory: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开目录失败: $e')),
        );
      }
    }
  }
}
