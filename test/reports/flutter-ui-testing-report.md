# Flutter 自动化 UI 测试复盘报告

## 项目信息
- **项目**: Coriander Player (Flutter 音乐播放器)
- **测试框架**: Maestro 2.6.0
- **测试设备**: iPhone 16 模拟器 (iOS 26.5)
- **日期**: 2026-06-08

---

## 一、测试方案选型

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **Maestro** ✅ | 声明式 YAML、跨平台、易于维护 | 需要安装 CLI | 本项目首选 |
| XCUITest | Apple 原生、性能好 | 仅 iOS、代码量大 | iOS 专属测试 |
| Appium | 跨平台、语言无关 | 配置复杂、不稳定 | 大型团队 |
| Patrol | Flutter 原生、支持 Native | 需要额外配置 | Flutter 深度测试 |

**选择 Maestro 的原因**：
1. 项目已有 Maestro 测试基础设施
2. YAML 声明式语法，维护成本低
3. 支持 iOS/Android 双平台
4. 内置截图、断言、等待等常用功能

---

## 二、Maestro 核心语法

### 2.1 基础结构
```yaml
appId: com.senyepss.corianderPlayer
---
- launchApp
- waitForAnimationToEnd:
    timeout: 5000
- assertVisible: "音乐库"
- takeScreenshot: screenshot-name
```

### 2.2 元素选择器

| 选择器类型 | 语法 | 示例 |
|-----------|------|------|
| 文本匹配 | `text: "..."` | `tapOn: "编辑标签"` |
| ID 匹配 | `id: "..."` | `longPressOn: { id: "audio_tile_0" }` |
| 正则匹配 | `textRegex: "..."` | `assertVisible: { textRegex: "音乐.*" }` |
| 语义标签 | `accessibilityText` | 自动从 Semantics 读取 |

### 2.3 常用操作
```yaml
# 点击
- tapOn: "按钮文字"

# 长按
- longPressOn: { id: "element_id" }

# 滚动
- scroll: { direction: DOWN }

# 等待
- waitForAnimationToEnd: { timeout: 2000 }

# 断言
- assertVisible: "期望文本"
- assertNotVisible: "不应显示的文本"

# 截图
- takeScreenshot: path/to/screenshot
```

---

## 三、关键发现与踩坑

### 3.1 Flutter Semantics 与 Maestro 的关系

**问题**：Flutter 的 `Text` 组件不会自动暴露为 Maestro 可见的文本。

**解决方案**：使用 `Semantics` 组件包装：
```dart
// ❌ Maestro 无法找到
Text("I Put A Spell On You")

// ✅ Maestro 可通过 id 找到
Semantics(
  identifier: "audio_tile_0",
  child: Text("I Put A Spell On You"),
)
```

### 3.2 accessibilityText vs text

**发现**：Flutter 的 `Semantics(label: ...)` 会生成 `accessibilityText`，而非 `text`。

```dart
// 生成 accessibilityText，不是 text
Semantics(
  label: "迷你播放器 - Coriander Player",
  child: ...
)
```

**Maestro 查找时**：
- `text` 选择器：找不到 `accessibilityText`
- `id` 选择器：通过 `Semantics(identifier: ...)` 找到

### 3.3 长按操作的最佳实践

```yaml
# ✅ 推荐：使用 Semantics identifier
- longPressOn:
    id: "audio_tile_0"

# ❌ 不推荐：依赖截断的文本
- longPressOn:
    text: "I Put A Spell On You - A..."
```

---

## 四、编辑标签页面测试用例

### 4.1 测试文件
`test/maestro/edit_tag_test.yaml`

### 4.2 测试流程
```yaml
appId: com.senyepss.corianderPlayer
---
# 1. 启动应用
- launchApp
- waitForAnimationToEnd: { timeout: 5000 }
- assertVisible: "音乐库"

# 2. 长按打开上下文菜单
- longPressOn: { id: "audio_tile_0" }
- waitForAnimationToEnd: { timeout: 1000 }
- takeScreenshot: edit-tag-01-context-menu

# 3. 进入编辑标签页面
- tapOn: "编辑标签"
- waitForAnimationToEnd: { timeout: 2000 }
- takeScreenshot: edit-tag-02-page-layout

# 4. 验证页面元素
- assertVisible: "编辑标签"
- assertVisible: "标题"
- assertVisible: "艺术家"
- assertVisible: "专辑"
- assertVisible: "在线搜索"

# 5. 截图最终布局
- takeScreenshot: edit-tag-03-final-layout
```

### 4.3 测试结果
| 步骤 | 状态 | 说明 |
|------|------|------|
| 启动应用 | ✅ PASS | 应用正常启动 |
| 长按打开菜单 | ✅ PASS | 上下文菜单正确显示 |
| 进入编辑标签 | ✅ PASS | 页面正确跳转 |
| 验证页面元素 | ✅ PASS | 所有元素可见 |
| 截图保存 | ✅ PASS | 3 张截图已保存 |

---

## 五、UI 验证结果

### 5.1 编辑标签页面布局（截图分析）

**改动前**：
- 封面居中 140×140，占据整行
- 左右两侧大量空白
- 输入框高度较大（48px+）

**改动后**：
- 封面左对齐 80×80
- 标签字段在右侧紧凑排列
- 输入框高度 38px
- 轨道号/年份/流派三列并排
- 搜索按钮+提示文字同行

### 5.2 空间分配
```
┌─────────────────────────────────┐
│  AppBar (返回 + 标题 + 保存)     │ ~56px
├─────────────────────────────────┤
│  ┌──────┐ ┌──────────────────┐  │
│  │ 封面  │ │ 标题             │  │
│  │ 80×80│ │ 艺术家           │  │ ~180px
│  │      │ │ 专辑             │  │
│  └──────┘ │ # │ 年份 │ 流派  │  │
│           └──────────────────┘  │
├─────────────────────────────────┤
│  [在线搜索] 搜索结果点击回显...  │ ~40px
├─────────────────────────────────┤
│                                 │
│  搜索结果列表（可滚动）          │ 剩余空间
│                                 │
└─────────────────────────────────┘
```

---

## 六、最佳实践总结

### 6.1 Semantics 标识符规范
```dart
// 为可交互元素添加 identifier
Semantics(
  identifier: 'audio_tile_${index}',
  child: ListTile(...)
)

// 为导航元素添加 identifier
Semantics(
  identifier: 'tab_library',
  child: NavigationDestination(...)
)

// 为迷你播放器添加语义标签
Semantics(
  label: '迷你播放器 - ${songTitle}',
  button: true,
  child: ...
)
```

### 6.2 测试文件组织
```
test/maestro/
├── config.yaml                    # 全局配置
├── flow.yaml                      # 基础流程
├── comprehensive_ui_test.yaml     # 综合 UI 测试
├── edit_tag_test.yaml             # 编辑标签测试
└── flows/                         # 按功能模块组织
```

### 6.3 截图命名规范
```
test/reports/screenshots/
├── edit-tag-01-context-menu.png
├── edit-tag-02-page-layout.png
└── edit-tag-03-final-layout.png
```

---

## 七、运行命令

```bash
# 运行单个测试
maestro test test/maestro/edit_tag_test.yaml

# 运行所有测试
maestro test test/maestro/

# 运行并查看输出
maestro test test/maestro/edit_tag_test.yaml --format=yaml

# 查看测试报告
open ~/.maestro/tests/
```

---

## 八、后续优化建议

1. **增加断言**：验证封面图片、输入框内容
2. **添加交互测试**：测试搜索功能、保存功能
3. **错误场景测试**：网络失败、保存失败
4. **性能监控**：记录页面加载时间
5. **CI/CD 集成**：在 GitHub Actions 中运行 Maestro 测试

---

## 九、相关文件

| 文件 | 说明 |
|------|------|
| `test/maestro/edit_tag_test.yaml` | 编辑标签测试用例 |
| `lib/page/settings_page/edit_tag_dialog.dart` | 编辑标签页面代码 |
| `lib/component/audio_tile.dart` | 音频列表项（含 Semantics） |
| `lib/component/app_shell.dart` | 应用外壳（含迷你播放器） |
