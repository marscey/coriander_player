# Coriander Player - Code Wiki

> 版本：1.5.1 | 协议：GPL-3.0 | 基于 [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player) fork

---

## 目录

- [1. 项目概述](#1-项目概述)
- [2. 技术栈](#2-技术栈)
- [3. 项目架构](#3-项目架构)
  - [3.1 整体架构图](#31-整体架构图)
  - [3.2 目录结构](#32-目录结构)
- [4. 核心模块详解](#4-核心模块详解)
  - [4.1 应用入口与初始化 (main / entry)](#41-应用入口与初始化-main--entry)
  - [4.2 播放服务 (play_service)](#42-播放服务-play_service)
  - [4.3 音乐库 (library)](#43-音乐库-library)
  - [4.4 歌词系统 (lyric)](#44-歌词系统-lyric)
  - [4.5 云服务 (cloud_service)](#45-云服务-cloud_service)
  - [4.6 Rust 原生层 (rust)](#46-rust-原生层-rust)
  - [4.7 BASS FFI 层 (src/bass)](#47-bass-ffi-层-srcbass)
  - [4.8 页面层 (page)](#48-页面层-page)
  - [4.9 组件层 (component)](#49-组件层-component)
  - [4.10 配置与偏好 (app_settings / app_preference)](#410-配置与偏好-app_settings--app_preference)
  - [4.11 主题系统 (theme_provider)](#411-主题系统-theme_provider)
  - [4.12 平台适配 (platform_helper / platform_dependency_manager)](#412-平台适配-platform_helper--platform_dependency_manager)
- [5. 关键类与函数参考](#5-关键类与函数参考)
- [6. 数据流与依赖关系](#6-数据流与依赖关系)
- [7. 数据持久化](#7-数据持久化)
- [8. 项目构建与运行](#8-项目构建与运行)
- [9. 平台差异说明](#9-平台差异说明)

---

## 1. 项目概述

Coriander Player 是一款使用 **Material You** 配色的跨平台本地及网盘音乐播放器，支持 Windows 和 macOS 桌面平台。核心功能包括：

- 多格式音频播放（mp3, flac, aac, m4a, wav, ogg, ape, opus 等 20+ 格式）
- 多引擎播放架构（BASS 引擎 / MediaKit 引擎），可运行时切换
- 本地音乐库扫描、索引与增量更新
- WebDAV 私有云音乐浏览与播放
- 多源歌词系统（本地内嵌歌词 / 外挂 LRC / 在线逐字歌词 QQ·Kugou·Netease）
- 桌面歌词独立窗口
- Material You 动态主题（跟随封面变色）
- 全局快捷键、系统媒体控制（Windows SMTC / macOS 通知栏）
- Windows WASAPI 独占模式

---

## 2. 技术栈

| 层面 | 技术 | 说明 |
|------|------|------|
| **UI 框架** | Flutter 3.1.4+ (Dart) | Material 3 设计 |
| **路由** | go_router ^14.0.1 | 声明式路由，ShellRoute 布局 |
| **状态管理** | provider ^6.1.1 | ChangeNotifier 模式 |
| **主播放引擎** | BASS 音频库 (un4seen.com) | FFI 绑定，Windows/macOS 原生 |
| **备选播放引擎** | media_kit ^1.1.11 | 基于 libmpv，全平台可用 |
| **原生桥接** | flutter_rust_bridge 2.8.0 | Dart ↔ Rust 双向通信 |
| **Rust 侧** | lofty 0.21.1 / image 0.25.2 / windows 0.57.0 | 标签读取、图片缩放、WinRT API |
| **云服务** | webdav_client ^1.2.2 + http | WebDAV PROPFIND 协议 |
| **在线歌词** | music_api (Git 依赖) | QQ音乐 / 酷狗 / 网易云 |
| **桌面歌词** | desktop_lyric (Git 依赖) | 独立 Flutter 窗口进程 |
| **系统媒体控制** | SMTC (Rust/WinRT) / audio_service (macOS) | 系统通知栏控件 |
| **快捷键** | hotkey_manager ^0.2.3 | 全局与应用内快捷键 |
| **窗口管理** | window_manager ^0.3.8 | 自定义标题栏、窗口尺寸 |
| **持久化** | JSON 文件 + shared_preferences | settings.json / index.json / playlists.json 等 |

---

## 3. 项目架构

### 3.1 整体架构图

```
┌──────────────────────────────────────────────────────────────┐
│                        Flutter UI 层                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────────┐   │
│  │  Pages   │ │Components│ │ AppShell │ │  GoRouter     │   │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───────┬───────┘   │
│       │            │            │                │           │
│  ┌────▼────────────▼────────────▼────────────────▼───────┐   │
│  │              Provider 状态管理层                       │   │
│  │  ThemeProvider │ CloudServiceManager │ PlayService     │   │
│  └────┬──────────────────────────────────────────┬───────┘   │
│       │                                         │           │
│  ┌────▼─────────────────────────────────────────▼───────┐   │
│  │                  业务逻辑层                           │   │
│  │  PlaybackService │ LyricService │ DesktopLyricService │   │
│  │  AudioLibrary    │ Playlist    │ MusicMatcher         │   │
│  └────┬─────────────────────────────────────────┬───────┘   │
│       │                                         │           │
│  ┌────▼──────────┐  ┌────────────────┐  ┌──────▼────────┐  │
│  │ PlayerEngine  │  │  CloudService  │  │  Lyric Parsers│  │
│  │ (Bass/MediaKit│  │  (WebDAV)      │  │  LRC/QRC/KRC  │  │
│  └────┬──────────┘  └────────────────┘  └───────────────┘  │
│       │                                                     │
│  ┌────▼──────────────────────────────────────────────────┐  │
│  │                   原生交互层                           │  │
│  │  BASS FFI (dart:ffi) │ flutter_rust_bridge │ SMTC     │  │
│  └────┬──────────────────┬────────────────────┬──────────┘  │
└───────┼──────────────────┼────────────────────┼─────────────┘
        │                  │                    │
   ┌────▼────┐      ┌─────▼──────┐      ┌──────▼──────┐
   │ BASS.dll│      │ Rust .so/.dll│     │ WinRT API  │
   │ (C 原生)│      │ (lofty等)   │     │ (Windows)   │
   └─────────┘      └────────────┘      └─────────────┘
```

### 3.2 目录结构

```
coriander_player/
├── lib/                          # Dart 主代码
│   ├── main.dart                 # 应用入口
│   ├── entry.dart                # MaterialApp + GoRouter 路由配置
│   ├── app_settings.dart         # 应用设置（单例）
│   ├── app_preference.dart       # 页面偏好（单例）
│   ├── app_paths.dart            # 路由路径常量
│   ├── theme_provider.dart       # 主题管理
│   ├── music_matcher.dart        # 在线歌词匹配
│   ├── hotkeys_helper.dart       # 快捷键注册
│   ├── platform_helper.dart      # 跨平台工具类
│   ├── platform_dependency_manager.dart  # 平台依赖管理
│   ├── utils.dart                # 通用工具（日志、拼音比较等）
│   ├── play_service/             # 🔊 播放服务模块
│   │   ├── play_service.dart         # 播放服务门面（单例）
│   │   ├── playback_service.dart     # 播放控制核心
│   │   ├── lyric_service.dart        # 歌词同步服务
│   │   ├── desktop_lyric_service.dart # 桌面歌词进程管理
│   │   ├── macos_media_control_service.dart # macOS 媒体控制
│   │   └── engine/                   # 播放引擎抽象层
│   │       ├── player_engine.dart        # 引擎接口
│   │       ├── player_engine_type.dart   # 引擎类型枚举
│   │       ├── player_engine_factory.dart # 引擎工厂
│   │       ├── bass_player_engine.dart   # BASS 引擎实现
│   │       ├── media_kit_player_engine.dart # MediaKit 引擎实现
│   │       └── platform_specific_initialization.dart
│   ├── library/                  # 📚 音乐库模块
│   │   ├── audio_library.dart        # 音乐库数据模型与索引
│   │   └── playlist.dart             # 播放列表
│   ├── lyric/                    # 🎵 歌词模块
│   │   ├── lyric.dart                # 歌词抽象基类
│   │   ├── lrc.dart                  # LRC 歌词解析
│   │   ├── qrc.dart                  # QQ 音乐 QRC 逐字歌词
│   │   ├── krc.dart                  # 酷狗 KRC 逐字歌词
│   │   └── lyric_source.dart         # 歌词来源管理
│   ├── cloud_service/            # ☁️ 云服务模块
│   │   ├── cloud_service.dart        # 模块导出
│   │   ├── cloud_connection.dart     # 云连接数据模型
│   │   ├── cloud_service_manager.dart # 云服务管理器
│   │   ├── webdav_service.dart       # WebDAV 协议实现
│   │   ├── cloud_audio_player.dart   # 云音频播放
│   │   ├── cloud_scanner.dart        # 云文件扫描
│   │   └── cloud_utils.dart          # 云服务工具
│   ├── page/                     # 📄 页面模块
│   │   ├── now_playing_page/         # 正在播放页面
│   │   ├── search_page/              # 搜索页面
│   │   ├── settings_page/            # 设置页面
│   │   ├── cloud_service/            # 云服务页面
│   │   └── ...                       # 其他列表/详情页
│   ├── component/                # 🧩 UI 组件
│   │   ├── app_shell.dart            # 应用外壳（响应式布局）
│   │   ├── side_nav.dart             # 侧边导航
│   │   ├── title_bar.dart            # 标题栏
│   │   ├── mini_now_playing.dart     # 迷你播放条
│   │   └── ...
│   └── src/                      # 🔧 生成的原生绑定代码
│       ├── bass/                     # BASS FFI 绑定
│       │   ├── bass.dart
│       │   ├── bass_player.dart
│       │   └── bass_wasapi.dart
│       └── rust/                     # flutter_rust_bridge 生成
│           ├── frb_generated.dart
│           └── api/                  # Rust API Dart 绑定
│               ├── tag_reader.dart
│               ├── smtc_flutter.dart
│               ├── system_theme.dart
│               ├── logger.dart
│               ├── installed_font.dart
│               └── utils.dart
├── rust/                         # 🦀 Rust 源码
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── frb_generated.rs
│       └── api/
│           ├── mod.rs
│           ├── tag_reader.rs          # 音乐标签读取 + 索引构建
│           ├── smtc_flutter.rs        # Windows SMTC 集成
│           ├── system_theme.rs        # 系统主题色获取
│           ├── installed_font.rs      # 已安装字体枚举
│           ├── logger.rs              # Rust→Dart 日志桥
│           └── utils.rs               # 工具函数
├── rust_builder/                 # Rust 构建插件
├── windows/                      # Windows 平台文件
│   ├── bass/                         # BASS 库 DLL 文件
│   └── build_desktop_lyric.ps1       # 桌面歌词构建脚本
├── macos/                        # macOS 平台文件
│   ├── bass/                         # BASS 库 dylib 文件
│   └── build_desktop_lyric.sh        # 桌面歌词构建脚本
├── docs/                         # 项目文档
├── pubspec.yaml                  # Flutter 依赖配置
├── flutter_rust_bridge.yaml      # FRB 配置
└── ffigen_config.yaml            # FFI 绑定生成配置
```

---

## 4. 核心模块详解

### 4.1 应用入口与初始化 (main / entry)

**文件**: [main.dart](lib/main.dart), [entry.dart](lib/entry.dart)

#### 启动流程

```
main()
 ├── WidgetsFlutterBinding.ensureInitialized()
 ├── MediaKit.ensureInitialized()          # 初始化 MediaKit
 ├── RustLib.init()                        # 初始化 Flutter Rust Bridge
 ├── initRustLogger()                      # 启动 Rust 日志流
 ├── HotkeysHelper.unregisterAll()         # 清理旧快捷键
 ├── HotkeysHelper.registerHotKeys()       # 注册全局快捷键
 ├── migrateAppData()                      # 迁移旧版数据目录
 ├── AppSettings.readFromJson()            # 读取应用设置
 │    ├── PlatformDependencyManager.initialize()  # 平台依赖初始化
 │    └── 检查播放器引擎兼容性
 ├── loadPrefFont()                        # 加载自定义字体
 ├── AppPreference.read()                  # 读取页面偏好
 ├── initWindow()                          # 初始化窗口
 └── runApp(Entry(welcome: welcome))       # 启动应用
```

#### Entry 类

`Entry` 是应用的根 Widget，负责：

- 通过 `MultiProvider` 注入 `ThemeProvider` 和 `CloudServiceManager`
- 配置 `MaterialApp.router`（Material 3 主题、国际化）
- 定义 `GoRouter` 路由表（ShellRoute 布局 + 独立页面）

**路由结构**:

| 路径 | 页面 | 说明 |
|------|------|------|
| `/welcoming` | WelcomingPage | 首次启动引导 |
| `/updating` | UpdatingPage | 索引更新 |
| `/audios` | AudiosPage | 音乐列表 |
| `/audios/detail` | AudioDetailPage | 音乐详情 |
| `/artists` | ArtistsPage | 艺术家列表 |
| `/artists/detail` | ArtistDetailPage | 艺术家详情 |
| `/albums` | AlbumsPage | 专辑列表 |
| `/albums/detail` | AlbumDetailPage | 专辑详情 |
| `/folders` | FoldersPage | 文件夹列表 |
| `/folders/detail` | FolderDetailPage | 文件夹详情 |
| `/playlists` | PlaylistsPage | 播放列表 |
| `/playlists/detail` | PlaylistDetailPage | 播放列表详情 |
| `/search` | SearchPage | 搜索 |
| `/search/result` | SearchResultPage | 搜索结果 |
| `/cloud` | CloudConnectionsPage | 云连接管理 |
| `/cloud/browser` | CloudFileBrowser | 云文件浏览 |
| `/settings` | SettingsPage | 设置 |
| `/settings/issue` | SettingsIssuePage | 提交 Issue |
| `/nowplaying` | NowPlayingPage | 正在播放（全屏，从底部滑入） |

所有列表/详情页面嵌套在 `ShellRoute → AppShell` 中，`NowPlayingPage` 作为独立全屏路由从底部滑入。

---

### 4.2 播放服务 (play_service)

**文件**: [play_service/](lib/play_service/)

这是整个应用的核心模块，采用**门面模式**组织三个子服务。

#### PlayService（门面）

```dart
class PlayService {
  late final playbackService = PlaybackService(this);
  late final lyricService = LyricService(this);
  late final desktopLyricService = DesktopLyricService(this);
}
```

单例模式，通过 `PlayService.instance` 全局访问。

#### PlaybackService（播放控制核心）

**文件**: [playback_service.dart](lib/play_service/playback_service.dart)

继承 `ChangeNotifier`，当 `nowPlaying` 变化时通知 UI 重建。

| 属性/方法 | 说明 |
|-----------|------|
| `nowPlaying` | 当前播放的 Audio 对象 |
| `playlist` | 当前播放列表 (`ValueNotifier<List<Audio>>`) |
| `playMode` | 播放模式：forward / loop / singleLoop |
| `shuffle` | 随机播放标志 |
| `playerState` | 当前播放状态 (playing/paused/completed/...) |
| `position` / `length` | 当前位置 / 总时长（秒） |
| `play(index, playlist)` | 播放指定曲目并设置播放列表 |
| `playIndexOfPlaylist(index)` | 播放当前列表的第 index 首 |
| `shuffleAndPlay(audios)` | 随机播放 |
| `nextAudio()` / `lastAudio()` | 下一曲 / 上一曲 |
| `start()` / `pause()` / `seek()` | 播放控制 |
| `switchEngine(type)` | 运行时切换播放引擎 |
| `setVolumeDsp(volume)` | 设置解码音量 |

**播放流程** (`_loadAndPlay`):

1. 更新播放索引和 `nowPlaying`
2. 检查引擎类型是否匹配，必要时切换引擎
3. 调用 `_player.setSource(path)` 设置音频源
4. 设置音量
5. 调用 `lyricService.updateLyric()` 获取歌词
6. 调用 `_player.play()` 开始播放
7. 通知 UI 更新 + 更新主题色
8. 更新 SMTC / macOS 媒体控制
9. 向桌面歌词发送状态

#### 播放引擎抽象层

**文件**: [engine/](lib/play_service/engine/)

采用**策略模式**，通过 `PlayerEngine` 抽象接口支持多引擎：

```dart
abstract class PlayerEngine {
  Future<void> initialize();
  Future<void> setSource(String path, {bool isAsset, bool isNetwork});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  void setVolume(double volume);
  void setSpeed(double speed);
  PlayerState get state;
  Duration get position;
  Duration get duration;
  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Future<void> dispose();
}
```

**引擎类型** (`PlayerEngineType`):

| 引擎 | 实现类 | 底层 | 平台 | 特性 |
|------|--------|------|------|------|
| `bass` | `BassPlayerEngine` | BASS 音频库 (FFI) | Windows, macOS | WASAPI 独占模式、低延迟 |
| `mediaKit` | `MediaKitPlayerEngine` | libmpv (media_kit) | 全平台 | 网络流支持、跨平台 |

**工厂类** `PlayerEngineFactory`:
- `createEngine(type)`: 根据类型创建引擎
- `getDefaultEngine()`: 根据平台和配置返回默认引擎（桌面端默认 BASS，移动端默认 MediaKit）

#### LyricService（歌词同步服务）

**文件**: [lyric_service.dart](lib/play_service/lyric_service.dart)

继承 `ChangeNotifier`，当歌词变更时通知 UI。

| 属性/方法 | 说明 |
|-----------|------|
| `currLyricFuture` | 当前歌词的 Future |
| `lyricLineStream` | 当前歌词行号流（供 UI 订阅） |
| `updateLyric()` | 根据默认来源更新歌词 |
| `useLocalLyric()` | 切换到本地歌词 |
| `useOnlineLyric()` | 切换到在线歌词 |
| `useSpecificLyric(lyric)` | 使用指定歌词 |
| `findCurrLyricLine()` | 重新计算当前歌词行（seek 后调用） |

歌词获取优先级：
1. 如果用户指定了默认歌词来源 → 按指定来源获取
2. 否则按 `AppSettings.localLyricFirst` 配置：本地优先或在线优先

#### DesktopLyricService（桌面歌词服务）

**文件**: [desktop_lyric_service.dart](lib/play_service/desktop_lyric_service.dart)

管理桌面歌词独立进程的生命周期和 IPC 通信。

- 通过 `Process.start` 启动 desktop_lyric 可执行文件
- 通过 stdin/stdout JSON 消息进行双向通信
- 支持的消息类型：播放状态、当前曲目、歌词行、主题变更、主题模式、解锁

---

### 4.3 音乐库 (library)

**文件**: [library/](lib/library/)

#### AudioLibrary（音乐库）

**文件**: [audio_library.dart](lib/library/audio_library.dart)

单例模式，从 `index.json` 加载音乐索引，构建三个集合：

| 集合 | 类型 | 说明 |
|------|------|------|
| `audioCollection` | `List<Audio>` | 所有音乐 |
| `artistCollection` | `Map<String, Artist>` | 艺术家名 → 艺术家 |
| `albumCollection` | `Map<String, Album>` | 专辑名 → 专辑 |

`_buildCollections()` 方法遍历所有 Audio，通过 `putIfAbsent` 建立艺术家-专辑-曲目的关联关系。

#### 数据模型

**Audio** — 音乐文件

| 字段 | 类型 | 说明 |
|------|------|------|
| `title` | String | 标题 |
| `artist` | String | 原始艺术家字符串 |
| `splitedArtists` | List\<String\> | 按 `artistSplitPattern` 分割后的艺术家列表 |
| `album` | String | 专辑名 |
| `track` | int | 曲目号 |
| `duration` | int | 时长（秒） |
| `bitrate` | int? | 比特率 (kbps) |
| `sampleRate` | int? | 采样率 |
| `path` | String | 绝对路径 |
| `modified` / `created` | int | UNIX 时间戳 |
| `by` | String? | 标签来源 (Lofty / Windows API) |
| `cover` | Future\<ImageProvider?\> | 48×48 缩略图（带缓存） |
| `mediumCover` | Future\<ImageProvider?\> | 200×200 封面 |
| `largeCover` | Future\<ImageProvider?\> | 400×400 大封面 |

**Artist** — 艺术家

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | String | 艺术家名 |
| `albumsMap` | Map\<String, Album\> | 关联专辑 |
| `works` | List\<Audio\> | 所有作品 |

**Album** — 专辑

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | String | 专辑名 |
| `artistsMap` | Map\<String, Artist\> | 参与的艺术家 |
| `works` | List\<Audio\> | 所有作品 |

**AudioFolder** — 文件夹

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | String | 绝对路径 |
| `audios` | List\<Audio\> | 文件夹中的音乐 |
| `modified` | int | 文件夹修改时间 |
| `latest` | int | 最新文件的创建时间 |

#### Playlist（播放列表）

**文件**: [playlist.dart](lib/library/playlist.dart)

用户自建播放列表，以 `Map<String, Audio>` 存储（key 为文件路径），持久化到 `playlists.json`。

---

### 4.4 歌词系统 (lyric)

**文件**: [lyric/](lib/lyric/)

#### 类继承体系

```
Lyric (abstract)
 ├── Lrc        — 非逐字歌词（LRC 格式）
 ├── Qrc        — QQ 音乐逐字歌词
 └── Krc        — 酷狗逐字歌词

LyricLine (abstract)
 ├── UnsyncLyricLine  — 非逐字歌词行
 │    └── LrcLine     — LRC 歌词行
 └── SyncLyricLine    — 逐字歌词行
      ├── QrcLine     — QRC 歌词行
      └── KrcLine     — KRC 歌词行

SyncLyricWord (abstract)
 ├── QrcWord
 └── KrcWord
```

#### LRC 歌词 (`lrc.dart`)

- 解析标准 `[mm:ss.ms]content` 格式
- 支持 `offset` 时间偏移标签
- 支持相同时间戳的原文/译文合并（用 `┃` 分隔）
- 间奏识别：空行与下一行时间差 > 5s 则视为间奏
- 来源：本地内嵌标签（Lofty 读取） / 外挂 .lrc 文件 / 网络歌词

#### QRC 歌词 (`qrc.dart`)

- QQ 音乐逐字歌词格式：`[start,length]content(word1(start,length)word2...)`
- 支持翻译文本合并
- 间奏空白行自动插入

#### KRC 歌词 (`krc.dart`)

- 酷狗逐字歌词格式：`[start,length]<wordStart,wordLen,0>content...`
- 支持 language frame 翻译
- 间奏空白行自动插入

#### LyricSource（歌词来源管理）

**文件**: [lyric_source.dart](lib/lyric/lyric_source.dart)

用户可为每首歌指定默认歌词来源（QQ / Kugou / Netease / Local），持久化到 `lyric_source.json`。

#### MusicMatcher（在线歌词匹配）

**文件**: [music_matcher.dart](lib/music_matcher.dart)

通过 `music_api` 包同时搜索 QQ 音乐、酷狗、网易云三个平台，按标题/艺术家/专辑的字符相似度评分排序，返回最佳匹配的歌词。

| 函数 | 说明 |
|------|------|
| `uniSearch(audio)` | 多平台统一搜索，返回评分排序结果 |
| `getMostMatchedLyric(audio)` | 获取最佳匹配歌词 |
| `getOnlineLyric(qqSongId, kugouSongHash, neteaseSongId)` | 按 ID 获取指定平台歌词 |

---

### 4.5 云服务 (cloud_service)

**文件**: [cloud_service/](lib/cloud_service/)

#### CloudConnection（连接模型）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | String | 唯一标识 |
| `name` | String | 连接名称 |
| `type` | CloudServiceType | 服务类型（目前仅 webdav） |
| `serverUrl` | String | 服务器地址 |
| `username` / `password` | String | 认证信息 |
| `isActive` | bool | 是否启用 |

#### CloudServiceManager（连接管理器）

继承 `ChangeNotifier`，管理所有云连接的 CRUD 操作，使用 `SharedPreferences` 持久化连接信息。为每个 WebDAV 连接创建 `WebDavService` 实例（懒加载，缓存复用）。

#### WebDavService（WebDAV 协议实现）

| 方法 | 说明 |
|------|------|
| `testConnection()` | 测试连接（HTTP HEAD） |
| `listFiles(directoryPath)` | 列出目录文件（PROPFIND Depth:1） |
| `downloadFile(filePath)` | 下载文件到内存 |
| `getFileUrl(filePath)` | 获取文件直链 URL |
| `scanAudioFiles(directoryPath)` | 扫描目录中的音频文件 |

使用正则解析 WebDAV XML 响应（非 XML DOM），自动过滤隐藏文件和当前目录节点。

#### CloudAudioPlayer（云音频播放）

下载云文件到系统临时目录，创建临时 `Audio` 对象后调用 `PlaybackService.play()` 播放，延迟 5 分钟后清理临时文件。

#### CloudScanner（云文件扫描）

下载云文件到临时目录后，调用 Rust 层 `buildIndexFromFoldersRecursively` 扫描标签并加入本地索引。

---

### 4.6 Rust 原生层 (rust)

**文件**: [rust/src/api/](rust/src/api/)

通过 `flutter_rust_bridge` 暴露给 Dart 的 API：

| 模块 | 文件 | 主要功能 |
|------|------|----------|
| **tag_reader** | tag_reader.rs | 音乐标签读取、封面提取、歌词提取、索引构建与增量更新 |
| **smtc_flutter** | smtc_flutter.rs | Windows System Media Transport Controls 集成 |
| **system_theme** | system_theme.rs | 获取 Windows 系统主题色和暗色模式 |
| **installed_font** | installed_font.rs | 枚举系统已安装字体 |
| **logger** | logger.rs | Rust → Dart 日志桥接 |
| **utils** | utils.rs | 通用工具函数 |

#### tag_reader.rs 详解

**核心数据结构**:

- `Audio` (Rust): 音乐文件元数据（title, artist, album, track, duration, bitrate, sample_rate, path, modified, created, by）
- `AudioFolder` (Rust): 文件夹索引
- `IndexActionState`: 索引操作进度状态

**核心函数**:

| 函数 | 说明 |
|------|------|
| `build_index_from_folders_recursively(folders, index_path, sink)` | 递归扫描文件夹构建音乐索引 |
| `update_index(index_path, sink)` | 增量更新索引（删除失效、更新修改、添加新增） |
| `get_picture_from_path(path, width, height)` | 获取封面图片（自动缩放） |
| `get_lyric_from_path(path)` | 获取歌词（内嵌 → 外挂 .lrc） |

**标签读取策略**:

1. 检查文件扩展名是否在 `SUPPORT_FORMAT` 表中
2. 如果 Lofty 支持 → 优先用 Lofty 读取
3. 如果 Lofty 失败或不支持 → 尝试 Windows API (`StorageFile.GetMusicPropertiesAsync`)
4. 都失败 → 使用文件名作为标题

**封面获取策略**:

1. 优先 Lofty 读取内嵌封面
2. Windows 平台回退到 `StorageFile.GetThumbnailAsync`
3. 自动按比例缩放并转为 PNG

**索引更新逻辑** (`update_index`):

- 删除不存在的文件夹记录
- 对比 `modified` 时间戳跳过未修改的文件夹
- 删除不存在的文件记录
- 重新读取被修改文件的标签
- 添加 `created > latest` 的新文件

---

### 4.7 BASS FFI 层 (src/bass)

**文件**: [src/bass/](lib/src/bass/)

通过 `dart:ffi` 直接调用 BASS 音频库的 C API。

#### BassPlayer

**文件**: [bass_player.dart](lib/src/bass/bass_player.dart)

BASS 库的 Dart 封装，核心功能：

| 方法 | 说明 |
|------|------|
| `BassPlayer()` | 构造函数：加载 BASS 库 + 插件，初始化设备 |
| `setSource(filePath)` | 创建音频流（支持 UTF-16/UTF-8 路径、内存加载） |
| `start()` / `pause()` / `seek(pos)` | 播放控制 |
| `setVolumeDsp(vol)` | 设置解码音量 |
| `useExclusiveMode(bool)` | 切换 WASAPI 独占模式（仅 Windows） |
| `free()` | 释放所有资源 |

**macOS 特殊处理**:

- BASS 库路径：`Frameworks/BASS/libbass.dylib`
- 插件路径：`Frameworks/BASS/libbass{format}.dylib`
- 文件加载：依次尝试 UTF-16 → UTF-8 → 无 ASYNCFILE → 内存加载

**Windows 特殊处理**:

- WASAPI 独占模式：通过 `BASS_WASAPI_Init` + `BASS_WASAPI_Start` 实现
- BASS 库路径：`BASS/bass.dll`
- 插件路径：`BASS/bass{format}.dll`

#### PlayerState 枚举

| 状态 | 说明 |
|------|------|
| `stopped` | 已停止或播放完成 |
| `playing` | 正在播放 |
| `paused` | 已暂停 |
| `pausedDevice` | 设备暂停（如 USB 声卡断开） |
| `stalled` | 数据不足导致停顿 |
| `completed` | 播放完成 |
| `unknown` | 未知状态 |

---

### 4.8 页面层 (page)

**文件**: [page/](lib/page/)

#### 页面分类

**列表页面** (UniPage 通用框架):

- AudiosPage, ArtistsPage, AlbumsPage, FoldersPage, PlaylistsPage
- 使用 `UniPage` 通用组件，支持排序、视图切换（列表/表格）

**详情页面**:

- AudioDetailPage, ArtistDetailPage, AlbumDetailPage, FolderDetailPage, PlaylistDetailPage

**功能页面**:

- NowPlayingPage: 正在播放全屏页（大/小屏自适应）
- SearchPage / SearchResultPage: 搜索与结果
- CloudConnectionsPage / CloudFileBrowser: 云服务管理
- SettingsPage: 设置（主题、播放引擎、快捷键等）
- WelcomingPage: 首次启动引导
- UpdatingPage: 索引更新进度

#### NowPlayingPage

支持两种布局：
- `LargePage`: 大屏布局（封面 + 歌词并排）
- `SmallPage`: 小屏布局（封面 + 歌词上下排列）

歌词视图控件：
- `VerticalLyricView`: 垂直滚动歌词
- `HorizontalLyricView`: 水平滚动歌词（迷你播放条）
- `LyricSourceView`: 歌词来源选择
- `LyricViewControls`: 歌词控制（对齐方式、字体大小等）

---

### 4.9 组件层 (component)

**文件**: [component/](lib/component/)

| 组件 | 说明 |
|------|------|
| `AppShell` | 应用外壳，响应式布局（小屏：Drawer 导航；大屏：侧边导航） |
| `SideNav` | 侧边导航栏 |
| `TitleBar` | 自定义标题栏 |
| `MiniNowPlaying` | 底部迷你播放条 |
| `AudioTile` / `AlbumTile` / `ArtistTile` | 列表项组件 |
| `SettingsTile` | 设置项组件 |
| `ResponsiveBuilder` | 响应式布局构建器（small / medium / large） |
| `ScrollAwareFutureBuilder` | 滚动感知的 Future 构建器 |
| `BuildIndexStateView` | 索引构建状态视图 |
| `RectangleProgressIndicator` | 矩形进度指示器 |

---

### 4.10 配置与偏好 (app_settings / app_preference)

#### AppSettings

**文件**: [app_settings.dart](lib/app_settings.dart)

单例模式，持久化到 `settings.json`。

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `themeMode` | ThemeMode | 跟随系统 | 亮色/暗色模式 |
| `defaultTheme` | int | 系统主题色 | 默认主题种子色 |
| `dynamicTheme` | bool | true | 跟随封面动态主题 |
| `useSystemTheme` | bool | true | 跟随系统主题色 |
| `useSystemThemeMode` | bool | true | 跟随系统暗色模式 |
| `artistSeparator` | List | ["/", "、"] | 艺术家分隔符 |
| `localLyricFirst` | bool | true | 本地歌词优先 |
| `windowSize` | Size | 1280×756 | 窗口尺寸 |
| `isWindowMaximized` | bool | false | 窗口最大化 |
| `fontFamily` / `fontPath` | String? | null | 自定义字体 |
| `playerEngineType` | PlayerEngineType? | null | 播放器引擎类型 |

#### AppPreference

**文件**: [app_preference.dart](lib/app_preference.dart)

单例模式，持久化到 `app_preference.json`。存储各页面的排序方式、排序顺序、内容视图偏好以及播放偏好（播放模式、音量）。

---

### 4.11 主题系统 (theme_provider)

**文件**: [theme_provider.dart](lib/theme_provider.dart)

继承 `ChangeNotifier`，单例模式。

| 方法 | 说明 |
|------|------|
| `applyTheme(seedColor)` | 从种子色生成亮/暗主题 |
| `applyThemeFromImage(image, themeMode)` | 从图片提取主题色 |
| `applyThemeFromAudio(audio)` | 从音频封面提取主题色（需 `dynamicTheme` 开启） |
| `applyThemeMode(themeMode)` | 切换亮/暗模式 |
| `changeFontFamily(fontFamily)` | 切换字体 |

主题变更时同步通知桌面歌词进程。

---

### 4.12 平台适配 (platform_helper / platform_dependency_manager)

#### PlatformHelper

**文件**: [platform_helper.dart](lib/platform_helper.dart)

纯静态工具类，提供跨平台路径、BASS 库路径、桌面歌词路径等平台相关逻辑。

| 属性/方法 | 说明 |
|-----------|------|
| `isMacOS` / `isWindows` / `isLinux` / `isDesktop` | 平台判断 |
| `bassLibraryPath` | BASS 主库路径 |
| `bassWasapiLibraryPath` | WASAPI 库路径（仅 Windows） |
| `bassPluginPaths` | BASS 插件路径列表 |
| `desktopLyricExecutablePath` | 桌面歌词可执行文件路径 |
| `normalizePath(filePath)` | 路径标准化 |
| `joinPaths(paths)` | 跨平台路径拼接 |
| `supportsWasapi()` | 是否支持 WASAPI |

#### PlatformDependencyManager

**文件**: [platform_dependency_manager.dart](lib/platform_dependency_manager.dart)

单例模式，管理平台特定依赖的初始化和查询。

| 方法 | 说明 |
|------|------|
| `initialize()` | 初始化平台依赖 |
| `getSupportedPlayerEngines()` | 获取当前平台支持的引擎列表 |
| `isPlayerEngineSupported(type)` | 检查引擎是否受支持 |
| `getRecommendedPlayerEngine()` | 获取推荐引擎 |

---

## 5. 关键类与函数参考

### 单例类

| 类 | 访问方式 | 说明 |
|----|----------|------|
| `PlayService` | `PlayService.instance` | 播放服务门面 |
| `AudioLibrary` | `AudioLibrary.instance` | 音乐库 |
| `AppSettings` | `AppSettings.instance` | 应用设置 |
| `AppPreference` | `AppPreference.instance` | 页面偏好 |
| `ThemeProvider` | `ThemeProvider.instance` | 主题管理 |
| `PlatformDependencyManager` | `PlatformDependencyManager.instance` | 平台依赖管理 |

### ChangeNotifier 提供者

| 类 | 通知时机 | Provider 位置 |
|----|----------|---------------|
| `ThemeProvider` | 主题色/模式变更 | Entry (MultiProvider) |
| `CloudServiceManager` | 云连接增删改 | Entry (MultiProvider) |
| `PlaybackService` | nowPlaying 变更 | 直接监听 |
| `LyricService` | 歌词变更 | 直接监听 |
| `DesktopLyricService` | 桌面歌词状态变更 | 直接监听 |

### Rust API (通过 flutter_rust_bridge)

| Dart 函数 | Rust 函数 | 说明 |
|-----------|-----------|------|
| `buildIndexFromFoldersRecursively()` | `build_index_from_folders_recursively()` | 构建音乐索引 |
| `updateIndex()` | `update_index()` | 增量更新索引 |
| `getPictureFromPath()` | `get_picture_from_path()` | 获取封面图片 |
| `getLyricFromPath()` | `get_lyric_from_path()` | 获取歌词文本 |
| `getSystemTheme()` | `get_system_theme()` | 获取系统主题色 |
| `initRustLogger()` | `init_rust_logger()` | 初始化日志流 |

---

## 6. 数据流与依赖关系

### 模块依赖关系图

```
main.dart
  ├── entry.dart (UI 入口)
  │    ├── theme_provider.dart
  │    ├── cloud_service/ (CloudServiceManager)
  │    └── page/* (所有页面)
  │         ├── play_service/ (PlayService)
  │         │    ├── playback_service.dart
  │         │    │    ├── engine/* (PlayerEngine)
  │         │    │    │    └── src/bass/* (BassPlayer)
  │         │    │    └── src/rust/api/smtc_flutter.dart
  │         │    ├── lyric_service.dart
  │         │    │    ├── lyric/* (Lrc/Qrc/Krc)
  │         │    │    └── music_matcher.dart
  │         │    │         └── music_api (外部包)
  │         │    └── desktop_lyric_service.dart
  │         │         └── desktop_lyric (外部包)
  │         ├── library/* (AudioLibrary, Playlist)
  │         │    └── src/rust/api/tag_reader.dart
  │         └── cloud_service/* (WebDavService)
  ├── app_settings.dart
  ├── app_preference.dart
  ├── platform_dependency_manager.dart
  └── hotkeys_helper.dart
```

### 播放数据流

```
用户点击播放
    │
    ▼
PlaybackService.play(index, playlist)
    │
    ├── _loadAndPlay(index, playlist)
    │    ├── PlayerEngine.setSource(path)     ← 设置音频源
    │    ├── PlayerEngine.play()              ← 开始播放
    │    ├── LyricService.updateLyric()       ← 获取歌词
    │    │    ├── Lrc.fromAudioPath()         ← 本地歌词
    │    │    └── getMostMatchedLyric()        ← 在线歌词
    │    │         └── music_api (QQ/Kugou/Netease)
    │    ├── ThemeProvider.applyThemeFromAudio() ← 动态主题
    │    ├── SMTC.updateDisplay()             ← 系统媒体控制
    │    └── DesktopLyricService.send*()      ← 桌面歌词
    │
    ▼
PlayerEngine.positionStream ──→ LyricService (歌词同步)
                              ──→ SMTC (进度更新)
                              ──→ DesktopLyricService (歌词行推送)
```

---

## 7. 数据持久化

所有数据文件存储在 `{用户文档目录}/coriander_player/` 下：

| 文件 | 格式 | 说明 |
|------|------|------|
| `index.json` | JSON | 音乐库索引（版本 110） |
| `settings.json` | JSON | 应用设置 |
| `app_preference.json` | JSON | 页面偏好 |
| `playlists.json` | JSON | 用户播放列表 |
| `lyric_source.json` | JSON | 每首歌的默认歌词来源 |
| `cloud_connections` | SharedPreferences | 云连接信息 |

### index.json 结构

```json
{
  "version": 110,
  "folders": [
    {
      "path": "C:\\Music",
      "modified": 1700000000,
      "latest": 1700001000,
      "audios": [
        {
          "title": "Song Title",
          "artist": "Artist1/Artist2",
          "album": "Album Name",
          "track": 1,
          "duration": 240,
          "bitrate": 320,
          "sample_rate": 44100,
          "path": "C:\\Music\\song.mp3",
          "modified": 1700000000,
          "created": 1699999000,
          "by": "Lofty"
        }
      ]
    }
  ]
}
```

---

## 8. 项目构建与运行

### 环境要求

- Flutter SDK >= 3.1.4, < 4.0.0
- Rust 工具链（通过 rust_builder 自动构建）
- Windows: Visual Studio Build Tools (CMake)
- macOS: Xcode + CocoaPods

### 构建步骤

```bash
# 1. 获取依赖
flutter pub get

# 2. 构建 Rust 库（由 rust_builder 自动完成）
# 首次构建会自动下载并编译 Rust 代码

# 3. 构建 Windows 版本
flutter build windows

# 4. 构建 macOS 版本
flutter build macos

# 5. 构建桌面歌词组件
# Windows:
powershell -ExecutionPolicy Bypass -File .\windows\build_desktop_lyric.ps1
# macOS:
chmod +x ./macos/build_desktop_lyric.sh && ./macos/build_desktop_lyric.sh

# 6. 运行调试
flutter run -d windows
flutter run -d macos
```

### BASS 库配置

- **Windows**: 将 BASS DLL 文件放在 `windows/bass/` 目录，CMake 构建时自动复制
- **macOS**: 将 BASS dylib 文件放在 `macos/bass/` 目录，构建时自动复制到 `Frameworks/BASS/`
- BASS 库可从 [un4seen.com](https://www.un4seen.com/bass.html) 下载

### flutter_rust_bridge 代码生成

```bash
# 配置文件: flutter_rust_bridge.yaml
# rust_input: rust/src/api/**/*.rs
# dart_output: lib/src/rust

# 重新生成绑定代码
flutter_rust_bridge_codegen generate
```

---

## 9. 平台差异说明

| 特性 | Windows | macOS |
|------|---------|-------|
| **默认播放引擎** | BASS | BASS |
| **WASAPI 独占模式** | ✅ 支持 | ❌ 不支持 |
| **系统媒体控制** | SMTC (WinRT) | audio_service + just_audio |
| **系统主题色获取** | WinRT API | 默认蓝色 (#3B82F6) |
| **BASS 库格式** | .dll | .dylib |
| **BASS 库路径** | exe目录/BASS/ | app/Frameworks/BASS/ |
| **桌面歌词** | .exe 可执行文件 | .app 包 |
| **文件选择器** | filepicker_windows | file_picker |
| **全局快捷键** | hotkey_manager | hotkey_manager |
| **标签读取回退** | Windows API (StorageFile) | 仅 Lofty |
| **封面获取回退** | Windows API (Thumbnail) | 仅 Lofty |
| **窗口标题栏** | 隐藏 (自定义) | 系统标准 |
