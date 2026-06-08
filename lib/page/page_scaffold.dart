import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/component/responsive_builder.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// title, actions, body
///
/// 提供基本的响应式布局：
///
/// 小屏幕时，折叠第一个组件以外的其他组件。后两个放在同一行；
/// 若 action 总数大于 3，把第二个起倒数第三个为止的组件相继放在下面。
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.actions,
    required this.body,
    this.showBackButton = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ResponsiveBuilder(builder: (context, screenType) {
      List<Widget> rowChildren;

      final canPop = showBackButton && context.canPop();
      // 一级页面（Tab 根页面）不显示返回按钮
      final currentPath = GoRouterState.of(context).uri.toString();
      final isRootPage = app_paths.START_PAGES.any(
        (p) => currentPath == p || currentPath == '$p/',
      );
      final backBtn = (canPop && !isRootPage)
          ? Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                tooltip: "返回",
                onPressed: () => context.pop(),
                icon: const Icon(Symbols.arrow_back),
              ),
            )
          : null;

      if (actions.isEmpty) {
        rowChildren = subtitle == null
            ? [
                if (backBtn != null) backBtn,
                onlyTitle(scheme)
              ]
            : [
                if (backBtn != null) backBtn,
                withSubtitle(scheme)
              ];
      } else {
        switch (screenType) {
          case ScreenType.small:
            {
              // 小屏：定位按钮、随机播放、顺序播放始终可见，其余折叠
              final alwaysVisible = <int>[];
              for (int i = 0; i < actions.length; i++) {
                final typeName = actions[i].runtimeType.toString();
                if (typeName.contains('SequentialPlay') ||
                    typeName.contains('ShufflePlay') ||
                    typeName.contains('LocatePlaying')) {
                  alwaysVisible.add(i);
                }
              }
              // fallback：如果没有找到播放按钮，显示前两个
              if (alwaysVisible.isEmpty) {
                for (int i = 0; i < actions.length && i < 2; i++) {
                  alwaysVisible.add(i);
                }
              }

              final foldedActions = <Widget>[];
              for (int i = 0; i < actions.length; i++) {
                if (!alwaysVisible.contains(i)) {
                  foldedActions.add(actions[i]);
                }
              }

              final menuStyle = MenuStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );

              rowChildren = [
                if (backBtn != null) backBtn,
                subtitle == null ? onlyTitle(scheme) : withSubtitle(scheme),
                const SizedBox(width: 12.0),
                // 始终显示随机播放和顺序播放按钮
                for (final i in alwaysVisible) actions[i],
                if (foldedActions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: MenuAnchor(
                      style: menuStyle,
                      menuChildren: foldedActions,
                      builder: (_, controller, __) => IconButton.filledTonal(
                        tooltip: "更多",
                        onPressed: () {
                          controller.isOpen
                              ? controller.close()
                              : controller.open();
                        },
                        icon: const Icon(Symbols.more_vert),
                      ),
                    ),
                  ),
              ];
              break;
            }
          case ScreenType.medium:
          case ScreenType.large:
            {
              rowChildren = [
                if (backBtn != null) backBtn,
                subtitle == null ? onlyTitle(scheme) : withSubtitle(scheme),
                const SizedBox(width: 16.0),
                Wrap(spacing: 8.0, children: actions)
              ];
            }
        }
      }

      return ColoredBox(
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: rowChildren,
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    });
  }

  Expanded onlyTitle(ColorScheme scheme) {
    return Expanded(
      child: Text(
        title,
        style: TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.bold,
          color: scheme.onSurface,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Expanded withSubtitle(ColorScheme scheme) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 13.0, color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          )
        ],
      ),
    );
  }
}
