# Liquid Glass 移动端完成度审计

| 项目 | 内容 |
|---|---|
| 审计日期 | 2026-11-23 |
| 代码基线 | 分支 `mobile-ui-merged`，HEAD `1bd84cf`（含托盘资源修复未提交） |
| 审计范围 | `lib/` 全量，重点 `glass_theme/`、`glass_app_shell`、`page/`、`component/` |
| 静态检查 | `flutter analyze lib` → 0 error / 24 warning（均为合并前旧告警） |
| 自动化测试 | `test/maestro/` 24 个流程，**0 个覆盖 Glass 模式** |

---

## 一、结论

移动端 Glass 已经“搭好了骨架、铺开了页面”，但还没有“收口”。

- **壳层（导航 + 搜索 + 播放 pill）基本完成**，是整套 Glass 里最完整、最接近 iOS 26 的部分。
- **一级 6 个入口里 5 个有 Glass 版**（音乐库 / 歌单 / 类别 / 连接 / 搜索），设置页也有 Glass 分支；**「本地文件夹」整块没有 Glass，且移动端没有入口**。
- **详情页 5 个里有 4 个 Glass 化**（音频 / 专辑 / 歌单 / 艺术家 / 流派），文件夹详情没有。
- **交互层是最大的缺口**：`GlassDialog` 全项目只有 13 处引用，而 `AlertDialog` / `showModalBottomSheet` 在 Glass 页里仍有 30+ 处，移动端会频繁弹出 Material 风格弹窗和底部表单。
- **开关语义不统一**：约 30 处判断只读 `liquidGlassEnabled`、不带 `isMobile`；另有 3 个详情页**完全不判断开关，永远渲染 Glass**。这会让“桌面端以后再做”的边界变得不可控。

一句话：**页面覆盖约 85%，交互与一致性约 50%–60%，测试 0%。**

---

## 二、覆盖矩阵

### 2.1 壳与导航（`lib/component/glass_app_shell.dart`，1251 行）

| 能力 | 状态 | 证据 |
|---|---|---|
| Glass 壳切换（移动端） | ✅ | `entry.dart:180`（`liquidGlassEnabled && isMobile`） |
| 底部玻璃导航栏（4 tab） | ✅ | `glass_app_shell.dart:226` + `GlassSearchableBottomBar` |
| 搜索 pill / 展开态 / 历史列表 | ✅ | `_SearchBrowseView`（942 行起） |
| 播放条 Pill + 迷你模式 | ✅ | `_PlayBarPill`（462 行起）、`_isMiniMode` |
| 本地 / 搜索 / 设置 入口 | ⚠️ | `_kTabs` 只有 音乐库/歌单/类别/连接；`_kTabBranchIndices=[0,1,2,4]` |
| 搜索结果页壳 | ⚠️ | 搜索态直接返回裸 `GlassScaffold`（`211–223`），与 `GlassPageScaffold` 分叉 |

### 2.2 一级页面

| 页面 | Glass | 证据 / 说明 |
|---|---|---|
| 音乐库 | ✅ | `audios_page.dart` → `UniPage<Audio>`（`uni_page.dart:733`） |
| 歌单 | ✅ | `playlists_page.dart:105` + `_GlassPlaylistTile`（299） |
| 类别 | ✅ | `categories_page.dart:44` |
| 连接 | ✅ | `cloud_connections_page.dart:75` |
| 搜索 | ✅ | `search_page.dart:51`、`search_result_page.dart:86` |
| 设置 | ✅ | `settings_page/page.dart:28` |
| 本地文件夹 | ❌ | `folders_page.dart` 0 处 Glass，`surfaceContainerLow` 工具条 + Material 列表 |
| 最近播放 | ❌ | `recent_plays_page.dart` 无任何引用（疑似死代码） |

### 2.3 详情页

| 页面 | Glass | 是否受开关控制 | 证据 |
|---|---|---|---|
| 音频详情 | ✅ | ✅ 条件分支（含 `isMobile`） | `entry.dart:201` |
| 云文件浏览 | ✅ | ✅ 条件分支 | `entry.dart:313` |
| 播放页 | ✅ | ✅ 条件分支 | `now_playing_page/page.dart:113` |
| 专辑详情 | ✅ | ❌ **永远 Glass** | `album_detail_page_new.dart:241` |
| 歌单详情 | ✅ | ❌ **永远 Glass** | `playlist_detail_page.dart:279` |
| 艺术家详情 | ✅ | ❌ **永远 Glass** | `artist_detail_page_v3.dart` 全文无 `liquidGlassEnabled` |
| 流派详情 | ✅ | ⚠️ 只读开关、无 `isMobile` | `genres_page.dart:79` |
| 文件夹详情 | ❌ | — | `folder_detail_page.dart` 0 处 Glass |

### 2.4 弹窗 / 菜单 / 表单

| 能力 | 状态 | 证据 |
|---|---|---|
| Glass 菜单（tile 长按菜单） | ✅ 广泛使用 | `GlassMenuItem` 出现在 `audio_tile`、`playlists_page`、`recent_plays_page` |
| Glass 确认框 | ⚠️ 仅局部 | `glass_dialog.dart` 191 行；`GlassDialog(` 全项目 13 处 |
| 云连接表单 | ✅ | `glass_cloud_connection_form.dart` |
| 主题选择器 | ✅ | `theme_settings.dart:28` → `GlassThemePickerDialog` |
| 编辑标签 | ⚠️ 双实现 | `glass_edit_tag_dialog.dart`（927 行）与 `edit_tag_dialog.dart` 并存，`audio_tile.dart:239/259/698` 按开关分支 |
| 其余弹窗 | ❌ | `audio_tile.dart` 12 处、`uni_page.dart` 7 处、`glass_cloud_file_browser.dart` 5 处、`glass_now_playing_page.dart` 3 处仍为 Material `AlertDialog` / `showModalBottomSheet` |
| 首启欢迎页 / 建索引页 | ❌ | `welcoming_page.dart`、`updating_page.dart` 均 0 处 Glass |

---

## 三、已经做扎实的部分

1. **外壳（1251 行）**：底部栏用 `GlassSearchableBottomBar` + 播放 Pill + 迷你模式，交互模型（重复点当前 tab 回根、切 tab 退搜索）接近 Apple Music。
2. **云文件浏览（2233 行）**：功能上是旧版的超集，比旧版多 `_playAll` / `_shuffleAll` / `_toggleSelectAll` / 页内搜索 / 溢出标题处理（`_checkOverflow`、`_measureTitleHeight`）。
3. **播放页（1038 行）**：歌词视图 / 播放列表 / 封面背景 / 收藏（旧版没有 `Symbols.favorite`）都在。
4. **参数中心化**：`glass_theme/glass_presets.dart` 已建立 9 组预设，15 个文件引用它（方向正确）。
5. **列表/卡片组件**：`audio_tile`、`artist_tile`、`album_tile`、`unified_list_tile`、`settings_tile` 都有 Glass 分支。

---

## 四、未完成清单（按优先级）

### P0 — 影响“移动端算不算做完”

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| 1 | 「本地文件夹」无 Glass，且移动端无入口 | `folders_page.dart` 0 处 Glass；`_kTabs` 不含 `FOLDERS_PAGE` | 移动端无法管理/新增音乐目录；若 iOS 只走云服务，需产品上明确“不做” |
| 2 | 3 个详情页强制 Glass，无视开关 | `album_detail_page_new.dart:241`、`playlist_detail_page.dart:279`、`artist_detail_page_v3.dart`（无判断） | 关闭 Glass 时仍是玻璃页；桌面端现在已经在混用，违背“先移动端后桌面端”的推进顺序 |
| 3 | 开关判定两套口径 | 带 `isMobile` 的只有 `entry.dart:180`、`now_playing_page/page.dart:113`、`search_page.dart:51`、`search_result_page.dart:86`；其余约 30 处只读 `liquidGlassEnabled` | 桌面端一旦打开开关，会得到“Material 壳 + 玻璃 tile/设置页”的混合体，后续做桌面端时无法渐进放开 |
| 4 | 首启流程全 Material | `welcoming_page.dart`、`updating_page.dart` | 移动端第一屏不是 Glass，第一次进应用的观感断层 |
| 5 | 弹窗/底部表单残留 Material | 见 2.4，`GlassDialog` 仅 13 处 | 玻璃页里弹白底 Material 对话框，是观感破坏最明显的一类 |

### P1 — 一致性与技术债

| # | 问题 | 证据 |
|---|---|---|
| 6 | 搜索历史两份独立实现 | `glass_app_shell.dart:22` 的 `SearchHistoryManager` 与 `search_result_page.dart:18` 的 `_SearchHistoryManager` 各存一份，互不同步 |
| 7 | 预设被复制 | 壳层 `_barGlassSettings`（164 行起，3 处）、`artist_detail_page_v3.dart` 4 处、`search_result_page.dart:309` 自己 new 了一份 |
| 8 | 深色适配不完整 | 预设里只有 `bottomBarSettings` / `playBarPillSettings` 接 `isDark`；`card/listTile/settingsTile/search/sheet` 都是固定白色透明度 |
| 9 | 设置项用“伪玻璃” | `settings_tile.dart:72–92` 用 `scheme.surface` alpha 容器模拟，而非 `GlassContainer`（性能取舍，但和 iOS 26 观感有差距） |
| 10 | 同一功能两套实现 | 云浏览 2233 + 旧 7xx、播放页 1038 + 旧版、编辑标签 927 + 旧版；修一处 bug 要改两处 |
| 11 | 已知视觉 workaround | `glass_presets.dart:165` 注释：为避免“双层 GlassScaffold 白色条带”才统一背景函数 |
| 12 | 死代码 | `recent_plays_page.dart` 无引用 |

### P2 — 打磨项

| # | 问题 | 证据 |
|---|---|---|
| 13 | 移动端播放页无音量控件 | Glass 版图标集合无 `Symbols.volume_up`，旧版有 |
| 14 | 3 处硬编码白色玻璃色 | `lib/page`、`lib/component` 内 `Color(0x..FFFFFF)` / `Colors.white.withValues` |
| 15 | 无 Glass 自动化验收 | `test/maestro/` 24 个 flow 全是 Material UI |
| 16 | 桌面端被 `isMobile` 挡住 | `entry.dart:180` 条件决定桌面永远走 Material 壳（当前符合预期，但需在桌面阶段改造入口） |

---

## 五、给“先移动端、后桌面端”的改造建议

**第一步：把开关收口成一处**

新增 `AppPreference.glassActiveFor(BuildContext)`（或 `GlassGate.of(context)`），内部逻辑：

```dart
bool get glassActive => liquidGlassEnabled && PlatformHelper.isMobile; // 移动端阶段
```

把所有 `AppPreference.instance.liquidGlassEnabled` 的直读替换成它；桌面阶段只需改这一处（改成 `|| desktopGlassEnabled`），不用再动 30 个页面。

**第二步：给 3 个“永远玻璃”的详情页加条件**

`album_detail_page_new` / `playlist_detail_page` / `artist_detail_page_v3` 补 `if (!gate) return PageScaffold(...)` 分支，恢复桌面与关闭态的 Material 呈现。

**第三步：弹窗统一入口**

做一个 `showGlassDialog(context, ...)` / `showGlassSheet(...)` 工厂：Glass 态走 `GlassDialog`/玻璃底部表单，否则回落 `AlertDialog`/`showModalBottomSheet`。按调用量先改 `audio_tile.dart`（12 处）与 `uni_page.dart`（7 处）。

**第四步：补入口或明确不做**

- 若移动端要管理本地目录：`FoldersPage` 加 Glass 版，并在 Glass 壳里加第 5 个入口（或放进搜索浏览页的“设置/库管理”区）。
- 若 iOS 只走云 + 系统文件：在文档和设置页里明确“本地目录仅桌面端”，避免以后反复讨论。

**第五步：桌面端阶段**

到那一步再引入 `desktopGlassEnabled`、把 `GlassScaffold` 的窗口适配（`minSize`、拖拽区、右键菜单、hover 态）补上——这些当前代码里完全没有，属于桌面阶段的新工作量，不是移动端的尾巴。

---

## 六、验证方式（现状）

```bash
# 静态检查（只看 lib，rust_builder 的报错忽略）
flutter analyze lib

# 移动端跑 Glass：把 app_preference.json 里 liquidGlassEnabled 置 true，重启
# macOS 上 Glass 壳不会生效（entry.dart:180 的 isMobile 判断），需要 iOS 模拟器/真机
flutter run -d <iOS 设备>
```

审计时点没有 iOS 设备在跑，因此矩阵中的「状态」来自代码结构证据（分支、条件、组件引用），不是截图验证。
