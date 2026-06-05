import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/platform_dependency_manager.dart';
import 'package:coriander_player/play_service/engine/player_engine_type.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class PlayerEngineSelector extends StatefulWidget {
  const PlayerEngineSelector({super.key});

  @override
  State<PlayerEngineSelector> createState() => _PlayerEngineSelectorState();
}

class _PlayerEngineSelectorState extends State<PlayerEngineSelector> {
  final settings = AppSettings.instance;
  final dependencyManager = PlatformDependencyManager.instance;
  List<PlayerEngineType> _supportedEngines = [];

  @override
  void initState() {
    super.initState();
    // 获取当前平台支持的播放器引擎
    _supportedEngines = dependencyManager.getSupportedPlayerEngines();
    
    // 检查当前设置的引擎是否受支持，如果不支持则设置为推荐引擎
    if (settings.playerEngineType != null &&
        !dependencyManager.isPlayerEngineSupported(settings.playerEngineType!)) {
      settings.playerEngineType = dependencyManager.getRecommendedPlayerEngine();
      settings.saveSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有设置播放器引擎类型，则使用推荐的引擎
    final currentEngine = settings.playerEngineType ?? dependencyManager.getRecommendedPlayerEngine();

    // 构建支持的引擎按钮段
    final segments = _supportedEngines.map((engine) {
      switch (engine) {
        case PlayerEngineType.bass:
          return const ButtonSegment<PlayerEngineType>(
            value: PlayerEngineType.bass,
            label: Text("BASS"),
            icon: Icon(Symbols.music_note),
          );
        case PlayerEngineType.mediaKit:
          return const ButtonSegment<PlayerEngineType>(
            value: PlayerEngineType.mediaKit,
            label: Text("MediaKit"),
            icon: Icon(Symbols.speaker_group),
          );
      }
    }).toList();

    return SettingsTile(
      description: "播放器引擎",
      subtitle: "切换引擎后需重启应用生效",
      action: SegmentedButton<PlayerEngineType>(
        showSelectedIcon: false,
        segments: segments,
        selected: {currentEngine},
        onSelectionChanged: (newSelection) async {
          if (newSelection.first == settings.playerEngineType) return;

          LOGGER.i("[EngineSelector] User selected: ${newSelection.first}");

          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                content: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('正在切换播放器引擎...'),
                  ],
                ),
              ),
            );
          }

          try {
            LOGGER.i("[EngineSelector] Calling switchEngine...");
            await PlayService.instance.playbackService.switchEngine(newSelection.first);
            LOGGER.i("[EngineSelector] switchEngine returned successfully");
            
            setState(() {});
          } catch (e) {
            LOGGER.e("[EngineSelector] switchEngine failed: $e");
            showTextOnSnackBar('切换播放器引擎失败: $e');
          } finally {
            LOGGER.i("[EngineSelector] Closing dialog, context.mounted=${context.mounted}");
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }
          
          // 显示切换成功提示
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('播放器引擎已切换'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );
  }
}