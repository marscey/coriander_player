import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_cover_prefetcher.dart';
import 'package:coriander_player/component/auto_scroll_text.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/component/scroll_aware_future_builder.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class PlaylistAudioItem extends StatefulWidget {
  final Audio audio;
  final int index;
  final VoidCallback? onTap;
  final Color? textColor;

  const PlaylistAudioItem({
    super.key,
    required this.audio,
    required this.index,
    this.onTap,
    this.textColor,
  });

  @override
  State<PlaylistAudioItem> createState() => _PlaylistAudioItemState();
}

class _PlaylistAudioItemState extends State<PlaylistAudioItem> {
  int? _lastTapTime;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onChanged);
    PlayService.instance.playbackService.addListener(_onChanged);
    AudioLibrary.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onChanged);
    PlayService.instance.playbackService.removeListener(_onChanged);
    AudioLibrary.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _isNowPlaying {
    final nowPlaying = PlayService.instance.playbackService.nowPlaying;
    return nowPlaying != null && nowPlaying.path == widget.audio.path;
  }

  bool get _isUnavailable =>
      PlayService.instance.playbackService.unavailablePaths
          .contains(widget.audio.path);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final defaultTextColor = widget.textColor ?? scheme.onSurface;
    final activeTextColor = scheme.primary;
    final isUnavailable = _isUnavailable;
    final isNowPlaying = _isNowPlaying;

    if (!isUnavailable) {
      CloudCoverPrefetcher.instance.prefetch(widget.audio);
    }

    final itemTextColor = isUnavailable
        ? scheme.onSurface.withValues(alpha: 0.38)
        : (isNowPlaying ? activeTextColor : defaultTextColor);
    final placeholder = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: 0.8),
              scheme.primary.withValues(alpha: 0.4),
            ],
          ),
        ),
        child: Icon(
          Symbols.music_note,
          color: defaultTextColor.withValues(alpha: 0.7),
          size: 20,
        ),
      ),
    );
    final showIndex = AppSettings.instance.showTrackIndex;

    return InkWell(
      onTap: () {
        if (isNowPlaying) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_lastTapTime != null && now - _lastTapTime! < 300) {
            _lastTapTime = null;
            widget.onTap?.call();
          } else {
            _lastTapTime = now;
          }
        } else {
          _lastTapTime = null;
          widget.onTap?.call();
        }
      },
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
                      color: isNowPlaying ? activeTextColor : defaultTextColor,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              if (showIndex) const SizedBox(width: 8.0),
              PlayingIndicatorOverlay(
                size: PlayingIndicatorSize.small,
                isActivelyPlaying: isNowPlaying,
                isBuffering: isNowPlaying &&
                    PlayService.instance.playbackService.isBuffering,
                child: ScrollAwareFutureBuilder(
                  key: ValueKey(widget.audio.coverImage),
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
                    AutoScrollText(
                      text: widget.audio.title,
                      style: TextStyle(color: itemTextColor, fontSize: 14),
                      scrollSpeed: AppSettings.instance.marqueeSpeed,
                    ),
                    AutoScrollText(
                      text: widget.audio.subtitleText,
                      style: TextStyle(color: itemTextColor, fontSize: 12),
                      scrollSpeed: AppSettings.instance.marqueeSpeed,
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
