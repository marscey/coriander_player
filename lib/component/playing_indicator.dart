import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

/// 播放指示器尺寸预设
enum PlayingIndicatorSize {
  /// 列表视图图标 (24px)
  small,

  /// 连接列表图标 (36px)
  medium,

  /// 网格视图图标 (48px)
  large,
}

/// 可复用的播放指示器组件。
///
/// 自动监听 PlaybackService 状态：
/// - 播放中：波形条跳动动画
/// - 暂停：动画冻结在当前位置
/// - 停止/非当前：隐藏
///
/// 同时监听 ChangeNotifier 和 playerStateStream，确保实时响应播放/暂停。
class PlayingIndicator extends StatefulWidget {
  final PlayingIndicatorSize size;
  final bool isActivelyPlaying;
  final Color? barColor;

  const PlayingIndicator({
    super.key,
    required this.size,
    required this.isActivelyPlaying,
    this.barColor,
  });

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  StreamSubscription<PlayerState>? _playerStateSub;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // 监听 ChangeNotifier（用于 nowPlaying 变化等）
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
    // 监听 playerStateStream（用于播放/暂停状态实时变化）
    _playerStateSub =
        PlayService.instance.playbackService.playerStateStream.listen((state) {
      _updateAnimation();
    });
    _updateAnimation();
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActivelyPlaying != widget.isActivelyPlaying) {
      _updateAnimation();
    }
  }

  void _onPlaybackChanged() {
    _updateAnimation();
  }

  void _updateAnimation() {
    if (!widget.isActivelyPlaying) {
      _controller.stop();
      _controller.value = 0;
      return;
    }

    final playerState = PlayService.instance.playbackService.playerState;

    if (playerState == PlayerState.playing) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (playerState == PlayerState.paused) {
      _controller.stop();
    } else {
      _controller.stop();
      _controller.value = 0;
    }

    if (mounted) setState(() {});
  }

  double get _iconSize {
    switch (widget.size) {
      case PlayingIndicatorSize.small:
        return 24;
      case PlayingIndicatorSize.medium:
        return 36;
      case PlayingIndicatorSize.large:
        return 48;
    }
  }

  double get _barWidth {
    switch (widget.size) {
      case PlayingIndicatorSize.small:
        return 2.5;
      case PlayingIndicatorSize.medium:
        return 3.0;
      case PlayingIndicatorSize.large:
        return 4.0;
    }
  }

  List<double> get _barHeights {
    switch (widget.size) {
      case PlayingIndicatorSize.small:
        return [5, 7, 10, 7];
      case PlayingIndicatorSize.medium:
        return [6, 9, 12, 9];
      case PlayingIndicatorSize.large:
        return [8, 12, 16, 12];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActivelyPlaying) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final color = widget.barColor ?? scheme.primary;

    return SizedBox(
      width: _iconSize,
      height: _iconSize,
      child: Center(
        child: _buildBars(color),
      ),
    );
  }

  Widget _buildBars(Color color) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) {
            final delay = i * 0.125;
            final value = _controller.value;
            final scaleY =
                0.5 + 0.5 * math.sin((value + delay) * 2 * math.pi);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: _barWidth * 0.375),
              child: Transform.scale(
                scaleY: scaleY,
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: _barWidth,
                  height: _barHeights[i],
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 播放指示器覆盖层。
///
/// 将原始图标变暗（通过 opacity），然后在上面叠加波形条指示器。
/// 背景完全透明，通过图标变暗与波形条形成对比。
class PlayingIndicatorOverlay extends StatelessWidget {
  final PlayingIndicatorSize size;
  final bool isActivelyPlaying;
  final Color? barColor;
  final Widget child;

  const PlayingIndicatorOverlay({
    super.key,
    required this.size,
    required this.isActivelyPlaying,
    this.barColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActivelyPlaying) return child;

    return Stack(
      children: [
        Opacity(
          opacity: 0.35,
          child: child,
        ),
        Positioned.fill(
          child: Center(
            child: PlayingIndicator(
              size: size,
              isActivelyPlaying: isActivelyPlaying,
              barColor: barColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// 播放定位按钮组件。
///
/// 条件显示的定位按钮，当有音频播放时显示，点击后执行定位回调。
/// 不同页面传入不同的 onLocate 回调即可。
class LocatePlayingButton extends StatelessWidget {
  /// 是否有音频正在播放（控制按钮可见性）
  final bool hasPlayingAudio;

  /// 点击定位按钮的回调
  final VoidCallback onLocate;

  const LocatePlayingButton({
    super.key,
    required this.hasPlayingAudio,
    required this.onLocate,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasPlayingAudio) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.my_location, size: 20),
      tooltip: "定位播放文件",
      onPressed: onLocate,
    );
  }
}
