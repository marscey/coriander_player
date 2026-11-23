import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class ScrollAwareFutureBuilder<T> extends StatefulWidget {
  final Future<T> Function() future;
  final AsyncWidgetBuilder builder;

  const ScrollAwareFutureBuilder({
    super.key,
    required this.future,
    required this.builder,
  });

  @override
  State<ScrollAwareFutureBuilder<T>> createState() =>
      _ScrollAwareFutureBuilderState<T>();
}

class _ScrollAwareFutureBuilderState<T>
    extends State<ScrollAwareFutureBuilder<T>> {
  Future<T>? _future;
  bool _isDeferred = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createFuture();
    });
  }

  void _createFuture() {
    if (!context.mounted) return;

    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      if (!_isDeferred) {
        _isDeferred = true;
        if (mounted) setState(() {});
      }
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (mounted) {
          scheduleMicrotask(_createFuture);
        }
      });
      return;
    }

    _isDeferred = false;
    if (_future == null) {
      _future = widget.future();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null || _isDeferred) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _createFuture();
      });
      return const SizedBox.shrink();
    }

    return FutureBuilder<T>(
      future: _future,
      builder: widget.builder,
    );
  }
}
