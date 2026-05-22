import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/component/scroll_aware_future_builder.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 统一的播放列表音频项组件，用于播放列表场景（mini播放器弹窗、播放器主界面播放列表等）
/// 与 AudioTile 不同，此组件更轻量，无右键菜单和多选功能
class PlaylistAudioItem extends StatelessWidget {
  final Audio audio;
  final int index;
  final bool isNowPlaying;
  final VoidCallback? onTap;
  final Color? textColor;

  const PlaylistAudioItem({
    super.key,
    required this.audio,
    required this.index,
    required this.isNowPlaying,
    this.onTap,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final defaultTextColor = textColor ?? scheme.onSurface;
    final activeTextColor = scheme.primary;
    final itemTextColor = isNowPlaying ? activeTextColor : defaultTextColor;
    final placeholder = Icon(
      Symbols.broken_image,
      size: 40.0,
      color: defaultTextColor,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: SizedBox(
          height: 48.0,
          child: Row(
            children: [
              // 序号
              SizedBox(
                width: 28.0,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: isNowPlaying ? activeTextColor : defaultTextColor,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 8.0),
              // 封面 + 播放指示器
              PlayingIndicatorOverlay(
                size: PlayingIndicatorSize.small,
                isActivelyPlaying: isNowPlaying,
                child: ScrollAwareFutureBuilder(
                  future: () => audio.cover,
                  builder: (context, snapshot) {
                    if (snapshot.data == null) return placeholder;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(6.0),
                      child: Image(
                        image: snapshot.data!,
                        width: 40.0,
                        height: 40.0,
                        errorBuilder: (_, __, ___) => placeholder,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12.0),
              // 标题 + 副标题
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audio.title,
                      style: TextStyle(color: itemTextColor, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      audio.subtitleText,
                      style: TextStyle(
                          color: itemTextColor, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              // 时长
              Text(
                Duration(seconds: audio.duration).toStringHMMSS(),
                style: TextStyle(color: itemTextColor, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
