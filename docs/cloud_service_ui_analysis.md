# 云服务连接与云文件预览页面 UI 实现分析

> 分析日期：2026-06-09
> 项目：Coriander Player（Flutter 跨平台音乐播放器）

---

## 一、路由结构

### 路径常量

**文件**：`lib/app_paths.dart`（第32-33行）

| 常量名 | 路径值 | 说明 |
|--------|--------|------|
| `CLOUD_CONNECTIONS_PAGE` | `/cloud` | 云服务连接列表页 |
| `CLOUD_BROWSER_PAGE` | `/cloud/browser` | 云文件浏览器（实际解析为 `/cloud/browser/:connectionId`） |

`CLOUD_CONNECTIONS_PAGE` 被包含在 `START_PAGES` 列表中，可作为应用启动页。

### GoRouter 路由定义

**文件**：`lib/entry.dart`（第218-239行）

```dart
StatefulShellBranch(routes: [
  GoRoute(
    path: app_paths.CLOUD_CONNECTIONS_PAGE,        // "/cloud"
    pageBuilder: (context, state) => const SlideTransitionPage(
      child: CloudConnectionsPage(),
    ),
    routes: [
      GoRoute(
        path: "browser/:connectionId",
        builder: (context, state) {
          final args = state.extra as CloudBrowserArgs?;
          return CloudFileBrowser(
            connectionId: state.pathParameters['connectionId']!,
            initialPath: args?.initialPath ?? '',
            locateToPath: args?.locateToPath,
          );
        },
      ),
    ],
  ),
]),
```

**要点**：

- 云服务分支是 `StatefulShellRoute.indexedStack` 的**第6个分支**（index 5）
- 列表页使用 `SlideTransitionPage`（垂直上滑动画，150ms）
- 文件浏览器通过路径参数 `:connectionId` 识别连接，通过 `state.extra` 传递可选的 `CloudBrowserArgs`（初始路径 + 定位路径）
- `CloudServiceManager` 通过 `ChangeNotifierProvider` 在 `Entry` 组件中注入（`entry.dart:110`），全局可用

---

## 二、完整页面链路

```
底部导航栏 "连接" (index 2)
  └─ CloudConnectionsPage              ← lib/page/cloud_service/cloud_connections_page.dart
       ├─ 空状态（暂无云服务连接）
       └─ 连接列表（ListView.builder）
            └─ Card > ListTile（每个 WebDAV 连接）
                 ├─ onTap → context.push('/cloud/browser/${connection.id}')
                 └─ PopupMenuButton
                      ├─ "浏览文件" → context.push('/cloud/browser/${connection.id}')
                      ├─ "编辑连接" → showDialog(CloudConnectionForm)
                      ├─ "测试连接" → service.testConnection()
                      └─ "删除连接" → showDialog(AlertDialog) → manager.removeConnection()
                           └─ CloudFileBrowser             ← lib/page/cloud_service/cloud_file_browser.dart
                                ├─ 面包屑导航栏（路径 + 搜索/定位/更多）
                                ├─ 文件列表（ListView / GridView 双模式）
                                │    ├─ 目录 → 递归进入子目录
                                │    ├─ 音频文件 → CloudAudioPlayer.playCloudFile()
                                │    ├─ 图片文件 → showDialog(InteractiveViewer)
                                │    └─ 右键/长按菜单（播放/添加到播放列表/添加到音乐库/下载等）
                                └─ 多选模式（长按进入，批量操作）
```

---

## 三、导航入口

### 侧边栏（桌面端）

**文件**：`lib/component/side_nav.dart`（第25行）

```dart
DestinationDesc(Symbols.cloud, "连接", app_paths.CLOUD_CONNECTIONS_PAGE),
```

### 底部导航栏（移动端）

**文件**：`lib/component/side_nav.dart`（第100-109行）

底部导航栏映射 `_mobileNavBranchMapping = [0, 1, 5, 7, 8]`，其中 index 2 → destinations[5]（"连接"）。

### AppShell 布局

**文件**：`lib/component/app_shell.dart`

三种响应式布局：

| 布局 | 组件 | 适用场景 |
|------|------|---------|
| `_AppShell_Small` | 侧边栏（折叠） | 小屏桌面 |
| `_AppShell_Large` | 侧边栏（展开） | 大屏桌面 |
| `_AppShell_Mobile` | 底部导航栏 | 移动端 |

所有布局均渲染 `navigationShell`（`StatefulNavigationShell`）+ `MiniNowPlaying` 悬浮层。

---

## 四、云服务连接列表页

**文件**：`lib/page/cloud_service/cloud_connections_page.dart`（331行）

### 数据源

通过 `Consumer<CloudServiceManager>` 监听连接列表变化，自动重建 UI。

### 空状态

当无连接时，显示居中的 `cloud_off` 图标 + "暂无云服务连接" 文本。

### 连接列表项

每个连接渲染为 `Card` > `ListTile`：

```
┌─────────────────────────────────────────────┐
│  ☁️~~  │ 连接名称（displayName ?? name）       │
│ (波形) │ WebDAV · http://example.com:5244/dav │
│        │ 上次同步：2026-06-09 10:30            │     ⋮ │
└─────────────────────────────────────────────┘
```

| 区域 | 内容 | 说明 |
|------|------|------|
| Leading | 云图标 + `PlayingIndicatorOverlay` | 当前播放连接显示波形动画 |
| Title | `connection.displayName ?? connection.name` | 连接名称 |
| Subtitle | 服务类型 + 服务器 URL + 上次同步时间 | 三行信息 |
| Trailing | `PopupMenuButton` | 4个操作选项 |
| onTap | 导航到文件浏览器 | `context.push('/cloud/browser/${connection.id}')` |

### PopupMenuButton 操作

| 菜单项 | 功能 | 视觉样式 |
|--------|------|---------|
| 浏览文件 | 跳转云文件浏览器 | 默认 |
| 编辑连接 | 弹出 `CloudConnectionForm` 对话框 | 默认 |
| 测试连接 | 发送 HTTP HEAD 请求验证连通性 | 默认 |
| 删除连接 | 确认对话框 → 移除连接 | 红色文字 |

### "定位正在播放"功能

`_locatePlayingConnection` 方法计算当前播放云音频的父目录路径，通过 `CloudBrowserArgs(dirPath, playingPath)` 传递给文件浏览器，自动滚动到播放中的文件。

---

## 五、云文件浏览器

**文件**：`lib/page/cloud_service/cloud_file_browser.dart`（1600行）

这是云服务模块最核心的页面，实现了一个功能完整的文件浏览器。

### 状态管理

```dart
class _CloudFileBrowserState extends State<CloudFileBrowser> {
  String _currentPath;              // 当前 WebDAV 目录路径
  Future<List<WebDavFile>>? _filesFuture;  // 文件列表 Future
  List<WebDavFile> _currentFiles;   // 缓存的文件列表
  Set<String> _selectedFiles;       // 多选：已选文件路径集合
  Set<String> _hoveredPaths;        // 桌面端：悬停高亮路径
  bool _isSelectionMode = false;    // 多选模式开关
  FileViewMode _viewMode;           // 列表/网格视图
  FileSortBy _sortBy;               // 排序字段
  FileSortOrder _sortOrder;         // 排序方向
  String _searchQuery;              // 搜索关键词
  bool _isSearching = false;        // 搜索模式开关
}
```

### 页面结构

```
Material > SafeArea > Column
  ├── 面包屑导航栏（_buildBreadcrumb）
  │    ├── ← 返回按钮
  │    ├── 连接名称 > 目录1 > 目录2 > ...（路径段）
  │    └── 🔍 搜索 | 📍 定位播放 | ✕ 取消多选 | ⋮ 更多
  └── Expanded > FutureBuilder
       ├── 加载中：CircularProgressIndicator
       ├── 错误：错误文本
       └── 数据：_buildContent(files)
            ├── 列表模式：ListView.builder（64px itemExtent）
            └── 网格模式：LayoutBuilder + Wrap（响应式列数）
```

### 文件列表项 — 列表模式

**方法**：`_buildFileItem`（第538-676行）

```
┌──────────────────────────────────────────────────┐
│  1  │ 📁  │ 文件夹名称                      │  ⋮  │
│     │     │ 文件夹                           │     │
├──────────────────────────────────────────────────┤
│  2  │ 🎵~~│ 歌曲名称.flac                   │  ⋮  │
│     │     │ 64.8 MB · 2026-06-01            │     │
├──────────────────────────────────────────────────┤
│  3  │ 🖼️  │ album_cover.jpg                 │  ⋮  │
│     │     │ 2.1 MB · 2026-05-20             │     │
└──────────────────────────────────────────────────┘
```

| 区域 | 内容 | 说明 |
|------|------|------|
| 序号 | `index + 1` | 从1开始的行号 |
| 图标 | 文件类型图标 + `PlayingIndicatorOverlay` | 正在播放显示波形 |
| 信息 | 文件名（主）+ 大小·日期（副） | 副标题灰色 |
| 尾部 | `PopupMenuButton` 或 `Checkbox` | 多选模式切换 |

### 文件列表项 — 网格模式

**方法**：`_buildGridItem`（第365-487行）

```
┌─────────────┐
│   55×55     │
│  📁 / 🎵   │  ← 图标区（含可选复选框/菜单按钮）
│             │
│ 文件名称    │  ← 文件名（maxLines: 2）
└─────────────┘
```

- 响应式列数：`LayoutBuilder` 根据屏幕宽度计算，每列最小200px
- 视觉状态：选中（`secondaryContainer` 背景）、悬停（半透明背景）、播放中（`primary` 颜色文件名）

### 长按行为

| 平台 | 触发方式 | 行为 |
|------|---------|------|
| 移动端 | `onLongPress` | 进入多选模式 + 选中当前项 |
| 桌面端 | `onLongPress` | 进入多选模式 + 选中当前项 |
| 桌面端 | `onHover` | 高亮悬停项背景 |

**注意**：移动端和桌面端的长按行为相同，均进入多选模式。桌面端额外支持悬停高亮。

### 右键/更多菜单

**列表菜单**：`_buildListMenuButton`（第695-719行）
**网格菜单**：`_buildGridMenuButton`（第504-534行）

| 菜单项 | 适用文件类型 | 功能 |
|--------|------------|------|
| 播放 | 音频文件 | 调用 `CloudAudioPlayer.playCloudFile` |
| 添加到播放列表 | 音频文件 | 递归扫描目录后添加 |
| 添加到音乐库 | 音频文件 | 读取元数据后添加到本地库 |
| 预览图片 | 图片文件 | 打开全屏对话框 + `InteractiveViewer` |
| 扫描到音乐库 | 目录 | 递归扫描目录中所有音频 |
| 下载 | 所有文件 | 下载到本地下载目录 |

### 面包屑导航栏

**方法**：`_buildBreadcrumb`（第789-1123行）

```
┌─────────────────────────────────────────────────────────┐
│ ← │ 测试音乐 > 歌单 > B站宝宝哄睡神曲    🔍  📍  ⋮    │
└─────────────────────────────────────────────────────────┘
```

- 左侧返回按钮：返回上一级目录，根目录时 pop 路由
- 路径段：连接名 > 目录1 > 目录2，每段可点击跳转
- 右侧工具栏：搜索、定位播放文件、取消多选（多选模式下）、更多菜单

### 面包屑"更多"菜单

**方法**：面包屑中第929-1029行

| 菜单项 | 功能 |
|--------|------|
| 视图切换 | 列表模式 ↔ 网格模式 |
| 排序：名称 | 按文件名排序（显示升降序指示） |
| 排序：大小 | 按文件大小排序 |
| 排序：修改时间 | 按最后修改时间排序 |
| 排序：类型 | 按文件类型排序 |
| 扫描到音乐库 | 扫描当前目录到本地库 |
| 添加到播放列表 | 添加当前目录音频到播放列表 |
| 添加选中到音乐库 | 仅多选模式下显示 |

### 文件加载与排序

**文件加载**（第111-119行）：

```dart
Future<void> _loadFiles() async {
  final manager = context.read<CloudServiceManager>();
  final service = manager.getService(widget.connectionId);
  _filesFuture = service.listFiles(_currentPath);
}
```

**排序逻辑**（第121-149行）：

1. 目录始终排在文件前面
2. 按选中的 `FileSortBy` 字段排序（名称/大小/修改时间/类型）
3. 支持升降序切换

**搜索/过滤**（第152-156行）：

大小写不敏感的子串匹配，实时过滤当前目录文件列表。

### 音频播放

**方法**：`_playAudio`（第1212-1239行）

调用 `CloudAudioPlayer.playCloudFile`，传入：
- `WebDavService` 实例
- 文件路径和文件名
- 当前目录所有音频文件作为播放列表

播放策略取决于引擎：
- **mediaKit**：直接 URL 流式播放（无需下载）
- **BASS**：需先下载到临时目录再播放

### 图片预览

**方法**：图片预览对话框（第1127-1174行）

打开全屏 `Dialog`，包含 `AppBar`（标题为文件名）和 `InteractiveViewer`（支持缩放/平移），通过 `Image.network` + 认证头加载图片。

### 图片缩略图

**方法**：`_buildImageThumbnail`（第723-785行）

从 WebDAV 加载图片缩略图，显示加载进度和错误回退。

### 内部对话框

| 对话框 | 文件行号 | 功能 |
|--------|---------|------|
| `_ScanToLibraryDialog` | 第1453-1526行 | 显示扫描进度，调用 `CloudAudioPlayer.addCloudFolderToLibrary` |
| `_AddToLibraryDialog` | 第1528-1599行 | 显示添加进度，调用 `CloudAudioPlayer.addCloudFilesToLibrary` |

---

## 六、连接表单

**文件**：`lib/page/cloud_service/cloud_connection_form.dart`（262行）

### 表单字段

| 字段 | 类型 | 必填 | 校验规则 |
|------|------|------|---------|
| 连接名称 | `TextFormField` | 是 | 非空 |
| 显示名称 | `TextFormField` | 否 | — |
| 服务器地址 | `TextFormField` | 是 | 必须以 `http` 开头 |
| 用户名 | `TextFormField` | 是 | 非空 |
| 密码 | `TextFormField`（obscured） | 是 | 非空 |

### 操作按钮

| 按钮 | 功能 |
|------|------|
| 取消 | 关闭对话框 |
| 测试连接 | 创建临时 `WebDavService` → `service.testConnection()` |
| 保存 | 创建/更新 `CloudConnection` → `manager.addConnection/updateConnection` |

新连接 ID 使用 `DateTime.now().millisecondsSinceEpoch.toString()` 生成。

---

## 七、状态管理 — CloudServiceManager

**文件**：`lib/cloud_service/cloud_service_manager.dart`（271行）

### 类结构

```dart
class CloudServiceManager extends ChangeNotifier {
  static CloudServiceManager? _instance;
  List<CloudConnection> _connections = [];
  Map<String, WebDavService> _services = {};  // 缓存的 Service 实例
  Completer<void> _readyCompleter = Completer<void>();
}
```

### 密码存储策略

采用**双存储策略**（第39-127行）：

1. **主存储**：`FlutterSecureStorage`（加密存储，平台特定）
2. **回退存储**：`SharedPreferences`（JSON Map: `{connectionId: password}`）

加载时自动从 SharedPreferences 迁移到 SecureStorage。

### 连接 CRUD

| 方法 | 功能 | 行号 |
|------|------|------|
| `addConnection` | 添加连接（去除同ID旧连接），保存并通知 | 第204行 |
| `updateConnection` | 按索引替换连接，保存并通知 | 第211行 |
| `removeConnection` | 移除连接和缓存的Service，删除密码，保存并通知 | 第220行 |
| `clearAllConnections` | 清空所有连接 | 第236行 |

### Service 工厂

```dart
WebDavService getService(String connectionId) {
  return _services.putIfAbsent(connectionId, () {
    final conn = _connections.firstWhere((c) => c.id == connectionId);
    return WebDavService(
      serverUrl: conn.serverUrl,
      username: conn.username,
      password: _passwords[connectionId] ?? conn.password,
    );
  });
}
```

懒初始化 + 缓存，同一连接ID只创建一次 Service 实例。

---

## 八、WebDAV 协议客户端

**文件**：`lib/cloud_service/webdav_service.dart`（401行）

### WebDavFile 模型

```dart
class WebDavFile {
  String path;          // 完整路径
  String name;          // 文件/目录名
  bool isDirectory;     // 是否为目录
  int size;             // 文件大小（字节）
  DateTime lastModified;// 最后修改时间
  String? contentType;  // MIME 类型
}
```

### 核心方法

| 方法 | HTTP 方法 | 功能 | 行号 |
|------|----------|------|------|
| `testConnection` | HEAD | 验证服务器连通性 | 第55行 |
| `listFiles` | PROPFIND (Depth:1) | 列出目录内容，解析 XML 响应 | 第70行 |
| `downloadFile` | GET | 完整下载文件 | 第267行 |
| `downloadRange` | GET (Range) | 分段下载（用于元数据读取） | 第283行 |
| `getFileSize` | HEAD | 获取文件大小 | 第314行 |
| `getFileUrl` | — | 构建完整 URL | 第334行 |
| `getStreamingUrl` | GET (跟踪重定向) | 解析 CDN URL（如 S3 预签名） | 第343行 |
| `getAuthHeaders` | — | 返回 Basic Auth 头 | 第377行 |
| `scanAudioFiles` | — | 递归扫描目录中的音频文件 | 第381行 |

### XML 响应解析

`_parseWebDavResponse`（第116-251行）使用正则表达式从 WebDAV PROPFIND XML 响应中提取：`href`、`displayname`、`contentlength`、`getlastmodified`、`resourcetype`（目录标识）。处理 URL 编码、HTML 实体解码和路径规范化。

---

## 九、云音频播放器

**文件**：`lib/cloud_service/cloud_audio_player.dart`（1094行）

### 类结构

`CloudAudioPlayer` 是一个**纯静态工具类**，无实例，所有方法均为 static。

### 流式播放判断

```dart
static bool get _supportsStreaming =>
    PlayService.instance.playerEngine is MediaKitPlayerEngine;
```

仅 `mediaKit` 引擎支持直接 URL 流式播放；BASS 引擎需要先下载完整文件。

### 播放流程

**`playCloudFile`**（第753-840行）主入口：

```
├─ 流式支持（mediaKit）
│    ├─ 为目录内所有音频创建 streaming Audio 对象
│    ├─ 构建播放列表
│    ├─ 调用 playbackService.play(index, audioList)
│    └─ 异步触发元数据更新（Range 请求读取头尾）
│
└─ 非流式（BASS）
     ├─ 下载第一个文件到临时目录
     ├─ 播放该文件
     └─ 后台下载其余文件，通过 addToNext 添加到队列
```

### 元数据读取策略

| 策略 | 方法 | 下载量 | 速度 | 行号 |
|------|------|--------|------|------|
| Range 请求（快速） | `_updateMetadataViaRange` | 头64KB + 尾128KB | 快 | 第187-289行 |
| 全量下载（回退） | `_updateMetadataViaFullDownload` | 完整文件 | 慢 | 第292-408行 |
| Range 创建 Audio | `_createAudioViaRange` | 头64KB + 尾128KB | 快 | 第547-679行 |

### 批量操作方法

| 方法 | 功能 | 行号 |
|------|------|------|
| `addCloudFolderToPlaylist` | 递归扫描目录 → 添加到播放列表 | 第842-883行 |
| `addCloudFilesToPlaylist` | 添加指定文件到播放列表 | 第885-922行 |
| `addCloudFolderToLibrary` | 递归扫描 → 读取元数据 → 添加到本地库 | 第924-990行 |
| `addCloudFilesToLibrary` | 添加指定文件到本地库 | 第1024-1093行 |

### 文件名解析

`_parseFileName`（第94-113行）支持以下格式：
- `Artist - Title`
- `Artist -- Title`
- `Artist — Title`

---

## 十、数据模型

### CloudConnection

**文件**：`lib/cloud_service/cloud_connection.dart`（62行）

```dart
class CloudConnection {
  String id;                    // 唯一标识（毫秒时间戳）
  String name;                  // 连接名称
  CloudServiceType type;        // 服务类型（当前仅 webdav）
  String serverUrl;             // 服务器地址
  String username;              // 用户名
  String password;              // 密码
  String? displayName;          // 可选显示名称
  DateTime lastSync;            // 上次同步时间
  bool isActive;                // 是否激活
}
```

`CloudServiceType` 枚举当前仅有 `webdav`，注释中标注了未来扩展方向（s3、ftp、onedrive、googledrive）。

---

## 十一、缓存管理

**文件**：`lib/cloud_service/cloud_cache_manager.dart`（473行）

### 核心特性

- **单例模式**：`CloudCacheManager._()`
- **缓存键**：WebDAV 路径的 MD5 哈希
- **索引文件**：`cache_index.json`
- **最大缓存**：默认 2GB，可配置
- **淘汰策略**：LRU（`_evictIfNeeded`，第359行）

### 核心方法

| 方法 | 功能 |
|------|------|
| `getCachedFilePath` | 获取缓存文件路径（不存在则返回 null） |
| `isCached` | 检查文件是否已缓存 |
| `saveToCache` | 保存完整文件到缓存 |
| `saveStreamToCache` | 流式保存到缓存 |
| `clearCache` | 清空所有缓存 |
| `removeCache` | 移除指定缓存 |
| `getCacheSize` | 获取当前缓存大小 |

---

## 十二、辅助组件

### PlayingIndicator

**文件**：`lib/component/playing_indicator.dart`（261行）

| 组件 | 功能 | 尺寸 |
|------|------|------|
| `PlayingIndicator` | 4条正弦波动画条 | small(24px) / medium(36px) / large(48px) |
| `PlayingIndicatorOverlay` | 包裹子组件，播放时变暗(35% opacity) + 叠加波形 | — |
| `LocatePlayingButton` | 定位正在播放的文件 | — |

### PageScaffold

**文件**：`lib/page/page_scaffold.dart`（201行）

响应式页面布局包装器，被 `CloudConnectionsPage` 使用，提供标题、副标题、操作按钮和内容区。小屏时自动折叠操作按钮。

---

## 十三、架构设计要点

### 1. 单例 + Provider 双层状态管理

`CloudServiceManager` 既是单例（静态 `_instance`），又通过 `ChangeNotifierProvider` 注入 Widget 树。页面层通过 `Consumer<CloudServiceManager>` 或 `context.watch/read` 访问。

### 2. Service 实例缓存

`WebDavService` 按连接ID懒创建并缓存在 `_services` Map 中，避免重复实例化。

### 3. 密码双存储 + 自动迁移

使用 `FlutterSecureStorage`（加密）作为主存储，`SharedPreferences` 作为回退。加载时自动将 SharedPreferences 中的密码迁移到 SecureStorage。

### 4. 流式 vs 下载的双播放策略

根据播放引擎能力自动选择：mediaKit 支持流式，BASS 需要下载。这对用户透明。

### 5. Range 请求优化元数据读取

仅下载文件头尾（共192KB）即可读取大部分音频元数据，避免下载完整文件。

### 6. 文件浏览器为自包含 Stateful Widget

`CloudFileBrowser`（1600行）是一个自包含的 `StatefulWidget`，管理所有文件浏览状态（路径、排序、搜索、多选、视图模式），不依赖外部状态管理（除 `CloudServiceManager` 外）。

---

## 十四、发现的架构问题

### 问题1：测试硬编码凭据

**位置**：`lib/cloud_service/cloud_service_manager.dart:164-177`

当连接列表为空且 `autoTestConfig` 为 true 时，会添加一个硬编码的测试 WebDAV 连接（含明文密码）。这在生产代码中存在安全隐患。

### 问题2：文件浏览器体量过大

`cloud_file_browser.dart` 达 1600 行，包含 UI 渲染、文件操作、对话框、搜索、排序、面包屑等所有逻辑。建议拆分为独立组件。

### 问题3：XML 解析使用正则表达式

**位置**：`webdav_service.dart:116-251`

使用正则表达式解析 WebDAV PROPFIND XML 响应，而非 XML 解析器。虽然项目已引入 `xml` 包（`pubspec.yaml`），但未在此处使用。正则方式对特殊字符和嵌套结构的容错性较差。

### 问题4：连接表单未使用已有 xml 包

表单中的服务器地址校验仅检查 `http` 前缀，无更细致的 URL 格式校验。

### 问题5：缓存索引一致性

`CloudCacheManager` 的 `cache_index.json` 在应用异常退出时可能不一致（文件已写入但索引未更新），可能导致孤立缓存文件。

### 问题6：文件浏览器无下拉刷新

`CloudFileBrowser` 加载文件后无下拉刷新机制。如果 WebDAV 服务端文件发生变化，用户需退出并重新进入才能看到更新。

---

## 十五、关键文件索引

### UI 页面层

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/page/cloud_service/cloud_connections_page.dart` | 331 | 连接列表页（"连接"标签页） |
| `lib/page/cloud_service/cloud_file_browser.dart` | 1600 | 云文件浏览器（列表/网格/搜索/多选） |
| `lib/page/cloud_service/cloud_connection_form.dart` | 262 | 连接添加/编辑对话框 |

### 业务逻辑层

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/cloud_service/cloud_connection.dart` | 62 | CloudConnection 模型 + CloudServiceType 枚举 |
| `lib/cloud_service/cloud_service_manager.dart` | 271 | 状态管理、CRUD、密码存储 |
| `lib/cloud_service/webdav_service.dart` | 401 | WebDAV 协议客户端 + WebDavFile 模型 |
| `lib/cloud_service/cloud_audio_player.dart` | 1094 | 播放、元数据、音乐库集成 |
| `lib/cloud_service/cloud_cache_manager.dart` | 473 | 本地文件缓存（LRU 淘汰） |
| `lib/cloud_service/cloud_scanner.dart` | 95 | 文件夹扫描工具 |
| `lib/cloud_service/cloud_utils.dart` | 86 | 路径工具、格式化函数 |

### 支撑组件

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/component/playing_indicator.dart` | 261 | 播放波形动画 + 定位按钮 |
| `lib/component/page_scaffold.dart` | 201 | 响应式页面布局包装器 |
| `lib/component/side_nav.dart` | 160 | 侧边栏 + 底部导航栏 |
| `lib/component/app_shell.dart` | 147 | Shell 布局（三种响应式） |
