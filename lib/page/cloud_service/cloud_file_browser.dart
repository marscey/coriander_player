import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../../cloud_service/cloud_service_manager.dart';
import '../../cloud_service/webdav_service.dart' as webdav;
import '../../cloud_service/cloud_utils.dart' as cloud_utils;
import 'dart:io';
import '../../cloud_service/cloud_audio_player.dart';
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
  List<webdav.WebDavFile> _currentFiles = [];
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
                value: 'scan_to_library',
                child: Text('扫描到音乐库'),
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
          _currentFiles = files;
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
        ...directories.map((file) => _buildFileItem(file, audioFiles)),
        ...audioFiles.map((file) => _buildFileItem(file, audioFiles)),
        ...otherFiles.map((file) => _buildFileItem(file, audioFiles)),
      ],
    );
  }

  Widget _buildFileItem(webdav.WebDavFile file, List<webdav.WebDavFile> currentAudioFiles) {
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
                  value: 'scan_folder_to_library',
                  child: Text('扫描到音乐库'),
                ),
              ],
              const PopupMenuItem(
                value: 'download',
                child: Text('下载'),
              ),
            ],
            onSelected: (value) => _handleFileAction(file, value, currentAudioFiles),
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
          _playAudio(file, currentAudioFiles);
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

  Future<void> _playAudio(webdav.WebDavFile file, List<webdav.WebDavFile> currentAudioFiles) async {
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
              SnackBar(content: Text('开始播放: ${file.name}（共 ${currentAudioFiles.length} 首）')),
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

  Future<void> _handleFileAction(webdav.WebDavFile file, String action, List<webdav.WebDavFile> currentAudioFiles) async {
    switch (action) {
      case 'play':
        _playAudio(file, currentAudioFiles);
        break;
      case 'add_to_playlist':
        _addToPlaylist([file]);
        break;
      case 'scan_folder_to_library':
        _scanFolderToLibrary(file);
        break;
      case 'download':
        _downloadFile(file);
        break;
    }
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'scan_to_library':
        _scanCurrentFolderToLibrary();
        break;
      case 'add_to_playlist':
        final selectedFiles = _getSelectedFiles();
        _addToPlaylist(selectedFiles);
        break;
    }
  }

  List<webdav.WebDavFile> _getSelectedFiles() {
    if (_isSelectionMode && _selectedFiles.isNotEmpty) {
      return _currentFiles.where((f) => _selectedFiles.contains(f.path)).toList();
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

  Future<void> _scanFolderToLibrary(webdav.WebDavFile folder) async {
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

  Future<String> getDownloadDir() async {
    return cloud_utils.getDownloadDir();
  }
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
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() {
        _status = '扫描失败: $e';
        _done = true;
      });
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