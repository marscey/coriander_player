import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'glass_presets.dart';

/// Glass 风格弹窗容器
///
/// 替代 Material 的 [Dialog] / [AlertDialog]，将内容包裹在 [GlassContainer] 中，
/// 配合 [sheetSettings] 玻璃预设，提供统一的液态玻璃弹窗外观。
///
/// 用法：
/// ```dart
/// showDialog(
///   context: context,
///   barrierColor: Colors.black54,
///   builder: (context) => GlassDialog(
///     title: '标题',
///     actions: [...],
///     child: ...,
///   ),
/// );
/// ```
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    this.title,
    this.titleWidget,
    required this.child,
    this.actions = const [],
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(20.0),
    this.showCloseButton = false,
    this.onClose,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget child;
  final List<Widget> actions;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final bool showCloseButton;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;
    // 键盘避让：弹窗整体上移，并缩减最大高度避免顶部被截断
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Center(
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          shape: const LiquidRoundedSuperellipse(borderRadius: 24),
          settings: sheetSettings,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width ?? (isMobile ? double.infinity : 480),
              maxHeight: (height ?? MediaQuery.of(context).size.height * 0.85) -
                  viewInsetsBottom,
            ),
            child: Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (titleWidget != null)
                    titleWidget!
                  else if (title != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title!,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (showCloseButton)
                            GlassButton(
                              icon: const Icon(CupertinoIcons.xmark, size: 18),
                              iconSize: 18,
                              width: 36,
                              height: 36,
                              useOwnLayer: true,
                              onTap: onClose ?? () => Navigator.pop(context),
                            ),
                        ],
                      ),
                    ),
                  Flexible(child: child),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 16.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions
                          .expand((w) sync* {
                            yield w;
                            yield const SizedBox(width: 8.0);
                          })
                          .toList()
                        ..removeLast(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass 风格的文本按钮（弹窗操作按钮）
///
/// 使用 [GlassButton.custom] 承载图标 + 文字组合内容。
class GlassDialogButton extends StatelessWidget {
  const GlassDialogButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDisabled = onTap == null;
    final textColor = isDisabled
        ? scheme.onSurface.withValues(alpha: 0.4)
        : (primary ? scheme.onPrimary : scheme.onSurface);

    final children = <Widget>[
      if (isLoading)
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
        )
      else if (icon != null)
        Icon(icon, size: 18, color: textColor),
      if (isLoading || icon != null) const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: primary ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ];

    return GlassButton.custom(
      onTap: onTap ?? () {},
      enabled: !isDisabled,
      shape: const LiquidRoundedSuperellipse(borderRadius: 12),
      height: 40,
      useOwnLayer: true,
      stretch: 0.15,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}
