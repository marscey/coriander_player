# Coriander Player 测试体系

本项目包含两套并行的移动端测试体系：**Flutter 集成测试**和 **Maestro 声明式测试**。

## 目录结构

```
coriander_player/
├── integration_test/               # Flutter 集成测试（Dart 代码）
│   │                               # ⚠️ 必须在项目根目录，Flutter 框架硬编码约定
│   ├── mobile_ui_test.dart         #   移动端 UI 适配测试
│   ├── webdav_cloud_test.dart      #   WebDAV 云服务测试
│   └── ios_media_control_test.dart #   iOS 媒体控制测试
└── test/
    ├── maestro/                    # Maestro 测试流（YAML 声明式）
    │   ├── config.yaml             #   全局配置（appId）
    │   ├── flow.yaml               #   主测试流（9 个场景）
    │   ├── smoke_test.yaml         #   冒烟测试
    │   └── nav_test.yaml           #   导航切换测试
    ├── unit/                       # Flutter 单元/Widget 测试
    │   └── widget_test.dart        #   占位冒烟测试
    └── TESTING.md                  #   本文档
```

### 为什么 `integration_test/` 在根目录而不是 `test/` 下？

Flutter 框架在源码中**硬编码**了目录名：

```dart
// packages/flutter_tools/lib/src/commands/test.dart
const _kIntegrationTestDirectory = 'integration_test';
```

当 `flutter test` 发现文件路径（相对于项目根目录）包含 `integration_test/` 时，会以**集成测试模式**运行（需要连接设备/模拟器）；否则以**单元测试模式**运行（在 Flutter Tester 中执行）。

如果将集成测试放到 `test/integration/`，Flutter 会报错：

```
Warning: integration_test plugin was not detected.
Please make sure your tests are in the `integration_test/` directory of your package.
```

因此 `integration_test/` 必须保持在项目根目录，这是 Flutter 的硬性约定，无法绕过。

---

## 一、Flutter 集成测试

### 原理

使用 Flutter 官方 `integration_test` 包，在真实 Flutter 引擎中运行测试代码，可以访问 Widget 树、模拟用户操作、截图验证。

### 前置条件

- Flutter SDK 已安装
- iOS 模拟器已启动（或 Android 模拟器）

### 运行命令

```bash
# 构建 iOS 模拟器版本（首次或代码变更后需要）
flutter build ios --simulator

# 在已启动的模拟器上运行移动端 UI 测试
flutter test integration_test/mobile_ui_test.dart

# 运行 WebDAV 云服务测试
flutter test integration_test/webdav_cloud_test.dart

# 运行 iOS 媒体控制测试
flutter test integration_test/ios_media_control_test.dart

# 运行所有集成测试
flutter test integration_test/
```

### 关于 `test_driver/` 目录（已删除）

旧版 `flutter drive` 模式需要 `test_driver/integration_test.dart` 作为驱动入口。Flutter 3.x 推荐直接使用 `flutter test integration_test/xxx.dart`，不再需要此目录，已删除。

### 测试用例一览

#### mobile_ui_test.dart — 移动端 UI 适配

| # | 验证项 | 说明 |
|---|--------|------|
| 1 | 启动页显示 | "音乐库"文本可见 |
| 2 | NavigationBar 存在 | 移动端使用底部导航栏 |
| 3 | 导航栏 5 项正确 | 音乐库、最近播放、连接、搜索、设置；不含"本地" |
| 4 | 桌面端 UI 隐藏 | 无"全屏/最小化/关闭"按钮 |
| 5 | Mini 播放器可见 | "Coriander Player"文本存在 |
| 6 | 导航切换 - 最近播放 | 点击后页面切换 |
| 7 | 导航切换 - 连接 | 跳转到云服务连接页面 |
| 8 | 导航切换 - 搜索 | 跳转到搜索页面 |
| 9 | 导航切换 - 设置 | 跳转到设置页面 |
| 10 | 最终布局验证 | 回到音乐库，导航栏和 Mini 播放器仍在 |

#### webdav_cloud_test.dart — WebDAV 云服务

| # | 验证项 | 说明 |
|---|--------|------|
| 1 | 导航到连接页面 | 点击底部"连接"Tab |
| 2 | 添加 WebDAV 连接 | 填写表单并保存 |
| 3 | 浏览 WebDAV 文件 | 进入文件浏览器 |
| 4 | 进入文件夹浏览 | 点击文件夹查看内容 |
| 5 | 播放 WebDAV 音频 | 点击音频文件触发播放 |
| 6 | 返回连接列表 | 验证导航回退正常 |

### 注意事项

- 所有测试必须在**同一个 `testWidgets`** 中运行，因为 `flutter_rust_bridge` 只能初始化一次
- 测试前会自动创建空的 `index.json`、`playlists.json` 等数据文件，避免应用崩溃
- `webdav_cloud_test.dart` 中包含 WebDAV 凭据，**不要提交到公开仓库**

---

## 二、Maestro 声明式测试

### 原理

使用 YAML 文件描述测试步骤（启动应用、点击元素、断言可见、截图），由 Maestro CLI 驱动模拟器执行。无需编写代码，适合快速验证 UI 和交互流程。

### 前置条件

```bash
# 安装 Maestro CLI（二选一）
# 方式 1：Homebrew（推荐）
brew tap mobile-dev-inc/tap
brew install mobile-dev-inc/tap/maestro

# 方式 2：官方脚本
curl -fsSL "https://get.maestro.mobile.dev" | bash

# 验证安装
maestro --version   # 应输出 2.x.x

# 确保 iOS 模拟器已启动并安装了应用
flutter build ios --simulator
# 安装 app 到模拟器
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
```

### 运行命令

```bash
# 运行单个测试流
maestro test test/maestro/flow.yaml

# 运行所有测试流
maestro test test/maestro/

# 运行并生成 JUnit 报告
maestro test test/maestro/flow.yaml --format JUNIT --output report.xml

# 运行并保存截图到指定目录
maestro test test/maestro/flow.yaml --artifact-output test/maestro/screenshots
```

### 测试流一览

#### flow.yaml — 主测试流（9 个场景）

| # | 场景名 | 操作 | 截图 |
|---|--------|------|------|
| 1 | 初始启动验证 | launchApp → 断言"音乐库"可见 | 01-initial-launch |
| 2 | 底部导航栏结构验证 | 断言 5 个 Tab 均可见 | 02-nav-bar-structure |
| 3 | 桌面端 UI 隐藏验证 | 断言"全屏/最小化/关闭"不可见 | 03-no-desktop-ui |
| 4 | Mini 播放器验证 | 断言"Coriander Player"可见 | 04-mini-player-visible |
| 5 | 导航切换 - 最近播放 | 点击"最近播放" | 05-nav-recent-plays |
| 6 | 导航切换 - 连接 | 点击"连接" → 断言"云服务连接" | 06-nav-cloud-connection |
| 7 | 导航切换 - 搜索 | 点击"搜索" | 07-nav-search |
| 8 | 导航切换 - 设置 | 点击"设置" | 08-nav-settings |
| 9 | 完整布局最终验证 | 断言"音乐库" + "Coriander Player" | 09-final-full-layout |

#### smoke_test.yaml — 冒烟测试

启动应用，断言 "Music" 可见（英文版，需确认语言环境）。

#### nav_test.yaml — 导航切换测试

依次切换 4 个 Tab（最近播放、连接、搜索、设置），每个切换后截图。

### config.yaml — 全局配置

```yaml
appId: com.senyepss.corianderPlayer
```

所有测试流共享此 appId，无需在每个 YAML 中重复声明（但当前各文件仍各自声明了 appId 以保持独立可运行）。

---

## 三、两套体系对比

| 维度 | Flutter 集成测试 | Maestro 声明式测试 |
|------|-----------------|-------------------|
| **语言** | Dart | YAML |
| **编写难度** | 较高，需了解 Flutter Widget 树 | 低，声明式语法 |
| **执行方式** | Flutter 引擎内运行 | 外部 CLI 驱动模拟器 |
| **断言能力** | 强（可检查 Widget 类型、属性） | 弱（仅文本可见性） |
| **截图** | `binding.takeScreenshot()` | `takeScreenshot` 命令 |
| **适用场景** | 精确验证 UI 结构和逻辑 | 快速冒烟测试和回归验证 |
| **CI 集成** | `flutter test` | `maestro test --format JUNIT` |
| **跨平台** | Flutter 支持的所有平台 | Android + iOS |
| **调试** | 可断点调试 | Maestro Studio 可视化 |

### 推荐使用策略

- **日常开发验证**：优先用 Maestro，快速编写、快速运行
- **精确 UI 断言**（如检查 NavigationBar 的 destinations）：用 Flutter 集成测试
- **CI 流水线**：两者都跑，Maestro 做冒烟、Flutter 做深度验证

---

## 四、常见问题

### Q: Maestro 报 `Unable to launch app`

应用未安装到模拟器。需要先构建并安装：

```bash
flutter build ios --simulator
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
```

### Q: Flutter 集成测试报 `_pendingFrame == null`

多次调用 `app.main()` 导致状态泄漏。解决方案：将所有测试合并到同一个 `testWidgets` 中。

### Q: Flutter 集成测试报 `integration_test plugin was not detected`

测试文件不在 `integration_test/` 目录下。Flutter 框架硬编码了此目录名，必须将集成测试放在项目根目录的 `integration_test/` 中。

### Q: Maestro 找不到中文文本元素

确保模拟器系统语言为中文，或在 YAML 中使用 `id` 选择器而非纯文本匹配。

### Q: 如何查看 Maestro 截图

截图保存在 `--artifact-output` 指定的目录中，例如 `test/maestro/screenshots/`。

### Q: `test_driver/` 目录还需要吗？

不需要，已删除。旧版 `flutter drive` 模式的驱动文件，Flutter 3.x 推荐直接用 `flutter test integration_test/xxx.dart` 运行。
