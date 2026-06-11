# 📱 iOS 端主界面 UI 分析报告

> 分析时间：2026-06-10  
> 项目：Coriander Player  
> 平台：iOS (iPhone/iPad)

---

## 一、整体架构

iOS 端采用 **移动端专用布局** (`_AppShell_Mobile`)，与桌面端完全分离，提供原生移动体验。

```
┌─────────────────────────────────┐
│         SafeArea                │
│  ┌───────────────────────────┐  │
│  │                           │  │
│  │     内容区域               │  │
│  │     (navigationShell)     │  │
│  │                           │  │
│  │                           │  │
│  ├───────────────────────────┤  │
│  │    迷你播放器              │  │
│  │    (MiniNowPlaying)       │  │
│  │    高度: 64px             │  │
│  ├───────────────────────────┤  │
│  │    底部导航栏              │  │
│  │    (MobileBottomNav)      │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

**核心组件**：
- `AppShell` - 主容器，根据平台选择布局
- `MobileBottomNav` - 底部导航栏
- `MiniNowPlaying` - 迷你播放器
- `PageScaffold` - 页面脚手架
- `UniPage` - 通用页面组件

---

## 二、底部导航栏 (MobileBottomNav)

**位置**: `lib/component/side_nav.dart:114`

### 2.1 标签页配置

从 9 个主功能中精选 5 个显示在底部导航栏：

| 序号 | 图标 | 标签 | 路径 | 功能描述 |
|:---:|------|------|------|----------|
| 1 | 🎵 | 音乐库 | `/audios` | 本地音乐浏览与管理 |
| 2 | 🕐 | 最近播放 | `/recent` | 播放历史记录 |
| 3 | ☁️ | 连接 | `/cloud` | WebDAV 云服务连接 |
| 4 | 🔍 | 搜索 | `/search` | 全局搜索功能 |
| 5 | ⚙️ | 设置 | `/settings` | 应用设置与配置 |

### 2.2 分支映射

```dart
/// 移动端底部导航栏的导航项
/// key: 显示在底部导航栏中的项 index (0-4)
/// value: 对应 StatefulShellRoute 的分支 index
const _mobileNavBranchMapping = [0, 1, 5, 7, 8];
```

### 2.3 设计特点

- **组件类型**: Material Design 3 `NavigationBar`
- **背景色**: `scheme.surfaceContainer`
- **选中指示**: Material 3 标准样式（图标+标签高亮）
- **语义标识符**（用于 Maestro 自动化测试）：
  - `tab_library` - 音乐库
  - `tab_recent` - 最近播放
  - `tab_cloud` - 连接
  - `tab_search` - 搜索
  - `tab_settings` - 设置

### 2.4 交互逻辑

```dart
void onDestinationSelected(int mobileIndex) {
  if (mobileIndex == selectedInMobile) return;
  final branchIndex = _mobileNavBranchMapping[mobileIndex];
  navigationShell.goBranch(
    branchIndex,
    initialLocation: branchIndex == navigationShell.currentIndex,
  );
}
```

- 点击标签切换到对应路由分支
- 重复点击同一标签会重置到该分支的初始位置
- 记住每个分支的路由栈状态

---

## 三、迷你播放器 (MiniNowPlaying)

**位置**: `lib/component/mini_now_playing.dart:14`

### 3.1 布局结构

```
┌─────────────────────────────────────────────┐
│  ┌─────┐  歌曲标题                   [≡] [▶]  │
│  │     │  艺术家名                             │
│  │ 封面│                                      │
│  │ 48px│                                      │
│  └─────┘                                      │
└─────────────────────────────────────────────┘
         ━━━━━━━━━━━━━━━━━━━━━━━━━━━
              进度条指示器
```

### 3.2 关键参数

| 属性 | 值 | 说明 |
|------|-----|------|
| 高度 | 64px | 固定高度 |
| 宽度 | `double.infinity` | 全屏宽度 |
| 左右边距 | 8px | 水平内边距 |
| 底部边距 | 8px | 距离底部导航栏 |
| 圆角 | 8px | 四角圆角 |
| 阴影 | `kElevationToShadow[4]` | Material Design 4 级阴影 |

### 3.3 功能特性

#### 3.3.1 封面显示

```dart
nowPlaying != null
    ? FutureBuilder(
        future: nowPlaying.cover,
        builder: (context, snapshot) => switch (snapshot.connectionState) {
          ConnectionState.done => snapshot.data == null
              ? placeholder
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image(
                    image: snapshot.data!,
                    width: 48.0,
                    height: 48.0,
                  ),
                ),
          _ => const CircularProgressIndicator(),
        },
      )
    : placeholder,
```

- **异步加载**: 使用 `FutureBuilder` 异步加载封面
- **尺寸**: 48x48px
- **圆角**: 8px
- **状态处理**:
  - 加载中: 显示 `CircularProgressIndicator`
  - 加载完成: 显示封面图片
  - 加载失败/无封面: 显示 `Symbols.broken_image` 占位符

#### 3.3.2 歌曲信息

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    Text(
      nowPlaying != null ? nowPlaying.title : "Coriander Player",
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: scheme.onSecondaryContainer),
    ),
    Text(
      nowPlaying != null ? nowPlaying.subtitleText : "Enjoy music",
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: scheme.onSecondaryContainer),
    ),
  ],
)
```

- **标题**: 歌曲名称，单行显示，溢出省略
- **副标题**: 艺术家/专辑信息，单行显示，溢出省略
- **颜色**: `scheme.onSecondaryContainer`
- **无歌曲时**: 显示 "Coriander Player" / "Enjoy music"

#### 3.3.3 操作按钮

**播放列表按钮**:
```dart
IconButton(
  tooltip: '播放列表',
  icon: Icon(Symbols.queue_music, color: scheme.onSecondaryContainer),
  onPressed: () => _showPlaylistBottomSheet(context),
)
```

**播放/暂停按钮**:
```dart
StreamBuilder(
  stream: playbackService.playerStateStream,
  initialData: playbackService.playerState,
  builder: (context, snapshot) {
    late void Function() onPressed;
    if (snapshot.data! == PlayerState.playing) {
      onPressed = playbackService.pause;
    } else if (snapshot.data! == PlayerState.completed) {
      onPressed = playbackService.playAgain;
    } else {
      onPressed = playbackService.start;
    }

    return IconButton.filled(
      tooltip: snapshot.data! == PlayerState.playing ? "暂停" : "播放",
      onPressed: onPressed,
      icon: Icon(
        snapshot.data! == PlayerState.playing
            ? Symbols.pause
            : Symbols.play_arrow,
      ),
    );
  },
)
```

- **实时响应**: 使用 `StreamBuilder` 监听播放状态流
- **状态映射**:
  - `PlayerState.playing` → 暂停图标 + 暂停功能
  - `PlayerState.completed` → 播放图标 + 重新播放功能
  - 其他状态 → 播放图标 + 开始播放功能

### 3.4 交互行为

1. **点击迷你播放器** → 跳转全屏播放页面 (`/nowplaying`)
   ```dart
   onTap: () => context.push(app_paths.NOW_PLAYING_PAGE)
   ```

2. **点击播放列表按钮** → 弹出播放列表底部 Sheet
   ```dart
   showModalBottomSheet(
     context: context,
     useRootNavigator: true,
     isScrollControlled: true,
     shape: const RoundedRectangleBorder(
       borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
     ),
     builder: (context) => DraggableScrollableSheet(
       initialChildSize: 0.6,
       minChildSize: 0.3,
       maxChildSize: 0.9,
       expand: false,
       builder: (context, scrollController) => /* 播放列表内容 */,
     ),
   )
   ```

### 3.5 可见性控制

```dart
/// 迷你播放器可见性通知器
/// AppShell 根据当前路由自动更新，MiniNowPlaying 监听此通知器
final ValueNotifier<bool> miniPlayerVisibleNotifier = ValueNotifier<bool>(true);

/// 所有 Tab 一级页面路径（mini player 在这些页面显示）
const List<String> _shellRootPages = [
  '/audios',
  '/recent',
  '/artists',
  '/albums',
  '/folders',
  '/cloud',
  '/playlists',
  '/search',
  '/settings',
];

void _updateVisibility() {
  final path = GoRouterState.of(context).uri.path;
  final normalizedPath = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  miniPlayerVisibleNotifier.value = _shellRootPages.contains(normalizedPath);
}
```

- **显示条件**: 仅在一级页面（Tab 根页面）显示
- **隐藏场景**: 进入详情页面（如歌曲详情、专辑详情）时自动隐藏
- **实现机制**: 通过 `ValueNotifier` 实现响应式更新

### 3.6 播放列表底部 Sheet

**组件**: `DraggableScrollableSheet`

**参数**:
- 初始大小: 60%
- 最小大小: 30%
- 最大大小: 90%
- 顶部圆角: 16px

**内容**:
```
┌─────────────────────────────────────┐
│  播放列表            [定位] [12 首]  │
├─────────────────────────────────────┤
│  ▶ 歌曲 1 - 艺术家 A               │
│    歌曲 2 - 艺术家 B               │
│    歌曲 3 - 艺术家 C               │
│    ...                              │
└─────────────────────────────────────┘
```

**功能**:
- 显示当前播放列表
- 高亮当前播放歌曲
- 定位按钮：自动滚动到当前播放歌曲
- 显示歌曲总数
- 点击歌曲切换播放

---

## 四、内容页面布局

### 4.1 页面脚手架 (PageScaffold)

**位置**: `lib/page/page_scaffold.dart:13`

#### 布局结构

```
┌─────────────────────────────────────────┐
│ [←] 页面标题                [操作按钮...]│
│       副标题（可选）                      │
├─────────────────────────────────────────┤
│                                         │
│           内容区域                       │
│           (body)                        │
│                                         │
└─────────────────────────────────────────┘
```

#### 页面头部

```dart
Padding(
  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: rowChildren,
  ),
)
```

**标题样式**:
```dart
Text(
  title,
  style: TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.bold,
    color: scheme.onSurface,
  ),
  overflow: TextOverflow.ellipsis,
)
```

**副标题样式**:
```dart
Text(
  subtitle!,
  style: TextStyle(fontSize: 13.0, color: scheme.onSurfaceVariant),
  overflow: TextOverflow.ellipsis,
)
```

#### 返回按钮逻辑

```dart
final canPop = showBackButton && context.canPop();
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
```

- 一级页面（Tab 根页面）**不显示**返回按钮
- 详情页面**显示**返回按钮

#### 操作按钮响应式布局

**小屏幕** (`ScreenType.small`):
```dart
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

// 折叠到"更多"菜单
if (foldedActions.isNotEmpty)
  MenuAnchor(
    style: menuStyle,
    menuChildren: foldedActions,
    builder: (_, controller, __) => IconButton.filledTonal(
      tooltip: "更多",
      onPressed: () {
        controller.isOpen ? controller.close() : controller.open();
      },
      icon: const Icon(Symbols.more_vert),
    ),
  )
```

**大屏幕** (`ScreenType.medium` / `ScreenType.large`):
```dart
Wrap(spacing: 8.0, children: actions)
```

- 所有按钮平铺显示
- 使用 `Wrap` 布局自动换行
- 间距 8px

### 4.2 通用页面 (UniPage)

**位置**: `lib/page/uni_page.dart:118`

#### 功能特性

1. **排序功能**
   ```dart
   sortMethods: [
     SortMethodDesc(
       icon: Symbols.title,
       name: "标题",
       method: (list, order) {
         switch (order) {
           case SortOrder.ascending:
             list.sort((a, b) => a.title.localeCompareTo(b.title));
             break;
           case SortOrder.decending:
             list.sort((a, b) => b.title.localeCompareTo(a.title));
             break;
         }
       },
     ),
     // ... 其他排序方式
   ]
   ```

   支持的排序方式：
   - 按标题
   - 按艺术家
   - 按专辑
   - 按创建时间
   - 按修改时间

2. **排序顺序**
   ```dart
   enum SortOrder {
     ascending,  // 升序
     decending;  // 降序
   }
   ```

3. **视图切换**
   ```dart
   enum ContentView {
     list,   // 列表视图
     table;  // 表格视图
   }
   ```

4. **随机播放/顺序播放**
   ```dart
   if (widget.enableShufflePlay) {
     actions.add(SequentialPlay<T>(contentList: widget.contentList));
     actions.add(ShufflePlay<T>(contentList: widget.contentList));
   }
   ```

5. **定位功能**
   ```dart
   if (widget.locateTo == null) return;

   int targetAt = widget.contentList.indexOf(widget.locateTo as T);
   WidgetsBinding.instance.addPostFrameCallback((_) {
     if (currContentView == ContentView.list) {
       scrollController.jumpTo(targetAt * 64);
     } else {
       // 表格视图定位逻辑
     }
   });
   ```

6. **多选模式**
   ```dart
   class MultiSelectController<T> extends ChangeNotifier {
     final Set<T> selected = {};
     bool enableMultiSelectView = false;
     int lastSelectedIndex = -1;

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
   ```

   支持的操作：
   - 单选/多选
   - Shift+点击范围选择
   - 全选/清空
   - 批量刮削元数据
   - 批量添加到歌单
   - 批量从库中移除

#### 列表视图

```dart
ContentView.list => ListView.builder(
  controller: scrollController,
  padding: const EdgeInsets.only(bottom: 96.0),
  itemCount: widget.contentList.length,
  itemExtent: 64,
  itemBuilder: (context, i) => widget.contentBuilder(
    context,
    widget.contentList[i],
    i,
    multiSelectController,
  ),
)
```

- **单行高度**: 64px
- **底部留白**: 96px（避免被迷你播放器遮挡）
- **性能优化**: 使用 `ListView.builder` 懒加载

#### 表格视图

```dart
const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 300,
  mainAxisExtent: 64,
  mainAxisSpacing: 8.0,
  crossAxisSpacing: 8.0,
);

ContentView.table => GridView.builder(
  controller: scrollController,
  padding: const EdgeInsets.only(bottom: 96.0),
  gridDelegate: gridDelegate,
  itemCount: widget.contentList.length,
  itemBuilder: (context, i) => widget.contentBuilder(
    context,
    widget.contentList[i],
    i,
    multiSelectController,
  ),
)
```

- **卡片最大宽度**: 300px
- **卡片高度**: 64px
- **间距**: 8px（水平和垂直）
- **底部留白**: 96px

#### 空状态

```dart
emptyStateBuilder: (context) => Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Symbols.library_music, size: 64, color: Theme.of(context).colorScheme.outline),
      const SizedBox(height: 16),
      Text('音乐库为空', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 8),
      Text('从云服务扫描音频或添加本地文件夹', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
    ],
  ),
)
```

- **大图标**: 64px
- **主提示**: "音乐库为空"
- **副提示**: "从云服务扫描音频或添加本地文件夹"

---

## 五、响应式断点

**位置**: `lib/component/responsive_builder.dart:1`

### 5.1 断点定义

```dart
enum ScreenType {
  /// width <= 640
  small,

  /// 640 < width < 1100
  medium,

  /// width >= 1100
  large,
}
```

### 5.2 iOS 行为

| 断点 | 宽度范围 | iOS 是否触发 | 说明 |
|------|----------|--------------|------|
| **Small** | ≤ 640px | ✅ 是 | iPhone 竖屏默认 |
| **Medium** | 640-1100px | ⚠️ 仅横屏 | iPad 竖屏或 iPhone 横屏 |
| **Large** | ≥ 1100px | ⚠️ 仅横屏 | iPad 横屏 |

**iOS 特殊处理**:
```dart
@override
Widget build(BuildContext context) {
  if (PlatformHelper.isMobile) {
    return _AppShell_Mobile(navigationShell: widget.navigationShell);
  }
  return ResponsiveBuilder(
    builder: (context, screenType) {
      // ... 桌面端布局
    },
  );
}
```

由于 `PlatformHelper.isMobile` 为 `true`，iOS **直接使用** `_AppShell_Mobile`，**跳过** `ResponsiveBuilder`，确保始终使用移动端布局。

---

## 六、主题与颜色

### 6.1 Material Design 3 / Material You

**主题配置** (`lib/entry.dart:77`):
```dart
ThemeData fromSchemeAndFontFamily({
  required ColorScheme colorScheme,
  String? fontFamily,
}) {
  final bool isDark = colorScheme.brightness == Brightness.dark;

  // For surfaces that use primary color in light themes and surface color in dark
  final Color primarySurfaceColor =
      isDark ? colorScheme.surface : colorScheme.primary;
  final Color onPrimarySurfaceColor =
      isDark ? colorScheme.onSurface : colorScheme.onPrimary;

  return ThemeData(
    fontFamily: fontFamily,
    colorScheme: colorScheme,
    brightness: colorScheme.brightness,
    primaryColor: primarySurfaceColor,
    canvasColor: colorScheme.surface,
    scaffoldBackgroundColor: colorScheme.surface,
    cardColor: colorScheme.surface,
    dividerColor: colorScheme.onSurface.withOpacity(0.12),
    indicatorColor: onPrimarySurfaceColor,
    applyElevationOverlayColor: isDark,
    useMaterial3: true,
    dialogTheme: DialogThemeData(backgroundColor: colorScheme.surface),
  );
}
```

### 6.2 关键颜色映射

| 用途 | 颜色属性 | 说明 |
|------|----------|------|
| 背景色 | `scheme.surfaceContainer` | 页面和组件背景 |
| 卡片背景 | `scheme.surface` | 内容卡片背景 |
| 主要文字 | `scheme.onSurface` | 标题、主要内容 |
| 次要文字 | `scheme.onSurfaceVariant` | 副标题、辅助信息 |
| 迷你播放器背景 | `scheme.secondaryContainer` | 迷你播放器容器 |
| 迷你播放器文字 | `scheme.onSecondaryContainer` | 迷你播放器内文字 |
| 分割线 | `scheme.onSurface.withOpacity(0.12)` | 分割线颜色 |

### 6.3 动态取色

- 支持从系统壁纸/主题提取颜色
- 亮色/暗色模式自动切换
- 用户可自定义主题色（通过设置页面）

---

## 七、iOS 特有优化

### 7.1 SafeArea 处理

```dart
Scaffold(
  backgroundColor: scheme.surfaceContainer,
  body: SafeArea(
    bottom: false,  // 底部不安全区域由底部导航栏处理
    child: Stack(children: [
      navigationShell,
      const MiniNowPlaying(),
    ]),
  ),
  bottomNavigationBar: MobileBottomNav(navigationShell: navigationShell),
)
```

- **顶部**: 适配刘海/灵动岛（SafeArea 自动处理）
- **底部**: `bottom: false` 让底部导航栏延伸到 Home Indicator 区域

### 7.2 手势支持

1. **底部导航栏切换**: 点击标签切换页面
2. **迷你播放器点击**: 跳转全屏播放页面
3. **播放列表 Sheet**: 拖拽调整大小（`DraggableScrollableSheet`）
4. **列表滚动**: 带惯性滚动，支持快速滑动
5. **返回手势**: iOS 原生右滑返回手势（通过 GoRouter 支持）

### 7.3 性能优化

1. **懒加载**:
   - `ListView.builder` / `GridView.builder` 仅渲染可见项
   - 封面图片异步加载

2. **状态管理**:
   - 播放状态使用 `StreamBuilder` 实时响应
   - 避免不必要的重建

3. **内存优化**:
   - 使用 `const` 构造函数
   - 合理使用 `AutomaticKeepAliveClientMixin`

---

## 八、文件位置汇总

### 8.1 核心组件

| 组件 | 文件路径 | 行号 |
|------|----------|------|
| App Shell (Mobile) | `lib/component/app_shell.dart` | 126 |
| 底部导航栏 | `lib/component/side_nav.dart` | 114 |
| 迷你播放器 | `lib/component/mini_now_playing.dart` | 14 |
| 页面脚手架 | `lib/page/page_scaffold.dart` | 13 |
| 通用页面 | `lib/page/uni_page.dart` | 118 |

### 8.2 工具类

| 工具 | 文件路径 | 说明 |
|------|----------|------|
| 响应式构建器 | `lib/component/responsive_builder.dart` | 屏幕断点判断 |
| 平台辅助 | `lib/platform_helper.dart` | 平台检测 |
| 路径工具 | `lib/app_paths.dart` | 路由路径常量 |

### 8.3 配置文件

| 文件 | 说明 |
|------|------|
| `lib/entry.dart` | 路由配置、主题配置 |
| `lib/app_paths.dart` | 路由路径定义 |
| `lib/app_preference.dart` | 用户偏好设置 |

### 8.4 页面文件

| 页面 | 文件路径 |
|------|----------|
| 音乐库 | `lib/page/audios_page.dart` |
| 最近播放 | `lib/page/recent_plays_page.dart` |
| 艺术家 | `lib/page/artists_page.dart` |
| 专辑 | `lib/page/albums_page.dart` |
| 文件夹 | `lib/page/folders_page.dart` |
| 云服务 | `lib/page/cloud_service/cloud_connections_page.dart` |
| 歌单 | `lib/page/playlists_page.dart` |
| 搜索 | `lib/page/search_page/search_page.dart` |
| 设置 | `lib/page/settings_page/page.dart` |
| 正在播放 | `lib/page/now_playing_page/page.dart` |

---

## 九、测试标识符（Maestro 自动化测试）

### 9.1 底部导航栏标签

```yaml
# 底部导航栏标签 ID
tab_library: 'nav-tab-0'
tab_recent: 'nav-tab-1'
tab_cloud: 'nav-tab-2'
tab_search: 'nav-tab-3'
tab_settings: 'nav-tab-4'
```

### 9.2 迷你播放器语义标签

```yaml
# 迷你播放器 Semantics label
'迷你播放器 - {歌曲名}'  # 有歌曲播放时
'迷你播放器 - Coriander Player'  # 无歌曲播放时
```

### 9.3 Maestro 测试示例

```yaml
appId: com.example.coriander_player
---
- launchApp
- tapOn: 'nav-tab-0'  # 点击音乐库标签
- tapOn: 'nav-tab-1'  # 点击最近播放标签
- tapOn: '迷你播放器 - *'  # 点击迷你播放器
```

---

## 十、设计亮点总结

### ✅ 优势

1. **原生移动体验**: 完全独立的移动端布局，非简单缩放桌面版
2. **Material Design 3**: 遵循最新设计规范，支持动态取色
3. **性能优化**: 懒加载、异步加载、流式响应
4. **响应式交互**: 迷你播放器智能显隐、播放列表 Sheet
5. **无障碍支持**: 语义标签、键盘快捷键（桌面端）
6. **测试友好**: 清晰的语义标识符，便于自动化测试
7. **状态管理**: Provider + ChangeNotifier，清晰的数据流
8. **路由管理**: GoRouter + StatefulShellRoute，支持分支路由栈

### 🎯 设计原则

1. **移动优先**: iOS 端优先考虑触摸交互和屏幕空间利用
2. **内容优先**: 最大化内容展示区域，操作按钮智能折叠
3. **即时反馈**: 播放状态实时更新，操作立即响应
4. **一致性**: 与桌面端共享业务逻辑，UI 完全独立

---

## 附录：关键代码片段

### A. App Shell 移动端布局

```dart
class _AppShell_Mobile extends StatelessWidget {
  const _AppShell_Mobile({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          navigationShell,
          const MiniNowPlaying(),
        ]),
      ),
      bottomNavigationBar: MobileBottomNav(navigationShell: navigationShell),
    );
  }
}
```

### B. 迷你播放器可见性控制

```dart
class _AppShellState extends State<AppShell> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateVisibility();
  }

  void _updateVisibility() {
    final path = GoRouterState.of(context).uri.path;
    final normalizedPath =
        path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
    miniPlayerVisibleNotifier.value = _shellRootPages.contains(normalizedPath);
  }
}
```

### C. 底部导航栏标签映射

```dart
const _mobileNavBranchMapping = [0, 1, 5, 7, 8];

final _mobileDestinations = <DestinationDesc>[
  destinations[0], // 音乐库
  destinations[1], // 最近播放
  destinations[5], // 连接
  destinations[7], // 搜索
  destinations[8], // 设置
];
```

---

**报告完成** ✅

> 本报告详细分析了 Coriander Player iOS 端主界面的 UI 架构、组件设计、交互逻辑和性能优化策略。
