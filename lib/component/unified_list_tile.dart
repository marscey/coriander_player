import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 统一列表项组件 — 三个 Tab 页面共用
///
/// 提供一致的视觉风格：
/// - 左侧 48x48 圆角图标容器
/// - 标题 + 副标题
/// - 右侧箭头或自定义 trailing
/// - 高度 64px
class UnifiedListTile extends StatelessWidget {
  const UnifiedListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconBackgroundColor,
    this.iconColor,
    this.isPlaying = false,
  });

  /// 左侧图标
  final IconData icon;

  /// 标题文字
  final String title;

  /// 副标题文字
  final String? subtitle;

  /// 右侧自定义组件（默认显示 chevron_right）
  final Widget? trailing;

  /// 点击回调
  final VoidCallback? onTap;

  /// 图标容器背景色（默认使用 primaryContainer）
  final Color? iconBackgroundColor;

  /// 图标颜色（默认使用 onPrimaryContainer）
  final Color? iconColor;

  /// 是否正在播放（显示跳动指示器覆盖在图标上）
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;
    final bgColor = iconBackgroundColor ?? scheme.primaryContainer;
    final fgColor = iconColor ?? scheme.onPrimaryContainer;

    // Glass 模式下使用渐变图标背景
    final glassIconBg = iconBackgroundColor ??
        scheme.primary.withValues(alpha: 0.7);
    final glassIconFg = iconColor ??
        scheme.onPrimary.withValues(alpha: 0.9);

    return Tooltip(
      message: title,
      child: Semantics(
        identifier: "unified_tile_$title",
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(useGlass ? 16.0 : 12.0),
          child: Container(
            height: useGlass ? null : 64,
            padding: useGlass
                ? const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0)
                : const EdgeInsets.symmetric(horizontal: 4.0),
            decoration: useGlass
                ? BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(
                      color: scheme.onSurface.withValues(alpha: 0.05),
                      width: 0.5,
                    ),
                  )
                : null,
            child: Row(
                children: [
                  // 图标容器（正在播放时叠加跳动指示器）
                  PlayingIndicatorOverlay(
                    size: PlayingIndicatorSize.medium,
                    isActivelyPlaying: isPlaying,
                    child: Container(
                      width: 48.0,
                      height: 48.0,
                      decoration: BoxDecoration(
                        color: useGlass ? glassIconBg : bgColor,
                        gradient: useGlass
                            ? LinearGradient(
                                colors: [
                                  glassIconBg,
                                  scheme.primary.withValues(alpha: 0.4),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Icon(icon, color: useGlass ? glassIconFg : fgColor, size: 28),
                    ),
                  ),
                  // 标题 + 副标题
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: useGlass ? 15.0 : 16.0,
                              fontWeight: useGlass ? FontWeight.w600 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              softWrap: false,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: useGlass
                                    ? scheme.onSurface.withValues(alpha: 0.6)
                                    : scheme.onSurfaceVariant,
                                fontSize: useGlass ? 12.0 : 13.0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // 右侧
                  trailing ??
                      Icon(
                        Symbols.chevron_right,
                        color: scheme.onSurfaceVariant,
                      ),
                ],
              ),
          ),
        ),
      ),
    );
  }
}
