# Maestro + iOS 测试实战指南

> 基于 Coriander Player 项目在 iPhone 16 模拟器上的实际测试经验整理。
> 测试日期：2026-06-10 | Maestro 版本：2.x | iOS Simulator：iPhone 16 (iOS 26.5)

---

## 一、环境准备

### 1.1 必要依赖

```bash
# 1. 安装 Maestro CLI（二选一）
brew tap mobile-dev-inc/tap && brew install mobile-dev-inc/tap/maestro
# 或
curl -fsSL "https://get.maestro.mobile.dev" | bash

# 2. 安装 Facebook IDB（iOS 模拟器通信必需）
brew tap facebook/fb && brew install facebook/fb/idb-companion

# 3. 验证安装
maestro --version    # → 2.x.x
idb-companion --version  # → 0.x.x
```

### 1.2 idb-companion 是什么？

Maestro 与 iOS 模拟器的通信**不通过** Xcode 的 `simctl`，而是通过 **Facebook IDB (Instrumentation Debug Bridge)**。

| 平台 | 通信方式 |
|------|---------|
| Android | ADB（直接可用） |
| iOS | **idb-companion**（必须单独安装） |

**缺少时症状**：
```
idb-companion NOT FOUND
Please install it via: brew install facebook/fb/idb-companion
```

### 1.3 构建并安装 App 到模拟器

```bash
# 方式 A：flutter run（推荐，构建+安装+运行一步完成）
flutter run -d <device-id> --debug

# 方式 B：手动构建 + 安装
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
```

> **注意**：`flutter run` 后 App 会保持运行状态，Maestro 的 `launchApp` 会直接连接到已运行的实例。无需先 `quit` 再 `launch`。

---

## 二、运行测试

### 2.1 基本命令

```bash
# 运行单个测试文件
maestro test test/maestro/artist_detail_immersive_test.yaml

# 运行目录下所有测试
maestro test test/maestro/

# 输出 JUnit 格式报告（CI 集成用）
maestro test test/maestro/flow.yaml --format JUNIT --output report.xml
```

### 2.2 运行结果解读

```
 ║  > Flow: artist_detail_immersive_test
 ║    ✅   Launch app "com.senyepss.corianderPlayer"   # 成功
 ║    ✅   Assert that "音乐库" is visible              # 断言通过
 ║    ❌   Assert that "首作品" is visible              # 断言失败！
 ║    🔲   Take screenshot ...                          # 未执行（前置失败）
```

| 符号 | 含义 |
|------|------|
| ✅ | 步骤成功 |
| ❌ | 步骤失败，测试终止 |
| 🔲 | 因前置步骤失败而跳过 |

### 2.3 调试产物位置

每次运行都会生成调试目录：

```
~/.maestro/tests/<timestamp>/
├── maestro.log                          # 完整日志（含 XCUITest 驱动信息）
├── screenshot-❌-<timestamp>.png         # 失败时的截图（关键！用于排查）
├── commands-(test-name).json            # 执行步骤的 JSON 记录
└── xctest_runner_<timestamp>.log        # XCTest 底层驱动日志
```

**排查流程**：失败后第一时间查看 `screenshot-❌-*.png`，确认页面实际状态。

---

## 三、踩坑记录与解决方案

### 坑 #1：scroll 命令在 iOS 上不支持参数

**错误写法**：
```yaml
- scroll:                    # ❌ 等同于默认 swipe UP
- scroll: { direction: UP }  # ❌ Unknown Property: direction
```

**原因**：Maestro 的 `scroll` 命令在 iOS 上是固定行为（等同于无参数的 `swipe UP`），不接受任何参数。

**正确做法**：使用 `swipe` 命令替代：
```yaml
# 简单方向控制
- swipe:
    direction: UP          # 内容向上滚
    duration: 300

# 精确坐标控制
- swipe:
    start: 50%, 80%        # 从屏幕中下部开始
    end: 50%, 20%          # 到屏幕上部结束
    duration: 600
```

### 坑 #2：文本断言是精确匹配

**现象**：截图上清晰可见 `"19 首作品"`，但断言失败：
```yaml
- assertVisible: "首作品"           # ❌ 匹配不到 "19 首作品"
- assertVisible: "/\\d+ 首作品/"   # ❌ 正则也不生效
```

**原因**：Maestro 的 `visible:` 对文本做的是**精确匹配**（或子串匹配取决于版本），且正则支持不稳定。

**解决方案**：
1. 用已知必定存在的其他元素做断言（如艺术家名称）
2. 使用 `waitForAnimationToEnd` 固定延迟代替对不确定文本的等待
3. 给目标 Widget 添加 `Key` 或 `SemanticsLabel`，用 `id:` 选择器定位

```yaml
# 推荐：用固定延迟 + 可靠元素组合
- waitForAnimationToEnd:
    timeout: 5000
- assertVisible:
    text: "周杰伦"
    optional: true
```

### 坑 #3：部分 Flutter Text 组件不可被 Maestro 发现

**现象**：截图中可见的文本，在 UI 层次树中不存在对应的 accessibility label。

**原因**：Flutter 的 `Text` widget 默认不会自动生成 `SemanticsLabel`，除非它被包裹在语义化容器中或设置了 `semanticsLabel` 属性。

**影响范围**：
- 动态生成的文本（如 `"19 首作品"` 这种拼接字符串）
- 嵌套在复杂布局中的非交互文本
- `Text.rich()` 或 `RichText` 的部分内容

**解决方案**（按推荐顺序）：
1. **测试侧**：改用 `waitForAnimationToEnd` + 已知可靠元素
2. **代码侧**：给需要被测试识别的 Text 添加 `semanticsLabel`
3. **代码侧**：用 `Semantics` widget 包裹关键文本

```dart
// 代码侧改进示例
Text(
  '$songCount 首作品',
  semanticsLabel: '歌曲数量',  // 让 Maestro 能找到
)
```

### 坑 #4：swipe 可能无法触发 Flutter 自定义滚动区域

**现象**：执行多次 `swipe direction: UP` 后截图完全相同，页面没有滚动。

**可能原因**：
1. Swipe 的起始点落在了不可滚动的区域（如 AppBar、固定按钮区）
2. Flutter 的 `ListView.builder` / `CustomScrollView` 需要特定的触摸事件序列
3. Swipe 距离太短或速度太快，被 Flutter 识别为 tap 而非 scroll

**解决方案（待验证）**：
```yaml
# 方案 A：增大滑动距离和时长
- swipe:
    start: 50%, 70%
    end: 50%, 10%
    duration: 800

# 方案 B：用 scrollById 精确定位可滚动容器
- scrollUntilVisible:
    element:
      text: "某首歌名"
    direction: DOWN

# 方案 C：连续多次小幅度 swipe
- repeat:
    times: 3
    commands:
      - swipe:
          direction: UP
          duration: 400
```

---

## 四、iOS 特有注意事项

### 4.1 模拟器选择

Maestro 会自动检测已启动的模拟器。如果同时有多个模拟器运行，可以指定：

```bash
# 列出可用设备
xcrun simctl list devices available

# 启动指定模拟器
xcrun simctl boot <device-id>

# 在指定设备上运行测试
maestro test test.yaml --device <device-id>
```

### 4.2 App 状态管理

| 操作 | 效果 |
|------|------|
| `launchApp` | 如果 App 已在运行，连接到现有实例；否则冷启动 |
| `terminateApp` | 杀掉 App 进程 |
| 再次 `launchApp` | 完全重新启动（全新状态） |

**注意**：Flutter 的 `flutter run --debug` 保持 App 运行时，Maestro 的 `launchApp` 会复用该实例，App 状态（音乐库数据、缓存等）会保留。

### 4.3 截图与状态栏

iOS 模拟器的截图**包含完整的状态栏区域**（时间、信号、电池）。这对验证沉浸式设计非常有用——可以直接看到状态栏图标颜色与背景的对比效果。

### 4.4 中文环境

确保模拟器系统语言为简体中文，否则 UI 文本为英文导致断言失败：

```bash
# 检查当前语言
xcrun simctl spawn booted defaults read AppleLanguages

# 设置中文（需要重置模拟器或新建中文模拟器）
xcrun simctl erase all
# 然后在系统设置中选择中文
```

---

## 五、测试文件编写最佳实践

### 5.1 推荐的 YAML 结构

```yaml
appId: com.senyepss.corianderPlayer
---
# ============================================================
# 测试名称：一句话描述测试目的
# 覆盖场景：
#   1. 场景一描述
#   2. 场景二描述
# ============================================================
# 注意事项：
#   - xxx

# ---------- 阶段 1：准备 ----------
- launchApp
- extendedWaitUntil:
    visible: "可靠锚点文本"
    timeout: 10000

# ---------- 阶段 2：操作 ----------
- tapOn: "某个元素"
- waitForAnimationToEnd:
    timeout: 2000

# ---------- 阶段 3：验证 ----------
- takeScreenshot: path/to/screenshot.png
- assertVisible:
    text: "期望文本"
    optional: true    # optional = 失败不阻断测试流
```

### 5.2 选择器优先级

| 选择器类型 | 示例 | 可靠性 | 说明 |
|-----------|------|--------|------|
| `id:` | `id: artist_tile` | ⭐⭐⭐ 最高 | 代码中显式设置 Key |
| `text:` | `text: "周杰伦"` | ⭐⭐ 高 | 确定存在的静态文本 |
| `text:` + `optional: true` | — | ⭐⭐ | 允许缺失 |
| `visible:` | `visible: "N 首作品"` | ⭐ 低 | 动态文本易匹配失败 |

### 5.3 时间参数建议

| 场景 | 推荐值 | 说明 |
|------|--------|------|
| 页面首次加载 | `timeout: 10000` | 含 Rust FFI 初始化 |
| 页面导航转场 | `timeout: 2000` | 动画过渡时间 |
| 异步图片加载 | `timeout: 5000-8000` | Future 解析 + 渲染 |
| 滚动动画结束 | `timeout: 500-1000` | 物理动画衰减 |
| 单次点击反馈 | `timeout: 300-500` | ripple/水波纹 |

---

## 六、与其他测试体系的协作

### 6.1 Maestro vs Flutter Integration Test

| 维度 | Maestro | Flutter Integration Test |
|------|---------|--------------------------|
| 编写语言 | YAML | Dart |
| 滚动操作 | `swipe`（有时不可靠） | `TestGesture.scroll()`（精确） |
| 文本断言 | 弱（仅可见性） | 强（Widget 属性检查） |
| 状态栏验证 | 截图+人工审查 | 可读 SystemUiOverlayStyle |
| 适用场景 | 冒烟、导航流程 | 深度 UI 验证 |

**策略互补**：
- 用 Maestro 做**快速回归**（每次改完代码跑一遍确认没挂）
- 用 Flutter Integration Test 做**精确断言**（状态栏样式、Widget 类型等）

### 6.2 CI 集成建议

```yaml
# .github/workflows/maestro-test.yml（示例）
- name: Run Maestro tests
  run: maestro test test/maestro/ --format JUNIT --output maestro-results.xml
- name: Upload screenshots
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: maestro-screenshots
    path: test/reports/screenshots/
```
