import 'dart:ui';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/glass_theme/glass_controls.dart';
import 'package:coriander_player/glass_theme/app_dialog.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/glass_page_scaffold.dart';
import 'package:coriander_player/glass_theme/glass_dialog.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' hide GlassDialog;
import 'package:material_symbols_icons/symbols.dart';

typedef ContentBuilder<T> = Widget Function(BuildContext context, T item,
    int index, MultiSelectController<T>? multiSelectController);

typedef SortMethod<T> = void Function(List<T> list, SortOrder order);

class SortMethodDesc<T> {
  IconData icon;
  String name;
  SortMethod<T> method;

  SortMethodDesc({
    required this.icon,
    required this.name,
    required this.method,
  });
}

enum SortOrder {
  ascending,
  decending;

  static SortOrder? fromString(String sortOrder) {
    for (var value in SortOrder.values) {
      if (value.name == sortOrder) return value;
    }
    return null;
  }
}

enum ContentView {
  list,
  table;

  static ContentView? fromString(String contentView) {
    for (var value in ContentView.values) {
      if (value.name == contentView) return value;
    }
    return null;
  }
}

const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 300,
  mainAxisExtent: 64,
  mainAxisSpacing: 8.0,
  crossAxisSpacing: 8.0,
);

class MultiSelectController<T> extends ChangeNotifier {
  final Set<T> selected = {};
  bool enableMultiSelectView = false;

  /// 记录最后一次选择的索引，用于 Shift+点击范围选择
  int lastSelectedIndex = -1;

  void useMultiSelectView(bool multiSelectView) {
    enableMultiSelectView = multiSelectView;
    notifyListeners();
  }

  void select(T item) {
    selected.add(item);
    notifyListeners();
  }

  void selectAtIndex(T item, int index) {
    selected.add(item);
    lastSelectedIndex = index;
    notifyListeners();
  }

  void unselect(T item) {
    selected.remove(item);
    notifyListeners();
  }

  void clear() {
    selected.clear();
    lastSelectedIndex = -1;
    notifyListeners();
  }

  void selectAll(Iterable<T> items) {
    selected.addAll(items);
    notifyListeners();
  }

  /// 选择从 [fromIndex] 到 [toIndex] 范围内的所有项目
  void selectRange(List<T> items, int fromIndex, int toIndex) {
    final start = fromIndex < toIndex ? fromIndex : toIndex;
    final end = fromIndex < toIndex ? toIndex : fromIndex;
    for (int i = start; i <= end && i < items.length; i++) {
      selected.add(items[i]);
    }
    lastSelectedIndex = toIndex;
    notifyListeners();
  }
}

/// `AudiosPage`, `ArtistsPage`, `AlbumsPage`, `FoldersPage`, `FolderDetailPage` 页面的主要组件，
/// 提供随机播放以及更改排序方式、排序顺序、内容视图的支持。
///
/// `enableShufflePlay` 只能在 `T` 是 `Audio` 时为 `ture`
///
/// `enableSortMethod` 为 `true` 时，`sortMethods` 不可为空且必须包含一个 `SortMethodDesc`
///
/// `defaultContentView` 表示默认的内容视图。如果设置为 `ContentView.list`，就以单行列表视图展示内容；
/// 如果是 `ContentView.table`，就以最大 300 * 64 的子组件以 8 为间距组成的表格展示内容。
///
/// `multiSelectController` 可以使页面进入多选状态。如果它不为空，则 `multiSelectViewActions` 也不可为空
class UniPage<T> extends StatefulWidget {
  const UniPage({
    super.key,
    required this.pref,
    required this.title,
    this.subtitle,
    required this.contentList,
    required this.contentBuilder,
    this.primaryAction,
    required this.enableShufflePlay,
    required this.enableSortMethod,
    required this.enableSortOrder,
    required this.enableContentViewSwitch,
    this.sortMethods,
    this.pinnedItems,
    this.locateTo,
    this.multiSelectController,
    this.multiSelectViewActions,
    this.emptyStateBuilder,
    this.glassMenuItems = const [],
    this.showBackButton = true,
    this.showSettingsButton = false,
  });

  final PagePreference pref;

  final String title;
  final String? subtitle;

  final List<T> contentList;
  final ContentBuilder<T> contentBuilder;

  final Widget? primaryAction;

  final bool enableShufflePlay;
  final bool enableSortMethod;
  final bool enableSortOrder;
  final bool enableContentViewSwitch;

  final List<SortMethodDesc<T>>? sortMethods;

  /// 固定在列表顶部的项（不参与排序）
  final List<T>? pinnedItems;

  final T? locateTo;

  final MultiSelectController<T>? multiSelectController;
  final List<Widget>? multiSelectViewActions;
  final Widget Function(BuildContext context)? emptyStateBuilder;

  /// Glass 模式下追加到 ⋯ 菜单顶部的自定义菜单项
  ///（GlassMenuLabel / GlassMenuItem / GlassMenuDivider 等）
  final List<Widget> glassMenuItems;

  /// 是否显示返回按钮（tab 根页面应设为 false）
  final bool showBackButton;

  /// 是否在右上角显示设置齿轮图标（tab 根页面应设为 true）
  final bool showSettingsButton;

  @override
  State<UniPage<T>> createState() => _UniPageState<T>();
}

class _UniPageState<T> extends State<UniPage<T>> {
  late SortMethodDesc<T>? currSortMethod =
      widget.sortMethods?[widget.pref.sortMethod];
  late SortOrder currSortOrder = widget.pref.sortOrder;
  late ContentView currContentView = widget.pref.contentView;
  late ScrollController scrollController = ScrollController();

  /// 固定项数量（pinned items 不参与排序）
  int get _pinnedCount => widget.pinnedItems?.length ?? 0;

  /// 总项目数（固定项 + 可排序列表项）
  int get _totalItemCount => _pinnedCount + widget.contentList.length;

  @override
  void initState() {
    super.initState();
    // 排序只作用于 contentList，不影响 pinnedItems
    if (widget.contentList.isNotEmpty) {
      currSortMethod?.method(widget.contentList, currSortOrder);
    }
    if (widget.locateTo == null) return;

    int targetAt = widget.contentList.indexOf(widget.locateTo as T);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (currContentView == ContentView.list) {
        scrollController.jumpTo((_pinnedCount + targetAt) * 64);
      } else {
        final renderObject = context.findRenderObject();
        if (renderObject is RenderBox) {
          final ratio =
              PlatformDispatcher.instance.views.first.devicePixelRatio;
          final width = renderObject.size.width - 32;
          final crossAxisCount = (width * ratio / 300).floor();
          final offset = ((_pinnedCount + targetAt) ~/ crossAxisCount) * (64.0 + 8.0);
          scrollController.jumpTo(offset);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant UniPage<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 排序只作用于 contentList
    if (widget.contentList.isNotEmpty) {
      currSortMethod?.method(widget.contentList, currSortOrder);
    }
  }

  void setSortMethod(SortMethodDesc<T> sortMethod) {
    setState(() {
      currSortMethod = sortMethod;
      widget.pref.sortMethod = widget.sortMethods?.indexOf(sortMethod) ?? 0;
      if (widget.contentList.isNotEmpty) {
        currSortMethod?.method(widget.contentList, currSortOrder);
      }
    });
  }

  void setSortOrder(SortOrder sortOrder) {
    setState(() {
      currSortOrder = sortOrder;
      widget.pref.sortOrder = currSortOrder;
      if (widget.contentList.isNotEmpty) {
        currSortMethod?.method(widget.contentList, currSortOrder);
      }
    });
  }

  void setContentView(ContentView contentView) {
    setState(() {
      currContentView = contentView;
      widget.pref.contentView = contentView;
    });
  }

  /// 构建 GlassMenu 菜单项（与 Artist V3 的 ⋯ 菜单完全一致）
  List<Widget> _buildGlassMenuItems() {
    final items = <Widget>[];

    // 自定义菜单项（页面级，如"新建歌单"、"添加连接"等）
    if (widget.glassMenuItems.isNotEmpty) {
      items.addAll(widget.glassMenuItems);
    }

    // 排序方式
    if (widget.enableSortMethod && widget.sortMethods != null) {
      items.add(const GlassMenuLabel(title: '排序方式'));
      items.addAll(
        widget.sortMethods!.map((sm) => GlassMenuItem(
              title: sm.name,
              icon: Icon(sm.icon, size: 20),
              trailing: sm.name == currSortMethod?.name
                  ? const Icon(CupertinoIcons.checkmark_alt, size: 16)
                  : null,
              onTap: () => setSortMethod(sm),
            )),
      );
    }

    // 升序/降序
    if (widget.enableSortOrder) {
      if (items.isNotEmpty) items.add(const GlassMenuDivider());
      items.add(GlassMenuItem(
        title: currSortOrder == SortOrder.ascending ? '升序' : '降序',
        icon: Icon(
          currSortOrder == SortOrder.ascending
              ? Symbols.arrow_upward
              : Symbols.arrow_downward,
          size: 20,
        ),
        onTap: () => setSortOrder(
          currSortOrder == SortOrder.ascending
              ? SortOrder.decending
              : SortOrder.ascending,
        ),
      ));
    }

    // 视图切换
    if (widget.enableContentViewSwitch) {
      if (items.isNotEmpty) items.add(const GlassMenuDivider());
      items.add(GlassMenuItem(
        title: currContentView == ContentView.list ? '列表视图' : '表格视图',
        icon: Icon(
          currContentView == ContentView.list ? Symbols.list : Symbols.table,
          size: 20,
        ),
        onTap: () => setContentView(
          currContentView == ContentView.list
              ? ContentView.table
              : ContentView.list,
        ),
      ));
    }

    // 顺序播放 & 随机播放
    if (widget.enableShufflePlay) {
      if (items.isNotEmpty) items.add(const GlassMenuDivider());
      items.add(GlassMenuItem(
        title: '顺序播放',
        icon: const Icon(Symbols.repeat, size: 20),
        onTap: () => PlayService.instance.playbackService.play(
          0,
          widget.contentList as List<Audio>,
        ),
      ));
      items.add(GlassMenuItem(
        title: '随机播放',
        icon: const Icon(Symbols.shuffle, size: 20),
        onTap: () => PlayService.instance.playbackService.shuffleAndPlay(
          widget.contentList as List<Audio>,
        ),
      ));
    }

    return items;
  }

  /// 构建多选模式下的 GlassMenu 菜单项
  /// 包含：批量刮削、添加到歌单、从库移除
  /// [退出多选] 和 [全选/取消全选] 已放到 actions 中作为独立按钮，不在此菜单里
  List<Widget> _buildMultiSelectGlassMenuItems(
      MultiSelectController<T> multiSelectController) {
    final items = <Widget>[];

    // 多选操作组（由页面通过 multiSelectViewActions 传入）
    // 将原本的 actions 组件转换为 GlassMenuItem 形式
    for (final action in widget.multiSelectViewActions ?? <Widget>[]) {
      // MultiSelectSelectOrClearAll 和 MultiSelectExit 已放到 actions 中，跳过
      if (action is MultiSelectSelectOrClearAll) continue;
      if (action is MultiSelectExit) continue;
      // RemoveFromLibrary 转换为 GlassMenuItem（带二次确认）
      if (action is RemoveFromLibrary) {
        items.add(GlassMenuItem(
          title: '从音乐库移除',
          icon: const Icon(Symbols.delete, size: 20),
          isDestructive: true,
          onTap: () => _showRemoveConfirmDialog(
              context, multiSelectController as MultiSelectController<Audio>),
        ));
        continue;
      }
      // BatchScrapeMetadata 转换为 GlassMenuItem
      if (action is BatchScrapeMetadata) {
        items.add(GlassMenuItem(
          title: '批量刮削元数据',
          icon: const Icon(Symbols.auto_awesome, size: 20),
          onTap: () => _showBatchScrapeDialog(
              context, multiSelectController as MultiSelectController<Audio>),
        ));
        continue;
      }
      // AddAllToPlaylist 转换为 GlassMenuItem
      if (action is AddAllToPlaylist) {
        items.add(GlassMenuItem(
          title: '添加到歌单',
          icon: const Icon(Symbols.playlist_add, size: 20),
          onTap: () => _showAddToPlaylistDialog(
              context, multiSelectController as MultiSelectController<Audio>),
        ));
        continue;
      }
    }

    return items;
  }

  /// 从音乐库移除的二次确认对话框
  void _showRemoveConfirmDialog(
      BuildContext context, MultiSelectController<Audio> controller) {
    final selected = controller.selected;
    if (selected.isEmpty) return;
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AdaptiveDialog(
        title: const Text('确认移除'),
        content: Text('确定将 ${selected.length} 首音频从音乐库中移除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              for (final audio in selected) {
                await AudioLibrary.instance.removeAudio(audio);
              }
              controller.clear();
              controller.useMultiSelectView(false);
              if (context.mounted) Navigator.pop(ctx);
              showTextOnSnackBar(
                '已从音乐库移除 ${selected.length} 首音频',
              );
            },
            child: Text(
              '移除',
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }

  /// 批量刮削元数据对话框
  void _showBatchScrapeDialog(
      BuildContext context, MultiSelectController<Audio> controller) {
    final selected = controller.selected.toList();
    if (selected.isEmpty) return;
    int completed = 0;
    final total = selected.length;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AdaptiveDialog(
            title: const Text("批量刮削元数据"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppProgressBar(
                    value: total > 0 ? completed / total : 0),
                const SizedBox(height: 12),
                Text("已完成 $completed / $total"),
              ],
            ),
            actions: [
              if (completed >= total)
                TextButton(
                  onPressed: () {
                    AudioLibrary.instance.notifyUpdated();
                    PlayService.instance.playbackService.refreshNowPlaying();
                    Navigator.pop(ctx);
                    controller.clear();
                    controller.useMultiSelectView(false);
                  },
                  child: const Text("完成"),
                ),
            ],
          );
        },
      ),
    );

    for (final audio in selected) {
      MetadataService.instance.scrapeAndApply(audio: audio).then((_) {
        completed++;
        audio.clearCoverCache();
        if (completed >= total) {
          showTextOnSnackBar("批量刮削完成：$total 首音频");
        }
      }).catchError((_) {
        completed++;
      });
    }
  }

  /// 添加到歌单对话框
  void _showAddToPlaylistDialog(
      BuildContext context, MultiSelectController<Audio> controller) {
    final selected = controller.selected.toList();
    if (selected.isEmpty) return;
    // 弹出歌单选择菜单
    final playlists = PlaylistManager.instance.allPlaylists;
    if (playlists.isEmpty) {
      showTextOnSnackBar('没有可用的歌单，请先创建歌单');
      return;
    }
    final useGlass = AppPreference.instance.glassActive;

    void addToPlaylist(Playlist playlist) {
      PlaylistManager.instance.addAudiosToPlaylist(playlist, selected);
      Navigator.pop(context);
      showTextOnSnackBar(
        '已添加 ${selected.length} 首到歌单「${playlist.name}」',
      );
    }

    if (useGlass) {
      // Glass 模式：使用 GlassDialog 保持视觉一致性
      showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (ctx) => GlassDialog(
          title: '添加到歌单',
          width: 420,
          height: 480,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          actions: [
            GlassDialogButton(
              label: '取消',
              icon: Symbols.close,
              onTap: () => Navigator.pop(ctx),
            ),
          ],
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: playlists.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            itemBuilder: (ctx, i) {
              final playlist = playlists[i];
              return _GlassPlaylistTile(
                playlist: playlist,
                onTap: () => addToPlaylist(playlist),
              );
            },
          ),
        ),
      );
    } else {
      // 普通模式：保持 AlertDialog
      showDialog(
        context: context,
        builder: (ctx) => AdaptiveDialog(
          title: const Text('添加到歌单'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (ctx, i) => ListTile(
                leading: const Icon(Symbols.playlist_play),
                title: Text(playlists[i].name),
                onTap: () => addToPlaylist(playlists[i]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final useGlass = AppPreference.instance.glassActive;
    final List<Widget> actions = [];
    if (widget.primaryAction != null) {
      actions.add(widget.primaryAction!);
    }
    // Glass 模式下：排序/视图切换/播放等按钮放到三个点菜单中（_buildGlassMenuItems），
    // 不展开在导航栏上；普通模式则展开在导航栏上
    if (!useGlass) {
      if (widget.enableShufflePlay) {
        actions.add(SequentialPlay<T>(contentList: widget.contentList));
        actions.add(ShufflePlay<T>(contentList: widget.contentList));
      }
      if (widget.enableSortMethod) {
        actions.add(SortMethodComboBox<T>(
          sortMethods: widget.sortMethods!,
          contentList: widget.contentList,
          currSortMethod: currSortMethod!,
          setSortMethod: setSortMethod,
        ));
      }
      if (widget.enableSortOrder) {
        actions.add(SortOrderSwitch<T>(
          sortOrder: currSortOrder,
          setSortOrder: setSortOrder,
        ));
      }
      if (widget.enableContentViewSwitch) {
        actions.add(ContentViewSwitch<T>(
          contentView: currContentView,
          setContentView: setContentView,
        ));
      }
    }

    return widget.multiSelectController == null
        ? result(null, actions)
        : ListenableBuilder(
            listenable: widget.multiSelectController!,
            builder: (context, _) => result(
              widget.multiSelectController!,
              actions,
            ),
          );
  }

  Widget result(
      MultiSelectController<T>? multiSelectController, List<Widget> actions) {
    final useGlass = AppPreference.instance.glassActive;
    // Glass 模式下：多选操作通过 menuItems + 全选按钮处理，finalActions 只用普通 actions
    // 普通模式下：多选时使用 multiSelectViewActions（展开按钮组）
    final isInMultiSelectView =
        multiSelectController?.enableMultiSelectView == true;
    final finalActions = useGlass
        ? actions
        : (multiSelectController == null
            ? actions
            : isInMultiSelectView
                ? widget.multiSelectViewActions!
                : actions);
    final isEmpty = _totalItemCount == 0 && widget.emptyStateBuilder != null;

    // ── Glass 模式：CustomScrollView + GlassPageHeader ──
    if (useGlass) {
      // 内容 sliver（根据 contentView 模式不同）
      final contentSliver = isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 140.0),
                child: widget.emptyStateBuilder!(context),
              ),
            )
          : switch (currContentView) {
              ContentView.list => SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 140.0),
                  sliver: SliverList.separated(
                    itemCount: _totalItemCount,
                    separatorBuilder: (context, i) =>
                        const SizedBox(height: 6.0),
                    itemBuilder: (context, i) {
                      if (i < _pinnedCount) {
                        return widget.contentBuilder(
                          context,
                          widget.pinnedItems![i],
                          i,
                          multiSelectController,
                        );
                      }
                      final contentIndex = i - _pinnedCount;
                      return widget.contentBuilder(
                        context,
                        widget.contentList[contentIndex],
                        contentIndex,
                        multiSelectController,
                      );
                    },
                  ),
                ),
              ContentView.table => SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 140.0),
                  sliver: SliverGrid.builder(
                    gridDelegate: gridDelegate,
                    itemCount: _totalItemCount,
                    itemBuilder: (context, i) {
                      if (i < _pinnedCount) {
                        return widget.contentBuilder(
                          context,
                          widget.pinnedItems![i],
                          i,
                          multiSelectController,
                        );
                      }
                      final contentIndex = i - _pinnedCount;
                      return widget.contentBuilder(
                        context,
                        widget.contentList[contentIndex],
                        contentIndex,
                        multiSelectController,
                      );
                    },
                  ),
                ),
            };

      final body = CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: GlassPageHeader(
              title: widget.title,
              subtitle: widget.subtitle,
            ),
          ),
          contentSliver,
        ],
      );

      final isInMultiSelectView =
          multiSelectController?.enableMultiSelectView == true;

      // 多选模式下：menuItems 替换为多选操作组（批量刮削/添加到歌单/移除）
      // 普通模式下：menuItems 为 primaryAction 菜单项 + 排序/视图切换等
      final glassMenuItems = isInMultiSelectView
          ? _buildMultiSelectGlassMenuItems(multiSelectController!)
          : _buildGlassMenuItems();

      // 多选模式参数
      final isAllSelected = isInMultiSelectView &&
          multiSelectController != null &&
          widget.contentList.isNotEmpty &&
          multiSelectController.selected.length >= widget.contentList.length;

      return GlassPageScaffold(
        title: widget.title,
        subtitle: widget.subtitle,
        menuItems: glassMenuItems,
        body: body,
        showBackButton: widget.showBackButton,
        showSettingsButton:
            widget.showSettingsButton && !isInMultiSelectView,
        isSelectionMode: isInMultiSelectView,
        selectionCount: multiSelectController?.selected.length ?? 0,
        isAllSelected: isAllSelected,
        onExitSelection: isInMultiSelectView
            ? () {
                multiSelectController!.clear();
                multiSelectController.useMultiSelectView(false);
              }
            : null,
        onToggleSelectAll: isInMultiSelectView && multiSelectController != null
            ? () {
                if (multiSelectController.selected.length >=
                    widget.contentList.length) {
                  multiSelectController.clear();
                } else {
                  for (final item in widget.contentList) {
                    multiSelectController.select(item);
                  }
                }
              }
            : null,
      );
    }

    // ── 普通模式：PageScaffold ──
    final bodyContent = isEmpty
        ? widget.emptyStateBuilder!(context)
        : Material(
            type: MaterialType.transparency,
            child: switch (currContentView) {
              ContentView.list => ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 96.0),
                  itemCount: _totalItemCount,
                  separatorBuilder: (context, i) =>
                      const SizedBox(height: 6.0),
                  itemBuilder: (context, i) {
                    if (i < _pinnedCount) {
                      return widget.contentBuilder(
                        context,
                        widget.pinnedItems![i],
                        i,
                        multiSelectController,
                      );
                    }
                    final contentIndex = i - _pinnedCount;
                    return widget.contentBuilder(
                      context,
                      widget.contentList[contentIndex],
                      contentIndex,
                      multiSelectController,
                    );
                  },
                ),
              ContentView.table => GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 96.0),
                  gridDelegate: gridDelegate,
                  itemCount: _totalItemCount,
                  itemBuilder: (context, i) {
                    if (i < _pinnedCount) {
                      return widget.contentBuilder(
                        context,
                        widget.pinnedItems![i],
                        i,
                        multiSelectController,
                      );
                    }
                    final contentIndex = i - _pinnedCount;
                    return widget.contentBuilder(
                      context,
                      widget.contentList[contentIndex],
                      contentIndex,
                      multiSelectController,
                    );
                  },
                ),
            },
          );

    // 经典模式：设置入口放入 actions（会被 PageScaffold 折叠到更多菜单中）
    final classicActions = List<Widget>.from(finalActions);
    if (widget.showSettingsButton &&
        multiSelectController?.enableMultiSelectView != true) {
      classicActions.add(
        IconButton(
          tooltip: '设置',
          onPressed: () => context.push(app_paths.SETTINGS_PAGE),
          icon: const Icon(Symbols.settings),
        ),
      );
    }

    return PageScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: classicActions,
      body: bodyContent,
    );
  }
}

/// Glass 风格的歌单列表项，用于"添加到歌单"弹窗
class _GlassPlaylistTile extends StatelessWidget {
  const _GlassPlaylistTile({
    required this.playlist,
    required this.onTap,
  });

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(Symbols.playlist_play, size: 22, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  playlist.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Symbols.chevron_right, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
