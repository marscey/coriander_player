# 移动端 UI/UX 统一方案 — 设计规范

> 版本: 1.0 | 日期: 2026-06-20
> 适用范围: 仅移动端（iOS / Android），不影响桌面端

---

## 一、现状问题分析

### 1.1 Tab 页面 UI 不一致

| 页面 | 当前布局 | 问题 |
|------|---------|------|
| **歌单** (PlaylistsPage) | `UniPage<Playlist>` — 支持列表/表格视图切换、排序、多选 | 布局完整，但 Glass 模式下菜单项独立定义 |
| **类别** (CategoriesPage) | 自定义 `_CategoryTile` 卡片列表 — 无排序/视图切换 | 布局风格与其他两个 Tab 页面完全不同，缺少交互能力 |
| **连接** (CloudConnectionsPage) | `Card + ListTile + PopupMenuButton` — 无排序/视图切换 | 使用 Material Card 而非统一 Tile，Glass 模式下空状态处理不一致 |

**核心差异**：
- 歌单页使用 `UniPage` 通用框架（含排序、视图切换、多选），类别页和连接页是独立实现
- 类别页的 `_CategoryTile` 样式（56px 图标容器 + 标题/副标题 + 箭头）与歌单页的 `ListTile` 风格不同
- 连接页使用 `Card` 包裹，视觉层级高于其他两个页面
- Glass 模式下三个页面的 `GlassPageHeader` + `CustomScrollView` 结构已统一，但内容区域的 Tile 组件不统一

### 1.2 二级页面导航转场问题

| 路由 | 当前转场 | 期望转场 |
|------|---------|---------|
| `SlideTransitionPage` (Tab 一级页面) | **纵向微滑** `(0, 0.10)→(0, 0)` | 无需转场（Tab 页面应即时切换） |
| 类别→艺术家/专辑/流派 | `SlideTransitionPage` 纵向微滑 | **横向右滑入** `(1, 0)→(0, 0)` |
| 艺术家→艺术家详情 | `builder`（默认平台转场） | **横向右滑入** |
| 专辑→专辑详情 | `builder`（默认平台转场） | **横向右滑入** |
| 歌单→歌单详情 | `builder`（默认平台转场） | **横向右滑入** |
| 连接→文件浏览器 | `builder`（默认平台转场） | **横向右滑入** |
| NowPlaying 全屏 | **底部滑入** `(0, 1)→(0, 0)` | 保持底部滑入（模态覆盖，非层级导航） |
| AlbumDetailPageNew (顶级) | **底部滑入** `(0, 1)→(0, 0)` | **横向右滑入**（这是层级导航，不是模态） |

**关键问题**：
1. `SlideTransitionPage` 使用纵向偏移 `(0, 0.10)`，看起来像"从下微弹"，不是标准的 iOS 横向推入
2. 多个二级路由使用 `builder` 而非 `pageBuilder`，无法控制转场动画
3. `AlbumDetailPageNew` 作为顶级路由使用底部滑入，与层级导航语义不符
4. iOS 原生 `UINavigationController` 的标准行为是横向推入 + 左滑手势返回，当前实现缺失

### 1.3 手势返回问题

- GoRouter 的 `StatefulShellRoute` 在 iOS 上**默认支持** `CupertinoPageRoute` 的左滑返回手势
- 但当前路由大量使用 `CustomTransitionPage`，**未启用** `CupertinoPage` 的手势返回
- 部分路由使用 `builder`，由平台决定转场，Android 上可能没有手势返回

---

## 二、设计目标

### 2.1 核心原则

1. **iOS 26 Liquid Glass 规范**：玻璃仅用于导航与控制层，内容区域保持不透明
2. **平台一致性**：移动端遵循 iOS Human Interface Guidelines 的导航模式
3. **双模式兼容**：普通模式（PageScaffold）和 Glass 模式（GlassPageScaffold）同步改造
4. **最小侵入**：改动仅影响移动端，桌面端逻辑不受影响

### 2.2 交互规范

| 交互 | 规范 | 参考 |
|------|------|------|
| Tab 切换 | 即时切换，无转场动画 | iOS UITabBar |
| 二级页面进入 | 从右侧横向滑入 | iOS UINavigationController.push |
| 二级页面退出（手势） | 左侧边缘右滑返回 | iOS 交互式返回手势 |
| 二级页面退出（按钮） | 点击返回按钮触发与手势一致的动画 | iOS back button |
| 模态覆盖（NowPlaying） | 从底部滑入 | iOS modal presentation |
| 菜单/弹出层 | 液态变形弹出 | iOS 26 Liquid Glass |

---

## 三、Tab 页面 UI 统一方案

### 3.1 统一布局结构

三个 Tab 页面统一采用以下结构：

```
┌──────────────────────────────┐
│  GlassAppBar (glass)         │  ← 导航层：设置按钮(根) / 返回按钮(详情)
│  ┌──────────────────────────┐│
│  │  ⚙️  标题(渐显)    ⋯   ││  ← leading + title + menu
│  └──────────────────────────┘│
├──────────────────────────────┤
│                              │
│  GlassPageHeader             │  ← 大标题 + 副标题（滚动时渐隐）
│  ┌──────────────────────┐    │
│  │ 标题 (28pt Bold)     │    │
│  │ 副标题 (14pt)        │    │
│  └──────────────────────┘    │
│                              │
│  Content Tiles               │  ← 不透明内容区域
│  ┌──────────────────────┐    │
│  │  [Icon]  标题        >│    │  ← 统一 Tile 样式
│  ├──────────────────────┤    │
│  │  [Icon]  标题        >│    │
│  └──────────────────────┘    │
│                              │
├──────────────────────────────┤
│  GlassBottomBar (glass)      │  ← 导航层
│  PlayBarPill (glass)         │  ← 浮动播放条
└──────────────────────────────┘
```

### 3.2 统一 Tile 组件 — `GlassListTile`

新建统一列表项组件，替代当前三种不同风格的 Tile：

**普通模式**：
```
┌─────────────────────────────────────┐
│  [48x48 圆角图标]  标题 (16pt w500)  >│
│                    副标题 (13pt)      │
└─────────────────────────────────────┘
高度: 64px, 水平内边距: 16px
```

**Glass 模式**：
```
┌─────────────────────────────────────┐
│  [48x48 圆角图标]  标题 (16pt w500)  >│
│                    副标题 (13pt)      │
└─────────────────────────────────────┘
高度: 64px, 水平内边距: 12px
图标容器: primaryContainer 背景, 12px 圆角
右侧: chevron_right 图标
```

**组件接口**：
```dart
class UnifiedListTile extends StatelessWidget {
  const UnifiedListTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isPlaying = false,
  });
}
```

### 3.3 各页面具体改造

#### 歌单页 (PlaylistsPage)
- **无需大改**：已使用 `UniPage<Playlist>`，结构合理
- **微调**：`ListTile` 的 `leading` 图标尺寸统一为 48x48，与类别页一致
- **Glass 模式**：`glassMenuItems` 已实现，保持不变

#### 类别页 (CategoriesPage)
- **改造重点**：将自定义 `_CategoryTile` 改为使用 `UniPage<CategoryItem>` 或统一 Tile
- **新增能力**：支持排序（按名称/数量）、视图切换（列表/网格）
- **具体方案**：
  - 将三个分类项封装为 `List<CategoryItem>` 数据
  - 使用 `UniPage<CategoryItem>` 替代当前独立布局
  - 或保持当前简洁布局，但将 `_CategoryTile` 改为 `UnifiedListTile` 样式
  - 图标容器从 56px 缩小到 48px，与其他页面统一

#### 连接页 (CloudConnectionsPage)
- **改造重点**：将 `Card + ListTile` 改为 `UnifiedListTile` 样式
- **移除**：`PopupMenuButton`，操作项移至 `GlassMenu` 或长按菜单
- **空状态**：统一使用 `UniPage` 的 `emptyStateBuilder`
- **具体方案**：
  - 使用 `UniPage<CloudConnection>` 替代当前独立布局
  - 或保持当前布局，但将 `Card` 替换为 `UnifiedListTile`
  - `PopupMenuButton` 的操作项移至 `glassMenuItems`（编辑/测试/删除）

### 3.4 视觉参数统一

| 参数 | 值 | 说明 |
|------|---|------|
| Tile 高度 | 64px | 与 `UniPage` 的 `itemExtent: 64` 一致 |
| 图标容器尺寸 | 48x48px | 统一（当前类别页 56px） |
| 图标容器圆角 | 12px | 统一 |
| 图标容器背景 | `primaryContainer` | 统一 |
| 图标颜色 | `onPrimaryContainer` | 统一 |
| 图标大小 | 28px | 统一 |
| 标题字号 | 16pt w500 | 统一 |
| 副标题字号 | 13pt | 统一 |
| 右侧箭头 | `chevron_right` | 统一 |
| 列表间距 | 8px (Glass) / 0px (普通) | 统一 |
| 底部留白 | 140px (Glass) / 96px (普通) | 为 PlayBarPill 留空间 |

---

## 四、二级页面导航转场统一方案

### 4.1 转场动画分类

| 类型 | 动画方向 | 适用场景 | 实现方式 |
|------|---------|---------|---------|
| **推入 (Push)** | 右→左 | 所有层级导航（二级页面进入） | `CupertinoPage` 或自定义横向滑入 |
| **弹出 (Pop)** | 左→右 | 所有层级导航（二级页面退出） | 系统自动反向 |
| **模态 (Modal)** | 下→上 | NowPlaying 全屏播放页 | 保持现有底部滑入 |
| **无动画** | 无 | Tab 一级页面切换 | `NoTransitionPage` |

### 4.2 新增转场组件

#### 4.2.1 `MobilePushPage` — 移动端标准推入转场

```dart
/// 移动端标准推入转场 — 从右侧滑入
///
/// 仅在移动端生效，桌面端使用默认转场
class MobilePushPage<T> extends CustomTransitionPage<T> {
  MobilePushPage({
    required super.child,
    super.name,
    super.arguments,
    super.restorationId,
    super.key,
  }) : super(
          transitionsBuilder: _transitionsBuilder,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          barrierDismissible: false,
        );

  static Widget _transitionsBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // iOS 风格：新页面从右侧滑入
    final slideIn = Tween(
      begin: const Offset(1.0, 0.0),  // 从右侧开始
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.linearToEaseOut,  // iOS 标准曲线
    ));

    // 旧页面轻微左移 + 暗化（iOS 风格）
    final slideOut = Tween(
      begin: Offset.zero,
      end: const Offset(-0.3, 0.0),  // 左移 30%
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.linearToEaseOut,
    ));

    final fadeOut = Tween(
      begin: 1.0,
      end: 0.6,  // 暗化到 60%
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.linearToEaseOut,
    ));

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: fadeOut,
        child: SlideTransition(
          position: slideIn,
          child: child,
        ),
      ),
    );
  }
}
```

#### 4.2.2 `MobileModalPage` — 移动端模态转场（底部滑入）

```dart
/// 移动端模态转场 — 从底部滑入
///
/// 仅用于 NowPlaying 等模态覆盖场景
class MobileModalPage<T> extends CustomTransitionPage<T> {
  MobileModalPage({
    required super.child,
    super.name,
    super.arguments,
    super.restorationId,
    super.key,
  }) : super(
          transitionsBuilder: _transitionsBuilder,
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 350),
        );

  static Widget _transitionsBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slideIn = Tween(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.fastOutSlowIn,
    ));

    return SlideTransition(
      position: slideIn,
      child: child,
    );
  }
}
```

### 4.3 路由配置改造

#### entry.dart 路由改造对照表

| 路由 | 改造前 | 改造后 |
|------|-------|-------|
| Tab 一级页面 (audios, playlists, categories, cloud, search, settings) | `SlideTransitionPage` | `NoTransitionPage`（Tab 切换无动画） |
| 类别→艺术家 | `SlideTransitionPage` | `MobilePushPage` |
| 类别→专辑 | `SlideTransitionPage` | `MobilePushPage` |
| 类别→流派 | `SlideTransitionPage` | `MobilePushPage` |
| 艺术家→详情 | `builder` | `MobilePushPage` |
| 专辑→详情 (嵌套) | `builder` | `MobilePushPage` |
| 专辑→详情 (顶级) | `CustomTransitionPage` 底部滑入 | `MobilePushPage` |
| 歌单→详情 | `builder` | `MobilePushPage` |
| 连接→浏览器 | `builder` | `MobilePushPage` |
| 流派→详情 | `builder` | `MobilePushPage` |
| NowPlaying | `CustomTransitionPage` 底部滑入 | `MobileModalPage`（保持底部滑入） |
| 音频详情 | `builder` | `MobilePushPage` |
| 文件夹详情 | `builder` | `MobilePushPage` |
| 搜索结果 | `builder` | `MobilePushPage` |

### 4.4 手势返回支持

GoRouter 在 iOS 上使用 `CupertinoPageRoute` 时自动支持左滑返回手势。关键配置：

1. **使用 `CupertinoPage` 替代 `CustomTransitionPage`**（推荐方案）：
   - `CupertinoPage` 自动提供 iOS 原生右滑入 + 左滑返回手势
   - 无需自定义转场，系统自动处理

2. **或使用 `CustomTransitionPage` + 手动启用手势**：
   - 需要设置 `canTransitionTo` 和 `canTransitionFrom`
   - 更复杂但转场可控

**推荐方案**：在移动端使用 `CupertinoPage`，桌面端保持 `MaterialPageRoute` 行为。

```dart
Page<dynamic> _buildPage({
  required Widget child,
  bool isModal = false,
}) {
  if (PlatformHelper.isMobile && !isModal) {
    // 移动端：CupertinoPage 自动提供右滑入 + 左滑返回
    return CupertinoPage(child: child);
  }
  if (isModal) {
    return MobileModalPage(child: child);
  }
  // 桌面端：默认无动画或简单淡入
  return MaterialPage(child: child);
}
```

### 4.5 类别页面特殊修正

**当前问题**：
- 类别→艺术家/专辑/流派 使用 `SlideTransitionPage`（纵向微滑 `(0, 0.10)→(0, 0)`）
- 看起来像"从下往上弹入"，不符合层级导航语义
- 左侧滑动手势无法返回（因为不是 `CupertinoPageRoute`）

**修正方案**：
1. 将 `SlideTransitionPage` 替换为 `CupertinoPage`
2. iOS 自动获得右滑入 + 左滑返回
3. Android 使用 `MaterialPage` 的默认转场（也是右滑入）

---

## 五、实施计划

### Phase 1: 导航转场统一（优先级最高）

**修改文件**: `lib/entry.dart`

1. 新增 `MobilePushPage` 和 `MobileModalPage` 转场组件
2. 将所有二级路由从 `builder` 改为 `pageBuilder`，使用 `CupertinoPage`（移动端）
3. Tab 一级页面改为 `NoTransitionPage` 或移除 `SlideTransitionPage`
4. NowPlaying 保持底部滑入（`MobileModalPage`）
5. 删除旧的 `SlideTransitionPage` 类

**验证标准**：
- [ ] 所有二级页面从右侧滑入
- [ ] iOS 左滑手势可正常返回
- [ ] 返回按钮触发一致的动画
- [ ] NowPlaying 仍从底部滑入
- [ ] Tab 切换无动画
- [ ] 桌面端不受影响

### Phase 2: Tab 页面 UI 统一

**修改文件**:
- `lib/component/unified_list_tile.dart`（新建）
- `lib/page/categories_page.dart`
- `lib/page/cloud_service/cloud_connections_page.dart`
- `lib/page/playlists_page.dart`（微调）

1. 创建 `UnifiedListTile` 统一组件
2. 改造 CategoriesPage：使用统一 Tile 样式
3. 改造 CloudConnectionsPage：Card → UnifiedListTile
4. 统一图标容器尺寸（48x48）和间距

**验证标准**：
- [ ] 三个 Tab 页面 Tile 样式一致
- [ ] Glass 模式和普通模式均统一
- [ ] 桌面端不受影响

### Phase 3: 细节优化

1. 二级页面导航栏返回按钮样式统一
2. 过渡动画参数微调（时长、曲线）
3. Glass 模式下页面切换时的玻璃效果衔接

---

## 六、技术细节

### 6.1 CupertinoPage vs CustomTransitionPage

| 特性 | CupertinoPage | CustomTransitionPage |
|------|--------------|-------------------|
| iOS 左滑返回 | 自动支持 | 需手动实现 |
| 转场动画 | iOS 原生右滑入 | 自定义 |
| Android 行为 | 右滑入（Material 风格） | 自定义 |
| 交互式转场 | 自动 | 需手动 |
| 推荐度 | 移动端首选 | 特殊转场场景 |

### 6.2 GoRouter + StatefulShellRoute 手势返回

GoRouter 的 `StatefulShellRoute.indexedStack` 在 iOS 上**支持**交互式返回手势，前提是：
1. 使用 `CupertinoPage` 或 `CupertinoPageRoute`
2. 不在 `StatefulShellBranch` 的根路由上使用 `builder`（应使用 `pageBuilder`）

### 6.3 平台判断

所有改动通过 `PlatformHelper.isMobile` 守卫，确保桌面端不受影响：

```dart
if (PlatformHelper.isMobile) {
  return CupertinoPage(child: child);
}
return MaterialPage(child: child);
```

---

## 七、视觉参考

### 7.1 iOS 26 标准导航转场

```
进入二级页面:
┌──────┐     ┌──────┐
│ 页面A │ ──→ │ 页面B │
│      │     │从右侧 │
│ ←30% │     │滑入   │
│ 暗60%│     │      │
└──────┘     └──────┘

退出二级页面（手势/按钮）:
┌──────┐     ┌──────┐
│ 页面A │ ←── │ 页面B │
│恢复亮 │     │向右侧 │
│恢复位 │     │滑出   │
└──────┘     └──────┘
```

### 7.2 Tab 页面统一 Tile 布局

```
普通模式:
╔══════════════════════════════════╗
║  ┌──────┐  标题              ▸  ║
║  │ 图标 │  副标题               ║
║  └──────┘                       ║
╚══════════════════════════════════╝

Glass 模式:
╭──────────────────────────────────╮
│  ┌──────┐  标题              ▸  │
│  │ 图标 │  副标题               │
│  └──────┘                       │
╰──────────────────────────────────╯
  ↑ 无边框，透明背景
```

---

*文档结束*
