import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:coriander_player/play_service/lyric_service.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

enum LyricTextAlign {
  left,
  center,
  right;

  static LyricTextAlign? fromString(String lyricTextAlign) {
    for (var value in LyricTextAlign.values) {
      if (value.name == lyricTextAlign) return value;
    }
    return null;
  }
}

class LyricViewController extends ChangeNotifier {
  final nowPlayingPagePref = AppPreference.instance.nowPlayingPagePref;
  late LyricTextAlign lyricTextAlign = nowPlayingPagePref.lyricTextAlign;
  late double lyricFontSize = nowPlayingPagePref.lyricFontSize;
  late double translationFontSize = nowPlayingPagePref.translationFontSize;

  /// 在左对齐、居中、右对齐之间循环切换
  void switchLyricTextAlign() {
    lyricTextAlign = switch (lyricTextAlign) {
      LyricTextAlign.left => LyricTextAlign.center,
      LyricTextAlign.center => LyricTextAlign.right,
      LyricTextAlign.right => LyricTextAlign.left,
    };

    nowPlayingPagePref.lyricTextAlign = lyricTextAlign;
    notifyListeners();
  }

  void increaseFontSize() {
    lyricFontSize += 1;
    translationFontSize += 1;

    nowPlayingPagePref.lyricFontSize = lyricFontSize;
    nowPlayingPagePref.translationFontSize = translationFontSize;
    notifyListeners();
  }

  void decreaseFontSize() {
    if (translationFontSize <= 14) return;

    lyricFontSize -= 1;
    translationFontSize -= 1;

    nowPlayingPagePref.lyricFontSize = lyricFontSize;
    nowPlayingPagePref.translationFontSize = translationFontSize;
    notifyListeners();
  }
}

class LyricViewControls extends StatelessWidget {
  const LyricViewControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SetLyricSourceBtn(),
          SizedBox(height: 8.0),
          _LyricOffsetBtn(),
          SizedBox(height: 8.0),
          _LyricAlignSwitchBtn(),
          SizedBox(height: 8.0),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IncreaseFontSizeBtn(),
              SizedBox(width: 8.0),
              _DecreaseFontSizeBtn(),
            ],
          )
        ],
      ),
    );
  }
}

class _LyricAlignSwitchBtn extends StatelessWidget {
  const _LyricAlignSwitchBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.switchLyricTextAlign,
      tooltip: "切换歌词对齐方向",
      color: scheme.onSecondaryContainer,
      icon: Icon(switch (lyricViewController.lyricTextAlign) {
        LyricTextAlign.left => Symbols.format_align_left,
        LyricTextAlign.center => Symbols.format_align_center,
        LyricTextAlign.right => Symbols.format_align_right,
      }),
    );
  }
}

class _IncreaseFontSizeBtn extends StatelessWidget {
  const _IncreaseFontSizeBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.increaseFontSize,
      tooltip: "增大歌词字体",
      color: scheme.onSecondaryContainer,
      icon: const Icon(Symbols.text_increase),
    );
  }
}

class _DecreaseFontSizeBtn extends StatelessWidget {
  const _DecreaseFontSizeBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.decreaseFontSize,
      tooltip: "减小歌词字体",
      color: scheme.onSecondaryContainer,
      icon: const Icon(Symbols.text_decrease),
    );
  }
}

class _LyricOffsetBtn extends StatelessWidget {
  const _LyricOffsetBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricService = PlayService.instance.lyricService;

    return ListenableBuilder(
      listenable: lyricService,
      builder: (context, _) {
        final currentOffset = lyricService.lyricOffsetMs;
        final label = currentOffset == 0
            ? "歌词微调"
            : currentOffset > 0
                ? "+${currentOffset}ms"
                : "${currentOffset}ms";

        return IconButton(
          onPressed: () => _showOffsetDialog(context, lyricService),
          tooltip: "歌词时间微调",
          color: currentOffset != 0 ? scheme.primary : scheme.onSecondaryContainer,
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.timer, size: 18),
              if (currentOffset != 0) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showOffsetDialog(BuildContext context, LyricService lyricService) {
    final scheme = Theme.of(context).colorScheme;
    final currentOffset = lyricService.lyricOffsetMs;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text("歌词时间微调"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "正值=歌词提前显示，负值=歌词延后显示\n当前偏移：${currentOffset == 0 ? '无' : '${currentOffset}ms'}",
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _offsetStepButton(ctx, scheme, lyricService, -500, "-0.5s", setDialogState),
                    const SizedBox(width: 8),
                    _offsetStepButton(ctx, scheme, lyricService, -100, "-0.1s", setDialogState),
                    const SizedBox(width: 8),
                    _offsetStepButton(ctx, scheme, lyricService, 100, "+0.1s", setDialogState),
                    const SizedBox(width: 8),
                    _offsetStepButton(ctx, scheme, lyricService, 500, "+0.5s", setDialogState),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  lyricService.resetLyricOffset();
                  Navigator.pop(ctx);
                },
                child: const Text("重置"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("完成"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _offsetStepButton(
    BuildContext ctx,
    ColorScheme scheme,
    LyricService lyricService,
    int deltaMs,
    String label,
    StateSetter setDialogState,
  ) {
    return OutlinedButton(
      onPressed: () {
        final newOffset = lyricService.lyricOffsetMs + deltaMs;
        lyricService.setLyricOffset(newOffset);
        setDialogState(() {});
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
