import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app_paths.dart' as app_paths;
import '../../cloud_service/cloud_connection.dart';
import '../../cloud_service/cloud_service_manager.dart';
import '../../play_service/play_service.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'cloud_file_browser.dart';
import 'cloud_connection_form.dart';

class CloudConnectionsPage extends StatefulWidget {
  const CloudConnectionsPage({super.key});

  @override
  State<CloudConnectionsPage> createState() => _CloudConnectionsPageState();
}

class _CloudConnectionsPageState extends State<CloudConnectionsPage> {
  @override
  void initState() {
    super.initState();
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

  bool _isConnectionPlaying(CloudConnection connection) {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    return nowPlaying != null &&
        nowPlaying.isCloudAudio &&
        nowPlaying.connectionId == connection.id;
  }

  bool get _hasPlayingCloudAudio {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    return nowPlaying != null && nowPlaying.isCloudAudio;
  }

  void _locatePlayingConnection() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || !nowPlaying.isCloudAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未在播放云音频')),
      );
      return;
    }
    final connectionId = nowPlaying.connectionId;
    if (connectionId == null) return;

    // 计算播放文件所在的目录路径
    final playingPath = nowPlaying.path;
    final dirPath = playingPath.contains('/')
        ? playingPath.substring(0, playingPath.lastIndexOf('/'))
        : '';

    // 跳转到连接的文件浏览器，带上初始路径和定位目标
    context.push(
      '${app_paths.CLOUD_BROWSER_PAGE}/$connectionId',
      extra: CloudBrowserArgs(dirPath, playingPath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer<CloudServiceManager>(
      builder: (context, manager, child) {
        final connections = manager.connections;

        if (connections.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: scheme.outline),
                const SizedBox(height: 16),
                Text('暂无云服务连接',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text('点击下方按钮添加连接',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _showAddConnectionDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('添加连接'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0),
              child: Row(
                children: [
                  Text(
                    '云服务连接',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (_hasPlayingCloudAudio)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: IconButton.filledTonal(
                        onPressed: _locatePlayingConnection,
                        icon: const Icon(Icons.my_location, size: 20),
                        tooltip: '定位正在播放的云音频',
                      ),
                    ),
                  FilledButton.tonal(
                    onPressed: () => _showAddConnectionDialog(context),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 18),
                        SizedBox(width: 4),
                        Text('添加连接'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8.0),
                itemCount: connections.length,
                itemBuilder: (context, index) {
                  final connection = connections[index];
                  return _buildConnectionItem(context, connection, manager);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConnectionItem(
    BuildContext context,
    CloudConnection connection,
    CloudServiceManager manager,
  ) {
    final isPlaying = _isConnectionPlaying(connection);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: PlayingIndicatorOverlay(
          size: PlayingIndicatorSize.medium,
          isActivelyPlaying: isPlaying,
          child: Icon(Icons.cloud, size: 36),
        ),
        title: Text(
          connection.displayName ?? connection.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('类型: ${_getServiceTypeName(connection.type)}'),
            Text('服务器: ${connection.serverUrl}'),
            Text('最后同步: ${_formatDate(connection.lastSync)}'),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'browse',
              child: ListTile(
                leading: Icon(Icons.folder_open),
                title: Text('浏览文件'),
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit),
                title: Text('编辑连接'),
              ),
            ),
            const PopupMenuItem(
              value: 'test',
              child: ListTile(
                leading: Icon(Icons.check_circle),
                title: Text('测试连接'),
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('删除连接', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
          onSelected: (value) => _handleConnectionAction(
            context,
            connection,
            manager,
            value,
          ),
        ),
        onTap: () {
          context.push(
            '${app_paths.CLOUD_BROWSER_PAGE}/${connection.id}',
          );
        },
      ),
    );
  }

  String _getServiceTypeName(CloudServiceType type) {
    switch (type) {
      case CloudServiceType.webdav:
        return 'WebDAV';
      default:
        return '未知';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '今天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return '昨天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  void _handleConnectionAction(
    BuildContext context,
    CloudConnection connection,
    CloudServiceManager manager,
    String action,
  ) async {
    switch (action) {
      case 'browse':
        context.push(
          '${app_paths.CLOUD_BROWSER_PAGE}/${connection.id}',
        );
        break;
      case 'edit':
        _showEditConnectionDialog(context, connection);
        break;
      case 'test':
        await _testConnection(context, connection);
        break;
      case 'delete':
        await _deleteConnection(context, connection, manager);
        break;
    }
  }

  void _showAddConnectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const CloudConnectionForm(),
    );
  }

  void _showEditConnectionDialog(
      BuildContext context, CloudConnection connection) {
    showDialog(
      context: context,
      builder: (context) => CloudConnectionForm(connection: connection),
    );
  }

  Future<void> _testConnection(
      BuildContext context, CloudConnection connection) async {
    final manager = context.read<CloudServiceManager>();
    final service = manager.getService(connection.id);

    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接测试失败：服务不可用')),
      );
      return;
    }
    try {
      final isConnected = await service.testConnection();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isConnected ? '连接成功' : '连接失败'),
          backgroundColor: isConnected ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接测试失败：$e')),
      );
    }
  }

  Future<void> _deleteConnection(
    BuildContext context,
    CloudConnection connection,
    CloudServiceManager manager,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content:
            Text('确定要删除连接 "${connection.displayName ?? connection.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await manager.removeConnection(connection.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接已删除')),
      );
    }
  }
}
