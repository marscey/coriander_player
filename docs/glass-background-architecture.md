# 液态玻璃页面背景层与淡化层架构分析

> 生成日期：2026-07-03
> 分析文件：`lib/page/cloud_service/glass_cloud_file_browser.dart`、`lib/glass_theme/glass_presets.dart`、`liquid_glass_widgets` 0.16.1
> 适用范围：所有使用 `buildGlassBackground` + `GlassScrollEdgeEffect` 的 Glass 页面

---

## 1. 图层结构总览

一个 Glass 页面从底到顶共有 5 层：

```
┌─────────────────────────────────────────────┐
│  Layer 5: 悬浮导航栏 (GlassButton/GlassContainer)  │  ← 液态玻璃组件
├─────────────────────────────────────────────┤
│  Layer 4: 淡化遮罩 (GlassScrollEdgeEffect)         │  ← 渐变遮罩
├─────────────────────────────────────────────┤
│  Layer 3: 滚动内容 (CustomScrollView)              │  ← 列表/网格
├─────────────────────────────────────────────┤
│  Layer 2: 背景层 (buildGlassBackground)            │  ← 渐变背景
├─────────────────────────────────────────────┤
│  Layer 1: Scaffold 底色 (transparent)             │  ← 透明
└─────────────────────────────────────────────┘
```

在 `glass_cloud_file_browser.dart` 的 `build` 方法中对应：

```dart
Stack(children: [
  Positioned.fill(child: buildGlassBackground(scheme)),   // Layer 2
  Positioned.fill(child: NotificationListener(            // Layer 3
    child: GlassScrollEdgeEffect(                         // Layer 4
      fadeColor: scheme.secondaryContainer,
      child: CustomScrollView(...),
    ),
  )),
  Positioned(top: 0, child: _buildFloatingPillNavBar()),  // Layer 5
])
```

---

## 2. Layer 2：背景层 (`buildGlassBackground`)

### 源文件
`lib/glass_theme/glass_presets.dart` 第 165–202 行

### 结构
三层 `Stack`：

| 子层 | 组件 | 颜色 | 作用 |
|------|------|------|------|
| 2a | `ColoredBox` | `scheme.secondaryContainer` | 纯色底色（兜底） |
| 2b | `DecoratedBox` + `LinearGradient` | `primary(0.18)` → `secondaryContainer(0.55)` → `surface(0.9)` | 主题色渐变 |
| 2c | `DecoratedBox` + `LinearGradient` | `black(0.22)` → `black(0.06)` | 顶部暗化（提升文字对比度） |

### 颜色来源
`ColorScheme` 由 `ThemeProvider` 生成，有两种路径：

1. **用户手动选色**：`ColorScheme.fromSeed(seedColor: 用户选择的颜色)`
2. **音乐封面动态主题**：`ColorScheme.fromImageProvider(provider: 封面图像)`

播放新歌曲时，`applyThemeFromAudio()` 异步生成新的 `ColorScheme`，调用 `notifyListeners()` 触发 `MaterialApp` 重建，所有 `Theme.of(context).colorScheme` 取值自动更新。

### 关键特性
- **不含液态玻璃组件**：纯 `ColoredBox` + `DecoratedBox`，无 GPU 着色器开销
- **名字带 "Glass" 但实现是普通渐变**：`buildGlassBackground` 仅为 Glass 风格页面提供视觉底色
- **颜色对主题变化敏感**：`secondaryContainer` 和 `primary` 随封面颜色明显变化

---

## 3. Layer 4：淡化遮罩 (`GlassScrollEdgeEffect`)

### 源文件
`liquid_glass_widgets` 包 0.16.1，`lib/widgets/shared/glass_scroll_edge_effect.dart`

### 工作原理

`GlassScrollEdgeEffect` 有两条渲染路径：

#### 路径 A：纹理捕获（在 `GlassPage` / `LiquidGlassScope` 内）
1. `didChangeDependencies()` 获取 `LiquidGlassScope` 的 `GlobalKey`
2. 通过 `boundary.toImage(pixelRatio: 1.0)` 将背景捕获为 `ui.Image`
3. 用 `_TextureFadePainter` 绘制背景纹理的顶部/底部切片
4. 叠加渐变 alpha 遮罩（`BlendMode.dstIn`），实现内容淡入淡出

#### 路径 B：纯色渐变（在 `GlassPage` 外，当前页面走这条）
1. `_backgroundKey == null`（无 `LiquidGlassScope` 祖先）
2. 使用 `fadeColor` 画一个 `LinearGradient` 覆盖层
3. 渐变方向：顶部不透明 → 底部透明
4. 曲线：`_kFadeCurves[soft]`，5 档 alpha `[1.0, 0.70, 0.30, 0.04, 0.0]`

当前云文件浏览页面 **不在 `GlassPage` 内**（`entry.dart` 用的是 `_platformPage` 直接包裹 `GlassCloudFileBrowser`），所以走路径 B。

### 渐变曲线

```
soft 风格（默认）:
alpha:  1.0  →  0.70  →  0.30  →  0.04  →  0.0
stop:   0.0      0.15     0.45     0.75     0.92

│■■■■■■■▓▓▓░░░░░░░░░░░░░░ ░ ░ ░     │
│完全不透明          逐渐透明        完全透明│
│(导航栏区域)                      (内容区域)│
```

### 关键参数

| 参数 | 当前值 | 说明 |
|------|--------|------|
| `topFadeHeight` | `topPad + 60 + 6 + 50` | 覆盖状态栏 + 导航栏 + 缓冲区 |
| `bottomFadeHeight` | `0` | 不使用底部淡化 |
| `fadeColor` | `scheme.secondaryContainer` | 与背景层底色一致 |
| `style` | `soft`（默认） | 柔和渐变 |

---

## 4. 颜色同步机制

### 数据流

```
播放新歌曲
  └─ ThemeProvider.applyThemeFromAudio(audio)
       └─ ColorScheme.fromImageProvider(封面图像)
            └─ lightScheme / darkScheme = 新ColorScheme
                 └─ notifyListeners()
                      └─ MaterialApp 重建
                           └─ Theme.of(context).colorScheme 更新
                                ├─ buildGlassBackground(scheme) → 背景色更新 ✅
                                └─ GlassScrollEdgeEffect(fadeColor: scheme.xxx) → 淡化色更新 ✅
```

### 已修复的色差 Bug

**问题**：`fadeColor` 原来用 `scheme.surface`，而背景底色用 `scheme.secondaryContainer`。Material 3 的 `surface` 是低饱和高亮度色调，在不同封面下变化极小（如 `#FDF8F8` → `#F8F9FD`），而 `secondaryContainer` 变化明显（如 `#F5D5D0` → `#D0DCF5`）。

**结果**：切歌后背景颜色明显变了，但淡化区域颜色几乎没变，造成视觉色差。

**修复**：`fadeColor` 改为 `scheme.secondaryContainer`，与背景底色保持一致。

### 设计原则

> **`fadeColor` 必须与 `buildGlassBackground` 的最底层底色（`ColoredBox` 的颜色）一致。**

因为淡化遮罩的视觉效果是"用底色覆盖内容"，如果遮罩颜色与实际底色不同，覆盖区域会出现色差。

---

## 5. 性能分析

### 各层 GPU 开销

| 层 | 组件 | GPU 开销 | 备注 |
|----|------|----------|------|
| Layer 2 | `buildGlassBackground` | 极低 | 纯 `DecoratedBox` 渐变，无着色器 |
| Layer 3 | `CustomScrollView` | 低 | 列表项为普通 `Container`，无玻璃 |
| Layer 4 | `GlassScrollEdgeEffect` | 低 | 路径 B 仅一个 `LinearGradient` 覆盖层 |
| Layer 5 | 导航栏玻璃组件 | **高** | 3 个 `GlassQuality.premium` 组件 |

### 性能优化历史

| 优化项 | 修改前 | 修改后 | 影响 |
|--------|--------|--------|------|
| 列表项更多按钮 | `GlassButton(premium)` | 普通 `IconButton` | 消除 N 个玻璃渲染层 |
| 导航栏按钮数 | 5 个（返回+搜索+定位+更多+胶囊） | 3 个（返回+更多+胶囊） | 减少 40% GPU 负载 |
| 列表项背景 | `Container` 半透明 | 未改（已是非玻璃） | 无影响 |

### 性能结论

当前页面的性能瓶颈仅在 **Layer 5 导航栏**的 3 个 `GlassQuality.premium` 组件。Layer 2 和 Layer 4 都是普通渐变，不影响性能。

---

## 6. 架构注意事项

### 6.1 `fadeColor` 与背景色的绑定关系

如果未来修改 `buildGlassBackground` 的底层颜色（如从 `secondaryContainer` 改为 `surfaceContainer`），**必须同步修改所有使用 `GlassScrollEdgeEffect` 的页面的 `fadeColor`**。

当前只有 `glass_cloud_file_browser.dart` 显式传了 `fadeColor`。其他 Glass 页面如果在 `GlassPage` 内使用，走纹理路径则不需要 `fadeColor`。

### 6.2 `GlassScrollEdgeEffect` 的重建机制

- `didChangeDependencies()` 只在 **首次挂载** 或 **InheritedWidget 变化** 时调用
- 主题变化时，`ThemeProvider.notifyListeners()` → `MaterialApp` 重建 → 子页面 `build()` 重新执行
- `GlassScrollEdgeEffect` 是 `StatefulWidget`，其 `build()` 方法会重新执行，`fadeColor` 会取到新的 `scheme.secondaryContainer`
- 纹理路径（路径 A）的背景图像不会自动重新捕获，除非 `didChangeDependencies` 被触发（`LiquidGlassScope` 的 key 是 `final` 不变的，所以 `InheritedWidget` 不会 notify）

### 6.3 页面是否在 `GlassPage` 内

| 页面 | 是否在 GlassPage 内 | 渲染路径 | 需要 fadeColor |
|------|---------------------|----------|----------------|
| 云文件浏览 | 否 | 路径 B（纯色渐变） | 是 |
| Artist V3 | 是 | 路径 A（纹理捕获） | 否 |
| 其他 Glass 页面 | 视情况而定 | — | — |

判断方法：检查 widget 树中是否有 `LiquidGlassScope` 祖先。如果有，`GlassScrollEdgeEffect` 走纹理路径，`fadeColor` 被忽略；如果没有，走纯色路径，`fadeColor` 必须与背景底色一致。

---

## 7. 总结

```
背景层 (buildGlassBackground)          淡化层 (GlassScrollEdgeEffect)
    │                                        │
    │  底色: scheme.secondaryContainer       │  fadeColor: scheme.secondaryContainer
    │  渐变: primary → secondaryContainer    │  渐变: 不透明 → 透明
    │         → surface                      │
    │                                        │
    └────────── 颜色必须一致 ──────────────────┘
                    │
              ThemeProvider
                    │
         ColorScheme.fromImageProvider
              (音乐封面)
```

**核心原则**：背景层和淡化层是两个独立图层，但颜色必须绑定到同一个 `ColorScheme` 属性，确保主题切换时两者同步变化。
