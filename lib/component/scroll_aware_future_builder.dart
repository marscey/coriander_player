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
  T? _cachedData;

  void _createDeferredFuture() {
    if (!context.mounted) return;

    // 如果已有缓存数据，直接使用
    if (_cachedData != null) {
      if (_future == null) {
        setState(() {
          _future = Future.value(_cachedData);
        });
      }
      return;
    }

    // 检查是否应延迟加载（滚动中）
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      if (_future != null) {
        setState(() {
          _future = null;
        });
      }
      // 滚动停止后重试
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (mounted) {
          scheduleMicrotask(_createDeferredFuture);
        }
      });
      return;
    }

    // 创建新的 Future
    setState(() {
      _future = widget.future();
    });
  }

  @override
  Widget build(BuildContext context) {
    _createDeferredFuture();

    if (_future == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        // 缓存成功加载的数据
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          _cachedData = snapshot.data;
        }
        return widget.builder(context, snapshot);
      },
    );
  }
}
