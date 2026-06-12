# 🖥️ 桌面端主界面 UI 分析报告

> 分析时间：2026-06-12
> 项目：Coriander Player
> 平台：Windows / macOS / Linux
> 设计系统：Material Design 3 (MD3)

---

## 一、整体架构

桌面端采用 **响应式侧边栏布局**，根据屏幕尺寸自适应切换布局模式，并支持侧边栏展开/折叠，提供专业的桌面音乐播放器体验。

### 1.1 三种布局模式

```
┌─────────────────────────────────────────────────────────────┐
│                     标题栏 (TitleBar)                        │
│  [Logo] [应用名] [歌词滚动区域]          [搜索][侧边栏][窗口] │
├────────┬────────────────────────────────────────────────────┤
│        │                                                    │
│  侧边  │              内容区域                               │
│  导航  │         (navigationShell)                          │
│  栏    │                                                    │
│        │                                                    │
│        ├────────────────────────────────────────────────────┤
│        │              迷你播放器                             │
│        │         (MiniNowPlaying)                           │
└────────┴────────────────────────────────────────────────────┘
```

**布局模式**：

| 模式 | 屏幕宽度 | 侧边栏类型 | 特点 |
|------|----------|------------|------|
| **Small** | ≤ 640px | NavigationDrawer (抽屉) | 窄屏模式，侧边栏可收起 |
| **Medium/Large** | > 640px | NavigationDrawer (展开/折叠) | 大中屏幕，支持侧边栏动态展开/折叠 |

> **注意**：Medium 和 Large 模式共用 `_AppShell_Large` 布局类，通过 `SideNavController` 控制侧边栏展开/折叠。标题栏在 Medium/Large 模式下均显示水平歌词视图。

---

## 二、标题栏 (TitleBar)

**位置**: `lib/component/title_bar.dart:21`

### 2.1 响应式标题栏

标题栏高度：**56px**（Small 模式）/ **48px**（Medium/Large 模式）

#### Small 模式 (≤ 640px)

```dart
SizedBox(
  height: 56.0,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8.0),
    child: Row(
      children: [
        // ===== 左侧：内容区（应用标识，可拖拽） =====
        Expanded(
          child: DragToMoveArea(
            child: Row(
              children: [
                Image.asset("app_icon.ico", width: 20, height: 20),
                const SizedBox(width: 8.0),
                Text(
                  "Coriander Player",
                  style: TextStyle(color: scheme.onSurface, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        // ===== 右侧：操作区（搜索 / 导航切换 / 窗口控制） =====
        const _TitleBarSearchBtn(),
        const SizedBox(width: 2.0),
        const _OpenDrawerBtn(),
        if (!PlatformHelper.isMacOS) ...[
          const SizedBox(width: 4.0),
          const WindowControlls(),
        ],
      ],
    ),
  ),
)
```

**特点**：
- 左侧：Logo（20px）+ 应用名称（14px）
- 右侧：搜索按钮 → 抽屉打开按钮 → 窗口控制按钮（非 macOS）
- macOS 隐藏窗口控制按钮（使用原生红绿灯按钮）

#### Medium 模式 (640-1100px)

```dart
Row(
  children: [
    // 左侧：应用图标（固定左侧留白 28px）
    Padding(
      padding: const EdgeInsets.only(left: 28.0, right: 16.0),
      child: Image.asset("app_icon.ico", width: 24, height: 24),
    ),
    const SizedBox(width: 12.0),
    // 中间：水平歌词视图
    const Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: HorizontalLyricView(),
      ),
    ),
    // 右侧：搜索 / 侧边栏切换 / 窗口控制
    const _TitleBarSearchBtn(),
    const SizedBox(width: 2.0),
    const _ToggleSideNavBtn(),
    if (!PlatformHelper.isMacOS) ...[
      const SizedBox(width: 4.0),
      const WindowControlls(),
    ],
  ],
)
```

**特点**：
- 左侧：Logo（24px，左侧留白 28px）
- 中间：**水平歌词滚动区域**（`HorizontalLyricView`）
- 右侧：搜索按钮 → 侧边栏切换按钮 → 窗口控制按钮

#### Large 模式 (≥ 1100px)

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: ListenableBuilder(
    listenable: SideNavController.instance,
    builder: (context, _) {
      final expanded = SideNavController.instance.expanded;
      return Row(
        children: [
          // 左侧：应用标识 + 间距（展开:288px, 折叠:56px）
          DragToMoveArea(
            child: SizedBox(
              width: expanded ? 288 : 56,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Image.asset("app_icon.ico", width: 24, height: 24),
                    if (expanded) ...[
                      const SizedBox(width: 8.0),
                      Text("Coriander Player", ...),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 中间：水平歌词
          Expanded(
            child: DragToMoveArea(
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: HorizontalLyricView(),
              ),
            ),
          ),
          // 右侧：搜索 / 侧边栏切换 / 窗口控制
          const _TitleBarSearchBtn(),
          const _ToggleSideNavBtn(),
          if (!PlatformHelper.isMacOS) const WindowControlls(),
        ],
      );
    },
  ),
)
```

**特点**：
- 左侧区域宽度随侧边栏状态动态变化：**展开时 288px**（Logo + 应用名称），**折叠时 56px**（仅 Logo）
- 中间：**水平歌词滚动区域**
- 右侧：搜索按钮 → 侧边栏切换按钮 → 窗口控制按钮

### 2.2 窗口控制按钮 (WindowControlls)

**位置**: `lib/component/title_bar.dart:255`

**功能**：
```dart
class WindowControlls extends StatefulWidget {
  // ... 状态管理
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.0,
      children: [
        IconButton(
          tooltip: _isFullScreen ? "退出全屏" : "全屏",
          onPressed: _isProcessing ? null : _toggleFullScreen,
          icon: Icon(
            _isFullScreen ? Symbols.close_fullscreen : Symbols.open_in_full,
          ),
        ),
        IconButton(
          tooltip: "最小化",
          onPressed: windowManager.minimize,
          icon: const Icon(Symbols.remove),
        ),
        IconButton(
          tooltip: _isFullScreen ? "全屏模式下不可用" : (_isMaximized ? "还原" : "最大化"),
          onPressed: _isFullScreen || _isProcessing ? null : _toggleMaximized,
          icon: Icon(
            _isMaximized ? Symbols.fullscreen_exit : Symbols.fullscreen,
          ),
        ),
        IconButton(
          tooltip: "关闭",
          onPressed: () async {
            // 关闭逻辑：保存数据后最小化到托盘或完全退出
            if (AppSettings.instance.closeToTray) {
              await savePlaylists();
              await saveLyricSources();
              await AppSettings.instance.saveSettings();
              await AppPreference.instance.save();
              PlayService.instance.desktopLyricService.killDesktopLyric();
              await windowManager.hide();
            } else {
              await savePlaylists();
              await saveLyricSources();
              await AppSettings.instance.saveSettings();
              await AppPreference.instance.save();
              PlayService.instance.close();
              await HotkeysHelper.unregisterAll();
              await windowManager.setPreventClose(false);
              await windowManager.close();
              exit(0);
            }
          },
          icon: const Icon(Symbols.close),
        ),
      ],
    );
  }
}
```

**按钮功能**：
1. **全屏/退出全屏**：切换全屏模式，全屏时禁用最大化按钮
2. **最小化**：最小化窗口
3. **最大化/还原**：切换窗口最大化状态，全屏时禁用
4. **关闭**：保存数据后根据设置最小化到托盘或完全退出

**状态管理**：
- 监听窗口状态变化（`WindowListener`）
- 异步操作防重复点击（`_isProcessing` 状态锁）
- 窗口最大化/还原/全屏状态变化时自动保存设置

### 2.3 侧边栏切换按钮 (_ToggleSideNavBtn)

**位置**: `lib/component/title_bar.dart:217`

```dart
class _ToggleSideNavBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SideNavController.instance,
      builder: (context, _) {
        final expanded = SideNavController.instance.expanded;
        return IconButton(
          tooltip: expanded ? "收起导航栏" : "展开导航栏",
          onPressed: SideNavController.instance.toggle,
          icon: Icon(
            expanded ? Symbols.side_navigation : Symbols.menu,
          ),
        );
      },
    );
  }
}
```

**功能**：
- Medium/Large 模式下显示
- 点击切换侧边导航栏展开/折叠状态
- 展开时显示 `Symbols.side_navigation` 图标，折叠时显示 `Symbols.menu` 图标
- 通过 `SideNavController` 单例管理全局状态

### 2.4 水平歌词视图 (HorizontalLyricView)

**位置**: `lib/component/horizontal_lyric_view.dart`

**布局**：
```dart
DecoratedBox(
  decoration: BoxDecoration(
    color: scheme.secondaryContainer,
    borderRadius: BorderRadius.circular(16.0),
  ),
  child: ListenableBuilder(
    listenable: PlayService.instance.lyricService,
    builder: (context, _) => FutureBuilder(
      future: PlayService.instance.lyricService.currLyricFuture,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Enjoy Music",
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          );
        }
        return _LyricHorizontalScrollArea(snapshot.data!);
      },
    ),
  ),
)
```

**特点**：
- **背景色**: `scheme.secondaryContainer`
- **圆角**: 16px
- **高度**: 随标题栏高度（48px）
- **内容**: 滚动显示当前歌词
- **无歌词时**: 显示 "Enjoy Music" 占位文字
- **动画**: 歌词切换时平滑滚动

**歌词滚动逻辑**：
- 监听 `PlayService.instance.lyricService.lyricLineStream` 获取同步歌词
- 支持 LrcLine（无翻译）和 SyncLyricLine（带翻译，用 ┃ 分隔）
- 歌词行切换时自动滚动到新位置，停留 300ms

---

## 三、侧边导航栏 (SideNav)

**位置**: `lib/component/side_nav.dart:29`

### 3.1 导航项配置

```dart
final destinations = <DestinationDesc>[
  DestinationDesc(Symbols.library_music, "音乐库", app_paths.AUDIOS_PAGE),
  DestinationDesc(Symbols.list, "歌单", app_paths.PLAYLISTS_PAGE),
  DestinationDesc(Symbols.category, "类别", app_paths.CATEGORIES_PAGE),
  DestinationDesc(Symbols.folder, "本地", app_paths.FOLDERS_PAGE),
  DestinationDesc(Symbols.cloud, "连接", app_paths.CLOUD_CONNECTIONS_PAGE),
  DestinationDesc(Symbols.search, "搜索", app_paths.SEARCH_PAGE),
  DestinationDesc(Symbols.settings, "设置", app_paths.SETTINGS_PAGE),
];
```

**7 个导航项**：

| 序号 | 图标 | 标签 | 路径 | 功能描述 |
|:---:|------|------|------|----------|
| 1 | 🎵 | 音乐库 | `/audios` | 本地音乐浏览与管理 |
| 2 | 📋 | 歌单 | `/playlists` | 播放列表管理 |
| 3 | 📂 | 类别 | `/categories` | 艺术家/专辑/流派分类浏览 |
| 4 | 📁 | 本地 | `/folders` | 按文件夹浏览 |
| 5 | ☁️ | 连接 | `/cloud` | WebDAV 云服务 |
| 6 | 🔍 | 搜索 | `/search` | 全局搜索 |
| 7 | ⚙️ | 设置 | `/settings` | 应用设置 |

**类别页面**（`/categories`）是一个入口页面，包含三个子分类：

| 子分类 | 路径 | 说明 |
|--------|------|------|
| 艺术家 | `/categories/artists` | 按艺术家浏览 |
| 专辑 | `/categories/albums` | 按专辑浏览 |
| 流派 | `/categories/genres` | 按流派浏览 |

### 3.2 响应式导航实现

```dart
class SideNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, screenType) {
        switch (screenType) {
          case ScreenType.small:
          case ScreenType.large:
            return _buildNavigationDrawer(
              scheme: scheme,
              selected: selected,
              onDestinationSelected: onDestinationSelected,
            );
          case ScreenType.medium:
            return _buildNavigationRail(
              scheme: scheme,
              selected: selected,
              onDestinationSelected: onDestinationSelected,
            );
        }
      },
    );
  }
}
```

#### Small/Large 模式：NavigationDrawer

**特点**：
- 完整显示图标 + 文字标签
- 背景色：`scheme.surfaceContainer`
- 选中指示：Material Design 3 标准样式

#### Medium 模式：NavigationRail

**特点**：
- 只显示图标，不显示文字标签
- 背景色：`scheme.surfaceContainer`
- 选中指示：图标高亮

### 3.3 侧边栏展开/折叠控制 (SideNavController)

**位置**: `lib/component/app_shell.dart:32`

```dart
class SideNavController extends ChangeNotifier {
  static final SideNavController instance = SideNavController();

  bool _expanded = true;
  bool get expanded => _expanded;

  void toggle() {
    _expanded = !_expanded;
    notifyListeners();
  }

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }
}
```

**功能**：
- **单例模式**：全局唯一实例，通过 `SideNavController.instance` 访问
- **默认展开**：`_expanded = true`
- **联动效果**：标题栏和 AppShell 同时监听此控制器
  - 标题栏左侧区域宽度随展开状态动态变化（288px ↔ 56px）
  - AppShell 中侧边栏通过 `AnimatedSize`（200ms `easeInOut`）动画展开/折叠
  - 内容区域左上角圆角随展开状态变化（8px ↔ 0）

### 3.4 路由分支与导航项映射

**位置**: `lib/entry.dart:143`

```dart
branches: [
  // 0: 音乐库
  StatefulShellBranch(routes: [GoRoute(path: AUDIOS_PAGE, ...)]),
  // 1: 歌单
  StatefulShellBranch(routes: [GoRoute(path: PLAYLISTS_PAGE, ...)]),
  // 2: 类别
  StatefulShellBranch(routes: [GoRoute(path: CATEGORIES_PAGE, ...)]),
  // 3: 本地
  StatefulShellBranch(routes: [GoRoute(path: FOLDERS_PAGE, ...)]),
  // 4: 连接
  StatefulShellBranch(routes: [GoRoute(path: CLOUD_CONNECTIONS_PAGE, ...)]),
  // 5: 搜索
  StatefulShellBranch(routes: [GoRoute(path: SEARCH_PAGE, ...)]),
  // 6: 设置
  StatefulShellBranch(routes: [GoRoute(path: SETTINGS_PAGE, ...)]),
]
```

**移动端底部导航栏映射**：
```dart
const _mobileNavBranchMapping = [0, 1, 3, 5, 6];
// 移动端显示 5 项：音乐库、歌单、本地、搜索、设置
```

### 3.5 路由路径定义

**位置**: `lib/app_paths.dart`

```dart
const String AUDIOS_PAGE = "/audios";
const String AUDIO_DETAIL_PAGE = "/audios/detail";

const String CATEGORIES_PAGE = "/categories";
const String ARTISTS_PAGE = "/categories/artists";
const String ARTIST_DETAIL_PAGE = "/categories/artists/detail";
const String ALBUMS_PAGE = "/categories/albums";
const String ALBUM_DETAIL_PAGE = "/categories/albums/detail";
const String GENRES_PAGE = "/categories/genres";
const String GENRE_DETAIL_PAGE = "/categories/genres/detail";

const String FOLDERS_PAGE = "/folders";
const String FOLDER_DETAIL_PAGE = "/folders/detail";

const String PLAYLISTS_PAGE = "/playlists";
const String PLAYLIST_DETAIL_PAGE = "/playlists/detail";

const String SEARCH_PAGE = "/search";
const String SEARCH_RESULT_PAGE = "/search/result";

const String NOW_PLAYING_PAGE = "/nowplaying";

const String SETTINGS_PAGE = "/settings";
const String SETTINGS_ISSUE_PAGE = "/settings/issue";

const String WELCOMING_PAGE = "/welcoming";
const String UPDATING_DIALOG = "/updating";

const String CLOUD_CONNECTIONS_PAGE = "/cloud";
const String CLOUD_BROWSER_PAGE = "/cloud/browser";

/// 可以作为 start page 的 pages
const List<String> START_PAGES = [
  AUDIOS_PAGE,
  PLAYLISTS_PAGE,
  CATEGORIES_PAGE,
  FOLDERS_PAGE,
  CLOUD_CONNECTIONS_PAGE,
];
```

---

## 四、内容区域

### 4.1 内容容器

**Small 模式**：
```dart
Scaffold(
  backgroundColor: scheme.surfaceContainer,
  appBar: PreferredSize(
    preferredSize: Size.fromHeight(48.0),
    child: TitleBar(),
  ),
  drawer: SideNav(navigationShell: navigationShell),
  body: Stack(children: [navigationShell, const MiniNowPlaying()]),
)
```

**Medium/Large 模式**：
```dart
Scaffold(
  backgroundColor: scheme.surfaceContainer,
  appBar: PreferredSize(
    preferredSize: Size.fromHeight(48.0),
    child: TitleBar(),
  ),
  body: ListenableBuilder(
    listenable: SideNavController.instance,
    builder: (context, _) {
      final expanded = SideNavController.instance.expanded;
      return Row(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.centerLeft,
            child: expanded
                ? SideNav(navigationShell: navigationShell)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(expanded ? 8.0 : 0),
                ),
                child: navigationShell,
              ),
              const MiniNowPlaying()
            ]),
          ),
        ],
      );
    },
  ),
)
```

**特点**：
- **Small 模式**：侧边栏作为抽屉（Drawer），内容区域全屏
- **Medium/Large 模式**：侧边栏内联在左侧，通过 `AnimatedSize` 动画展开/折叠
  - 展开时左上角圆角 8px，折叠时无圆角
- **背景色**: `scheme.surfaceContainer`
- **叠加**: 迷你播放器覆盖在内容底部

### 4.2 迷你播放器可见性

```dart
const List<String> _shellRootPages = [
  '/audios',
  '/categories',
  '/categories/artists',
  '/categories/albums',
  '/categories/genres',
  '/folders',
  '/cloud',
  '/playlists',
  '/playlists/detail',
  '/search',
  '/settings',
];
```

迷你播放器仅在上述根页面显示，进入详情页面（如音频详情、专辑详情）时隐藏。

---

## 五、迷你播放器 (MiniNowPlaying)

**位置**: `lib/component/mini_now_playing.dart`

### 5.1 布局参数

| 属性 | 桌面端 | 移动端 |
|------|--------|--------|
| **宽度** | 600px（固定） | 全屏宽度 |
| **高度** | 64px | 64px |
| **左右边距** | 8px | 8px |
| **底部边距** | 32px | 8px |
| **圆角** | 8px | 8px |
| **阴影** | 4 级 | 4 级 |

### 5.2 响应式布局

```dart
@override
Widget build(BuildContext context) {
  if (!miniPlayerVisibleNotifier.value) return const SizedBox.shrink();

  final isMobile = PlatformHelper.isMobile;
  return ResponsiveBuilder(builder: (context, screenType) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          8.0,
          0,
          8.0,
          isMobile ? 8.0 : (screenType == ScreenType.small ? 8.0 : 32.0),
        ),
        child: SizedBox(
          height: 64.0,
          width: isMobile ? double.infinity : 600.0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: kElevationToShadow[4],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LayoutBuilder(builder: (context, constraints) {
                return RectangleProgressIndicator(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  child: const _NowPlayingForeground(),
                );
              }),
            ),
          ),
        ),
      ),
    );
  });
}
```

**桌面端特点**：
- **固定宽度**: 600px
- **底部边距**: 32px（Small 模式为 8px）
- **居中对齐**: 水平居中
- **进度条**: `RectangleProgressIndicator` 覆盖整个迷你播放器区域

---

## 六、响应式断点策略

**位置**: `lib/component/responsive_builder.dart`

### 6.1 断点定义

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

**二级响应式构建器**（用于播放页面）：
```dart
/// ResponsiveBuilder2: two breakpoints -- small (<=928), large (>928)
```

### 6.2 桌面端布局切换

| 断点 | AppShell 类 | 侧边栏 | 标题栏 | 迷你播放器 |
|------|------------|--------|--------|-----------|
| **Small** (≤ 640px) | `_AppShell_Small` | NavigationDrawer (抽屉) | Logo + 搜索 + 抽屉按钮 + 窗口控制 | 全屏宽度 |
| **Medium/Large** (> 640px) | `_AppShell_Large` | NavigationDrawer (内联，可展开/折叠) | Logo + 歌词 + 搜索 + 侧边栏切换 + 窗口控制 | 600px 固定宽度 |

### 6.3 关键设计决策

1. **Small 模式使用抽屉**：
   - 窄屏下抽屉可以完全隐藏，节省空间
   - 点击抽屉按钮打开，覆盖在内容上方
   - 标题栏高度 56px（比其他模式高 8px，便于触摸操作）

2. **Medium/Large 模式使用内联 NavigationDrawer**：
   - 两种模式共用 `_AppShell_Large`，通过 `SideNavController` 控制展开/折叠
   - 展开时显示完整图标+文字，折叠时完全隐藏
   - `AnimatedSize`（200ms）提供平滑动画
   - 标题栏左侧区域动态适配（288px ↔ 56px）

3. **标题栏统一显示搜索和窗口控制**：
   - 所有模式均显示搜索按钮（`_TitleBarSearchBtn`）
   - Medium/Large 模式显示侧边栏切换按钮（`_ToggleSideNavBtn`）
   - macOS 隐藏自定义窗口控制（使用系统原生红绿灯按钮）

---

## 七、主题与颜色系统

### 7.1 Material Design 3 动态取色

**主题配置** (`lib/entry.dart:78`):
```dart
ThemeData fromSchemeAndFontFamily({
  required ColorScheme colorScheme,
  String? fontFamily,
}) {
  final bool isDark = colorScheme.brightness == Brightness.dark;
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

### 7.2 桌面端关键颜色映射

| 用途 | 颜色属性 | 说明 |
|------|----------|------|
| 标题栏背景 | `scheme.surfaceContainer` | 标题栏整体背景 |
| 侧边栏背景 | `scheme.surfaceContainer` | 侧边导航栏背景 |
| 内容区域背景 | `scheme.surface` | 页面内容背景 |
| 歌词区域背景 | `scheme.secondaryContainer` | 标题栏歌词区域 |
| 标题文字 | `scheme.onSurface` | 应用名称、页面标题 |
| 副标题文字 | `scheme.onSurfaceVariant` | 页面副标题、辅助信息 |
| 选中状态 | `scheme.primary` | 侧边栏选中项 |
| 未选中状态 | `scheme.onSurfaceVariant` | 侧边栏未选中项 |
| 类别入口背景 | `scheme.primaryContainer` | 类别页面图标容器背景 |

### 7.3 暗色模式优化

**当前实现**：
- ✅ 使用 Material Design 3 的语义颜色系统
- ✅ 支持动态取色（`ThemeProvider` 管理亮色/暗色 ColorScheme）
- ✅ 自动适配亮色/暗色模式
- ✅ 暗色模式下 primary surface 使用 `scheme.surface` 而非 `scheme.primary`

---

## 八、桌面端特有功能

### 8.1 窗口管理

**位置**: `lib/component/title_bar.dart:255`

**功能**：
1. **全屏模式**：
   - 通过按钮触发切换
   - 全屏时禁用最大化按钮
   - 进入/退出全屏时自动保存设置

2. **窗口状态持久化**：
   - 最大化/还原状态自动保存（`onWindowMaximize` / `onWindowUnmaximize`）
   - 窗口恢复状态自动保存（`onWindowRestore`）
   - 全屏状态自动保存（`onWindowEnterFullScreen` / `onWindowLeaveFullScreen`）

3. **关闭行为**：
   - **关闭到托盘**：保存播放列表、歌词源、设置、偏好 → 关闭桌面歌词窗口 → 隐藏窗口
   - **完全退出**：保存数据 → 关闭播放服务 → 注销热键 → 关闭窗口

### 8.2 系统托盘

**位置**: `lib/entry.dart:395`

```dart
Future<void> _initSystemTray() async {
  String iconPath;
  if (Platform.isWindows) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    iconPath = p.join(exeDir, 'data', 'flutter_assets', 'app_icon.ico');
  } else if (Platform.isMacOS) {
    iconPath = 'app_icon.ico';
  } else {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    iconPath = p.join(exeDir, 'data', 'flutter_assets', 'app_icon.ico');
  }

  await trayManager.setIcon(iconPath);
  await trayManager.setToolTip('Coriander Player');

  Menu menu = Menu(items: [
    MenuItem(key: 'show_window', label: '显示主窗口'),
    MenuItem.separator(),
    MenuItem(key: 'exit_app', label: '退出'),
  ]);
  await trayManager.setContextMenu(menu);
}
```

**功能**：
- 显示应用图标（按平台区分路径：Windows `.ico`、macOS `app_icon.ico`、Linux `.ico`）
- 鼠标左键点击：显示主窗口并聚焦
- 鼠标右键点击：显示上下文菜单
  - "显示主窗口"
  - "退出"
- 窗口关闭事件拦截：默认隐藏窗口而非退出

### 8.3 拖拽移动区域

```dart
DragToMoveArea(
  child: Row(
    children: [
      Image.asset("app_icon.ico", ...),
      if (expanded) Text("Coriander Player", ...),
    ],
  ),
)
```

**功能**：
- 标题栏大部分区域支持拖拽移动窗口
- Large 模式下有两个 `DragToMoveArea`：左侧标识区 + 中间歌词区
- 避免与按钮、输入框等交互元素冲突

### 8.4 键盘快捷键

**位置**: `lib/hotkeys_helper.dart`

**常用快捷键**：
- `Space`: 播放/暂停
- `Ctrl + ←`: 上一曲
- `Ctrl + →`: 下一曲
- `Esc`: 返回/关闭对话框

### 8.5 桌面歌词窗口

**位置**: `lib/play_service/desktop_lyric_service.dart`

- 管理外部桌面歌词窗口（独立子进程）
- 通过 stdin/stdout JSON 消息通信
- 支持：播放控制、锁定/解锁、主题同步、歌词同步
- 关闭应用时自动终止歌词窗口进程

### 8.6 macOS 媒体控制

**位置**: `lib/play_service/macos_media_control_service.dart`

- 集成系统媒体控制（`audio_service`）
- 支持蓝牙歌词显示（通过 MPNowPlayingInfoCenter）
- 管理锁屏封面缓存

---

## 九、文件位置汇总

### 9.1 核心组件

| 组件 | 文件路径 | 说明 |
|------|----------|------|
| App Shell | `lib/component/app_shell.dart:50` | 根布局 Shell（Small/Mobile/Large 三种模式） |
| 侧边栏控制器 | `lib/component/app_shell.dart:32` | `SideNavController` 展开/折叠状态管理 |
| 标题栏 | `lib/component/title_bar.dart:21` | 标题栏（3种模式） |
| 窗口控制按钮 | `lib/component/title_bar.dart:255` | 全屏、最小化、最大化、关闭 |
| 侧边栏切换 | `lib/component/title_bar.dart:217` | `_ToggleSideNavBtn` |
| 抽屉按钮 | `lib/component/title_bar.dart:204` | `_OpenDrawerBtn`（Small 模式） |
| 返回按钮 | `lib/component/title_bar.dart:238` | `NavBackBtn`（详情页） |
| 侧边导航栏 | `lib/component/side_nav.dart:29` | NavigationDrawer / NavigationRail |
| 水平歌词视图 | `lib/component/horizontal_lyric_view.dart` | 标题栏歌词滚动 |
| 迷你播放器 | `lib/component/mini_now_playing.dart` | 底部迷你播放器 |
| 页面脚手架 | `lib/page/page_scaffold.dart` | 页面头部和内容布局 |
| 通用页面 | `lib/page/uni_page.dart` | 排序、筛选、视图切换 |

### 9.2 页面文件

| 页面 | 文件路径 | 说明 |
|------|----------|------|
| 音乐库 | `lib/page/audios_page.dart` | 本地音乐浏览 |
| 歌单 | `lib/page/playlists_page.dart` | 播放列表管理 |
| 类别入口 | `lib/page/categories_page.dart` | 艺术家/专辑/流派分类入口 |
| 艺术家 | `lib/page/artists_page.dart` | 艺术家列表 |
| 专辑 | `lib/page/albums_page.dart` | 专辑列表 |
| 流派 | `lib/page/genres_page.dart` | 流派列表 |
| 本地文件夹 | `lib/page/folders_page.dart` | 文件夹浏览 |
| 搜索 | `lib/page/search_page/search_page.dart` | 搜索页面 |
| 设置 | `lib/page/settings_page/page.dart` | 设置页面 |
| 播放页面 | `lib/page/now_playing_page/page.dart` | 全屏播放（桌面双栏布局） |
| 正在播放(大) | `lib/page/now_playing_page/large_page.dart` | 桌面/平板双栏布局 |
| 正在播放(小) | `lib/page/now_playing_page/small_page.dart` | 移动端单栏布局 |

### 9.3 工具类

| 工具 | 文件路径 | 说明 |
|------|----------|------|
| 响应式构建器 | `lib/component/responsive_builder.dart` | 屏幕断点判断 |
| 平台辅助 | `lib/platform_helper.dart` | 平台检测 |
| 热键助手 | `lib/hotkeys_helper.dart` | 键盘快捷键 |
| 窗口管理器 | `lib/entry.dart:374` | 系统托盘、窗口状态 |

### 9.4 配置文件

| 文件 | 说明 |
|------|------|
| `lib/entry.dart` | 路由配置（GoRouter + 7 个 ShellBranch）、主题配置、系统托盘 |
| `lib/app_paths.dart` | 路由路径常量定义、可选起始页列表 |
| `lib/app_settings.dart` | 应用设置（窗口状态、关闭到托盘、播放引擎等） |
| `lib/app_preference.dart` | 用户偏好（起始页、排序方式、视图模式等） |
| `lib/theme_provider.dart` | 主题状态管理（颜色方案、字体、亮暗模式） |

---

## 十、桌面端 UI 架构总结图

```
main.dart
  |-- HotkeysHelper.registerHotKeys() [桌面：全局键盘快捷键]
  |-- initWindow() [桌面：窗口管理器、系统托盘]
  |-- runApp(App)
        |-- Entry
              |-- MaterialApp.router (GoRouter)
                    |-- StatefulShellRoute.indexedStack
                    |     |-- AppShell (根布局)
                    |     |     |-- [移动端] _AppShell_Mobile: navigationShell + MiniNowPlaying + MobileBottomNav
                    |     |     |-- [桌面 Small] _AppShell_Small: TitleBar + SideNav(drawer) + [navigationShell + MiniNowPlaying]
                    |     |     |-- [桌面 Medium/Large] _AppShell_Large:
                    |     |           TitleBar(含 HorizontalLyricView + _ToggleSideNavBtn)
                    |     |           + Row[SideNav(AnimatedSize) + ClipRRect(navigationShell) + MiniNowPlaying]
                    |     |
                    |     |-- Branch 0: /audios (AudiosPage → AudioDetailPage)
                    |     |-- Branch 1: /playlists (PlaylistsPage → PlaylistDetailPage)
                    |     |-- Branch 2: /categories (CategoriesPage → Artists/Albums/Genres)
                    |     |-- Branch 3: /folders (FoldersPage → FolderDetailPage)
                    |     |-- Branch 4: /cloud (CloudConnectionsPage → CloudFileBrowser)
                    |     |-- Branch 5: /search (SearchPage → SearchResultPage)
                    |     |-- Branch 6: /settings (SettingsPage → SettingsIssuePage)
                    |
                    |-- GoRoute: /nowplaying (NowPlayingPage)
                    |     |-- [Desktop Large ≥928px] 双栏: _NowPlayingInfo | VerticalLyricView/CurrentPlaylistView
                    |     |     |-- 控制: 音量、独占模式、桌面歌词切换、引擎指示器
                    |     |-- [Desktop Small / Mobile <928px] 单栏，三种视图模式切换
                    |
                    |-- GoRoute: /welcoming (WelcomingPage)
                    |-- GoRoute: /updating (UpdatingPage)
```

**桌面端特有功能**：
1. 自定义 `TitleBar` + `WindowControlls`（全屏、最小化、最大化、关闭）
2. `DragToMoveArea` 窗口拖拽移动
3. `SideNav` 展开/折叠（`SideNavController` + `AnimatedSize` 动画）
4. 标题栏 `HorizontalLyricView`（Medium/Large 模式）
5. `DesktopLyricService` 外部桌面歌词窗口
6. `HotkeysHelper` 全局键盘快捷键
7. 系统托盘（显示/退出菜单）
8. WASAPI 独占模式支持（`_ExclusiveModeSwitch`）
9. 音量 DSP 滑块（`_NowPlayingVolDspSlider`）
10. 关闭到托盘行为

---

**报告完成** ✅

> 本报告基于当前代码库（2026-06-12）分析 Coriander Player 桌面端主界面的 UI 架构、响应式设计、窗口管理和侧边栏折叠功能。
