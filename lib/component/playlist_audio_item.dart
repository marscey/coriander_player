import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/component/scroll_aware_future_builder.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class PlaylistAudioItem extends StatefulWidget {
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
  State<PlaylistAudioItem> createState() => _PlaylistAudioItemState();
}

class _PlaylistAudioItemState extends State<PlaylistAudioItem> {
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final defaultTextColor = widget.textColor ?? scheme.onSurface;
    final activeTextColor = scheme.primary;
    final itemTextColor = widget.isNowPlaying ? activeTextColor : defaultTextColor;
    final placeholder = Icon(
      Symbols.broken_image,
      size: 40.0,
      color: defaultTextColor,
    );
    final showIndex = AppSettings.instance.showTrackIndex;

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: SizedBox(
          height: 48.0,
          child: Row(
            children: [
              if (showIndex)
                SizedBox(
                  width: 28.0,
                  child: Text(
                    '${widget.index + 1}',
                    style: TextStyle(
                      color: widget.isNowPlaying ? activeTextColor : defaultTextColor,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              if (showIndex) const SizedBox(width: 8.0),
              PlayingIndicatorOverlay(
                size: PlayingIndicatorSize.small,
                isActivelyPlaying: widget.isNowPlaying,
                child: ScrollAwareFutureBuilder(
                  future: () => widget.audio.cover,
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
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.audio.title,
                      style: TextStyle(color: itemTextColor, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.audio.subtitleText,
                      style: TextStyle(
                          color: itemTextColor, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              Text(
                Duration(seconds: widget.audio.duration).toStringHMMSS(),
                style: TextStyle(color: itemTextColor, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
