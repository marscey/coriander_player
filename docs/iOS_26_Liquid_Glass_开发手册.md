# iOS 26 Liquid Glass 设计语言开发手册

> 基于 `liquid_glass_widgets` Flutter 组件库 v0.16.x 源码逆向整理

---

## 一、设计哲学：Glass vs Content

iOS 26 的核心设计原则是 **玻璃仅用于导航与控制层**，内容区域保持不透明。

| 玻璃适用 | 保持不透明 |
|---|---|
| 导航栏、Tab 栏、工具栏 | 列表单元格、表格行 |
| 浮动操作按钮 | 全屏背景 |
| Sheet、Popover、菜单 | 可滚动内容卡片 |
| 开关、滑块、分段控件 | 文章卡片、媒体播放器 |

典型页面结构：

```
┌──────────────────────────┐
│   GlassAppBar (glass)    │  ← 导航层
├──────────────────────────┤
│                          │
│   不透明内容区域          │  ← 标准 Flutter 组件
│   (ListView, Cards...)   │
│                          │
├──────────────────────────┤
│  GlassBottomBar (glass)  │  ← 导航层
└──────────────────────────┘
```

---

## 二、快速开始

### 2.1 初始化

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize(); // 预热 shader，消除首帧白闪
  runApp(LiquidGlassWidgets.wrap(child: const MyApp()));
}
```

### 2.2 推荐配置

```dart
runApp(LiquidGlassWidgets.wrap(
  child: const MyApp(),
  adaptiveQuality: true,          // 自动基准测试设备，实时调整质量
  theme: GlassThemeData.simple(   // 全局玻璃默认值
    blur: 10,
    thickness: 30,
    quality: GlassQuality.standard,
  ),
));
```

### 2.3 页面模板

```dart
GlassScaffold(
  background: Image.asset('assets/wallpaper.jpg', fit: BoxFit.cover),
  statusBarStyle: GlassStatusBarStyle.auto,
  appBar: GlassAppBar(title: const Text('My App')),
  bottomBar: GlassBottomBar(
    selectedIndex: 0,
    onTabSelected: (_) {},
    tabs: const [
      GlassBottomBarTab(icon: Icon(CupertinoIcons.music_albums), label: '音乐库'),
      GlassBottomBarTab(icon: Icon(CupertinoIcons.music_note_list), label: '歌单'),
    ],
  ),
  body: CustomScrollView(slivers: [...]),
)
```

---

## 三、渲染管线与质量层级

### 3.1 三级质量体系

| 质量 | 渲染技术 | 性能 | 适用场景 |
|---|---|---|---|
| **Minimal** | `BackdropFilter` + Rec.709 饱和度矩阵 + Canvas 描边镜面边缘 | 极低 | 旧设备回退、GPU 预算紧张时的列表卡片 |
| **Standard** | 轻量 Fragment Shader | 低 | 95% 场景，可滚动内容 |
| **Premium** | Impeller 双通道管线（模糊 + 折射 Shader） | 中高 | 静态 Hero 区域、导航栏、底部栏 |

### 3.2 渲染管线数据流

```
GlassPage
  → LiquidGlassScope（背景采样作用域）
    → AdaptiveLiquidGlassLayer（提供 LiquidGlassLayer）
      → AdaptiveGlass（每个玻璃表面）
        → 质量判断:
          Premium + Impeller → 完整双通道 Shader
          Premium + Skia/Web → Lightweight Shader
          Standard → Lightweight Shader
          Minimal → _FrostedFallback（BackdropFilter）
```

### 3.3 平台支持

| 平台 | 渲染器 | 能力 |
|---|---|---|
| iOS | Impeller (Metal) | 完整 Shader 管线 + 色差 |
| Android | Impeller (Vulkan) | 完整 Shader 管线 + 色差 |
| macOS | Impeller (Metal) | 完整 Shader 管线 + 色差 |
| Web | CanvasKit | 轻量 Fragment Shader |
| Windows/Linux | Skia | 轻量 Fragment Shader |

### 3.4 质量优先级链（5 级，高优先）

1. **组件显式参数** — `GlassCard(quality: ...)`
2. **祖先 Inherited** — `AdaptiveLiquidGlassLayer(quality: ...)`
3. **自适应上限** — `GlassAdaptiveScope` 基准测试结果
4. **主题数据** — `GlassThemeData.qualityFor(context)`
5. **组件默认值** — 各组件自己的默认质量

---

## 四、LiquidGlassSettings — 玻璃材质配方

### 4.1 核心参数

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `blur` | double | 5 | 模糊强度（霜化程度） |
| `thickness` | double | 20 | 玻璃厚度（影响边缘折射强度） |
| `refractiveIndex` | double | 1.2 | 折射率（Standard: 边缘厚度 0.7=细边, 1.5=粗边; Premium: 实际折射） |
| `chromaticAberration` | double | 0.01 | 色差（彩虹边缘） |
| `saturation` | double | 1.5 | 背景饱和度调整（1.0=不变） |
| `lightIntensity` | double | 0.5 | 镜面高光强度 |
| `lightAngle` | double | 0.75π | 光源角度（135° = 左上方，iOS 26 标准） |
| `ambientStrength` | double | 0 | 环境光强度 |
| `glassColor` | Color | 透明 | 玻璃着色（透明度控制着色强度） |
| `glowIntensity` | double | 0.75 | Fresnel 边缘辉光强度 |
| `specularSharpness` | enum | medium | 镜面锐度（soft/medium/sharp） |
| `shadowElevation` | double | 1.0 | 亮色模式阴影缩放（0=无, 1=默认, 2=双倍） |
| `whitenStrength` | double | 0.0 | 亮色模式增白层（0-1） |
| `whitenGated` | bool | true | 增白是否亮度门控（true=仅影响亮像素） |

### 4.2 推荐预设配方

| 场景 | blur | thickness | glassColor | refractiveIndex | saturation | ambientStrength |
|---|---|---|---|---|---|---|
| **standard** (滚动内容) | 4 | 10 | 白8% | 1.2 | 1.2 | 0 |
| **interactive** (按钮) | 10 | 10 | 白20% | 0.7 | 0.0* | 0.3 |
| **surface** (静态表面) | 10 | 10 | 白20% | 1.15 | 1.2 | 0.3 |
| **bottomBar** (底部栏) | 20 | 20 | 白15% | 1.2 | 1.2 | 0.5 |
| **overlay** (覆盖层) | 10 | 10 | 白12% | 0.7 | 1.2 | 0.4 |
| **sheet** (底部面板) | 10 | 10 | 白12% | 0.15 | 1.2 | 0.4 |
| **input** (输入框) | 20 | 10 | 白12% | 0.7 | 1.2 | 0.4 |

> *interactive 预设 saturation=0.0：静止时无发光，按下时自动动画至 1.0

### 4.3 iOS 26 关键常数

- **lightAngle = 0.75 * π (135°)** — 所有玻璃表面统一左上方光源
- **sheet 预设 refractiveIndex=0.15** — 近乎不可见的边缘，避免大型面板硬边伪影
- **GlassShadow.elevation** — 6% 黑, 8px 模糊, 2px Y 偏移（仅亮色模式）
- **GlassShadow.contact** — 2% 黑, 2px 模糊, 1px Y 偏移

### 4.4 Figma 参数映射

```dart
LiquidGlassSettings.figma(
  refraction: 50,    // 0-100% → refractiveIndex via 1 + (v/100) × 0.2
  depth: 20,         // 逻辑像素 → thickness
  dispersion: 10,    // 0-100% → chromaticAberration via 4 × (v/100)
  frost: 5,          // 逻辑像素 → blur
)
```

---

## 五、主题系统

### 5.1 三级覆盖层级（高优先胜出）

1. **组件 `settings` 参数** — 显式组件级覆盖
2. **`GlassPage(themeOverride: ...)`** — 单页面覆盖
3. **`GlassTheme` / `wrap(theme:...)`** — 全局默认值

### 5.2 亮暗模式主题

```dart
GlassThemeData(
  light: GlassThemeVariant(
    settings: GlassThemeSettings(
      thickness: 12.0,
      blur: 5.0,
      glassColor: Color.fromRGBO(210, 220, 240, 0.12), // 12% 冷蓝白
      lightIntensity: 0.85,
      ambientStrength: 0.15,
      chromaticAberration: 0.02,
    ),
  ),
  dark: GlassThemeVariant(
    settings: GlassThemeSettings(
      thickness: 10.0,
      blur: 4.0,
      glassColor: Color.fromRGBO(255, 255, 255, 0.08), // 8% 白
      lightIntensity: 0.7,
      ambientStrength: 0.0,
      chromaticAberration: 0.01,
    ),
  ),
)
```

### 5.3 辉光颜色

```dart
GlassGlowColors(
  primary: Colors.blue,       // 主品牌色
  secondary: Color(0xFF5856D6), // iOS 紫色
  success: Color(0xFF34C759),   // iOS 绿色
  warning: Color(0xFFFF9500),   // iOS 橙色
  danger: Color(0xFFFF3B30),    // iOS 红色
  info: Color(0xFF5AC8FA),      // iOS 浅蓝
  glowBlurRadius: 4.0,         // 高斯模糊 sigma
  glowSpreadRadius: 0,         // 扩展比例
  glowOpacity: 1,              // 主透明度乘数
)
```

---

## 六、组件目录与 iOS 26 映射

### 6.1 结构层 (Structural)

| 组件 | iOS 26 对应 | 关键参数 |
|---|---|---|
| `GlassScaffold` | 页面脚手架 | `background`, `appBar`, `bottomBar`, `contentAwareBrightness`, `header` |
| `GlassPage` | 全屏玻璃页面根 | `background`, `statusBarStyle`, `edgeToEdge`, `themeOverride` |
| `GlassAppBar` | `UINavigationBar` | `title`, `leading`, `trailing`, `centerTitle`(true), 默认透明背景 |
| `GlassBottomBar` | `UITabBar` | `tabs`, `selectedIndex`, `enableBlend`, `maskingQuality`, `tabWidth` |
| `GlassSearchableBottomBar` | `UITabBar` + 搜索 | `searchConfig`, `isSearchActive`, `barHeight` |
| `GlassTabBar` | `UISegmentedControl` | `tabs`, `isScrollable`, `selectedIndex` |
| `GlassToolbar` | `UIToolbar` | 浮动工具栏 |

### 6.2 容器层 (Containers)

| 组件 | iOS 26 对应 | 关键参数 |
|---|---|---|
| `GlassContainer` | 基础玻璃表面 | `shape`, `settings`, `allowElevation`(false) |
| `GlassCard` | 分组内嵌卡片 | `padding`(16), `shape`(12px超椭圆), `margin` |
| `GlassListTile` | `UICollectionViewListCell` | `leading`, `title`, `subtitle`, `trailing`, `isLast` |
| `GlassGroupedSection` | 分组列表 | `header`, `footer`, 自动管理 `isLast` |
| `GlassDivider` | `UITableView` 分隔线 | `.vertical()` 构造器 |
| `GlassStepper` | `UIStepper` | `value`, `min`, `max`, `step`, `wraps` |

### 6.3 交互层 (Interactive)

| 组件 | iOS 26 对应 | 关键参数 |
|---|---|---|
| `GlassButton` | 各种按钮样式 | `icon`, `label`, `shape`(LiquidOval), `interactionScale`(1.05), `stretch`(0.5), `anchorStretch`(true), `style`(filled/prominent/transparent) |
| `GlassIconButton` | `UIBarButtonItem` | `shape`(roundedSquare) |
| `GlassSegmentedControl` | `UISegmentedControl` | `segments`, `height`(32), `borderRadius`(16) |
| `GlassSwitch` | `UISwitch` | `activeColor`(systemGreen), `width`(58), `height`(26), 跳跃动画 |
| `GlassSlider` | `UISlider` | `activeColor`, `thumbColor` |
| `GlassChip` | 筛选药丸/标签 | `selected`, `selectedColor` |
| `GlassBadge` | `UITabBarItem.badgeValue` | `count`, `.dot()` 构造器 |
| `GlassButtonGroup` | 分组按钮栏 | `showDividers`, `.icons()` 构造器 |
| `GlassPullDownButton` | `UIMenu` 下拉 | `items`, `buttonWidth` |
| `GlassPageControl` | `UIPageControl` | `count`, `currentPage`, 胶囊形指示器 |

### 6.4 输入层 (Input)

| 组件 | iOS 26 对应 | 关键参数 |
|---|---|---|
| `GlassTextField` | `UITextField` | `placeholder`, `prefixIcon`, `suffixIcon`, `useOwnLayer` |
| `GlassTextArea` | 多行 `UITextView` | `placeholder`, `minLines` |
| `GlassSearchBar` | `UISearchBar` | `placeholder`, `showsCancelButton` |
| `GlassPasswordField` | 安全 `UITextField` | 自带显示/隐藏切换 |
| `GlassPicker` | `UIPickerView` | `value`, `placeholder`, `icon` |
| `GlassFormField` | 标签+错误文本包装 | `label`, `helperText`, `child` |

### 6.5 反馈层 (Feedback)

| 组件 | iOS 26 对应 | 关键参数 |
|---|---|---|
| `GlassProgressIndicator` | `UIProgressView` / `UIActivityIndicatorView` | `.circular()`, `.linear()`, `size`, `strokeWidth`, `value` |
| `GlassToast` | 通知药丸/HUD | `message`, `type`(success/error/info/warning), `position` |

### 6.6 覆盖层 (Overlays)

| 组件 | iOS 26 对应 | 关键参数 |
|---|---|---|
| `GlassDialog` | `UIAlertController(.alert)` | `title`, `message`, `actions` |
| `GlassActionSheet` | `UIAlertController(.actionSheet)` | `title`, `actions` |
| `GlassSheet` | `UISheetPresentationController` | `settings`, `builder` |
| `GlassModalSheet` | 模态面板变体 | `initialState`, `mode`, `peekSize`, `halfSize`, `fullSize` |
| `GlassMenu` | `UIMenu` / 上下文菜单 | `menuAlignment`(9方向), `items`, 液态变形 |
| `GlassPopover` | 气泡弹窗 | `popoverWidth`, `popoverHeight`, `triggerBuilder` |

---

## 七、液态变形引擎 (Liquid Morph Engine)

### 7.1 双 Blob 模型

菜单打开时，两个概念"Blob"驱动视觉效果：

- **Blob A（锚点）** — 幽灵触发器，在动画前 40% 缩小至 0，断开液态桥
- **Blob B（菜单体）** — 沿 J 曲线超调轨迹从触发器中心移动到菜单中心

SDF metaball shader 自动在两个 Blob 之间创建泪滴颈部——无需显式颈部几何体。

### 7.2 弹簧物理

```
mass: 1.0, stiffness: 120.0, damping: 16.0
→ ω₀ ≈ 11 rad/s, ζ ≈ 0.73 (欠阻尼)
```

欠阻尼是有意设计：ζ < 1 让弹簧超调，驱动打开时的泪滴颈和关闭时的橡皮筋回弹。

### 7.3 MorphSpeed

| 速度 | 刚度 | ω₀ | 手感 |
|---|---|---|---|
| `slow` | 60 | ≈7.7 | 缓慢，适合教程/减少动效 |
| `normal` | 120 | ≈11 | **默认**，iOS 26 原生对等 |
| `fast` | 200 | ≈14 | 快速，适合高频交互 |
| `instant` | 500 | ≈22 | 近瞬间，Reduce Motion |

### 7.4 MorphPhase 生命周期

```
打开方向: idle → detaching → travelling → arriving → settled
关闭方向: settled → arriving → travelling → detaching → [bounce] → idle
```

| Phase | rawValue 范围 | 含义 |
|---|---|---|
| `idle` | < 0.001 | 静止，覆盖层可安全移除 |
| `detaching` | 0.001–0.4 或 < 0 | Blob A 缩小，液态桥形成 |
| `travelling` | 0.4–0.8 | 泪滴拉伸峰值，颈部最大 |
| `arriving` | 0.8–1.0 | Blob B 接近目标，颈部收缩 |
| `settled` | ≥ 1.0 | Blob B 完全到达菜单位置 |

### 7.5 自定义变形组件示例

```dart
class _MyMorphWidgetState extends State<MyMorphWidget>
    with TickerProviderStateMixin {
  late final GlassMorphController _morph;

  @override
  void initState() {
    super.initState();
    _morph = GlassMorphController(vsync: this, speed: MorphSpeed.normal);
    _morph.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _morph.computeState(finalDx: 0, finalDy: -120);
    return Stack(children: [
      // Blob A: 幽灵触发器
      if (_morph.isShowing && !_morph.hasHandedOff)
        Positioned(
          left: triggerLeft + state.pushDx,
          top: triggerTop + state.pushDy,
          child: Transform.scale(scale: state.anchorScale, child: _Trigger()),
        ),
      // Blob B: 变形菜单
      if (_morph.isShowing)
        Positioned(
          left: triggerLeft + state.currentDx,
          top: triggerTop + state.currentDy,
          child: Transform.scale(
            scale: state.containerScale,
            child: LiquidGlass(blendRadius: state.blend, child: _Menu()),
          ),
        ),
      // 真实触发器
      Positioned(
        left: triggerLeft, top: triggerTop,
        child: Visibility(
          visible: !_morph.isShowing || _morph.hasHandedOff,
          child: _Trigger(onTap: _morph.open),
        ),
      ),
    ]);
  }
}
```

---

## 八、GlassModalSheet 完整参考

### 8.1 状态机

| 状态 | 说明 |
|---|---|
| `hidden` | 完全离屏 |
| `peek` | 最小可见状态（如迷你播放器） |
| `half` | 默认中间状态 |
| `full` | 最大展开 |

### 8.2 模式

| 模式 | 说明 |
|---|---|
| `dismissible` | 可下滑至 `hidden` 完全关闭 |
| `persistent` | 锁定在屏幕上，下滑最低到 `peek` |

### 8.3 几何变形参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `halfSize` | 0.45 | 半屏高度（>1.0 为像素，否则为屏幕比例） |
| `fullSize` | null | 全屏高度（默认屏幕高-90） |
| `peekSize` | 90 | 最小可见高度 |
| `horizontalMargin` | 8 | 侧边距（展开时 lerp 至 0） |
| `peekWidth` | null | 浮动药丸宽度 |
| `peekBottomMargin` | null | 浮动药丸底距 |
| `topBorderRadius` | null | null 时自动适配设备圆角 |

### 8.4 自适应圆角

| 设备 | 圆角 |
|---|---|
| 桌面 / Home Button iPhone | 0.0 |
| iPhone Pro Max (Island) | 64.0 |
| iPhone Pro / Base (Island) | 50.0 |
| iPhone with Notch | 44.0 |
| Android (Gesture Nav) | 28.0 |

### 8.5 Apple Maps 风格浮动药丸

```dart
GlassModalSheet.show(
  context: context,
  mode: SheetMode.persistent,
  peekWidth: 340,
  peekSize: 72,
  peekBottomMargin: 32,
  peekTopBorderRadius: 36,
  peekBottomRadius: 36,
  builder: (context) => SearchInput(),
);
```

### 8.6 Smart Silence

```dart
GlassModalSheet.show(
  context: context,
  suppressInteractionOnChildren: true, // 子组件触摸时不抖动面板
  builder: (context) => InteractiveMenu(),
);
```

### 8.7 Apple Maps 持久面板

```dart
GlassModalSheetScaffold(
  background: MyInteractiveMap(), // 背景可交互！
  sheetChild: MySheetContent(),
  initialState: SheetState.peek,
  mode: SheetMode.persistent,
)
```

### 8.8 滚动同步

```dart
// Sheet 内的 ListView 必须使用提供的 ScrollController
final scrollData = ScrollControllerProvider.of(context);
return ListView(
  controller: scrollData?.controller,
  physics: scrollData?.physics,
  children: [...],
);
```

### 8.9 响应式 UI（Morphing UI）

```dart
final state = GlassModalSheetStateProvider.of(context);
final progress = state?.progress ?? 0.0; // 0.0 (Peek) → 1.0 (Full)
return Opacity(opacity: progress, child: MyComplexWidget());
```

### 8.10 渲染层堆栈

```
Scaffold Background (e.g. Map)
  → Interaction Listener
    → Positioned Box (Dynamic Metrics)
      → LiquidStretch (Rubber-banding)
        → Layer 1: Background Shadow & Solid Color
        → Layer 2: AdaptiveGlass (Backdrop Blur)
        → Layer 3: GlassGlow (Tactile Glare)
        → Layer 4: AdaptiveLiquidGlassLayer (Content Glass)
          → ClipPath (RoundedSuperellipse Clipping)
            → Primary Content Payload
            → Drag Handle (Handle Zone)
```

---

## 九、内容感知亮度

iOS 26 核心特性：浮动控件根据背后滚动内容自动切换亮/暗外观。

```dart
GlassScaffold(
  contentAwareBrightness: true,
  bottomBar: GlassBottomBar(
    adaptiveBrightness: true,
    onBrightnessChanged: (b) => debugPrint('Bar is now: $b'),
    tabs: [...],
    selectedIndex: _index,
    onTabSelected: (i) => setState(() => _index = i),
  ),
  body: CustomScrollView(slivers: [...]),
)
```

**裁决算法**: WCAG 对比度投票 — 每个网格单元投票哪种字形颜色对比度更好。非简单亮度阈值，中等亮度内容保持浅色外观。

**防抖**: 粘性平票 + 双阈值滞后（默认 0.6），防止边界内容闪烁。

**采样成本**: 滚动时每 180ms 采样一次，空闲时零采样。捕获降采样到约 16 物理像素/网格单元。

---

## 十、形状体系

| 形状 | 类 | 参数 | 适用场景 |
|---|---|---|---|
| 超椭圆 (Squircle) | `LiquidRoundedSuperellipse` | `borderRadius` | 卡片、面板（iOS 标准） |
| 椭圆 | `LiquidOval` | 无 | 圆形按钮 |
| 圆角矩形 | `LiquidRoundedRectangle` | `borderRadius` | 简单矩形 |
| 上下不同圆角矩形 | `LiquidVerticalRoundedRectangle` | `topRadius`, `bottomRadius` | 底部面板 |
| 上下不同圆角超椭圆 | `LiquidVerticalRoundedSuperellipse` | `topRadius`, `bottomRadius` | 高品质底部面板 |
| 泪滴形 | `LiquidTeardropShape` | `topWidth`, `bottomWidth`, `topRadius`, `bottomRadius`, `alignX` | 菜单变形中间态 |

---

## 十一、交互物理

### 11.1 锚定拉伸 (Anchor Stretch)

iOS 26 按钮的 squash & stretch 行为：

```dart
GlassButton(
  anchorStretch: true,  // 默认 true
  anchorStretchSettings: AnchorStretchSettings(
    intensity: 0.5,       // 拉伸强度
    squashFactor: 0.3,    // 挤压因子
    translationDamping: 0.15, // 平移阻尼
    bounciness: 0.15,     // 弹性
  ),
)
```

- 拉伸上限 30%，挤压上限 15%
- 体积保持: `volumeCorrection = sqrt(targetVolume / currentVolume)`
- 宽高比校正: 长轴方向阻尼 = `1 / aspectRatio`

### 11.2 触摸辉光

```dart
GlassButton(
  glowColor: Colors.white24,
  glowRadius: 1.0,
  glowBlurRadius: 0,
  glowOnTapOnly: false,  // true = 拖拽>10px 自动抑制
)
```

按下时切换到 `GlassSpring.interactive()`（快速跟随），释放时切换到 `GlassSpring.smooth()`（缓慢消散）。

### 11.3 交互行为模式

```dart
GlassInteractionBehavior.full    // 缩放 + 发光
GlassInteractionBehavior.scaleOnly // 仅缩放
GlassInteractionBehavior.none    // 无交互效果
```

---

## 十二、无障碍

**默认自动生效**，无需配置：

| 系统设置 | 效果 |
|---|---|
| **Reduce Motion** | 所有弹簧/果冻动画瞬间到达目标 |
| **Reduce Transparency / High Contrast** | Glass Shader 替换为纯 `BackdropFilter` 霜化面板，零 GPU shader 开销 |

优先级（高胜出）：
1. `GlassAccessibilityScope` — 开发者显式覆盖
2. 系统 `MediaQuery` 标志 — 自动
3. `wrap(respectSystemAccessibility: false)` — 全局禁用

---

## 十三、性能优化

1. **`LiquidGlassWidgets.initialize()`** — 预热 shader
2. **Standard 用于可滚动内容**，Premium 用于固定表面
3. **Minimal 用于 GPU 密集屏幕** — 背景面板和列表卡片用 Minimal（零 shader），焦点元素用 Standard/Premium
4. **`GlassScaffold` 自动提升** — appBar 和 bottomBar 自动包裹 `GlassIsolationScope(isolated: true, defaultQuality: premium)`
5. **`useOwnLayer: true`** — 让组件拥有独立渲染层，避免 BackdropFilter 重组合闪烁
6. **自适应质量持久化** — 避免每次冷启动 3 秒降质：

```dart
final prefs = await SharedPreferences.getInstance();
final saved = prefs.getString('glass_quality');
final initial = saved != null ? GlassQuality.values.byName(saved) : null;

runApp(LiquidGlassWidgets.wrap(
  child: const MyApp(),
  adaptiveQuality: true,
  adaptiveConfig: GlassAdaptiveScopeConfig(
    initialQuality: initial,
    allowStepUp: true,
    onQualityChanged: (_, to) => prefs.setString('glass_quality', to.name),
  ),
));
```

7. **GPU 预算监控** — `GlassPerformanceMonitor` 在 debug/profile 模式自动启用，连续 60 帧超预算时发出 `FlutterError`，release 模式零开销。

---

## 十四、陀螺仪光照

```dart
GlassMotionScope(
  stream: gyroscopeEvents.map((e) => e.y * 0.5),
  child: Scaffold(
    appBar: GlassAppBar(title: const Text('My App')),
    body: ...,
  ),
)
```

无额外依赖 — 连接任何 Stream 源（滚动位置、鼠标、陀螺仪）。

---

## 十五、Z 轴隔离与背景折射

### 15.1 GlassIsolationScope

`GlassScaffold` 自动将 appBar 和 bottomBar 包裹为 `isolated: true, defaultQuality: premium`，防止 Z 轴撕裂（body 玻璃卡片的背景画在滚动文本后面，但前景画在上面）。

### 15.2 背景折射源

```dart
// 推荐：GlassPage 自动处理
GlassPage(
  background: Image.asset('assets/wallpaper.jpg', fit: BoxFit.cover),
  child: Scaffold(body: GlassSegmentedControl(...)),
)

// 手动：LiquidGlassScope.stack
LiquidGlassScope.stack(
  background: Image.asset('assets/wallpaper.jpg', fit: BoxFit.cover),
  content: Scaffold(body: GlassSegmentedControl(...)),
)
```

| 场景 | 推荐方案 |
|---|---|
| Skia / Web | `GlassPage(background:...)` — 自动连接 |
| iOS / macOS (Impeller) | `GlassQuality.premium` — 原生场景图 |
| 多个隔离区域 | 每个区域独立 `LiquidGlassScope` |

---

## 十六、镜面锐度

| 值 | 外观 |
|---|---|
| `GlassSpecularSharpness.soft` | 宽泛、漫射 — 霜化/哑光玻璃 |
| `GlassSpecularSharpness.medium` | **默认** — 匹配 iOS 26 |
| `GlassSpecularSharpness.sharp` | 紧凑、抛光 — 镜面表面 |

每个值映射到固定的 2 的幂指数，GPU 使用零超越函数乘法链计算。

---

## 十七、常见陷阱与最佳实践

| 陷阱 | 解决方案 |
|---|---|
| GlassScaffold 在复杂沉浸式布局中产生全局白雾 | 改用手动 Stack 组合 |
| `CupertinoIcons.search` 在 iOS 模拟器上渲染为 '?' | 使用 `Symbols.search` (size 28) |
| `GlassButton.custom` 在 `GlassButtonGroup` 中 `width: double.infinity` 溢出 | 使用 `Expanded` 分配宽度 |
| 高 blurSigma (28-40) 导致按钮反射呈色块 | 降低 blur 至 10-20 |
| 过高 opacity (0.12-0.18) 降低背后内容可见性 | 保持 glassColor opacity 在 0.08-0.12 |
| `Positioned` 必须是 `Stack` 的直接子组件 | 避免嵌套包装 |
| `Navigator.of(context).pushNamed()` 导致路由错误 | 使用 GoRouter 的 `context.go()` |
| `Theme.of(context)` 在 `dispose()` 中不安全 | 在 `initState` 中缓存值 |
| `album.works.first` 空列表导致 RangeError | 添加空列表检查 |
| ScrollController 在页面重建时 `hasClients` 守卫缺失 | 访问前检查 `hasClients` |

---

## 十八、GlassModalSheet 内部渲染常量

| 常量 | 值 | 说明 |
|---|---|---|
| Apple Maps 速度 | 0.15 | Peek→Half 变形压缩在前 15% 移动中 |
| 底部同步阈值 | 0.90 | 90% 展开时开始隐藏底部圆角 |
| 闪烁平台 | 0.04 | 4% 安全边距防止 fillThreshold 附近闪烁 |
| 速度吸附 | 700.0 px/s | 超过此速度忽略位置逻辑，直接跳转状态 |
| 弹簧常数 | mass:1, stiffness:220, damping:30 | "Liquid" 吸附手感 |

---

## 十九、LiquidGlassSettings 内部材质配方（Sheet 默认）

| 参数 | 默认值 | 说明 |
|---|---|---|
| `blur` | 10.0 | 霜化强度，实体化时 lerp 至 0 |
| `thickness` | 10.0 | 玻璃深度，影响边缘受光 |
| `refractiveIndex` | 0.15 | 边缘高光强度，iOS 26 专用调校 |
| `chromaticAberration` | 0.0 | 色差，Sheet 默认关闭以保性能 |
| `saturation` | 1.2 | 背景色增强，触摸时脉冲 |
| `lightIntensity` | 0.7 | 镜面边缘亮度 |
| `lightAngle` | 2.356 | 135°（左上方），iOS 标准光照 |
| `ambientStrength` | 0.4 | 玻璃表面基线亮度 |
| `glassColor` | 0x1FFFFFFF | 12% 白色着色（iOS 26 标准） |

---

*文档生成时间: 2026-06-17*
*基于 liquid_glass_widgets v0.16.x 源码*
