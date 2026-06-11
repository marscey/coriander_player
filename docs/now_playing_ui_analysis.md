# 正在播放页面 UI 实现分析

> 分析日期：2026-06-09
> 项目：Coriander Player（Flutter 跨平台音乐播放器）

---

## 一、路由结构

### 路径常量

**文件**：`lib/app_paths.dart`（第23行）

```dart
const String NOW_PLAYING_PAGE = "/nowplaying";
```

### GoRouter 路由定义

**文件**：`lib/entry.dart`（第291-311行）

```dart
GoRoute(
  path: app_paths.NOW_PLAYING_PAGE,       // "/nowplaying"
  pageBuilder: (context, state) => CustomTransitionPage(
    child: const NowPlayingPage(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),      // 从底部滑入
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.fastOutSlowIn,
        )),
        child: child,
      );
    },
    maintainState: false,
  ),
),
```

**要点**：

- 正在播放页是**顶层 GoRoute**，独立于 `StatefulShellRoute`，push 在所有 Shell 之上
- 自定义过渡动画：**底部上滑**（`Offset(0,1)→(0,0)`），`Curves.fastOutSlowIn`
- `maintainState: false`：退出时销毁状态，不保留页面实例

---

## 二、完整页面链路

```
任意页面
  └─ MiniNowPlaying（迷你播放器，底部悬浮）    ← lib/component/mini_now_playing.dart
       ├─ onTap → context.push('/nowplaying')
       │    └─ NowPlayingPage                    ← lib/page/now_playing_page/page.dart
       │         ├─ 背景：全屏封面 + 高斯模糊(sigma=120)
       │         ├─ 移动端：下滑手势关闭 + 底部下拉箭头
       │         ├─ 桌面端：AppBar 返回按钮 + 窗口拖拽区
       │         │
       │         ├─ _NowPlayingPage_Small（移动端布局）
       │         │    ├─ 顶部栏：下拉箭头 + 歌名 + 更多菜单
       │         │    ├─ 视图切换：封面 ↔ 歌词 ↔ 播放列表
       │         │    ├─ 专辑封面（响应式尺寸 220-380px）
       │         │    ├─ 歌曲信息（标题/副标题/音频元数据）
       │         │    ├─ 进度条 + 时间显示
       │         │    ├─ 播放控制（上一首/播放暂停/下一首）
       │         │    └─ 底部工具栏（播放模式/随机/歌词控制/更多）
       │         │
       │         └─ _NowPlayingPage_Large（桌面端布局）
       │              ├─ 左侧：封面 + 歌曲信息 + 播放控制
       │              └─ 右侧：歌词视图 或 播放列表视图
       │
       └─ 播放列表按钮 → showModalBottomSheet（DraggableScrollableSheet）
```

---

## 三、迷你播放器

**文件**：`lib/component/mini_now_playing.dart`（291行）

### 可见性控制

监听 `miniPlayerVisibleNotifier`（`ValueNotifier<bool>`，定义在 `app_shell.dart:26`）：

- **显示**：当前路由为 Shell 根页面（`/audios`、`/recent`、`/artists`、`/albums`、`/folders`、`/cloud`、`/playlists`、`/search`、`/settings`）
- **隐藏**：正在播放页、详情页等子页面

### 布局结构

```
┌──────────────────────────────────────────────────────┐
│ ▓▓▓▓▓▓▓▓▓▓▓▓ 进度条（RectangleProgressIndicator）▓▓ │
│ ┌────────────────────────────────────────────────┐  │
│ │ ┌──────┐  歌曲标题                    🎵  ⏵   │  │
│ │ │ 48×48 │  歌手 - 专辑名                        │  │
│ │ │ 封面  │                                       │  │
│ │ └──────┘                                       │  │
│ └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

| 区域 | 尺寸 | 说明 |
|------|------|------|
| 整体高度 | 64px | 移动端全宽，桌面端600px |
| 圆角 | 8px | `BorderRadius.circular(8)` |
| 阴影 | `kElevationToShadow[4]` | 悬浮阴影 |
| 进度条 | 外层 | `RectangleProgressIndicator` 显示播放进度 |
| 封面 | 48×48px | 圆角，通过 `FutureBuilder` 加载 `nowPlaying.cover` |
| 标题 | Text | `nowPlaying.title` |
| 副标题 | Text | `nowPlaying.subtitleText` |
| 播放列表按钮 | IconButton | `Symbols.queue_music`，打开底部播放列表 |
| 播放/暂停 | `IconButton.filled` | `StreamBuilder` 监听 `playerStateStream` |

### 播放列表底部弹窗

`_showPlaylistBottomSheet`（第81-167行）：

- 使用 `showModalBottomSheet` + `DraggableScrollableSheet`
- 初始高度60%，最小30%，最大90%
- 包含 `ListView` 显示播放队列
- 顶部"定位当前播放"按钮 + 曲目计数

### 位置

在 `app_shell.dart` 中，`MiniNowPlaying` 放置于 `Stack` 层，叠加在 `navigationShell` 之上：
- `_AppShell_Small`（第87行）
- `_AppShell_Large`（第110行）
- `_AppShell_Mobile`（第138行）

---

## 四、正在播放页面

**目录**：`lib/page/now_playing_page/`

### 文件结构

| 文件 | 行数 | 职责 |
|------|------|------|
| `page.dart` | 969 | 主页面 + 所有共享组件 + part 指令 |
| `small_page.dart` | 143 | 移动端布局（part of page.dart） |
| `large_page.dart` | 129 | 桌面端布局（part of page.dart） |
| `player_engine_indicator.dart` | 66 | 引擎标识（BASS/MediaKit）（part of page.dart） |
| `component/current_playlist_view.dart` | 110 | 播放列表面板 |
| `component/vertical_lyric_view.dart` | 268 | 垂直滚动歌词视图 |
| `component/lyric_view_controls.dart` | 263 | 歌词控制（对齐/字号/来源） |
| `component/lyric_view_tile.dart` | 429 | 单行歌词渲染（逐字同步） |
| `component/lyric_source_view.dart` | 535 | 歌词来源搜索/选择对话框 |
| `component/filled_icon_button_style.dart` | 99 | 播放控制按钮自定义样式 |

`page.dart` 使用 Dart `part`/`part of` 模式拆分，`small_page.dart`、`large_page.dart`、`player_engine_indicator.dart` 共享同一库作用域。

### 视图模式

**枚举**：`NowPlayingViewMode`（第35-46行）

| 模式 | 说明 |
|------|------|
| `onlyMain` | 仅显示专辑封面 + 歌曲信息 |
| `withLyric` | 显示垂直歌词视图 |
| `withPlaylist` | 显示当前播放列表 |

当前模式存储在全局 `ValueNotifier<NowPlayingViewMode>`（`NOW_PLAYING_VIEW_MODE`，第48行），通过 `AppPreference` 持久化。

---

## 五、页面背景

**代码位置**：`page.dart`（第114-155行）

```
Stack
  ├── Image (album cover, BoxFit.cover, 全屏)
  ├── Container (gradient: secondaryContainer + 黑色半透明)
  └── BackdropFilter (ImageFilter.blur(sigmaX: 120, sigmaY: 120))
```

使用全屏封面图 + 重高斯模糊（sigma=120）作为沉浸式背景，叠加双层渐变遮罩确保前景文字可读性。

---

## 六、移动端布局

**文件**：`small_page.dart`（143行）

### 页面结构

```
GestureDetector（下滑手势关闭）
  └─ Column
       ├── _NowPlayingMobileTopBar
       │    ├── 下拉箭头（↓，pop 路由）
       │    ├── 歌曲标题（居中）
       │    └── 更多菜单（⋮）
       │
       ├── 视图切换区域（Expanded）
       │    ├── onlyMain 模式：封面 + 歌曲信息
       │    ├── withLyric 模式：VerticalLyricView
       │    └── withPlaylist 模式：CurrentPlaylistView
       │
       ├── _NowPlayingSlider（进度条）
       │
       ├── _NowPlayingMainControls（播放控制）
       │
       └── 底部工具栏
            ├── 播放模式切换
            ├── 随机播放切换
            ├── 视图切换按钮
            └── 更多菜单
```

### 下滑关闭手势

`GestureDetector`（第174-231行）：

- `onVerticalDragUpdate`：跟手移动封面和控制区
- `onVerticalDragEnd`：偏移超过150px 或 速度超过500 → `context.pop()`；否则弹性回弹
- 使用 `AnimationController`（`_dismissAnimCtrl`）实现平滑回弹动画

### 顶部栏

`_NowPlayingMobileTopBar`（small_page.dart 第64-94行）：

```
┌──────────────────────────────────────┐
│  ↓    止战之殇                    ⋮  │
└──────────────────────────────────────┘
```

| 元素 | 功能 |
|------|------|
| ↓ 箭头 | `context.pop()`，关闭正在播放页 |
| 歌曲标题 | 居中显示 |
| ⋮ 更多 | 打开 `MenuAnchor` 菜单 |

### 视图切换按钮

`_NowPlayingMobileViewSwitchButton`（small_page.dart 第103-143行）：

循环切换：封面模式 → 歌词模式 → 播放列表模式 → 封面模式

---

## 七、桌面端布局

**文件**：`large_page.dart`（129行）

### 页面结构

```
Scaffold
  ├── AppBar（返回按钮 + 拖拽区 + 窗口控制按钮）
  └─ Row（Expanded）
       ├── 左侧面板（~50%宽度）
       │    ├── 专辑封面
       │    ├── 歌曲信息
       │    ├── 进度条
       │    ├── 播放控制
       │    └── 底部工具栏
       │
       └── 右侧面板（~50%宽度）
            ├── _NowPlayingLargeViewSwitch（歌词/播放列表切换）
            ├── withLyric 模式：VerticalLyricView
            └── withPlaylist 模式：CurrentPlaylistView
```

### AppBar

```dart
PreferredSize(
  preferredSize: Size.fromHeight(kToolbarHeight),
  child: Row([
    NavBackBtn,              // 返回按钮
    Expanded(DragToMoveArea), // 窗口拖拽区（Windows/Linux）
    WindowControls,          // 最小化/最大化/关闭（非 macOS）
  ]),
)
```

---

## 八、歌曲信息显示

**代码位置**：`page.dart` `_NowPlayingInfo`（第735-969行）

### 专辑封面

- 通过 `playbackService.nowPlaying?.largeCover` 加载
- 圆角 `ClipRRect(20px)`
- 响应式尺寸：`(availableWidth × 0.80).clamp(220.0, 380.0)`
- 无封面时显示占位图标（音乐符号 + 圆角容器）

### 标题区域

```
┌──────────────────────────────────────────┐
│          作词：方文山                      │  ← 标题（或当前歌词行）
│     止战之殇 - 周杰伦                      │  ← 副标题
│    FLAC · 1595kbps · 44.1kHz             │  ← 音频元数据
└──────────────────────────────────────────┘
```

| 区域 | 内容 | 说明 |
|------|------|------|
| 标题 | `AutoScrollText`（自动跑马灯） | 有歌词时显示当前歌词行，无歌词时显示歌名 |
| 副标题 | `AutoScrollText` | 有歌词时显示 "歌名 - 歌手"，否则显示 `subtitleText` |
| 元数据 | 格式 · 比特率 · 采样率 | 12px 灰色文本，如 "FLAC · 1595kbps · 44.1kHz" |

**歌词-标题联动**：当歌词激活时，标题区域显示当前歌词行（类似卡拉OK效果），副标题显示歌名和歌手。这是 `_NowPlayingInfo` 的核心交互设计。

---

## 九、播放控制

### 主控制栏

**代码位置**：`page.dart` `_NowPlayingMainControls`（第558-612行）

```
      ⏮         ⏵ / ⏸         ⏭
   (上一首)     (播放/暂停)     (下一首)
```

| 按钮 | 图标 | 操作 | 样式 |
|------|------|------|------|
| 上一首 | `Symbols.skip_previous` | `playbackService.lastAudio` | `LargeFilledIconButtonStyle(primary: false)` |
| 播放/暂停 | `Symbols.pause` / `Symbols.play_arrow` | 根据状态：播放中→暂停，已暂停→播放，已完成→重新播放 | `LargeFilledIconButtonStyle(primary: true)` |
| 下一首 | `Symbols.skip_next` | `playbackService.nextAudio` | `LargeFilledIconButtonStyle(primary: false)` |

播放/暂停使用 `StreamBuilder` 监听 `playerStateStream`，实时响应状态变化。

### 进度条

**代码位置**：`page.dart` `_NowPlayingSlider`（第615-732行）

```
 0:00:00 ──────────●────────────── 0:04:34
          ██████████░░░░░░░░░░░░░░░░
          当前进度        缓冲进度
```

- 嵌套 `StreamBuilder` 监听：时长、缓冲进度、播放状态、当前位置
- 支持拖拽 seek，拖拽时显示 `dragPosition`
- 时间格式：`Duration.toStringHMMSS()`

### 随机播放切换

**代码位置**：`page.dart` `_NowPlayingShuffleSwitch`（第535-555行）

- `Symbols.shuffle_on` / `Symbols.shuffle`
- 切换 `playbackService.useShuffle()`

### 播放模式切换

**代码位置**：`page.dart` `_NowPlayingPlayModeSwitch`（第492-533行）

```
顺序播放(forward) → 列表循环(loop) → 单曲循环(singleLoop)
    repeat           repeat_on        repeat_one_on
```

### 桌面端专属控件

| 控件 | 说明 | 位置 |
|------|------|------|
| 音量 DSP 滑块 | `MenuAnchor` + `Slider(0.0-1.0)` | page.dart 第418-490行 |
| 独占模式开关 | "Excl"/"Shrd" 文字切换（BASS引擎） | page.dart 第254-275行 |
| 桌面歌词开关 | 切换桌面浮动歌词窗口 | page.dart 第381-416行 |

---

## 十、歌词系统

### 垂直歌词视图

**文件**：`lib/page/now_playing_page/component/vertical_lyric_view.dart`（268行）

- 使用 `CustomScrollView` + `SliverFillRemaining` 上下填充（实现歌词居中）
- 当前行通过 `currentLyricTileKey`（GlobalKey）定位
- 自动滚动到当前行：`Scrollable.ensureVisible(alignment: 0.25)` — 当前行位于视口25%处
- 订阅 `lyricService.lyricLineStream` 实时更新
- 点击歌词行跳转到对应时间点
- 当前行100%不透明度，其他行30%不透明度

### 歌词行渲染

**文件**：`lib/page/now_playing_page/component/lyric_view_tile.dart`（429行）

#### 逐字同步歌词（KRC/QRC）

`_SyncLineContent`（第49行）使用 `ShaderMask` + `LinearGradient` 实现卡拉OK效果：

- 已唱部分：`scheme.primary`（主题色）
- 未唱部分：`scheme.primary.withOpacity(0.10)`（极淡主题色）
- 渐变停止点由 `positionMsStream` 驱动，实时跟踪播放位置

#### LRC 歌词

`_LrcLineContent`（第217行）：

- 按 "┃" 分隔符拆分（支持翻译对照）
- 纯文本渲染，无逐字高亮

#### 间奏动画

`LyricTransitionTile`（第308行）：

- 检测歌词行间隔 > 5秒判定为间奏
- 使用 `CustomPainter`（`LyricTransitionPainter`）绘制脉冲三点动画
- 由 `Ticker` 驱动

### 歌词控制

**文件**：`lib/page/now_playing_page/component/lyric_view_controls.dart`（263行）

| 控件 | 功能 | 说明 |
|------|------|------|
| `SetLyricSourceBtn` | 选择歌词来源 | 本地/在线/搜索 |
| `_LyricOffsetBtn` | 时间偏移调整 | ±0.1s 和 ±0.5s 步进 |
| `_LyricAlignSwitchBtn` | 对齐方式 | 左/中/右 循环切换 |
| `_IncreaseFontSizeBtn` | 增大字号 | — |
| `_DecreaseFontSizeBtn` | 缩小字号 | — |

`LyricViewController`（ChangeNotifier）管理 `lyricTextAlign`、`lyricFontSize`、`translationFontSize`，通过 `AppPreference` 持久化。

桌面端：歌词控件在鼠标悬停时显示（第41-43行）。
移动端：右下角浮动按钮切换显示/隐藏（`vertical_lyric_view.dart:94-121`）。

---

## 十一、更多菜单

**代码位置**：`page.dart` `_NowPlayingMoreAction`（第277-379行）

使用 `MenuAnchor` + `Symbols.more_vert` 图标：

| 菜单项 | 功能 | 目标 |
|--------|------|------|
| 艺术家（子菜单） | 列出当前曲目所有艺术家，点击跳转 | `ARTIST_DETAIL_PAGE` |
| 专辑 | 跳转专辑详情 | `ALBUM_DETAIL_PAGE` |
| 详细信息 | 查看音频元数据 | `AUDIO_DETAIL_PAGE` |
| 编辑标签 | 打开标签编辑对话框 | `EditTagDialog` |
| 刮削元数据 | 自动搜索元数据 | `EditTagDialog(autoSearch: true)` |

**注意**：当前实现中**没有**收藏/喜欢按钮和分享按钮。

---

## 十二、播放列表视图

### 正在播放页内

**文件**：`lib/page/now_playing_page/component/current_playlist_view.dart`（110行）

```
┌─────────────────────────────────────┐
│  播放列表          📍定位   12首曲目 │
├─────────────────────────────────────┤
│  1  ┌────┐  止战之殇        4:34    │
│     │ 40 │  周杰伦                   │
│     └────┘                          │
│  2  ┌────┐  爱情废柴          4:45  │
│     │ 40 │  周杰伦                   │
│     └────┘                          │
│  ...                                │
└─────────────────────────────────────┘
```

- 头部："播放列表" 标题 + `LocatePlayingButton`（定位当前播放）+ 曲目计数
- 列表项：`PlaylistAudioItem`（序号 + 封面40×40 + 标题/副标题 + 时长）
- 点击曲目：`playbackService.playIndexOfPlaylist(index)`
- 自动滚动到当前播放项

### 视图模式切换

| 平台 | 组件 | 切换方式 | 位置 |
|------|------|---------|------|
| 移动端 | `_NowPlayingMobileViewSwitchButton` | 循环：封面→歌词→播放列表 | small_page.dart 第103-143行 |
| 桌面端 | `_NowPlayingLargeViewSwitch` | 歌词/播放列表二选一切换 | large_page.dart 第92-128行 |

---

## 十三、迷你播放器 vs 正在播放页对比

| 特性 | 迷你播放器 | 正在播放页 |
|------|-----------|-----------|
| 封面尺寸 | 48×48px | 220-380px（响应式） |
| 歌曲信息 | 标题 + 副标题 | 标题 + 副标题 + 音频元数据 + 歌词联动 |
| 进度条 | 外层进度条（矩形） | 完整 Slider + 时间显示 + 缓冲进度 |
| 播放控制 | 仅播放/暂停 | 上一首 + 播放/暂停 + 下一首 |
| 歌词 | 无 | 垂直滚动 + 逐字同步 + 间奏动画 |
| 播放列表 | 底部弹窗（DraggableScrollableSheet） | 内嵌面板（随视图模式切换） |
| 更多操作 | 无 | 艺术家/专辑/详情/编辑标签/刮削 |
| 关闭方式 | — | 下滑手势 / 返回按钮 |
| 桌面专属 | 无 | 音量DSP / 独占模式 / 桌面歌词 |

---

## 十四、架构设计要点

### 1. part/part of 拆分模式

`page.dart`（969行）通过 Dart 的 `part` 指令拆分为4个文件，共享同一库作用域。这使得各布局文件可以自由访问 `page.dart` 中定义的私有类和方法，无需暴露公共 API。

### 2. 全局 ValueNotifier 状态管理

视图模式使用全局 `ValueNotifier<NowPlayingViewMode>`（`NOW_PLAYING_VIEW_MODE`），而非 Provider 或 Bloc。这简化了跨组件通信，但增加了全局状态耦合。

### 3. StreamBuilder 响应式播放状态

播放控制广泛使用 `StreamBuilder` 监听 `playerStateStream`、`positionStream`、`durationStream`，实现毫秒级实时更新。

### 4. 歌词-标题联动

标题区域在歌词激活时显示当前歌词行，这是一种紧凑的信息展示策略：在不增加额外UI空间的情况下，让用户同时感知歌名和歌词进度。

### 5. 双布局响应式

`ResponsiveBuilder2` 根据屏幕尺寸自动切换移动端/桌面端布局，而非使用断点手动判断。

### 6. 手势关闭机制

移动端的下滑关闭使用 `GestureDetector` + `AnimationController`，150px 阈值或 500 速度阈值，配合弹性回弹动画，符合 iOS 风格的交互范式。

---

## 十五、发现的架构问题

### 问题1：缺少收藏/喜欢功能

`_NowPlayingMoreAction` 菜单和页面底部工具栏中均无收藏/喜欢按钮。这是音乐播放器的常见核心功能。

### 问题2：缺少分享功能

无分享按钮或分享到社交媒体的入口。

### 问题3：page.dart 体量过大

`page.dart` 达 969 行（不含 part 文件），包含主页面、所有共享组件（信息展示、播放控制、进度条、更多菜单、音量控制等）。虽然通过 `part` 拆分了布局，但逻辑层仍集中在单文件中。

### 问题4：歌词控件移动端隐藏过深

移动端歌词控件需要点击右下角浮动按钮才能显示，首次使用的用户可能难以发现。建议在歌词模式下默认短暂显示后淡出。

### 问题5：进度条缺少精确拖拽预览

`_NowPlayingSlider` 在拖拽时不显示精确时间预览（如弹出气泡显示目标时间），仅通过下方固定时间文本间接指示。

### 问题6：无歌词时的视觉反馈

当歌曲无歌词时，切换到歌词视图仅显示空白区域，无"暂无歌词"提示或引导用户搜索歌词的入口。

---

## 十六、关键文件索引

### 主页面

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/page/now_playing_page/page.dart` | 969 | 主页面 + 所有共享组件 |
| `lib/page/now_playing_page/small_page.dart` | 143 | 移动端布局 |
| `lib/page/now_playing_page/large_page.dart` | 129 | 桌面端布局 |
| `lib/page/now_playing_page/player_engine_indicator.dart` | 66 | 引擎标识（BASS/MK） |

### 歌词组件

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/page/now_playing_page/component/vertical_lyric_view.dart` | 268 | 垂直滚动歌词视图 |
| `lib/page/now_playing_page/component/lyric_view_tile.dart` | 429 | 单行歌词渲染（逐字同步） |
| `lib/page/now_playing_page/component/lyric_view_controls.dart` | 263 | 歌词控制（对齐/字号/来源） |
| `lib/page/now_playing_page/component/lyric_source_view.dart` | 535 | 歌词来源搜索/选择 |

### 其他组件

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/page/now_playing_page/component/current_playlist_view.dart` | 110 | 播放列表面板 |
| `lib/page/now_playing_page/component/filled_icon_button_style.dart` | 99 | 播放控制按钮样式 |
| `lib/component/mini_now_playing.dart` | 291 | 迷你播放器（底部悬浮） |
| `lib/component/playlist_audio_item.dart` | — | 播放列表曲目项组件 |
| `lib/component/horizontal_lyric_view.dart` | — | 水平歌词视图（备用） |
