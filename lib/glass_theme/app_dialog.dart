import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/glass_theme/glass_dialog.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    hide GlassDialog;

/// 统一的自适应对话框：Glass 模式用玻璃弹窗，其余平台/关闭开关时用 Material。
///
/// 用法与 [AlertDialog] 基本一致，只需把 `AdaptiveDialog(` 换成 `AdaptiveDialog(`：
/// ```dart
/// showDialog(
///   context: context,
///   builder: (ctx) => AdaptiveDialog(
///     title: const Text('删除歌单'),
///     content: const Text('确定要删除吗？'),
///     actions: [
///       TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
///       TextButton(onPressed: _delete, child: const Text('删除')),
///     ],
///   ),
/// );
/// ```
class AdaptiveDialog extends StatelessWidget {
  const AdaptiveDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.actionsPadding,
    this.scrollable,
    this.insetPadding,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// 仅 Material 分支使用，Glass 分支忽略
  final EdgeInsetsGeometry? actionsPadding;
  final bool? scrollable;
  final EdgeInsets? insetPadding;

  @override
  Widget build(BuildContext context) {
    final actionWidgets = actions ?? const <Widget>[];

    if (!AppPreference.instance.glassActive) {
      return AdaptiveDialog(
        title: title,
        content: content,
        actions: actionWidgets,
        actionsPadding: actionsPadding,
        scrollable: scrollable ?? false,
        insetPadding: insetPadding,
      );
    }

    return GlassDialog(
      titleWidget: title,
      child: content ?? const SizedBox.shrink(),
      actions: [
        for (int i = 0; i < actionWidgets.length; i++)
          _adaptAction(actionWidgets[i], primary: i == actionWidgets.length - 1),
      ],
    );
  }

  /// 把 Material 的 TextButton 转成玻璃按钮；遇到复杂组件则原样保留
  Widget _adaptAction(Widget action, {required bool primary}) {
    if (action is TextButton) {
      final label = _textOf(action.child);
      if (label != null) {
        return GlassDialogButton(
          label: label,
          primary: primary,
          onTap: action.onPressed,
        );
      }
    }
    return action;
  }

  String? _textOf(Widget? child) {
    if (child is Text) return child.data;
    return null;
  }
}

/// 自适应底部表单：Glass 模式套一层玻璃容器，其余走原生 Material BottomSheet。
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  Color? backgroundColor,
  Color? barrierColor,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  RouteSettings? routeSettings,
  Clip? clipBehavior,
}) {
  final glass = AppPreference.instance.glassActive;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    backgroundColor: glass ? Colors.transparent : backgroundColor,
    useRootNavigator: useRootNavigator,
    barrierColor: glass ? Colors.black45 : (barrierColor),
    constraints: constraints,
    routeSettings: routeSettings,
    clipBehavior: clipBehavior,
    shape: glass ? null : shape,
    builder: (ctx) => glass
        ? GlassBottomSheetBody(child: builder(ctx))
        : builder(ctx),
  );
}

/// 玻璃底部表单的容器
class GlassBottomSheetBody extends StatelessWidget {
  const GlassBottomSheetBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: GlassContainer(
            useOwnLayer: true,
            quality: GlassQuality.premium,
            shape: const LiquidRoundedSuperellipse(borderRadius: 24),
            settings: sheetSettings(glassIsDark(context)),
            child: child,
          ),
        ),
      ),
    );
  }
}
