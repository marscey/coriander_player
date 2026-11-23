import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/unified_list_tile.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/glass_page_scaffold.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../../app_paths.dart' as app_paths;
import '../../cloud_service/cloud_connection.dart';
import 'cloud_connection_form.dart';
import 'glass_cloud_connection_form.dart';
import 'cloud_file_browser.dart';

class CloudConnectionsPage extends StatefulWidget {
  const CloudConnectionsPage({super.key});

  @override
  State<CloudConnectionsPage> createState() => _CloudConnectionsPageState();
}

class _CloudConnectionsPageState extends State<CloudConnectionsPage> {
  bool _hasPlayingCloudAudio = false;

  @override
  void initState() {
    super.initState();
    _refreshPlayingStatus();
    PlayService.instance.playbackService.addListener(_refreshPlayingStatus);
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_refreshPlayingStatus);
    super.dispose();
  }

  void _refreshPlayingStatus() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (!mounted) return;
    setState(() {
      _hasPlayingCloudAudio = nowPlaying?.isCloudAudio ?? false;
    });
  }

  void _locatePlayingConnection() {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    if (nowPlaying == null || !nowPlaying.isCloudAudio) return;
    final connectionId = nowPlaying.connectionId;
    if (connectionId == null) return;

    final dirPath = nowPlaying.path.contains('/')
        ? nowPlaying.path.substring(0, nowPlaying.path.lastIndexOf('/'))
        : '';

    context.push(
      '${app_paths.CLOUD_BROWSER_PAGE}/$connectionId',
      extra: CloudBrowserArgs(dirPath, nowPlaying.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CloudServiceManager>(
      builder: (context, manager, child) {
        final connections = manager.connections;
        final subtitle = connections.isEmpty
            ? null
            : "${connections.length} 个连接";

        final useGlass = AppPreference.instance.liquidGlassEnabled;

        final tileList = connections
            .map((c) => _buildConnectionTile(c))
            .toList();

        if (useGlass) {
          // Glass 模式菜单项
          final glassMenuItems = <Widget>[
            if (_hasPlayingCloudAudio)
              GlassMenuItem(
                title: '定位播放文件',
                icon: const Icon(Symbols.location_on, size: 20),
                onTap: _locatePlayingConnection,
              ),
            GlassMenuItem(
              title: '添加连接',
              icon: const Icon(Symbols.add, size: 20),
              onTap: () => _showAddConnectionDialog(context),
            ),
          ];

          if (connections.isEmpty) {
            return GlassPageScaffold(
              title: "云服务连接",
              subtitle: subtitle,
              menuItems: glassMenuItems,
              showBackButton: false,
              showSettingsButton: true,
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: GlassPageHeader(
                      title: "云服务连接",
                      subtitle: subtitle,
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 140.0),
                      child: _buildEmptyState(),
                    ),
                  ),
                ],
              ),
            );
          }

          return GlassPageScaffold(
            title: "云服务连接",
            subtitle: subtitle,
            menuItems: glassMenuItems,
            showBackButton: false,
            showSettingsButton: true,
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: GlassPageHeader(
                    title: "云服务连接",
                    subtitle: subtitle,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 140.0),
                  sliver: SliverList.separated(
                    itemCount: tileList.length,
                    itemBuilder: (context, i) => tileList[i],
                    separatorBuilder: (context, i) =>
                        const SizedBox(height: 8.0),
                  ),
                ),
              ],
            ),
          );
        }

        // 普通模式
        final actions = <Widget>[
          if (_hasPlayingCloudAudio)
            IconButton(
              tooltip: "定位播放文件",
              onPressed: _locatePlayingConnection,
              icon: const Icon(Symbols.location_on),
            ),
          IconButton(
            tooltip: "添加连接",
            onPressed: () => _showAddConnectionDialog(context),
            icon: const Icon(Symbols.add),
          ),
        ];

        return PageScaffold(
          title: "云服务连接",
          subtitle: subtitle,
          actions: actions,
          showBackButton: false,
          body: connections.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 96.0),
                  itemCount: tileList.length,
                  itemExtent: 64,
                  itemBuilder: (context, i) => tileList[i],
                ),
        );
      },
    );
  }

  Widget _buildConnectionTile(CloudConnection connection) {
    final typeName = _getServiceTypeName(connection.type);
    final sub = connection.serverUrl;
    final isPlaying = _isConnectionPlaying(connection);

    return UnifiedListTile(
      icon: CupertinoIcons.cloud,
      title: connection.displayName ?? connection.name,
      subtitle: "$typeName · $sub",
      isPlaying: isPlaying,
      onTap: () {
        context.push('${app_paths.CLOUD_BROWSER_PAGE}/${connection.id}');
      },
      iconBackgroundColor: isPlaying
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      iconColor: isPlaying
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : null,
      trailing: PopupMenuButton(
        itemBuilder: (context) => [
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
            value: 'copy',
            child: ListTile(
              leading: Icon(Icons.copy),
              title: Text('复制连接'),
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
        onSelected: (value) => _handleConnectionAction(connection, value),
      ),
    );
  }

  bool _isConnectionPlaying(CloudConnection connection) {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    return nowPlaying?.isCloudAudio ?? false
        ? nowPlaying!.connectionId == connection.id
        : false;
  }

  String _getServiceTypeName(CloudServiceType type) {
    switch (type) {
      case CloudServiceType.webdav:
        return "WebDAV";
    }
  }

  void _handleConnectionAction(CloudConnection connection, String action) async {
    switch (action) {
      case 'edit':
        _showEditConnectionDialog(connection);
        break;
      case 'test':
        await _testConnection(connection);
        break;
      case 'copy':
        await _copyConnection(connection);
        break;
      case 'delete':
        await _deleteConnection(connection);
        break;
    }
  }

  Future<void> _copyConnection(CloudConnection connection) async {
    final originalName = connection.displayName ?? connection.name;
    final newName = '${connection.name}_副本';
    final newDisplayName =
        connection.displayName != null ? '${originalName}_副本' : null;
    final newConnection = connection.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: newName,
      displayName: newDisplayName,
      lastSync: DateTime.now(),
    );
    await context.read<CloudServiceManager>().addConnection(newConnection);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制连接「$originalName」为新连接')),
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.cloud,
            size: 64,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            "暂无云服务连接",
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "点击 ⋯ 菜单添加连接",
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddConnectionDialog(BuildContext context) {
    final useGlass = AppPreference.instance.liquidGlassEnabled;
    showDialog(
      context: context,
      builder: (context) => useGlass
          ? const GlassCloudConnectionForm()
          : const CloudConnectionForm(),
    );
  }

  void _showEditConnectionDialog(CloudConnection connection) {
    final useGlass = AppPreference.instance.liquidGlassEnabled;
    showDialog(
      context: context,
      builder: (context) => useGlass
          ? GlassCloudConnectionForm(connection: connection)
          : CloudConnectionForm(connection: connection),
    );
  }

  Future<void> _testConnection(CloudConnection connection) async {
    final service = context.read<CloudServiceManager>().getService(connection.id);
    if (service == null) {
      if (!context.mounted) return;
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

  Future<void> _deleteConnection(CloudConnection connection) async {
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
      if (!context.mounted) return;
      await context.read<CloudServiceManager>().removeConnection(connection.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接已删除')),
      );
    }
  }
}
