# 液态玻璃改造差距分析

> 基于最近一次提交 `d9e9226f`（2026-06-17: 新增 Liquid Glass 风格 UI）+ 工作区未提交改动生成
> 首次生成：2026-06-25｜最近复核：2026-06-26（阶段1-3、5 已完成，阶段4 部分完成）

## 一、图标库统一性分析

### 问题概述

当前 Glass 页面中混用三种图标库：`Symbols.*`（Material Symbols）、`CupertinoIcons.*`（iOS 风格）、`Icons.*`（Material Icons），没有统一规范。参考实现（Artist V3、Album New）本身就混用，导致后续页面各有各的风格。

### 图标库使用现状（已逐文件核实）

| 文件 | 图标库混用情况 | 严重程度 |
|---|---|---|
| `glass_page_scaffold.dart` | 返回 `Icons.arrow_back_ios_new`、关闭 `CupertinoIcons.xmark`、设置 `Symbols.settings`、更多 `Icons.more_horiz` | 高（3 种混用） |
| `glass_cloud_file_browser.dart` | 返回 `Icons.arrow_back_ios_new`、定位 `Icons.my_location`、关闭 `CupertinoIcons.xmark`、更多导航栏 `Icons.more_horiz`、更多列表项 `Icons.more_vert`、文件夹 `CupertinoIcons.folder`、音乐 `Symbols.music_note` | 高（3 种混用） |
| `glass_app_shell.dart` | 底部 Tab `Symbols.library_music` + `CupertinoIcons.music_note_list`/`square_grid_2x2`/`cloud`；播放控制 `CupertinoIcons.pause_fill`/`play_arrow_solid` | 中（2 种混用） |
| `glass_now_playing_page.dart` | 列表项更多按钮 `Icons.more_vert`；其余全部 `Symbols.*` | 中 |
| `artist_detail_page_v3.dart` | `Symbols.*` 主导 + `CupertinoIcons.checkmark_alt`/`play_arrow_solid`/`shuffle` | 中（参考实现本身混用） |

### 建议统一方案

按功能场景统一图标库：

| 功能场景 | 当前使用 | 建议统一为 | 理由 |
|---|---|---|---|
| 返回按钮 | `Icons.arrow_back_ios_new` | `Icons.arrow_back_ios_new` | iOS 风格返回箭头，已统一 |
| 关闭/取消 | `CupertinoIcons.xmark` | `CupertinoIcons.xmark` | iOS 26 风格更贴近，与 `glass_page_scaffold` 一致 |
| 更多按钮（导航栏） | `Icons.more_horiz` | `Icons.more_horiz` | 水平三点，已统一 |
| 更多按钮（列表项） | `Icons.more_vert` | `Icons.more_vert` | 垂直三点，已统一 |
| 搜索 | `Symbols.search` | `Symbols.search` | 已统一 |
| 定位 | `Icons.my_location` | `Icons.my_location` | 已统一 |
| 设置 | `Symbols.settings` | `Symbols.settings` | 已统一 |
| 播放控制 | `CupertinoIcons.play_arrow_solid`/`pause_fill`/`forward_end_fill` | 保持不变 | iOS 风格播放按钮 |
| 排序/视图 | `Symbols.sort`/`grid_view`/`list` | 保持不变 | Material Symbols 填充图标 |
| 文件类型 | `CupertinoIcons.folder`/`doc` + `Symbols.music_note` | 保持不变 | 各场景合理 |

## 二、页面双版本覆盖情况

### 已有 Glass 版本的页面（19 个）

| 页面 | Glass 实现方式 | 状态 |
|---|---|---|
| AppShell（导航外壳） | `GlassAppShell` 独立文件 | 完成 |
| 艺术家详情 | `ArtistDetailPageV3` 内置 glass 分支 | 完成（参考实现） |
| 专辑详情 | `AlbumDetailPageNew` 内置 glass 分支 | 完成（参考实现） |
| 歌单详情 | `PlaylistDetailPage` 内置 glass 分支 | 完成 |
| 搜索页 | `SearchPage` 内置 glass 分支 | 完成 |
| 搜索结果页 | `SearchResultPage` 内置 glass 分支 | 完成 |
| 设置页 | `SettingsPage` 内置 glass 分支 | 完成 |
| 云连接列表 | `CloudConnectionsPage` 内置 glass 分支 | 完成 |
| 云文件浏览 | `GlassCloudFileBrowser` 独立文件 | 完成 |
| 正在播放 | `GlassNowPlayingPage` 独立文件 | 完成 |
| 分类页 | `CategoriesPage` 内置 glass 分支 | 完成 |
| 歌单列表 | `PlaylistsPage` 内置 glass 分支 | 完成 |
| 所有 UniPage 子类 | `UniPage` 内部 `useGlass` 切换 `GlassPageScaffold` | 完成（外壳级） |
| `GlassPageScaffold` | 通用骨架组件 | 完成 |
| 音频详情页 | `GlassAudioDetailPage` 独立文件 | 完成 |
| WebDAV 连接表单 | `GlassCloudConnectionForm` 独立文件 | 完成 |
| 设置-编辑标签 | `GlassEditTagDialog` 独立文件 | 完成 |
| 设置-主题选择器 | `GlassThemePickerDialog` 独立文件 | 完成 |
| 设置-缓存/更新/主题/刮擦器/引擎/艺术家分隔符 | 6 个弹窗内置 `useGlass` 分支 | 完成 |

### 未改造的页面（4 个，均为非 UniPage 独立实现）

#### 中优先级

| 页面 | 路径 | 说明 |
|---|---|---|
| 文件夹列表 | `lib/page/folders_page.dart` | 完全独立 Material 实现（自定义工具栏 + 文件夹列表），非 UniPage 子页 |
| 文件夹详情 | `lib/page/folder_detail_page.dart` | 完全独立 Material 实现（网格/列表双视图 + 定制菜单），非 UniPage 子页 |

#### 低优先级（几乎不访问 / 非移动端）

| 页面 | 路径 | 说明 |
|---|---|---|
| 欢迎页 | `lib/page/welcoming_page.dart` | 首次启动，一次性 |
| 更新页 | `lib/page/updating_page.dart` | 启动初始化，一次性 |
| 桌面正在播放 | `lib/page/now_playing_page/large_page.dart` | 桌面布局 |
| 桌面正在播放 | `lib/page/now_playing_page/small_page.dart` | 桌面布局 |

## 三、薄改造页面（外壳已玻璃化，内部未跟进）

以下页面通过 `UniPage` 获得了 `GlassPageScaffold` 外壳，列表项状态如下：

| 页面 | 外壳 | 列表项 | 状态 |
|---|---|---|---|
| `AudiosPage` | Glass | `AudioTile` 有 glass 分支 | 完成 |
| `ArtistsPage` | Glass | `artist_tile.dart` 有 glass 分支 | 完成 |
| `AlbumsPage` | Glass | `album_tile.dart` 有 glass 分支 | 完成 |
| `GenresPage` | Glass | `_GenreTile` 内置 glass 分支（渐变图标 + 透明背景） | 完成 |
| `RecentPlaysPage` | Glass | 通过 `AudioTile` 的 glass 分支处理 | 完成 |
| `FoldersPage` | Material | 独立 Material 实现 | 待完整页面 Glass 化 |
| `FolderDetailPage` | Material | 独立 Material 实现（网格/列表双视图） | 待完整页面 Glass 化 |

## 四、改造路线图

### 阶段 1：图标统一 ✅ 已完成

- [x] 返回按钮统一 `Icons.arrow_back_ios_new`
- [x] 导航栏更多按钮统一 `Icons.more_horiz`
- [x] 列表项更多按钮统一 `Icons.more_vert`（`glass_now_playing_page.dart` 第 278/292 行）
- [x] 搜索按钮统一 `Symbols.search`
- [x] 定位按钮统一 `Icons.my_location`
- [x] 关闭按钮统一 `CupertinoIcons.xmark`（`glass_cloud_file_browser.dart` 第 378/1080 行）

### 阶段 2：弹窗/对话框玻璃化 ✅ 已完成

- [x] `audio_detail_page.dart` → `GlassAudioDetailPage`
- [x] `cloud_connection_form.dart` → `GlassCloudConnectionForm`
- [x] `edit_tag_dialog.dart` → `GlassEditTagDialog`
- [x] `theme_picker_dialog.dart` → `GlassThemePickerDialog`
- [x] 路由调用处全部切换（`entry.dart` / `audio_tile.dart` / `glass_now_playing_page.dart` / `theme_settings.dart`）

### 阶段 3：设置二级页玻璃化 ✅ 已完成

- [x] `cache_settings.dart` → `_CacheDetailDialog` 内置 `useGlass` 分支
- [x] `check_update.dart` → `NewestUpdateView` 内置 `useGlass` 分支
- [x] `theme_settings.dart` → showDialog 切换 `GlassThemePickerDialog`
- [x] `scraper_settings.dart` → `ScraperSettingsDialog` + `_editApiBase` 两处 `useGlass` 分支
- [x] `artist_separator_editor.dart` → `_ArtistSeparatorEditDialog` 内置 `useGlass` 分支
- [x] `player_engine_selector.dart` → AlertDialog 切换 `useGlass` 分支

### 阶段 4：UniPage 子页列表项深化 ✅ 部分完成

- [x] `GenresPage` 列表项 Glass 化（`_GenreTile` 渐变图标 + 透明背景）
- [x] `RecentPlaysPage` 列表项（通过 `AudioTile` 的 glass 分支）
- [ ] `FoldersPage` 待完整页面 Glass 化（独立 Material 实现，非 UniPage 子页）
- [ ] `FolderDetailPage` 待完整页面 Glass 化（独立 Material 实现，非 UniPage 子页）

> 注：原路线图将 `FoldersPage` 和 `FolderDetailPage` 列入阶段4，但实际上它们不是 UniPage 子页，而是完全独立的 Material 实现。完整 Glass 化需要重写整个页面结构，超出"列表项深化"范畴，留待后续单独处理。

### 阶段 5：遗留代码清理 ✅ 已完成

- [x] 删除 `album_detail_page.dart`（已被 `album_detail_page_new.dart` 取代）
- [x] 删除 `artist_detail_page.dart`（已被 `artist_detail_page_v3.dart` 取代）
- [x] 删除 `uni_detail_page.dart`（无任何使用方，已被 V3/New 取代）

## 五、性能待验收项

- [ ] 启动时间增加不超过 200ms
- [ ] 列表滚动帧率保持 55 FPS 以上（中高端设备）

## 六、本次改造汇总

### 新建文件（5 个）

| 文件 | 用途 |
|---|---|
| `lib/glass_theme/glass_dialog.dart` | 通用玻璃弹窗容器（`GlassDialog` + `GlassDialogButton`） |
| `lib/page/glass_audio_detail_page.dart` | 音频详情页 Glass 版本 |
| `lib/page/cloud_service/glass_cloud_connection_form.dart` | 云连接表单 Glass 版本 |
| `lib/page/settings_page/glass_edit_tag_dialog.dart` | 编辑标签弹窗 Glass 版本（移动端用 `GlassPageScaffold`，桌面端用 `GlassDialog`） |
| `lib/page/settings_page/glass_theme_picker_dialog.dart` | 主题选择器 Glass 版本 |

### 修改文件（路由/调用切换）

| 文件 | 改动 |
|---|---|
| `lib/entry.dart` | 新增 `import glass_audio_detail_page.dart`；AudioDetailPage 路由切换 |
| `lib/page/cloud_service/cloud_connections_page.dart` | 2 处 showDialog 切换 GlassCloudConnectionForm |
| `lib/component/audio_tile.dart` | 4 处 EditTagDialog 调用切换 GlassEditTagDialog |
| `lib/page/now_playing_page/glass_now_playing_page.dart` | 2 处图标替换 + 2 处 EditTagDialog 调用切换 |
| `lib/page/cloud_service/glass_cloud_file_browser.dart` | 2 处图标替换（Icons.close → CupertinoIcons.xmark） |
| `lib/page/settings_page/theme_settings.dart` | showDialog 切换 GlassThemePickerDialog |
| `lib/page/settings_page/artist_separator_editor.dart` | `_ArtistSeparatorEditDialog` 内置 useGlass 分支 |
| `lib/page/settings_page/player_engine_selector.dart` | AlertDialog 切换 useGlass 分支 |
| `lib/page/settings_page/check_update.dart` | `NewestUpdateView` 内置 useGlass 分支 |
| `lib/page/settings_page/scraper_settings.dart` | 2 处 useGlass 切换 |
| `lib/page/settings_page/cache_settings.dart` | `_CacheDetailDialog` 内置 useGlass 分支 |
| `lib/component/unified_list_tile.dart` | 内置 useGlass 分支（渐变图标 + 透明背景） |
| `lib/page/genres_page.dart` | `_GenreTile` 内置 useGlass 分支 |

### 删除文件（3 个）

| 文件 | 理由 |
|---|---|
| `lib/page/album_detail_page.dart` | 已被 `album_detail_page_new.dart` 取代 |
| `lib/page/artist_detail_page.dart` | 已被 `artist_detail_page_v3.dart` 取代 |
| `lib/page/uni_detail_page.dart` | 无任何使用方，已被 V3/New 取代 |

### 切换逻辑统一

所有路由/调用处统一使用以下三元判断切换 Material/Glass 版本：

```dart
AppPreference.instance.liquidGlassEnabled
    ? Glass版本组件
    : Material版本组件
```

启用默认界面时跳转默认页面，启用液态玻璃界面时跳转液态玻璃页面。

### 验证结果

- `dart analyze lib/`：0 error，0 新增 warning（既有 warning 均为 unused import/field，与本次改造无关）
