import 'dart:io';
import 'package:coriander_player/cloud_service/cloud_cache_manager.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class CloudCacheSettings extends StatefulWidget {
  const CloudCacheSettings({super.key});

  @override
  State<CloudCacheSettings> createState() => _CloudCacheSettingsState();
}

class _CloudCacheSettingsState extends State<CloudCacheSettings> {
  int _cacheSize = 0;
  int _cacheCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheInfo();
  }

  Future<void> _loadCacheInfo() async {
    final size = await CloudCacheManager.instance.getCacheSize();
    final count = await CloudCacheManager.instance.getCacheFileCount();
    if (mounted) {
      setState(() {
        _cacheSize = size;
        _cacheCount = count;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = CloudCacheManager.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsTile(
          description: "云音频缓存",
          action: FilledButton.icon(
            icon: const Icon(Symbols.folder),
            label: const Text("管理缓存"),
            onPressed: () => _showCacheDialog(context),
          ),
        ),
        if (!_loading) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '${_cacheCount} 个缓存文件，共 ${cache.formatSize(_cacheSize)}',
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '路径: ${cache.cacheDir}',
              style: TextStyle(color: scheme.outline, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  void _showCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _CacheManagerDialog(
        onRefresh: _loadCacheInfo,
      ),
    );
  }
}

class _CacheManagerDialog extends StatefulWidget {
  final VoidCallback onRefresh;

  const _CacheManagerDialog({required this.onRefresh});

  @override
  State<_CacheManagerDialog> createState() => _CacheManagerDialogState();
}

class _CacheManagerDialogState extends State<_CacheManagerDialog> {
  int _cacheSize = 0;
  int _cacheCount = 0;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final size = await CloudCacheManager.instance.getCacheSize();
    final count = await CloudCacheManager.instance.getCacheFileCount();
    if (mounted) {
      setState(() {
        _cacheSize = size;
        _cacheCount = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = CloudCacheManager.instance;

    return AlertDialog(
      title: const Text('云音频缓存管理'),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '缓存目录: ${cache.cacheDir}',
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
            const SizedBox(height: 12),
            Text('缓存文件数: $_cacheCount 个'),
            const SizedBox(height: 4),
            Text('占用空间: ${cache.formatSize(_cacheSize)}'),
            const SizedBox(height: 16),
            if (_clearing)
              const Center(child: CircularProgressIndicator())
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Symbols.delete, size: 18),
                      label: const Text('清空缓存'),
                      onPressed: _cacheCount == 0 ? null : () async {
                        setState(() => _clearing = true);
                        await CloudCacheManager.instance.clearCache();
                        await _loadInfo();
                        widget.onRefresh();
                        if (mounted) setState(() => _clearing = false);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Symbols.folder_open, size: 18),
                      label: const Text('更改目录'),
                      onPressed: () async {
                        final picker = DirectoryPicker();
                        picker.title = '选择缓存目录';
                        final dir = picker.getDirectory();
                        if (dir != null) {
                          setState(() => _clearing = true);
                          await CloudCacheManager.instance.setCacheDirAndPersist(dir.path);
                          await _loadInfo();
                          widget.onRefresh();
                          if (mounted) setState(() => _clearing = false);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Symbols.folder_open, size: 18),
                label: const Text('打开缓存目录'),
                onPressed: () {
                  Process.run('explorer', [cache.cacheDir]);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
