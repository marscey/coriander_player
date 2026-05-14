import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../../cloud_service/cloud_service_manager.dart';
import '../../cloud_service/webdav_service.dart' as webdav;
import '../../cloud_service/cloud_utils.dart' as cloud_utils;
import 'dart:io';
import 'dart:async';
import '../../cloud_service/cloud_audio_player.dart';
import '../../cloud_service/cloud_scanner.dart';
import '../../utils.dart';

class CloudFileBrowser extends StatefulWidget {
  final String connectionId;
  final String initialPath;

  const CloudFileBrowser({
    super.key,
    required this.connectionId,
    this.initialPath = '',
  });

  @override
  State<CloudFileBrowser> createState() => _CloudFileBrowserState();
}

class _CloudFileBrowserState extends State<CloudFileBrowser> {
  late String _currentPath;
  late Future<List<webdav.WebDavFile>> _filesFuture;
  final Set<String> _selectedFiles = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadFiles();
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

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<CloudServiceManager>();
    final connection = manager.getConnection(widget.connectionId);
    
    if (connection == null) {
      return const Scaffold(
        body: Center(child: Text('连接不存在')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(connection.displayName ?? connection.name),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedFiles.clear();
                });
              },
            ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'scan',
                child: Text('扫描文件夹'),
              ),
              const PopupMenuItem(
                value: 'download',
                child: Text('下载到本地'),
              ),
              const PopupMenuItem(
                value: 'add_to_playlist',
                child: Text('添加到播放列表'),
              ),
            ],
            onSelected: (value) => _handleMenuAction(value),
          ),
        ],
      ),
      body: FutureBuilder<List<webdav.WebDavFile>>(
        future: _filesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('错误: ${snapshot.error}'));
          }

          final files = snapshot.data ?? [];
          return _buildFileList(files);
        },
      ),
    );
  }

  Widget _buildFileList(List<webdav.WebDavFile> files) {
    final directories = files.where((f) => f.isDirectory).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final audioFiles = files.where((f) => !f.isDirectory && f.isAudioFile).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final otherFiles = files.where((f) => !f.isDirectory && !f.isAudioFile).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return ListView(
      children: [
        if (_currentPath.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: const Text('返回上一级'),
            onTap: () {
              setState(() {
                _currentPath = _getParentPath(_currentPath);
                _loadFiles();
              });
            },
          ),
        ...directories.map((file) => _buildFileItem(file)),
        ...audioFiles.map((file) => _buildFileItem(file)),
        ...otherFiles.map((file) => _buildFileItem(file)),
      ],
    );
  }

  Widget _buildFileItem(webdav.WebDavFile file) {
    final isSelected = _selectedFiles.contains(file.path);
    
    return ListTile(
      leading: Icon(file.isDirectory 
        ? Icons.folder 
        : file.isAudioFile ? Icons.audiotrack : Icons.insert_drive_file),
      title: Text(file.name),
      subtitle: file.isDirectory 
        ? null 
        : Text(_formatFileSize(file.size)),
      trailing: _isSelectionMode
        ? Checkbox(
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
        : PopupMenuButton(
            itemBuilder: (context) => [
              if (file.isAudioFile) ...[
                const PopupMenuItem(
                  value: 'play',
                  child: Text('播放'),
                ),
                const PopupMenuItem(
                  value: 'add_to_playlist',
                  child: Text('添加到播放列表'),
                ),
              ],
              if (file.isDirectory) ...[
                const PopupMenuItem(
                  value: 'scan_folder',
                  child: Text('扫描文件夹'),
                ),
                const PopupMenuItem(
                  value: 'download_folder',
                  child: Text('下载文件夹'),
                ),
              ],
              const PopupMenuItem(
                value: 'download',
                child: Text('下载'),
              ),
            ],
            onSelected: (value) => _handleFileAction(file, value),
          ),
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
          _playAudio(file);
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
    );
  }

  String _getParentPath(String currentPath) {
    final parts = currentPath.split('/');
    if (parts.length <= 1) return '';
    return parts.sublist(0, parts.length - 1).join('/');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _playAudio(webdav.WebDavFile file) async {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(widget.connectionId);
    if (service != null) {
      try {
        await CloudAudioPlayer.playCloudFile(
          service: service,
          filePath: file.path,
          fileName: file.name,
          onPlayStarted: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('开始流式播放: ${file.name}')),
            );
          },
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _handleFileAction(webdav.WebDavFile file, String action) async {
    switch (action) {
      case 'play':
        _playAudio(file);
        break;
      case 'add_to_playlist':
        _addToPlaylist([file]);
        break;
      case 'scan_folder':
        _scanFolder(file);
        break;
      case 'download':
        _downloadFile(file);
        break;
    }
  }

  void _handleMenuAction(String action) {
    final files = _selectedFiles.isNotEmpty 
        ? _getSelectedFiles()
        : <webdav.WebDavFile>[];

    switch (action) {
      case 'scan':
        _scanSelectedFolders(files);
        break;
      case 'download':
        _downloadSelectedFiles(files);
        break;
      case 'add_to_playlist':
        _addToPlaylist(files);
        break;
    }
  }

  List<webdav.WebDavFile> _getSelectedFiles() {
    // 从当前显示的文件中获取选中的文件
    // 注意：这是一个同步实现，实际使用时可能需要从FutureBuilder中获取数据
    return [];
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法连接到云服务')),
        );
        return;
      }

      await CloudAudioPlayer.addCloudFilesToPlaylist(
        service: service,
        files: audioFiles,
        onProgress: (count) {
          if (count == audioFiles.length) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已添加到播放列表: $count 个文件')),
            );
          }
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加到播放列表失败: ${e.toString()}')),
      );
    }
  }

  Future<void> _scanFolder(webdav.WebDavFile folder) async {
    try {
      final manager = context.read<CloudServiceManager>();
      final service = manager.getService(widget.connectionId);
      if (service == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法连接到云服务')),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('扫描云文件夹'),
          content: StreamBuilder<String>(
            stream: _scanStream(service, folder.path),
            builder: (context, snapshot) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(snapshot.data ?? '正在扫描...'),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: ${e.toString()}')),
      );
    }
  }

  Stream<String> _scanStream(webdav.WebDavService service, String path) async* {
    int processedCount = 0;
    final statusController = StreamController<String>();
    
    try {
      yield '开始扫描...';
      
      await CloudScanner.scanCloudFolder(
        service: service,
        folderPath: path,
        onProgress: (count) {
          processedCount = count;
        },
        onStatus: (status) {
          statusController.add(status);
        },
      );
      
      await for (final status in statusController.stream) {
        yield status;
      }
      
      yield '扫描完成，共处理 $processedCount 个文件';
    } finally {
      await statusController.close();
    }
  }

  Future<void> _downloadFile(webdav.WebDavFile file) async {
    try {
      final manager = context.read<CloudServiceManager>();
      final service = manager.getService(widget.connectionId);
      if (service == null) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载完成: ${file.name}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: ${e.toString()}')),
      );
    }
  }

  Future<void> _scanSelectedFolders(List<webdav.WebDavFile> files) async {
    final folders = files.where((f) => f.isDirectory).toList();
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择文件夹')),
      );
      return;
    }

    try {
      final manager = context.read<CloudServiceManager>();
      final service = manager.getService(widget.connectionId);
      if (service == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法连接到云服务')),
        );
        return;
      }

      int totalProcessed = 0;
      for (final folder in folders) {
        await CloudScanner.scanCloudFolder(
          service: service,
          folderPath: folder.path,
          onProgress: (count) => totalProcessed += count,
          onStatus: (status) {},
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描完成: $totalProcessed 个文件')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量扫描失败: ${e.toString()}')),
      );
    }
  }

  Future<void> _downloadSelectedFiles(List<webdav.WebDavFile> files) async {
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择文件')),
      );
      return;
    }

    try {
      final manager = context.read<CloudServiceManager>();
      final service = manager.getService(widget.connectionId);
      if (service == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法连接到云服务')),
        );
        return;
      }

      final downloadDir = await getDownloadDir();
      int downloadedCount = 0;
      for (final file in files) {
        try {
          final localPath = path.join(downloadDir, file.name);
          final bytes = await service.downloadFile(file.path);
          final localFile = File(localPath);
          await localFile.writeAsBytes(bytes);
          downloadedCount++;
        } catch (e) {
          LOGGER.e('[CloudFileBrowser] 下载失败: ${file.name} - $e');
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载完成: $downloadedCount/${files.length} 个文件')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量下载失败: ${e.toString()}')),
      );
    }
  }

  Future<String> getDownloadDir() async {
    return cloud_utils.getDownloadDir();
  }
}