# 艺术家页面 UI 实现分析

> 分析日期：2026-06-09
> 项目：Coriander Player（Flutter 跨平台音乐播放器）

---

## 一、路由结构

### 路径常量

**文件**：`lib/app_paths.dart`

| 常量名 | 路径值 | 说明 |
|--------|--------|------|
| `ARTISTS_PAGE` | `/artists` | 艺术家列表页 |
| `ARTIST_DETAIL_PAGE` | `/artists/detail` | 艺术家详情页 |

`ARTISTS_PAGE` 被包含在 `START_PAGES` 列表中，意味着艺术家页面可被配置为应用启动页。

### GoRouter 路由定义

**文件**：`lib/entry.dart`（第170-184行）

```dart
StatefulShellBranch(routes: [
  GoRoute(
    path: app_paths.ARTISTS_PAGE,          // "/artists"
    pageBuilder: (context, state) => const SlideTransitionPage(
      child: ArtistsPage(),
    ),
    routes: [
      GoRoute(
        path: "detail",                     // 解析为 "/artists/detail"
        builder: (context, state) =>
            ArtistDetailPage(artist: state.extra as Artist),
      ),
    ],
  ),
]),
```

**要点**：

- 艺术家分支是 `StatefulShellRoute.indexedStack` 的**第3个分支**（index 2），顺序必须与 `side_nav.dart` 中 `destinations` 列表对应
- 列表页使用 `SlideTransitionPage`（自定义 `CustomTransitionPage`），垂直上滑动画，150ms，`Curves.fastOutSlowIn`
- 详情页作为子路由嵌套，通过 `state.extra` 接收 `Artist` 对象，无路径参数
- 详情页使用普通 `builder`（非 `pageBuilder`），继承 GoRouter 默认页面过渡动画

---

## 二、完整页面链路

```
侧边栏 "艺术家" (index 2)
  └─ ArtistsPage                        ← lib/page/artists_page.dart
       └─ UniPage<Artist>               ← lib/page/uni_page.dart（通用列表组件）
            └─ ArtistTile               ← lib/component/artist_tile.dart
                 └─ onTap → push /artists/detail
                      └─ ArtistDetailPage   ← lib/page/artist_detail_page.dart
                           └─ UniDetailPage<Artist, Audio, Album>  ← lib/page/uni_detail_page.dart
                                ├─ SliverAppBar（磨砂玻璃效果 + 折叠大标题）
                                ├─ Hero 区（圆形头像 + 高斯模糊背景）
                                ├─ 曲目列表（AudioTile）
                                └─ 专辑列表（ListTile → 跳转专辑详情）
```

---

## 三、艺术家列表页

**文件**：`lib/page/artists_page.dart`（63行）

### 数据源

```dart
AudioLibrary.instance.artistCollection.values.toList()
```

通过 `ListenableBuilder` 监听 `AudioLibrary.instance`，库数据变化时自动刷新列表。

### 配置项

| 属性 | 值 | 说明 |
|------|-----|------|
| `title` | "艺术家" | 页面标题 |
| `subtitle` | "${contentList.length} 位艺术家" | 动态显示数量 |
| `enableShufflePlay` | `false` | 不支持随机播放 |
| `enableSortMethod` | `true` | 支持排序方式切换 |
| `enableSortOrder` | `true` | 支持排序方向切换 |
| `enableContentViewSwitch` | `true` | 支持列表/网格视图切换 |

### 排序方式

1. **按名称**：`a.name.localeCompareTo(b.name)` — 字母序
2. **按作品数量**：`a.works.length.compareTo(b.works.length)` — 作品数

### UniPage 通用列表组件

**文件**：`lib/page/uni_page.dart`

该组件被 `ArtistsPage`、`AlbumsPage`、`FoldersPage`、`AudiosPage` 等多个页面复用，核心能力：

- **两种视图模式**：`ContentView.list`（`ListView.builder`，64px `itemExtent`）和 `ContentView.table`（`GridView.builder`，最大300px）
- **多选控制器**：`MultiSelectController<T>` 提供 `select`、`unselect`、`clear`、`selectAll`、`selectRange`、`lastSelectedIndex`（shift-click 范围选择）
- **动作栏**：排序方式组合框、排序方向开关、视图切换按钮、随机播放按钮

---

## 四、艺术家详情页

**文件**：`lib/page/artist_detail_page.dart`（119行）

### 页面结构

委托给 `UniDetailPage<Artist, Audio, Album>`，采用三层内容模型 `P(主图) → S(曲目) → T(关联项)`。

| 区域 | 组件 | 说明 |
|------|------|------|
| Hero 区 | `_AlbumInfoSection` | 圆形头像（`ClipOval`，移动端120px / 桌面端180px） |
| 背景 | 高斯模糊 | `BackdropFilter` sigma=50，叠加明暗遮罩 |
| 副标题 | 文本 | "${artist.works.length} 首作品" |
| 曲目列表 | `AudioTile` × N | 支持多选、排序 |
| 专辑列表 | `ListTile` × N | 三级内容，点击跳转专辑详情页 |

### 排序方式（4种）

1. 按标题（`title`）
2. 按专辑名（`albumName`）
3. 按创建时间（`createdTime`）
4. 按修改时间（`modifiedTime`）

### 多选操作

- `AddAllToPlaylist`：添加全部到播放列表
- `MultiSelectSelectOrClearAll`：全选/取消全选
- `MultiSelectExit`：退出多选模式

### UniDetailPage 通用详情页组件

**文件**：`lib/page/uni_detail_page.dart`（547行）

布局结构（Sliver 体系）：

1. **SliverAppBar**（第174-208行）：固定顶栏，磨砂玻璃效果（`surface.withValues(alpha: 0.85)`），返回按钮（filled tonal 样式），标题文本，"更多"按钮
2. **大标题**（第211-223行）：滚动时折叠，移动端28px / 桌面端32px
3. **信息区**（第226-237行）：`_AlbumInfoSection`，含封面图、背景模糊、操作按钮
4. **二级内容**（第240-263行）：`SliverFixedExtentList.builder`（列表模式，64/72px）或 `SliverGrid.builder`（网格模式）
5. **三级内容标题**（第266-279行）：仅在三级内容非空时显示
6. **三级内容列表**（第282-290行）：`SliverList.builder`
7. **字母索引**（第298-313行）：仅移动端，右侧定位（**当前为空实现**）

---

## 五、长按与右键菜单行为

### AudioTile 长按

**文件**：`lib/component/audio_tile.dart`（第291-309行）

```dart
onLongPress: () {
  if (widget.multiSelectController == null) return;
  if (PlatformHelper.isMobile) {
    _showMobileContextMenu(context, audio);    // 移动端底部菜单
  } else {
    // 桌面端：激活多选并选中当前项
    if (!widget.multiSelectController!.enableMultiSelectView) {
      widget.multiSelectController!.useMultiSelectView(true);
    }
    widget.multiSelectController!.selectAtIndex(audio, widget.audioIndex);
    HapticFeedback.mediumImpact();
  }
},
```

**移动端底部菜单**（`_showMobileContextMenu`，第528-632行）包含：

| 菜单项 | 功能 |
|--------|------|
| 下一首播放 | 将曲目加入播放队列下一位 |
| 多选 | 进入多选模式 |
| 详细信息 | 查看曲目元数据详情 |
| 编辑标签 | 编辑曲目标签信息 |
| 刮削元数据 | 从在线源获取曲目元数据 |
| 从音乐库移除 | 从本地库中删除该曲目引用 |

**桌面端右键菜单**（`MenuAnchor`，第78-233行）包含：

- "艺术家"子菜单（列出该音频的所有 `splitedArtists`，点击跳转艺术家详情）
- "专辑"跳转
- 下一首播放
- 多选
- 添加到播放列表
- 详细信息
- 编辑标签
- 刮削元数据
- 从音乐库移除

### ArtistTile / AlbumTile

| 组件 | 长按 | 右键 | 多选 | 文件 |
|------|------|------|------|------|
| `ArtistTile` | **无** | **无** | **不支持** | `lib/component/artist_tile.dart`（69行） |
| `AlbumTile` | **无** | **无** | **不支持** | `lib/component/album_tile.dart`（70行） |

两者仅使用 `InkWell` 的 `onTap` 进行导航跳转，无任何长按或上下文菜单交互。

---

## 六、进入艺术家详情页的5条路径

| 路径 | 入口 | 触发方式 | 涉及文件 |
|------|------|---------|---------|
| **A** | 侧边栏 → 艺术家列表 → ArtistTile | 点击 | `artist_tile.dart:29` |
| **B** | 音频右键/长按菜单 → "艺术家"子菜单 | 选择艺术家名 | `audio_tile.dart:89` |
| **C** | 正在播放页 → 更多菜单 → "艺术家"子菜单 | 选择艺术家名 | `now_playing_page/page.dart:304` |
| **D** | 专辑详情页 → 三级内容（艺术家列表） | 点击 ListTile | `album_detail_page.dart:42` |
| **E** | 搜索结果 → 艺术家标签页 → ArtistTile | 点击 | `search_result_page.dart:170` |

**统一导航方式**：所有路径均使用 `context.push(app_paths.ARTIST_DETAIL_PAGE, extra: artist)`。

---

## 七、Artist 数据模型

**文件**：`lib/library/audio_library.dart`（第597-612行）

```dart
class Artist {
  String name;
  Map<String, Album> albumsMap = {};   // 该艺术家的所有专辑
  List<Audio> works = [];              // 该艺术家的所有曲目

  Future<ImageProvider?> get picture =>  // 200×200，用于详情页头像
      works.first._getResizedPic(width: 200, height: 200);

  Artist({required this.name});
}
```

`picture` getter 延迟生成 200×200 图像，取自该艺术家第一首曲目的封面。

---

## 八、ArtistTile 组件详解

**文件**：`lib/component/artist_tile.dart`（69行）

```
┌──────────────────────────────────────┐
│  ┌──────┐                            │
│  │ 48×48 │  艺术家名称               │
│  │ 圆形  │  （maxLines: 2）          │
│  │ 封面  │                            │
│  └──────┘                            │
└──────────────────────────────────────┘
```

- 封面：`ClipOval`（圆形），48×48px，通过 `FutureBuilder` 从 `artist.works.first.cover` 加载
- 名称：`Text`，`maxLines: 2`，`softWrap: false`
- 交互：仅 `InkWell.onTap` → `context.push(ARTIST_DETAIL_PAGE, extra: artist)`
- 无长按、无右键菜单、无多选支持

---

## 九、发现的架构问题

### 问题1：移动端底部导航不含"艺术家"

**位置**：`lib/component/side_nav.dart:100`

```dart
_mobileNavBranchMapping = [0, 1, 5, 7, 8]
// 对应：音乐库, 最近播放, 连接(Cloud), 搜索, 设置
// 艺术家 (index 2) 不在其中
```

**影响**：移动用户只能通过抽屉菜单或搜索进入艺术家页面，路径较深。

---

### 问题2：字母索引未实现

**位置**：`lib/page/uni_detail_page.dart:309`

```dart
onIndexChanged: (index) {
  // 滚动到对应位置    ← 空函数体
},
```

**影响**：移动端右侧的字母索引栏虽然渲染，但点击无任何效果，属于视觉占位。

---

### 问题3：详情页"更多"按钮无功能

**位置**：`lib/page/uni_detail_page.dart:205`

```dart
onPressed: () {}    // 空实现
```

**影响**：SliverAppBar 右侧的"更多"按钮点击无响应，用户预期有操作但无反馈。

---

### 问题4：两个专辑详情页并存

| 实现 | 文件 | 是否使用 UniDetailPage | 艺术家交叉导航 | 多选支持 |
|------|------|----------------------|---------------|---------|
| `AlbumDetailPage`（旧版） | `lib/page/album_detail_page.dart` | 是 | 有 | 有 |
| `AlbumDetailPageNew`（新版） | `lib/page/album_detail_page_new.dart` | 否（535行独立实现） | **无** | **无** |

**路由实际指向**：`AlbumDetailPageNew`（`entry.dart:195`）

**影响**：
- 旧版的三级内容中包含艺术家 `ListTile`，可跳转艺术家详情
- 新版完全独立实现，无艺术家交叉导航能力
- 两个文件并存增加维护成本

---

### 问题5：ArtistTile / AlbumTile 交互能力不足

与 `AudioTile` 的丰富交互对比：

| 能力 | AudioTile | ArtistTile | AlbumTile |
|------|-----------|------------|-----------|
| 点击导航 | ✅ | ✅ | ✅ |
| 长按菜单 | ✅ | ❌ | ❌ |
| 右键菜单 | ✅ | ❌ | ❌ |
| 多选支持 | ✅ | ❌ | ❌ |
| 子菜单跳转 | ✅（艺术家/专辑） | — | — |

**影响**：用户无法对艺术家/专辑进行批量操作（如多选添加到播放列表），也无法快速访问上下文操作。

---

### 问题6：Artist 数据模型缺少缓存/懒加载

```dart
Future<ImageProvider?> get picture =>
    works.first._getResizedPic(width: 200, height: 200);
```

每次访问 `picture` 都重新生成 200×200 图像，无缓存机制。在艺术家列表页滑动时可能造成重复计算。

---

## 十、关键文件索引

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/app_paths.dart` | — | 路由路径常量定义 |
| `lib/entry.dart` | — | GoRouter 路由配置、Provider 注册 |
| `lib/page/artists_page.dart` | 63 | 艺术家列表页，委托 UniPage |
| `lib/page/artist_detail_page.dart` | 119 | 艺术家详情页，委托 UniDetailPage |
| `lib/page/uni_page.dart` | ~310 | 通用列表页组件（多选、排序、视图切换） |
| `lib/page/uni_detail_page.dart` | 547 | 通用详情页组件（SliverAppBar、三层内容模型） |
| `lib/component/artist_tile.dart` | 69 | 艺术家列表项组件（仅 onTap） |
| `lib/component/album_tile.dart` | 70 | 专辑列表项组件（仅 onTap） |
| `lib/component/audio_tile.dart` | ~630 | 音频列表项组件（长按、右键、多选） |
| `lib/library/audio_library.dart` | — | Artist / Album / Audio 数据模型 |
| `lib/component/side_nav.dart` | — | 侧边栏 / 底部导航栏 |
