import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double scrollSpeed;
  final Duration pauseDuration;
  final double blankSpace;

  const AutoScrollText({
    super.key,
    required this.text,
    required this.style,
    this.scrollSpeed = 40.0,
    this.pauseDuration = const Duration(seconds: 2),
    this.blankSpace = 40.0,
  });

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText>
    with TickerProviderStateMixin {
  Ticker? _ticker;
  bool _needsScroll = false;
  double _textWidth = 0;
  double _containerWidth = 0;
  double _scrollOffset = 0;
  Duration? _lastElapsed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOverflow();
    });
  }

  @override
  void didUpdateWidget(AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _stopTicker();
      _scrollOffset = 0;
      _lastElapsed = null;
      _needsScroll = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkOverflow();
      });
    }
  }

  void _checkOverflow() {
    if (!mounted) return;

    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    _textWidth = textPainter.width;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    _containerWidth = renderBox.size.width;

    final shouldScroll = _textWidth > _containerWidth;

    if (shouldScroll && !_needsScroll) {
      setState(() {
        _needsScroll = true;
      });
      _startScrollLoop();
    } else if (!shouldScroll && _needsScroll) {
      _stopTicker();
      setState(() {
        _needsScroll = false;
        _scrollOffset = 0;
      });
    }
  }

  Future<void> _startScrollLoop() async {
    if (!mounted || !_needsScroll) return;

    await Future.delayed(widget.pauseDuration);
    if (!mounted || !_needsScroll) return;

    _stopTicker();
    _lastElapsed = null;
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (_lastElapsed == null) {
      _lastElapsed = elapsed;
      return;
    }

    final delta = elapsed - _lastElapsed!;
    _lastElapsed = elapsed;

    final deltaMs = delta.inMicroseconds / 1000.0;
    _scrollOffset += deltaMs * widget.scrollSpeed / 1000.0;

    final cycleWidth = _textWidth + widget.blankSpace;
    if (_scrollOffset > cycleWidth * 10000) {
      final cycles = (_scrollOffset / cycleWidth).floor();
      _scrollOffset -= cycles * cycleWidth;
    }

    if (mounted) setState(() {});
  }

  void _stopTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lineHeight =
        (widget.style.fontSize ?? 14) * (widget.style.height ?? 1.2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleWidth = constraints.maxWidth;

        return ClipRect(
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white,
                  Colors.white,
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.06, 0.94, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SizedBox(
              width: visibleWidth,
              height: lineHeight,
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(-_scrollOffset, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 25.0),
                      Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                      SizedBox(width: widget.blankSpace),
                      Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                      SizedBox(width: widget.blankSpace),
                      Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                      const SizedBox(width: 25.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
