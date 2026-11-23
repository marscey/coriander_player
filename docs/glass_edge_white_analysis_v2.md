# 状态栏发白问题深度分析报告（v2）

## 一、三张截图的关键发现

| 截图 | 页面 | 状态栏区域 | 底部区域 |
|------|------|-----------|---------|
| 图1 | 艺术家列表（Tab 页） | 顶部发白 | 底部轻微发白 |
| 图2 | 艺术家详情 V3（未播放） | **顶部大面积发白** | **底部严重发白** |
| 图3 | 艺术家详情 V3（播放中） | 正常，无白色 | 正常，无白色 |

**核心线索：同一页面（Artist V3），播放音频前后表现完全不同。**

---

## 二、根因定位：双层 GlassScaffold + 双层 edgeFade 叠加

### 2.1 架构层次

```
┌─ GlassAppShell（glass_app_shell.dart）──────────────┐
│  GlassScaffold(                                       │
│    topEdgeFade: true,      ← 第 1 层边缘淡化          │
│    bottomEdgeFade: true,   ← 第 1 层边缘淡化          │
│    body: Tab 页面内容                                  │
│  )                                                     │
│  ┌─ Tab 页面（如 Artist V3）──────────────────────┐  │
│  │  GlassScaffold(                                   │  │
│  │    topEdgeFade: true,    ← 第 2 层边缘淡化 ⚠️    │  │
│  │    bottomEdgeFade: true, ← 第 2 层边缘淡化 ⚠️    │  │
│  │  )                                                │  │
│  └──────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────┘
```

### 2.2 三处 edgeFade 设置位置

| 文件 | 行号 | 参数 | 层级 |
|------|------|------|------|
| [glass_app_shell.dart](../lib/component/glass_app_shell.dart#L150-L151) | 150-151 | `topEdgeFade: true, bottomEdgeFade: true` | **外层（Shell）** |
| [glass_page_scaffold.dart](../lib/page/glass_page_scaffold.dart) | 已移除 | 无（v1 修复已删除） | 内层（页面） |
| [artist_detail_page_v3.dart](../lib/page/artist_detail_page_v3.dart#L329-L330) | 329-330 | `topEdgeFade: true, bottomEdgeFade: true` | **内层（详情页）** |

### 2.3 各截图的 edgeFade 叠加情况

| 截图 | 外层(Shell) | 内层(页面) | 结果 |
|------|------------|------------|------|
| 图1 艺术家列表 | ✅ top+bottom | ❌ 无（已移除） | 单层淡化 = 轻微发白 |
| 图2 Artist V3 未播放 | ✅ top+bottom | ✅ top+bottom | **双重叠加 = 严重发白** |
| 图3 Artist V3 播放中 | ✅ top+bottom | ✅ top+bottom | 视觉上正常（原因见下文） |

---

## 三、为什么播放音频后白色消失？

这是最关键的发现。可能的原因分析：

### 假设 A：Mini Player 改变了底部布局结构

当音频播放时，`GlassSearchableBottomBar` 从"普通模式"切换到"迷你模式"，显示正在播放的歌曲信息 Pill。

- 迷你模式下的 Pill 使用 `playBarPillSettings` 玻璃参数（`glassColor: Color(0xCCF2F2F7)` 高不透明度）
- 这个高不透明度的玻璃 Pill 可能**覆盖了底部的 edgeFade 白色条带**
- 同时触发了 Shell 级别的 `setState()` → 重新布局 → edgeFade 渲染区域变化

### 假设 B：系统状态栏样式自动切换

`GlassStatusBarStyle.auto` 会根据内容亮度自动选择状态栏文字颜色：
- 未播放时：背景较浅 → 状态栏使用深色文字 → edgeFade 白色条带可见
- 播放时：背景变深（可能是某个 listener 触发的重建改变了 Theme 或 ColorScheme）→ 状态栏切换为浅色文字 → edgeFade 效果被深色背景掩盖

### 假设 C（最可能）：播放触发全量重建，背景图正确加载

Artist V3 的 `_buildBackground()` 包含条件性背景图：

```dart
if (_resolvedBackgroundPic != null) ...[
  Image(...),           // 背景图
  BackdropFilter(       // 140px 强模糊
    filter: ImageFilter.blur(sigmaX: 140, sigmaY: 140),
  ),
]
```

如果 `_resolvedBackgroundPic` 是异步加载的，可能在首次进入页面时还未就绪（图2 显示纯色渐变 + edgeFade 白色）。播放音频时触发了 `setState()` → 重建 → 此时背景图已加载完成（图3 显示完整背景图 + 模糊，掩盖了 edgeFade）。

---

## 四、与 Demo 导航栏模式的关联分析

参考 [nav_bar_patterns_6_modes_analysis.md](./nav_bar_patterns_6_modes_analysis.md)：

| 模式 | topEdgeFade | bottomEdgeFade | 适用场景 |
|------|-------------|---------------|---------|
| 模式 2 (Large Title) | 未明确设置 | 未明确设置 | 音乐库主页 |
| 模式 6 (Fade Header) | **true** | **true** | 艺术家详情 |
| Demo 全局基础 | 未启用 | 未启用 | 所有 Demo 共享 |

**关键差异**：Demo 的 6 种模式中，**只有模式 6 启用了 edgeFade**，且模式 6 是专门为有背景图的详情页设计的。Demo 中模式 6 的 `ShowcaseBackground()` 提供了一个**高饱和度彩色渐变底图**，足以掩盖 edgeFade 的白色淡出。

我们的问题是：
1. **Tab 页面（Shell 级）不应该使用 edgeFade** — 它们是列表页，不是沉浸式详情页
2. **Artist V3 有 edgeFade 但没有始终有效的背景图** — 当背景图未加载或不存在时，edgeFade 就暴露为白色
3. **双层叠加放大了问题**

---

## 五、解决方案

### 方案：彻底移除所有 edgeFade，按需手动实现

#### 修复点 1：glass_app_shell.dart（外层 Shell）

```dart
// 修改前 L150-151
topEdgeFade: true,
bottomEdgeFade: true,

// 修改后：删除这两个参数（Shell 级不需要边缘淡化）
```

**理由**：Shell 是容器层，负责底部导航栏和页面切换。它的 body 区域由各子页面自己管理边缘效果。Shell 层做 edgeFade 会与所有子页面冲突。

#### 修复点 2：artist_detail_page_v3.dart（Artist V3 详情页）

```dart
// 修改前 L329-330
topEdgeFade: true,
bottomEdgeFade: true,

// 修改后：删除这两个参数
```

**理由**：虽然模式 6 推荐使用 edgeFade，但前提是有可靠的背景图覆盖。当前 Artist V3 的背景图是异步条件加载的，在未加载完成时会产生白色条带。如需边缘淡化效果，应在 `_buildBackground()` 的 Stack 最上层手动添加一个可控方向的暗色渐变遮罩（而非依赖 GlassScaffold 的默认白色淡出）。

#### 修复点 3：glass_page_scaffold.dart（已在 v1 修复中移除）

确认保持无 edgeFade 参数。

### 后续优化建议

如果需要边缘淡化视觉效果，推荐在 `_buildBackground()` 中手动添加：

```dart
Widget _buildBackground(ColorScheme scheme) {
  return Stack(
    fit: StackFit.expand,
    children: [
      // ... 现有背景层 ...

      // 手动顶部暗色淡化（替代 topEdgeFade，方向可控）
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment(0.0, 0.15),  // 仅影响顶部 15%
              colors: [
                Colors.black.withValues(alpha: 0.15),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),

      // 手动底部暗色淡化（替代 bottomEdgeFade）
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0.0, 0.85),
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.12),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
```

这种方式：
- 颜色方向可控（用暗色而非白色）
- 强度可调
- 不受 GlassScaffold 内部实现变化的影响
- 与背景图自然融合
