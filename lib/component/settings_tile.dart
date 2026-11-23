import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/glass_theme/glass_presets.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 由 SettingsGroup 注入，用于 SettingsTile 检测是否在分组内
class _SettingsGroupScope extends InheritedWidget {
  const _SettingsGroupScope({required super.child});

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.description,
    this.subtitle,
    required this.action,
    this.inGroup = false,
  });

  final String description;
  final String? subtitle;
  final Widget action;
  final bool inGroup;

  static bool _isInGroup(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_SettingsGroupScope>() != null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;
    final grouped = inGroup || _isInGroup(context);

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                description,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: useGlass ? 15.0 : 18.0,
                  fontWeight: useGlass ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12.0,
                      height: 1.3,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16.0),
        action,
      ],
    );

    if (useGlass && !grouped) {
      return GlassContainer(
        useOwnLayer: true,
        shape: const LiquidRoundedSuperellipse(borderRadius: 14),
        settings: listTileSettings(glassIsDark(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14.0,
            vertical: 10.0,
          ),
          child: content,
        ),
      );
    }

    if (useGlass && grouped) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: content,
      );
    }

    return content;
  }
}

/// 设置项分组卡片
///
/// Glass 模式下将多个设置项合并到一个大圆角卡片中，项之间用细分隔线分开。
/// 非 Glass 模式下直接渲染子项，不改变布局。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final useGlass = AppPreference.instance.glassActive;
    final scheme = Theme.of(context).colorScheme;

    if (!useGlass) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const SizedBox(height: 12.0),
          ],
        ],
      );
    }

    return _SettingsGroupScope(
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(
            color: scheme.onSurface.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 14.0,
                  endIndent: 14.0,
                  color: scheme.onSurface.withValues(alpha: 0.08),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
