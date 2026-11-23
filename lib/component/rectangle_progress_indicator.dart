import 'dart:async';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';

class RectangleProgressIndicator extends StatefulWidget {
  const RectangleProgressIndicator({
    super.key,
    required this.size,
    required this.child,
  });

  final Size size;
  final Widget child;

  @override
  State<RectangleProgressIndicator> createState() =>
      _RectangleProgressIndicatorState();
}

class _RectangleProgressIndicatorState
    extends State<RectangleProgressIndicator> {
  /// [positionStream] 的订阅，在dispose取消订阅
  late StreamSubscription<double> subscription;

  /// position / length, [0, 1]
  final progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    final playbackService = PlayService.instance.playbackService;
    _updateProgress();
    playbackService.addListener(_onServiceChanged);
    subscription =
        playbackService.positionStream.listen((event) {
      _updateProgress();
    });
  }

  void _onServiceChanged() {
    _updateProgress();
  }

  void _updateProgress() {
    final playbackService = PlayService.instance.playbackService;
    final len = playbackService.displayLength;
    final pos = playbackService.displayPosition;
    print("[DEBUG] MiniProgress: len=$len, pos=$pos, isRestored=${playbackService.isRestoredState}");
    progress.value = len > 0 ? (pos / len).clamp(0.0, 1.0) : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: widget.size,
      painter: RectangleProgressPainter(progress: progress, scheme: scheme),
      child: widget.child,
    );
  }

  @override
  void dispose() {
    PlayService.instance.playbackService.removeListener(_onServiceChanged);
    subscription.cancel();
    super.dispose();
  }
}

class RectangleProgressPainter extends CustomPainter {
  /// position / length, [0, 1]
  final ValueNotifier<double> progress;

  final ColorScheme scheme;

  RectangleProgressPainter({required this.progress, required this.scheme})
      : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final progressPainter = Paint();
    progressPainter.color = scheme.secondaryContainer;

    final trackPainter = Paint();
    trackPainter.color = scheme.surfaceContainer;

    /// 进度条背景
    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, size.width, size.height),
      trackPainter,
    );

    /// 进度
    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, size.width * progress.value, size.height),
      progressPainter,
    );
  }

  @override
  bool shouldRepaint(RectangleProgressPainter oldDelegate) => false;

  @override
  bool shouldRebuildSemantics(RectangleProgressPainter oldDelegate) => false;
}
