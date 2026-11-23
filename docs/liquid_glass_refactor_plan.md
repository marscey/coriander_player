# Coriander Player — 液态玻璃设计语言全量改造方案

> 文档类型：架构设计与实施方案
> 适用平台：iOS、Android（移动端优先）
> 核心组件：`liquid_glass_widgets` 包（`GlassScaffold`, `GlassAppBar`, `GlassButton`, `GlassBottomBar`, `GlassCard`, `GlassSearchableBottomBar`）

---

## 1. 设计目标与原则

### 1.1 设计目标

| 目标 | 说明 |
|------|------|
| **视觉一致性** | 所有页面遵循 iOS 26 Liquid Glass 设计语言，与 Apple Music / Podcasts 视觉风格一致 |
| **滚动驱动** | 导航栏、标题、迷你播放器的状态变化完全由滚动位置驱动，形成自然的交互反馈 |
| **双主题可切换** | 保留原有 Material Design 3 主题，通过设置开关 + 重启切换到 Liquid Glass 主题 |
| **零侵入改造** | 每个页面独立选择最合适的导航模式，不强制统一改造 |
| **性能保持** | 毛玻璃效果使用原生 `BackdropFilter`，避免多次叠加导致性能下降 |

### 1.2 设计原则

1. **内容优先，玻璃为辅**：玻璃效果服务于内容层级，不喧宾夺主
2. **滚动即状态**：用户的滚动行为直接驱动界面元素的透明度/尺寸/位置变化
3. **背景统一**：整个 App 的玻璃效果基于同一背景（当前页面的专辑封面 / 主题色渐变 / 纯色背景）
4. **参数统一**：使用 `RecommendedGlassSettings.standard` 作为基准，个别页面仅微调 `thickness` / `blur`
5. **导航即 AppBar**：页面顶部的返回按钮、标题、操作按钮由 `GlassAppBar` 统一承载，不使用 Flutter 原生 `AppBar`

---

## 2. 技术架构：双主题切换机制

### 2.1 架构总览

```
                    AppPreference.liquidGlassEnabled
                                │
                 ┌──────────────▼──────────────┐
                 │  GoRouter Shell 分支逻辑    │
                 │  lib/entry.dart            │
                 └──────────────┬──────────────┘
                                │
                ┌───────────────┴───────────────┐
                ▼                               ▼
    ┌────────────────────┐          ┌────────────────────┐
    │  Material Shell    │          │  Liquid Glass Shell│
    │  (原有 AppShell)   │          │  (glass_app_shell) │
    │  lib/component/    │          │  lib/component/    │
    │  app_shell.dart   │          │  glass_app_shell.dart │
    └─────────┬──────────┘          └──────────┬──────────┘
              │                                │
     ┌────────▼────────┐               ┌──────▼─────────┐
     │  Material Page  │               │  Glass Page    │
     │  UniPage /      │               │  GlassPageScaffold│
     │  PageScaffold   │               │  + 自定义实现  │
     └─────────────────┘               └────────────────┘
```

### 2.2 开关存储与读取

**文件**：`lib/app_preference.dart`

```dart
class AppPreference {
  // ... 其他偏好字段 ...

  /// 是否启用 Liquid Glass 界面（重启后生效）
  bool liquidGlassEnabled = false;

  Map<String, dynamic> toMap() {
    return {
      // ...
      "liquidGlassEnabled": liquidGlassEnabled,
    };
  }

  static AppPreference fromMap(Map<String, dynamic> prefMap) {
    instance.liquidGlassEnabled = prefMap["liquidGlassEnabled"] ?? false;
    // ... 其他字段 ...
    return instance;
  }
}
```

### 2.3 Shell 路由切换

**文件**：`lib/entry.dart`

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) {
    // 根据开关选择不同的 AppShell
    if (AppPreference.instance.liquidGlassEnabled
        && PlatformHelper.isMobile) {
      return GlassAppShell(navigationShell: navigationShell);
    }
    return AppShell(navigationShell: navigationShell);
  },
  // ...
)
```

### 2.4 页面内部切换

**UniPage**（`lib/page/uni_page.dart`）内部判断开关，自动选择页面骨架：

```dart
Widget result(MultiSelectController<T>? multiSelectController,
              List<Widget> actions) {
  final useGlass = AppPreference.instance.liquidGlassEnabled;

  if (useGlass) {
    return GlassPageScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: finalActions,
      body: bodyContent,
    );
  }

  return PageScaffold(
    title: widget.title,
    subtitle: widget.subtitle,
    actions: finalActions,
    body: bodyContent,
  );
}
```

---

## 3. 核心组件：GlassAppShell

**文件**：`lib/component/glass_app_shell.dart`

GlassAppShell 是整个 App 的骨架，负责：
- 承载 GoRouter 的页面（`navigationShell`）
- 实现玻璃风格的底部导航栏 + 迷你播放器
- 监听滚动事件，动态控制导航栏/迷你播放器的收缩状态

### 3.1 布局结构

```
┌──────────────────────────────────────┐
│                                      │
│      navigationShell (当前页面)      │
│                                      │
│                                      │
│  ┌─────────────────────────────────┐ │
│  │ Now Playing  ▶ Play             │ │ ← _PlayBarPill（迷你播放器）
│  └─────────────────────────────────┘ │
│                                      │
│  ┌─────────────────────────────────┐ │
│  │  🎵  🔍  🏠  📚  ⚙️             │ │ ← GlassBottomBar / GlassSearchableBottomBar
│  └─────────────────────────────────┘ │
└──────────────────────────────────────┘
```

### 3.2 迷你播放器（_PlayBarPill）

```dart
class _PlayBarPill extends StatelessWidget {
  // 复用 ArtistDetailPageV3._PlayBarPill 的实现
  // - 左侧：专辑封面（圆角方形）
  // - 中间：歌曲名 + 艺术家名
  // - 右侧：播放/暂停按钮
  // - 玻璃效果：GlassCard + RecommendedGlassSettings.overlay
  // - 点击进入 Now Playing 页
}
```

### 3.3 滚动监听逻辑

```dart
// 在 GlassAppShellState 中
bool _isMiniMode = false;

bool _onScrollNotification(ScrollNotification notification) {
  if (notification is ScrollUpdateNotification) {
    final metrics = notification.metrics;
    final mini = metrics.pixels > 50;  // 滚动超过 50px 进入 mini 模式
    if (mini != _isMiniMode) {
      setState(() => _isMiniMode = mini);
    }
  } else if (notification is ScrollEndNotification) {
    final metrics = notification.metrics;
    if (metrics.pixels <= 0 && _isMiniMode) {
      setState(() => _isMiniMode = false);  // 回到顶部退出 mini 模式
    }
  }
  return false;
}

// mini 模式下：
// - 迷你播放器：宽度缩减，只显示封面 + 播放按钮
// - GlassBottomBar：玻璃 thickness 增强（更不透明，避免与内容重叠）
```

### 3.4 GlassBottomBar 配置

```dart
GlassBottomBar(
  selectedIndex: _selectedTab,
  onTabSelected: (index) => setState(() => _selectedTab = index),
  settings: RecommendedGlassSettings.standard
      .copyWith(thickness: 20, blur: 3),
  tabs: [
    GlassBottomBarTab(icon: Icon(CupertinoIcons.music_note_2), label: '音乐'),
    GlassBottomBarTab(icon: Icon(CupertinoIcons.search), label: '搜索'),
    GlassBottomBarTab(icon: Icon(CupertinoIcons.music_albums), label: '歌单'),
    GlassBottomBarTab(icon: Icon(CupertinoIcons.gear), label: '设置'),
  ],
)
```

---

## 4. 核心组件：GlassPageScaffold

**文件**：`lib/page/glass_page_scaffold.dart`

GlassPageScaffold 是 UniPage 使用的玻璃风格页面骨架，相当于 Material 主题中的 `PageScaffold`。

### 4.1 布局结构

```
┌──────────────────────────────────────┐
│  [<]  Title              [action1] [action2] [⋯] │ ← GlassAppBar（模式 1/2）
├──────────────────────────────────────┤
│                                      │
│         body (页面内容)               │
│         (CustomScrollView            │
│          / ListView / 其他)          │
│                                      │
└──────────────────────────────────────┘
```

### 4.2 组件 API

```dart
class GlassPageScaffold extends StatefulWidget {
  const GlassPageScaffold({
    super.key,
    required this.title,        // 页面标题（显示在 GlassAppBar.title 中）
    this.subtitle,              // 副标题（显示在标题下方，滚动后渐隐）
    required this.actions,      // 操作按钮列表（GlassButton）
    required this.body,         // 页面内容（通常是 CustomScrollView / ListView）
    this.showBackButton = true, // 是否显示返回按钮
  });
}
```

### 4.3 实现细节

```dart
@override
Widget build(BuildContext context) {
  return NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      // 滚动驱动：更新 AppBar 的毛玻璃强度
      // pixels <= 0 → 完全透明
      // pixels > 50 → 最大玻璃厚度
    },
    child: Stack(
      children: [
        Positioned.fill(child: widget.body),
        Positioned(
          top: 0, left: 0, right: 0,
          child: _buildAppBar(scheme, totalAppBarH, canPop),
        ),
      ],
    ),
  );
}

Widget _buildAppBar(ColorScheme scheme, double barH, bool canPop) {
  return Container(
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
    height: barH,
    child: Row(
      children: [
        if (canPop) GlassButton(icon: Icon(Icons.arrow_back),
          onTap: () => Navigator.of(context).maybePop()),
        // 标题区
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (widget.subtitle != null) Text(widget.subtitle!,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        // 操作按钮（前两个直接显示，后面的收进菜单）
        ...widget.actions.sublist(0, min(2, widget.actions.length)),
        if (widget.actions.length > 2)
          GlassButton(icon: Icon(Icons.more_vert),
            onTap: () => _showMoreMenu(context)),
      ],
    ),
  );
}
```

### 4.4 滚动驱动毛玻璃

```dart
// 在 GlassPageScaffoldState 中
double _scrollPixels = 0;

// 滚动超过 50px 时，毛玻璃达到最大强度（thickness = 12）
// 0-50px 线性插值，渐入渐出
double get _glassThickness {
  final p = (_scrollPixels / 50).clamp(0.0, 1.0);
  // 平滑曲线：p^2 * (3 - 2p) — S-curve
  final smooth = p * p * (3 - 2 * p);
  return 2.0 + smooth * 10.0; // 从 2 平滑到 12
}
```

---

## 5. 各页面改造方案

### 5.1 艺术家详情页 (ArtistDetailPageV3)

**当前实现**：模式 6 (Fade Header) — **已完成**

```
┌──────────────────────────────────────┐
│                                      │
│   ┌─────────────────────────────┐   │
│   │     专辑封面背景图           │   │ ← BackgroundImage + 暗化滤镜
│   └─────────────────────────────┘   │
│                                      │
│   "艺术家名"                         │ ← 固定大标题（header）
│   "专辑数 · 歌曲数"                  │
│                                      │
│   [ 播放全部 ]  [ 随机 ]             │ ← GlassButton (排序/播放按钮组件)
│                                      │
│   ┌─────────────────────────────┐   │
│   │ 专辑列表 (GlassCard 网格)    │   │
│   └─────────────────────────────┘   │
│                                      │
│   ┌─────────────────────────────┐   │
│   │ 歌曲列表 (GlassCard 列表)    │   │
│   └─────────────────────────────┘   │
│                                      │
└──────────────────────────────────────┘
```

**关键代码**：
- `header` — 艺术家名 + 统计信息，随滚动淡出（`headerFadeDistance: 60`）
- 专辑封面作为 `GlassScaffold.background`，应用 `ImageFilter.blur(sigma: 5)` 作为毛玻璃的底图
- 歌曲列表使用 `GlassCard`（`settings: RecommendedGlassSettings.overlay`）
- 「播放全部 / 随机播放」按钮为 `GlassButton.custom`（自定义尺寸和玻璃参数）
- **底部导航栏 + 迷你播放器**：由 GlassAppShell 统一提供（滚动收缩逻辑已实现）

### 5.2 音乐库页面 (AudiosPage → UniPage<Audio>)

**推荐模式**：模式 2 (Large Title → Collapse) — **已通过 GlassPageScaffold 支持**

```
未滚动：
┌──────────────────────────────────────┐
│  [<]                                │ ← GlassAppBar（无标题）
│                                      │
│  音乐库                              │ ← Large Title（34px/bold）
│  1234 首歌曲                         │ ← 副标题
│                                      │
│  [排序] [筛选] [更多]                │ ← GlassButton
│                                      │
│  ┌────────────────────────────────┐ │
│  │ ▶  歌曲 1   艺术家名   3:45     │ │ ← GlassCard
│  └────────────────────────────────┘ │
│  ...                                │
└──────────────────────────────────────┘

滚动 50px 后：
┌──────────────────────────────────────┐
│  [<]    音乐库            [排序][⋯] │ ← GlassAppBar.title 渐显 (Opacity)
├──────────────────────────────────────┤
│  ┌────────────────────────────────┐ │
│  │ ▶  歌曲 1   艺术家名   3:45     │ │
│  └────────────────────────────────┘ │
│  ...                                │
└──────────────────────────────────────┘
```

### 5.3 艺术家列表 (ArtistsPage → UniPage<Artist>)

**推荐模式**：同 5.2 — **已通过 GlassPageScaffold 支持**

### 5.4 专辑详情页 (AlbumDetailPage)

**推荐模式**：模式 6 (Fade Header) — **待实现**

参考艺术家详情页 V3 实现：
- `background`：专辑封面（blur 5）
- `header`：专辑名 + 艺术家名 + 发行年份（随滚动淡出）
- `topEdgeFade: true, bottomEdgeFade: true`
- 歌曲列表：`GlassCard` 列表项

### 5.5 歌单页 (PlaylistsPage → UniPage<Playlist>)

**推荐模式**：模式 2 — **已通过 GlassPageScaffold 支持**

### 5.6 歌单详情页 (PlaylistDetailPage)

**推荐模式**：模式 6 (Fade Header) — **待实现**

（与专辑详情页类似，无封面背景时使用纯色或主题色渐变背景）

### 5.7 搜索页 (SearchPage)

**推荐模式**：模式 4 (Fade Only) + GlassSearchableBottomBar — **待实现**

- 搜索框嵌入底部导航栏（`GlassSearchableBottomBar`）
- 搜索结果使用模式 1 或模式 2 的布局
- 顶部无 AppBar（由搜索框承载导航功能）

### 5.8 设置页 (SettingsPage)

**推荐模式**：模式 1 (Inline Title) — **待实现**

- GlassAppBar：`title: Text('设置')` + 返回按钮
- 设置项：`GlassCard` 列表（分组）
- 子页面（如「外观」「播放引擎」）：模式 1 二级页面

### 5.9 Now Playing 播放页

**推荐模式**：模式 3 变体 + 自定义全屏布局 — **待实现**

- 全屏背景：专辑封面 blur + 暗化
- 内容：专辑封面（居中） + 歌曲信息 + 播放控制栏 + 进度条
- 玻璃效果：控制按钮区使用 `GlassButton`，信息区使用 `GlassCard`
- 退出：手势下滑或返回按钮

---

## 6. Glass 按钮与卡片组件规范

### 6.1 GlassButton — 圆形操作按钮

```dart
GlassButton(
  icon: Icon(Icons.play_arrow),   // 图标
  onTap: () => play(),            // 点击事件
  width: 44, height: 44,          // 尺寸
  iconSize: 24,                   // 图标大小
)
```

**推荐配置**：

| 场景 | width × height | iconSize | 位置 |
|------|---------------|---------|------|
| AppBar 返回按钮 | 40×40 | 20 | GlassAppBar.leading |
| AppBar 操作按钮 | 40×40 | 20 | GlassAppBar.actions |
| 列表项操作按钮 | 36×36 | 18 | GlassCard 右侧 |
| 大按钮（播放全部） | 自定义 | 32 | GlassButton.custom |

### 6.2 GlassCard — 列表项/内容块

```dart
GlassCard(
  settings: RecommendedGlassSettings.overlay,
  padding: EdgeInsets.all(16),
  child: Row(...),  // 左侧色块 + 标题 + 副标题（或歌曲信息）
)
```

**推荐配置**：

| 场景 | thickness | blur | glassColor | 对应 settings |
|------|----------|------|-----------|--------------|
| 标准列表项 | 10 | 10 | `rgba(255,255,255,0.12)` | `overlay` |
| 重要信息块（如艺术家信息） | 16 | 15 | `rgba(255,255,255,0.18)` | `standard.copyWith(...)` |
| 底部导航栏 | 20 | 3 | `rgba(255,255,255,0.22)` | `standard.copyWith(thickness: 20, blur: 3)` |

### 6.3 Glass 排序/播放按钮组件

**文件**：`lib/page/glass_action_buttons.dart`（在 GlassPageScaffold 中使用）

```dart
// 排序按钮 + 排序下拉菜单
Row(
  children: [
    GlassButton(
      icon: Icon(Icons.sort),
      onTap: () => showGlassSortMenu(context, SortOrder.values, currentOrder),
    ),
    SizedBox(width: 8),
    GlassButton(
      icon: Icon(Icons.filter_list),
      onTap: () => showGlassFilterMenu(context, ...),
    ),
    SizedBox(width: 8),
    GlassButton(
      icon: Icon(Icons.playlist_play),
      onTap: () => playAll(),
    ),
  ],
)
```

---

## 7. 推荐 Glass 参数总览

### 7.1 RecommendedGlassSettings 对照

| preset | thickness | blur | glassColor | 用途 |
|--------|----------|------|-----------|------|
| `standard` | 20 | 5 | `rgba(255,255,255,0.12)` | 底部导航栏、大卡片 |
| `overlay` | 10 | 10 | `rgba(255,255,255,0.12)` | 列表项、内容卡 |
| `navButton` | 16 | 12 | `rgba(255,255,255,0.15)` | 导航按钮 |

### 7.2 项目自定义参数

| 位置 | thickness | blur | glassColor | 说明 |
|------|----------|------|-----------|------|
| 底部导航栏 (GlassAppShell) | 20 | 3 | `rgba(255,255,255,0.22)` | 减少 blur 提升可读性 |
| 迷你播放器 (GlassAppShell) | 12 | 8 | `rgba(255,255,255,0.20)` | 与底部导航栏视觉平衡 |
| 页面顶部 AppBar (GlassPageScaffold) | 2→12 | 5→8 | 动态 | 随滚动强度变化 |
| 歌曲列表项 | 10 | 10 | `rgba(255,255,255,0.12)` | 同 overlay preset |
| 艺术家详情页卡片 | 14 | 12 | `rgba(255,255,255,0.15)` | 突出层级 |

---

## 8. 实施方案与进度

### 8.1 阶段划分

| 阶段 | 内容 | 状态 | 相关文件 |
|------|------|------|---------|
| 阶段 0 | 基础设施：liquidGlassEnabled 开关 + GoRouter Shell 分支 | ✅ 完成 | `lib/app_preference.dart`, `lib/entry.dart` |
| 阶段 1 | ArtistDetailPageV3 — 模式 6 参考实现 | ✅ 完成 | `lib/page/artist_detail_page_v3.dart` |
| 阶段 2 | GlassAppShell — Glass 风格底部导航栏 + 迷你播放器 | ✅ 完成 | `lib/component/glass_app_shell.dart` |
| 阶段 2+ | GlassPageScaffold — 通用页面骨架 + UniPage 切换 | ✅ 完成 | `lib/page/glass_page_scaffold.dart`, `lib/page/uni_page.dart` |
| 阶段 3 | 专辑详情页 — 模式 6（参考 V3） | ✅ 完成 | `lib/page/album_detail_page_new.dart` |
| 阶段 4 | 歌单详情页 — 模式 6（简化版） | ✅ 完成 | `lib/page/playlist_detail_page.dart` |
| 阶段 4+ | 列表项组件 Glass 改造：ArtistTile / AlbumTile / PlaylistsPage | ✅ 完成 | `lib/component/artist_tile.dart`, `lib/component/album_tile.dart`, `lib/page/playlists_page.dart` |
| 阶段 5 | 设置页 — 模式 1（标准二级页面）+ SettingsTile Glass 卡片 | ✅ 完成 | `lib/page/settings_page/page.dart`, `lib/component/settings_tile.dart` |
| 阶段 6 | 搜索页 — 模式 4 + GlassSearchableBottomBar | ✅ 完成 | `lib/page/search_page.dart`, `lib/page/search_page/search_result_page.dart` |
| 阶段 7 | Now Playing 播放页 — 自定义全屏布局 | ✅ 完成 | `lib/page/now_playing_page/glass_now_playing_page.dart` |
| 阶段 8 | 整体调优：玻璃参数统一、动画曲线优化、性能测试 | ✅ 完成 | 跨文件 |

### 8.2 优先级

1. **P0（核心体验）**：阶段 0、1、2（已完成）— 让用户可以开启 Liquid Glass 模式、看到艺术家详情页、看到统一的底部导航栏
2. **P1（常用页面）**：阶段 3、4、5 — 专辑详情、歌单详情、设置页
3. **P2（增强体验）**：阶段 6、7 — 搜索页（GlassSearchableBottomBar）、Now Playing 播放页
4. **P3（打磨）**：阶段 8 — 参数精调、性能优化

### 8.3 兼容性回退

- **设置项**："使用 Liquid Glass 界面（需重启）" — 默认 `false`
- **平台判断**：仅在移动端（iOS/Android）启用 Liquid Glass，桌面端保留原有 Material 3 界面（通过 `PlatformHelper.isMobile` 判断）
- **降级**：如 Glass 组件在某设备上性能不佳，用户可在设置中关闭并重启

---

## 9. 已知问题与注意事项

### 9.1 Flutter 构建警告

- **问题**：`liquid_glass_widgets` 包可能在某些 Flutter 版本上触发 "plugin should use Swift Package Manager" 警告
- **影响**：不影响运行，仅为构建时警告
- **处理**：等待包作者更新或忽略警告

### 9.2 多次 `BackdropFilter` 的性能考量

- **问题**：GlassBottomBar + GlassCard + GlassPageScaffold.AppBar 可能同时渲染多个毛玻璃层
- **影响**：低端设备可能有性能下降
- **处理**：
  1. Glass 层的 `blur` 值保持在 5-15 之间（越小越轻）
  2. 避免在同一页面有超过 3 个玻璃层
  3. 考虑使用 `RepaintBoundary` 包装频繁变化的玻璃区域
  4. 对低端设备可在开关中检测设备性能并自动降级

### 9.3 滚动监听与 `NotificationListener`

- **问题**：GlassPageScaffold 使用 `NotificationListener<ScrollNotification>`，如果内容不是 `ScrollView` 子类（如 `Row` / `Column`），不会收到滚动事件
- **处理**：确保传入 `GlassPageScaffold.body` 的组件是可滚动的（`CustomScrollView`, `ListView`, `NestedScrollView` 等），或在外部手动管理滚动状态

### 9.4 专辑封面加载延迟

- **问题**：艺术家详情页的背景图（专辑封面）需要异步加载，初始阶段可能出现短暂的空白
- **处理**：使用 `FadeInImage` 或 `Image` 的 `frameBuilder`，在封面加载前展示主题色背景，加载完成后淡入

### 9.5 暗色模式适配

- **问题**：当前 `glassColor` 基于浅色背景的透明度设计（`rgba(255,255,255,0.xx)`），在暗色模式下效果可能过强或过弱
- **处理**：在暗色模式下将 `glassColor` 的 alpha 调整为 0.15-0.25，在浅色模式下调整为 0.08-0.15，以获得相似的视觉效果

---

## 10. 验收标准

- [x] 设置中存在 "Liquid Glass 界面" 开关，重启后生效
- [x] 开启后底部导航栏和迷你播放器为玻璃风格
- [x] 艺术家详情页使用模式 6（Fade Header + 背景封面）
- [x] 音乐库/艺术家/专辑/歌单列表页使用模式 2（Large Title → Collapse）
- [x] 专辑详情页使用模式 6（参考艺术家详情页）
- [x] 歌单详情页使用模式 6 简化版
- [x] 设置页使用模式 1（Inline Title）
- [x] 搜索页使用模式 4 + GlassSearchableBottomBar
- [x] Now Playing 播放页为玻璃风格全屏布局
- [x] 暗色模式下玻璃效果视觉一致
- [x] 低端设备可关闭 Glass 模式降级
- [ ] 启动时间增加不超过 200ms
- [ ] 列表滚动帧率保持 55 FPS 以上（中高端设备）
