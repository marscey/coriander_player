# 移动端 Liquid Glass 全 UI 统一：现状审查与执行计划

> 分支 `mobile-ui-merged`（提交 `b541994` 起）。本文档承接 `docs/liquid-glass-mobile-audit.md`，记录 P0 收口后的真实状态与后续任务拆分。

## 一、P0 五项收口结果（已完成）

| # | 问题 | 处理方式 | 验收 |
|---|---|---|---|
| 1 | 开关两套口径（部分判定不带 `isMobile`） | 新增 `AppPreference.glassActive`（`liquidGlassEnabled && PlatformHelper.isMobile`），21 个文件 30 处直读改走它；仅设置页开关自身保留原始值 | `grep liquidGlassEnabled` 只剩定义、序列化、设置页开关 3 处 |
| 2 | 3 个详情页强制玻璃，桌面无回退 | 从 `67fd84c` 恢复 `UniDetailPageMaterial` / `ArtistDetailPageMaterial` / `AlbumDetailPageMaterial` / `PlaylistDetailPageMaterial`，`entry.dart` 4 条路由按 `glassActive` 二选一 | 桌面（glassActive=false）走 Material，移动端走玻璃 |
| 3 | 移动端仍暴露本地文件夹 | 设置页「音乐库」分组整体 `if (!PlatformHelper.isMobile)`；Glass 壳底部 tab 本就不含 folders | 移动端设置页无该分组、无入口 |
| 4 | 首启 / 建索引页是 Material | 欢迎页 Glass 化 + 「跳过，稍后设置」；`updating_page` 套 `GlassPageScaffold` | 两页在移动端无 Material 白底闪烁 |
| 5 | 玻璃页里残留 Material 弹窗 | 新增 `lib/glass_theme/app_dialog.dart`（`AdaptiveDialog` + `showAdaptiveSheet` + `GlassBottomSheetBody`），17 处 `AlertDialog`、11 处 `showModalBottomSheet` 全量替换（18 个文件） | `grep AlertDialog(\|showModalBottomSheet(` 在 `lib/` 归零 |

校验：`flutter analyze lib` → **0 error / 24 warning**（与改造前基线一致）；macOS 实跑启动正常（`welcome=false`，无异常栈）。

## 二、专家审查：还不统一的真实原因

页面骨架层面移动端已基本覆盖（12 个页面使用 `GlassPageScaffold`，另有搜索页、播放页、云文件浏览各自实现了 Glass 版），剩下的「一处玻璃一处 Material」来自**下面五类结构性欠账**，而不是某一页没做：

1. **预设参数多处复制**。`barGlassSettings` 在 `glass_app_shell.dart:167` 与 `artist_detail_page_v3.dart:165` 各写一份（注释还写明“照搬”），`navButtonSettings.copyWith` 在 4 处就地调参，`search_result_page.dart` 底部搜索条自带一套。改一处参数，其它页面不会同步 —— 这是长期不一致的最大来源。
2. **深色模式只做了一半**。`glass_presets.dart` 只有 `bottomBarSettings` / `playBarPillSettings` 接受 `isDark`；`sheetSettings`、`navButtonSettings`、对话框、导航 pill 都没有深色分支，深色主题下玻璃偏亮、文字对比度不足。
3. **假玻璃**。`settings_tile.dart:72–92` 用 `surface` + alpha 拼出“玻璃感”，不是真 `GlassContainer`，与相邻玻璃组件质感不同。
4. **交互控件仍是 Material**。弹窗容器已 Glass 化，但弹窗**内部**的 `Switch`、`Slider`、`TextField`、`CircularProgressIndicator`、`LinearProgressIndicator`（建索引页仍在用）还是 Material 样式；列表里的 `Checkbox`、`Radio`、`PopupMenuButton` 同样如此。
5. **无自动化兜底**。`test/maestro/` 26 个 flow 中没有一个在 `liquidGlassEnabled=true` 下跑，改动全靠肉眼。

另有可顺手清理的死代码/重复实现：`recent_plays_page.dart` 全项目无引用；搜索历史存在两份实现（`glass_app_shell.dart:22` 与 `search_result_page.dart:18`）。

## 三、任务清单

### P1：统一的基础设施（先做，否则后面每页都要返工）

- **P1-1 预设单一真相源**。把散落的 `_barGlassSettings`、4 处 `navButtonSettings.copyWith`、搜索条自带参数全部上收到 `glass_presets.dart`，按语义命名（`topBarSettings` / `searchBarSettings` / `tabBarSettings` / `sheetSettings` / `dialogSettings` / `navPillSettings`），页面只允许引用不允许自己写 `glassColor`。验收：`grep -c "LiquidGlassSettings(" lib` 中除 `glass_presets.dart` 外为 0。
- **P1-2 深色模式全量**。所有预设改成 `(bool isDark)` 形式并补齐深色配色，`GlassContainer` 调用处统一传 `Theme.of(context).brightness`；对话框、Sheet、导航 pill、列表卡片一并处理。验收：深色/浅色各截 6 张关键页，无“深色背景上的亮玻璃”。
- **P1-3 玻璃控件层**。新增 `lib/glass_theme/glass_controls.dart`：`GlassSwitch`、`GlassSlider`、`GlassTextField`、`GlassProgressBar`、`GlassCheckbox`、`GlassPopupMenu`（`glassActive` 为假时内部直接返回原生控件，调用方零判断）。验收：玻璃页面源码里不再出现 `Switch(`、`Slider(`、`TextField(`、`LinearProgressIndicator(`。
- **P1-4 假玻璃替换**。`settings_tile.dart` 改用真 `GlassContainer`；`page_scaffold.dart` 里同类模拟一并清理。

### P2：页面级一致性走查（按 6 组推进，逐组验收）

每组统一三件事：顶部栏用 `topBarSettings`、列表卡片用 `listCardSettings`、空态/加载态用玻璃组件。

1. **音乐库 / 类别 / 歌单 / 流派**（`uni_page`、`categories_page`、`playlists_page`、`genres_page`）
2. **详情页三件套**（`glass_audio_detail_page`、`artist_detail_page_v3`、`album_detail_page_new`、`playlist_detail_page`）——顺手把 Artist V3 的 4 处调参收进预设
3. **播放页**（`glass_now_playing_page` 及其歌词控件 `lyric_source_view`、`lyric_view_controls`、`mini_now_playing`）
4. **搜索**（`search_page`、`search_result_page`，合并两份搜索历史实现）
5. **云服务**（`cloud_connections_page`、`glass_cloud_file_browser`、`cloud_connection_form`）
6. **设置全组**（`settings_page` 及其 7 个子页：主题、刮削、缓存、引擎、艺术家分隔、检查更新、编辑标签）

验收统一标准：切到玻璃模式后，该组内**任意页面不出现 Material AppBar / 白底 Card / Material 弹窗 / 默认进度条**；页面间顶部栏高度、圆角、内边距数值一致。

### P3：验证与收尾

- **P3-1 Maestro 玻璃套件**。新增 `test/maestro/glass/`：启动即置 `liquidGlassEnabled=true`，覆盖 6 条主路径（音乐库→详情→播放、搜索、云连接、设置、首启跳过、深色切换）。
- **P3-2 真机验证**。iPhone（`00008110-000E35CC2612801E`）跑一遍，重点看安全区、滚动回弹、玻璃模糊在真机 GPU 上的开销（`GlassQuality.premium` 在低端机可能掉帧，需要留 `standard` 降级开关）。
- **P3-3 死代码清理**。删除 `recent_plays_page.dart`，合并搜索历史。
- **P3-4 桌面阶段预留**。桌面放开只需改 `AppPreference.glassActive` 一处，但 `GlassScaffold` / `GlassPageScaffold` 需要补桌面窗口尺寸适配（宽屏布局、无安全区、鼠标 hover 态），当前不做，仅记录。

## 四、顺序与风险

先 P1-1 + P1-2（两天级），再做 P1-3 + P1-4（一天级），然后 P2 六组并行推进，最后 P3 收口。**不要在 P1 未完成时先做 P2**：预设没收口，页面每改一次都要跟着改数值，返工量翻倍。

已知风险：`liquid_glass_widgets` 在 Android 低端机上的模糊开销未验证；`GlassQuality.premium` 是否需要在设置里暴露为选项，等 P3-2 真机数据再定。
