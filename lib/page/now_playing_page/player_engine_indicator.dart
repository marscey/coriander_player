part of 'page.dart';

/// 显示当前播放引擎的标识组件
class PlayerEngineIndicator extends StatelessWidget {
  const PlayerEngineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final engineType = AppSettings.instance.playerEngineType ?? PlayerEngineType.defaultForPlatform;
    
    return Tooltip(
      message: '当前播放引擎：${_getEngineName(engineType)}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: scheme.onSecondaryContainer.withOpacity(0.3),
            width: 1.0,
          ),
          color: scheme.secondaryContainer.withOpacity(0.3),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getEngineIcon(engineType),
              size: 12.0,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4.0),
            Text(
              _getEngineShortName(engineType),
              style: TextStyle(
                fontSize: 10.0,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getEngineName(PlayerEngineType type) {
    return switch (type) {
      PlayerEngineType.bass => 'BASS',
      PlayerEngineType.mediaKit => 'MediaKit',
    };
  }

  String _getEngineShortName(PlayerEngineType type) {
    return switch (type) {
      PlayerEngineType.bass => 'BASS',
      PlayerEngineType.mediaKit => 'MK',
    };
  }

  IconData _getEngineIcon(PlayerEngineType type) {
    return switch (type) {
      PlayerEngineType.bass => Symbols.music_note,
      PlayerEngineType.mediaKit => Symbols.speaker_group,
    };
  }
}