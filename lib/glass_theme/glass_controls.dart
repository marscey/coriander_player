import 'dart:math' as math;

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 玻璃控件层：Glass 模式下换成液态玻璃外观，非 Glass 模式内部直接回退原生控件。
///
/// 调用方**不需要**判断 `glassActive`，也不要再自己写 `Switch(` / `Slider(` /
/// `LinearProgressIndicator(` / `Checkbox(`，统一改用本文件的 App* 控件。

bool get _glass => AppPreference.instance.glassActive;

// ─── 开关 ──────────────────────────────────────────────

/// 自适应开关。Glass 模式为胶囊滑块，Material 模式为系统 Switch。
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    if (!_glass) {
      // 玻璃容器里可能没有 Material 祖先，这里显式兜一层透明 Material
      return Material(
        type: MaterialType.transparency,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor,
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final trackOn = activeColor ?? scheme.primary;
    final trackOff = scheme.onSurface.withValues(alpha: 0.35);

    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: GlassContainer(
            width: 46,
            height: 28,
            shape: const LiquidRoundedSuperellipse(borderRadius: 14),
            settings: navButtonSettings(glassIsDark(context)),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: value ? trackOn : trackOff,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 滑块 ──────────────────────────────────────────────

/// 自适应滑块。Glass 模式为细线玻璃轨道 + 玻璃圆钮。
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
    this.onChangeEnd,
    this.onChangeStart,
    this.activeColor,
    this.thumbColor,
    this.secondaryTrackValue,
    this.label,
    this.divisions,
    this.height = 32,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final ValueChanged<double>? onChangeStart;
  final Color? activeColor;

  /// 兼容 Material Slider：玻璃样式下用作圆钮高光色
  final Color? thumbColor;

  /// 兼容 Material Slider 的缓冲进度（如播放缓冲）
  final double? secondaryTrackValue;

  /// Material 分支专用：数值气泡文案
  final String? label;

  /// Material 分支专用：等分刻度
  final int? divisions;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!_glass) {
      return Material(
        type: MaterialType.transparency,
        child: SizedBox(
        height: height,
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeStart: onChangeStart,
          onChangeEnd: onChangeEnd,
          activeColor: activeColor,
          divisions: divisions,
          label: label,
        ),
      ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final progress =
        max <= min ? 0.0 : ((value - min) / (max - min)).clamp(0.0, 1.0);
    final tint = activeColor ?? scheme.primary;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final knobRadius = 9.0;
          final trackWidth = constraints.maxWidth;
          final usable = math.max(1.0, trackWidth - knobRadius * 2);

          void update(double dx) {
            final ratio = ((dx - knobRadius) / usable).clamp(0.0, 1.0);
            onChanged?.call(min + ratio * (max - min));
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (d) => update(d.localPosition.dx) : null,
            onHorizontalDragUpdate:
                enabled ? (d) => update(d.localPosition.dx) : null,
            onHorizontalDragEnd: enabled
                ? (_) => onChangeEnd?.call(value.clamp(min, max))
                : null,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.5,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // 轨道
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // 缓冲部分（若提供）
                  if (secondaryTrackValue != null)
                    FractionallySizedBox(
                      widthFactor: max <= min
                          ? 0.0
                          : ((secondaryTrackValue! - min) / (max - min))
                              .clamp(0.0, 1.0),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  // 已播放部分
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // 玻璃圆钮
                  Positioned(
                    left: progress * usable,
                    child: GlassContainer(
                      width: knobRadius * 2,
                      height: knobRadius * 2,
                      shape: LiquidRoundedSuperellipse(
                        borderRadius: knobRadius,
                      ),
                      settings: navButtonSettings(glassIsDark(context)),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: thumbColor ?? tint,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── 进度 ──────────────────────────────────────────────

/// 自适应线性进度条。Glass 模式为玻璃槽 + 高光填充，支持不确定态。
class AppProgressBar extends StatefulWidget {
  const AppProgressBar({
    super.key,
    this.value,
    this.height = 6,
    this.minHeight,
    this.color,
    this.backgroundColor,
    this.borderRadius,
    this.valueColor,
  });

  /// null 表示不确定进度
  final double? value;
  final double height;

  /// 兼容 Material 命名，等价于 height
  final double? minHeight;
  final Color? color;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  /// 兼容 Material 的动画色
  final Animation<Color>? valueColor;

  double get _barHeight => minHeight ?? height;

  @override
  State<AppProgressBar> createState() => _AppProgressBarState();
}

class _AppProgressBarState extends State<AppProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.value == null && _glass) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AppProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_glass) return;
    if (widget.value == null && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.value != null && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final h = widget._barHeight;
    final radius = widget.borderRadius ?? BorderRadius.circular(h / 2);
    final tintColor = widget.valueColor?.value ?? widget.color ?? scheme.primary;
    final trackColor =
        widget.backgroundColor ?? scheme.onSurface.withValues(alpha: 0.12);

    if (!_glass) {
      return SizedBox(
        height: h,
        child: LinearProgressIndicator(
          value: widget.value,
          minHeight: h,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(h / 2),
          color: tintColor,
          backgroundColor: trackColor,
        ),
      );
    }

    final tint = tintColor;
    final track = trackColor;

    Widget bar(double? factor) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: h,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: track)),
              if (factor != null)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: factor.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tint.withValues(alpha: 0.75), tint],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (widget.value != null) {
      return SizedBox(height: h, child: bar(widget.value));
    }

    return SizedBox(
      height: h,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // 0.15 宽的“光带”从左扫到右
          return SizedBox(
            height: h,
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: track)),
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment((t * 2 - 1) * 1.6, 0),
                      widthFactor: 0.35,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              tint.withValues(alpha: 0.0),
                              tint.withValues(alpha: 0.85),
                              tint.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 自适应圆形加载指示器（尺寸/颜色一致，玻璃页里不使用默认蓝）
class AppSpinner extends StatelessWidget {
  const AppSpinner({
    super.key,
    this.size = 24,
    this.strokeWidth = 2.5,
    this.color,
    this.backgroundColor,
    this.valueColor,
  });

  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;
  final Animation<Color>? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        strokeCap: StrokeCap.round,
        color: valueColor?.value ??
            color ??
            scheme.onSurface.withValues(alpha: 0.85),
        backgroundColor: backgroundColor,
      ),
    );
  }
}

// ─── 复选 ──────────────────────────────────────────────

/// 自适应复选框。Glass 模式为玻璃方块 + 勾选高光。
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.size = 22,
    this.visualDensity,
    this.materialTapTargetSize,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  final double size;

  /// Material 分支透传，玻璃分支忽略
  final VisualDensity? visualDensity;
  final MaterialTapTargetSize? materialTapTargetSize;

  @override
  Widget build(BuildContext context) {
    if (!_glass) {
      return Material(
        type: MaterialType.transparency,
        child: Checkbox(
          value: value,
          onChanged: onChanged,
          tristate: tristate,
          visualDensity: visualDensity ?? VisualDensity.compact,
          materialTapTargetSize: materialTapTargetSize,
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;

    return Semantics(
      checked: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: GlassContainer(
            width: size + 8,
            height: size + 8,
            shape:
                LiquidRoundedSuperellipse(borderRadius: (size + 8) / 2 * 0.45),
            settings: navButtonSettings(glassIsDark(context)),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: value
                      ? scheme.primary.withValues(alpha: 0.85)
                      : scheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(size * 0.28),
                  border: Border.all(
                    color: value
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: value
                    ? Icon(Icons.check, size: size * 0.7, color: scheme.surface)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 输入框装饰 ────────────────────────────────────────

/// 玻璃风格输入框装饰。与 `TextField` / `CupertinoTextField` 的容器统一。
///
/// 用法：`TextField(decoration: glassInputDecoration(context, hintText: '...'))`
InputDecoration glassInputDecoration(
  BuildContext context, {
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? errorText,
  EdgeInsetsGeometry? contentPadding,
  bool dense = false,
}) {
  final scheme = Theme.of(context).colorScheme;

  if (!_glass) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      isDense: dense,
      contentPadding: contentPadding,
      border: const OutlineInputBorder(),
    );
  }

  final radius = BorderRadius.circular(14);
  final borderColor = scheme.onSurface.withValues(alpha: 0.18);
  final fill = scheme.onSurface.withValues(alpha: 0.06);

  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    errorText: errorText,
    isDense: dense,
    filled: true,
    fillColor: fill,
    hintStyle: TextStyle(
      color: scheme.onSurface.withValues(alpha: 0.45),
      fontSize: 14,
    ),
    contentPadding: contentPadding ??
        EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: borderColor, width: 0.8),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: scheme.primary.withValues(alpha: 0.7),
        width: 1.2,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: scheme.error, width: 0.9),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: scheme.error, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: borderColor, width: 0.8),
    ),
  );
}

// ─── 弹出菜单 ──────────────────────────────────────────

/// 玻璃风格弹出菜单的容器装饰（配合 `PopupMenuButton.color` / `shape` 使用）
class GlassPopupMenuStyle {
  const GlassPopupMenuStyle._();

  static Color color(BuildContext context) {
    if (!_glass) return Theme.of(context).colorScheme.surface;
    final isDark = glassIsDark(context);
    return (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7))
        .withValues(alpha: isDark ? 0.94 : 0.92);
  }

  static ShapeBorder shape(BuildContext context) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_glass ? 18 : 8),
      side: _glass
          ? BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.12),
            )
          : BorderSide.none,
    );
  }
}
