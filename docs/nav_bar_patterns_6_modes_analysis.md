# Liquid Glass Widgets — 6 种导航栏模式解析

> 源代码路径：`.trae/test/liquid_glass_widgets/example/lib/demos/nav_bar_patterns_demo.dart`

iOS 26 Liquid Glass 设计语言提供了 6 种导航栏布局模式，用于应对不同页面的信息密度和内容沉浸度需求。所有模式共享同一组底层组件（`GlassScaffold` + `GlassAppBar` / `GlassBottomBar` + `GlassButton`），只是布局方式和滚动行为不同。

---

## 全局基础设置

所有 Demo 共享以下配置：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `GlassScaffold.background` | `ShowcaseBackground()` | 毛玻璃的底图（彩色渐变） |
| `GlassScaffold.settings` | `RecommendedGlassSettings.standard` | 标准玻璃参数 |
| `statusBarStyle` | `GlassStatusBarStyle.auto` | 根据亮/暗模式自动选择状态栏样式 |
| Glass Button 尺寸 | 40×40，iconSize 20 | 统一的导航按钮规格 |
| 内容填充 | `EdgeInsets.symmetric(horizontal: 24)` | 与 iOS 原生一致 |
| 底部留白 | `SizedBox(height: 100)` | 防止底部内容被导航栏遮挡 |

## 模式 1：Inline Title（标题与返回按钮同排）

**定位**：标准的紧凑型导航栏，与 Apple Notes、App Store 一致。

```
┌────────────────────────────────────┐
│  [<]        Inline Title        [⋯] │
├─────────────────────────────────────┤
│                                     │
│   ┌──────────────────────────────┐  │
│   │  [■]  Item 1                 │  │
│   └──────────────────────────────┘  │
│   ┌──────────────────────────────┐  │
│   │  [■]  Item 2                 │  │
│   └──────────────────────────────┘  │
│                                     │
└─────────────────────────────────────┘
```

### 结构

```dart
GlassScaffold(
  appBar: GlassAppBar(
    title: Text('Inline Title'),   // 标题始终显示
    leading: GlassButton(icon: back),
    actions: [GlassButton(icon: ellipsis)],
  ),
  body: CustomScrollView(...),
)
```

### 关键特性

| 特性 | 实现方式 |
|------|---------|
| 标题位置 | 返回按钮右侧，`Text` + `fontSize 20/bold` |
| appBar 是否透明 | `backgroundColor` 未设置 → 完全透明 |
| 内容起点 | `SizedBox(height: topPad + 44 + 16)` |
| 滚动时毛玻璃 | 由 `GlassScrollEdgeEffect` 自动处理 |
| 适用场景 | 简单列表页、二级页面、设置页面 |

### 适用的 Coriander Player 页面

- 设置页（二级页面）
- 艺术家/专辑详情页（简化版）
- 播放列表详情

---

## 模式 2：Large Title → Collapse（大标题滚入→导航栏渐现）

**定位**：iOS 原生的「大标题→紧凑标题」滚动模式，Apple Music / Podcasts 最常见的模式。

```
顶部（未滚动）                    滚动后
┌──────────────────────┐         ┌──────────────────────┐
│  [<]                │         │  [<]      Chats    [＋]│
│                      │         │                      │
│  Chats              │         ├──────────────────────┤
│  (34px, bold)        │         │   (collapsed)        │
├──────────────────────┤         │   ┌───────────────┐  │
│   ┌────────────────┐ │         │   │ [■] Item 1   │  │
│   │ [■] Item 1     │ │         │   └───────────────┘  │
│   └────────────────┘ │         │   ┌───────────────┐  │
│   ┌────────────────┐ │         │   │ [■] Item 2   │  │
│   │ [■] Item 2     │ │         │   └───────────────┘  │
│   └────────────────┘ │         │                       │
└──────────────────────┘         └──────────────────────┘
```

### 结构

```dart
// 滚动驱动
final _scrollController = ScrollController();
final _largeTitleHeight = 52.0;
final _collapseProgress =
    (_scrollOffset / _largeTitleHeight).clamp(0.0, 1.0);

GlassScaffold(
  appBar: GlassAppBar(
    // appBar 标题随滚动渐显
    title: Opacity(
      opacity: _collapseProgress,
      child: Text('Chats'),
    ),
    leading: GlassButton(...),
    actions: [GlassButton(camera), GlassButton(plus)],
  ),
  body: CustomScrollView(
    slivers: [
      // 顶部留白（状态栏 + appBar 高度）
      SliverToBoxAdapter(child: SizedBox(height: topPad + 44)),
      // 大标题（随滚动渐隐）
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Text(
            'Chats',
            style: TextStyle(
              fontSize: 34,
              // alpha 从 1 → 0
              color: color.withValues(alpha: 1.0 - _collapseProgress),
            ),
          ),
        ),
      ),
      _buildDummyContent(),
    ],
  ),
)
```

### 关键特性

| 特性 | 实现方式 |
|------|---------|
| 大标题高度 | 52px，与 `_collapseProgress` 同步 |
| 渐隐曲线 | 线性（`_collapseProgress = offset / 52`） |
| appBar 标题 | `Opacity(progress)`，滚动到 52px 时完全可见 |
| 内容中的大标题 | `Text(... color.withValues(alpha: 1.0 - progress))` |
| 适用场景 | 信息密度高但需要视觉层次的主列表页 |
| 是否需要 StatefulWidget | 是（需要监听滚动） |

### 适用的 Coriander Player 页面

- 音乐库主页
- 类别页（Artists/Albums/Genres）
- 搜索结果页

---

## 模式 3：Solid Background（纯色背景栏，WhatsApp 风格）

**定位**：不透明导航栏，用于需要突出品牌色或暗色主题的页面。

```
┌──────────────────────────────────┐
│  [<]  Solid Background [📷] [📞] │
│   (backgroundColor: #1F2C34)      │
├───────────────────────────────────┤
│                                   │
│   ┌────────────────────────────┐ │
│   │ [■] Item 1                 │ │
│   └────────────────────────────┘ │
│                                   │
└──────────────────────────────────┘
```

### 结构

```dart
GlassScaffold(
  edgeFade: false,         // 禁用边缘淡出（不需要内容透过导航栏）
  appBar: GlassAppBar(
    backgroundColor: isDark
        ? Color(0xFF1F2C34)   // 深绿灰
        : Color(0xFFE8EDF0),  // 浅灰
    title: Text('Solid Background', style: TextStyle(fontSize: 18, fontWeight: 600)),
    centerTitle: false,        // 左对齐（WhatsApp 风格）
    leading: GlassButton(back),
    actions: [GlassButton(videocam), GlassButton(phone)],
  ),
  body: CustomScrollView(...),
)
```

### 关键特性

| 特性 | 实现方式 |
|------|---------|
| `backgroundColor` | 明确设置纯色值（完全不透明） |
| `centerTitle: false` | 左对齐标题 |
| `edgeFade: false` | 禁用状态栏区域内容淡出 |
| Glass 按钮 | 仍为玻璃效果（浅色背景上仍可见折射） |
| 适用场景 | 聊天类应用、品牌色强烈的应用 |

### 适用的 Coriander Player 页面

- **不推荐**用于音乐播放器（会破坏内容沉浸感）
- 可能用于：专辑详情页（强调专辑封面背景色）
- 可选：设置页（如果采用深色主题 + 强调色）

---

## 模式 4：Fade Only — 无标题（仅返回按钮，内容自然延伸至状态栏）

**定位**：最纯粹的沉浸式布局，内容直接延伸到状态栏后方，仅保留导航按钮。

```
┌──────────────────────────────┐
│  [<]                          │  ← GlassAppBar 只有返回按钮
│                               │
│  Browse                        │  ← 大标题在内容区（不随滚动变化）
│  (34px, bold)                 │
│                               │
│  ┌─────────────────────────┐ │
│  │ [■] Item 1              │ │
│  └─────────────────────────┘ │
│  ┌─────────────────────────┐ │
│  │ [■] Item 2              │ │
│  └─────────────────────────┘ │
│                               │
└──────────────────────────────┘
```

### 结构

```dart
GlassScaffold(
  // appBar 只有返回按钮，没有 title
  appBar: GlassAppBar(
    leading: GlassButton(icon: back),
  ),
  body: CustomScrollView(
    slivers: [
      // 顶部留白（为状态栏 + 返回按钮区让位）
      SliverToBoxAdapter(child: SizedBox(height: topPad + 44)),
      // 内容区的大标题（不随滚动变化）
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Text('Browse', style: TextStyle(fontSize: 34, ...)),
        ),
      ),
      _buildDummyContent(),
    ],
  ),
)
```

### 关键特性

| 特性 | 实现方式 |
|------|---------|
| `GlassAppBar.title` | `null` |
| 顶部预留空间 | `topPad + 44`，避免内容与返回按钮重叠 |
| 滚动行为 | 无特殊逻辑（不折叠、不渐显） |
| 视觉效果 | 最大程度展示背景图/玻璃效果 |
| 适用场景 | 详情页、浏览/发现类页面、内容密集但层级简单的页面 |

### 适用的 Coriander Player 页面

- **Artist Detail V3** — 当前实现就是此模式的增强版
- Album 详情页
- 播放详情页（Now Playing）的专辑信息区

---

## 模式 5：Tab Bar + Bottom Fade（底部 Tab 栏 + 顶部/底部双边缘淡出）

**定位**：iOS 设置页、Apple Music Library 等带底部 Tab 的标准布局。

```
┌──────────────────────────────┐
│  [<]          Settings        │  ← GlassAppBar（标题）
├───────────────────────────────┤
│                               │
│  ┌─────────────────────────┐ │
│  │ [■] Item 1              │ │
│  └─────────────────────────┘ │
│  ┌─────────────────────────┐ │
│  │ [■] Item 2              │ │
│  └─────────────────────────┘ │
│                               │
│  (顶部和底部均有边缘淡出)       │
│                               │
├───────────────────────────────┤
│ [🏠] [🔍] [🔔] [👤]           │  ← GlassBottomBar
└──────────────────────────────┘
```

### 结构

```dart
GlassScaffold(
  bottomBar: GlassBottomBar(
    selectedIndex: _selectedTab,
    onTabSelected: (index) => setState(() => _selectedTab = index),
    settings: RecommendedGlassSettings.standard
        .copyWith(thickness: 20, blur: 3),
    tabs: [
      GlassBottomBarTab(icon: Icon(house_fill), label: 'Home'),
      GlassBottomBarTab(icon: Icon(search), label: 'Search'),
      GlassBottomBarTab(icon: Icon(bell_fill), label: 'Alerts'),
      GlassBottomBarTab(icon: Icon(person_fill), label: 'Profile'),
    ],
  ),
  appBar: GlassAppBar(
    title: Text('Settings'),
    leading: GlassButton(back),
  ),
  body: CustomScrollView(...),
)
```

### 关键特性

| 特性 | 实现方式 |
|------|---------|
| `bottomBar` | `GlassBottomBar`，4 Tab |
| 玻璃参数 | `thickness: 20, blur: 3`（比 appBar 更厚重） |
| `topEdgeFade / bottomEdgeFade` | 由 `GlassScrollEdgeEffect` 处理，默认开启 |
| Tab 选中状态 | `selectedIndex` + 选中 icon 变色 |
| 内容底部留白 | `SizedBox(height: 120)`（留给 bottomBar） |

### 适用的 Coriander Player 页面

- **整个 AppShell（Glass 模式下）** — 当前 `glass_app_shell.dart` 采用的就是此模式 + 搜索栏
- 播放列表页、类别页等需要 Tab 切换的一级页面

---

## 模式 6：Fade Header（无 AppBar，固定标题随滚动淡出）

**定位**：Apple Music / Podcasts 首页的最纯粹沉浸式布局。**没有传统 AppBar**，标题是内容的一部分，随滚动从固定位置淡出。

```
未滚动                             滚动 30px 后
┌──────────────────────────────┐  ┌──────────────────────────────┐
│                               │  │                              │
│  Listen Now          [SD]    │  │  (淡出中... [SD]             │
│  (34px, bold)                 │  │                              │
│                               │  ├──────────────────────────────┤
│  ┌─────────────────────────┐ │  │  ┌─────────────────────────┐ │
│  │ [🎵] Featured           │ │  │  │ [🎵] Featured           │ │
│  └─────────────────────────┘ │  │  └─────────────────────────┘ │
│  ┌─────────────────────────┐ │  │  ┌─────────────────────────┐ │
│  │ [🎵] New Releases       │ │  │  │ [🎵] New Releases       │ │
│  └─────────────────────────┘ │  │  └─────────────────────────┘ │
│                               │  │                              │
├───────────────────────────────┤  ├───────────────────────────────┤
│ [🏠] Radio  Library          │  │ [🏠] Radio  Library          │
└──────────────────────────────┘  └──────────────────────────────┘
```

### 结构

```dart
GlassScaffold(
  topEdgeFade: true,    // 顶部边缘内容淡出（关键）
  bottomEdgeFade: true, // 底部边缘淡出

  // header（不是 appBar）— 固定标题，随滚动淡出
  header: Padding(
    padding: EdgeInsets.fromLTRB(20, 8, 16, 0),
    child: Row(
      children: [
        Expanded(
          child: Text('Listen Now', style: TextStyle(
            fontSize: 34, fontWeight: FontWeight.w700,
          )),
        ),
        Container(width: 36, height: 36, ... child: Text('SD')),
      ],
    ),
  ),
  headerScrollController: _scrollController,   // 绑定滚动控制器
  headerFadeDistance: 30,                       // 30px 内完成淡出

  bottomBar: GlassBottomBar(...),
  body: CustomScrollView(
    controller: _scrollController,
    slivers: [
      // 预留 header 空间：topPad（状态栏） + 90（标题区）
      SliverToBoxAdapter(child: SizedBox(height: topPad + 90)),
      _buildDummyContent(),
      const SliverToBoxAdapter(child: SizedBox(height: 120)),
    ],
  ),
)
```

### 关键特性

| 特性 | 实现方式 |
|------|---------|
| `appBar` | **不存在** |
| `header` | `Widget` — 固定在顶部，内容区顶部留白容纳它 |
| `headerScrollController` | 将滚动控制器绑定，实现滚动→淡出联动 |
| `headerFadeDistance: 30` | 滚动 30px 内完成从可见到透明的渐变 |
| `topEdgeFade: true` | 内容靠近状态栏时自然淡出，避免紧贴状态栏 |
| `bottomEdgeFade: true` | 内容靠近底部导航栏时自然淡出 |

### 适用的 Coriander Player 页面

- **艺术家详情页 ArtistDetailPageV3** — 正在使用此模式（背景图 + 玻璃卡片内容）
- **专辑详情页 AlbumDetailPage**
- 播放列表详情页（有封面背景时）
- 搜索页（热门搜索/历史记录）

---

## 6 种模式横向对比

| 模式 | AppBar 标题 | Large Title | 滚动行为 | 底部导航 | 适用页面示例 |
|------|-------------|-------------|---------|---------|-----------|
| 1. Inline Title | ✅ 始终可见 | ❌ | 无 | ❌ | 设置页、二级页面 |
| 2. Large Title→Collapse | ✅ 渐显 | ✅ 渐隐 | 折叠 52px | ❌ | 音乐库、搜索结果 |
| 3. Solid Background | ✅ 始终可见 | ❌ | 无（纯色背景） | ❌ | 品牌色强调页 |
| 4. Fade Only (No Title) | ❌ | ✅ 始终可见 | 无 | ❌ | 详情页（简单） |
| 5. Tab Bar + Bottom Fade | ✅ 始终可见 | ❌ | 无 | ✅ | 设置主页、分类页 |
| 6. Fade Header (No App Bar) | ❌ | ✅ 随滚动淡出 | 30px 渐变 | ✅ | **艺术家/专辑详情** |

### 在 Coriander Player 中的映射建议

| 现有页面 | 推荐模式 | 备注 |
|---------|---------|------|
| 音乐库主页（AudiosPage） | 模式 2 (Large Title → Collapse) | 有排序/筛选按钮，大标题+列表 |
| 艺术家列表（ArtistsPage） | 模式 2 | 同上 |
| 艺术家详情 V3 | 模式 6 (Fade Header) | 当前已实现，完全符合 |
| 专辑详情页 | 模式 6 | 参考艺术家 V3 实现 |
| 歌单页（PlaylistsPage） | 模式 2 或 5 | 取决于是否有 Tab 切换 |
| 设置页 | 模式 1 (Inline Title) | 标准的二级页面布局 |
| 搜索页 | 模式 4 (Fade Only) 或 模式 6 | 取决于搜索框位置 |
| Now Playing 播放页 | 模式 3 + 自定义 | 全屏沉浸 + 控制栏 |

---

## 共享组件：Dummy Content（6 种模式通用）

所有模式使用同一个内容构建函数，强调滚动状态的变化而非内容的变化：

```dart
Widget _buildDummyContent({int count = 25, double topPadding = 0}) {
  return SliverList.separated(
    itemCount: count,
    separatorBuilder: (_, __) => const SizedBox(height: 12),
    itemBuilder: (context, index) => Padding(
      padding: EdgeInsets.only(
        top: index == 0 ? topPadding : 0,
        left: 24, right: 24,
      ),
      child: GlassCard(
        settings: RecommendedGlassSettings.overlay,
        padding: EdgeInsets.all(16),
        child: Row(children: [
          // 彩色方框 + 标题 + 副标题
          Container(width: 44, height: 44, color: Colors.primaries[...]),
          SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Item ${index + 1}', style: TextStyle(fontSize: 16, fontWeight: 600)),
                SizedBox(height: 4),
                Text('Scrollable content...', style: TextStyle(fontSize: 13, color: secondary)),
              ],
            ),
          ),
        ]),
      ),
    ),
  );
}
```

### 设计意图

- **`GlassCard` + `RecommendedGlassSettings.overlay`**：列表项的玻璃效果参数（`thickness: 10, blur: 10, glassColor: rgba(255,255,255,0.12)`）
- **固定结构**：左侧色块 + 标题两行，便于观察滚动时导航栏和玻璃效果的变化
- **Color 取色**：`Colors.primaries[index % Colors.primaries.length]` — 确保每一项有不同的颜色，用于观察玻璃的色彩拾取效果

---

## 关键结论

1. **`GlassAppBar` 不是必须的** — 模式 6 完全不使用 `appBar`，由 `header` + `topEdgeFade` 实现更纯粹的沉浸感
2. **滚动绑定是模式 2/6 的核心** — 需要 `ScrollController` 与 `GlassScaffold` 的 `headerScrollController` 配合
3. **`GlassBottomBar` 是 Shell 级组件**，不是页面级组件，应在 AppShell 中统一配置
4. **`edgeFade` 由 `GlassScrollEdgeEffect` 处理** — 它不是手动的 `BackdropFilter`，而是对滚动内容边缘做渐变淡出
5. **参数一致性**：`RecommendedGlassSettings.standard` 是所有模式的基准，个别调整 `thickness`/`blur` 即可
