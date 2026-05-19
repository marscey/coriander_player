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
  - [4.13 快捷键系统 (hotkeys_helper)](#413-快捷键系统-hotkeys_helper)
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
- WebDAV 私有云音乐浏览、流式播放与缓存管理
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
| **备选播放引擎** | media_kit ^1.1.11 | 基于 libmpv，全平台可用，支持网络流 |
| **原生桥接** | flutter_rust_bridge 2.8.0 | Dart ↔ Rust 双向通信 |
| **Rust 侧** | lofty 0.21.1 / image 0.25.2 / windows 0.57.0 | 标签读取、图片缩放、WinRT API |
| **云服务** | webdav_client ^1.2.2 + http | WebDAV PROPFIND 协议 |
| **在线歌词** | music_api (Git 依赖) | QQ音乐 / 酷狗 / 网易云 |
| **桌面歌词** | desktop_lyric (Git 依赖) | 独立 Flutter 窗口进程 |
| **系统媒体控制** | SMTC (Rust/WinRT) / audio_service (macOS) | 系统通知栏控件 |
| **快捷键** | hotkey_manager ^0.2.3 | 全局与应用内快捷键 |
| **窗口管理** | window_manager ^0.3.8 | 自定义标题栏、窗口尺寸 |
| **安全存储** | flutter_secure_storage ^9.0.0 | 云连接密码加密存储 |
| **持久化** | JSON 文件 + SharedPreferences | settings.json / index.json / playlists.json 等 |
| **缓存管理** | crypto (MD5) | 云音频文件缓存索引 |

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
│  │  CloudAudioPlayer│ CloudCacheManager │ CloudScanner   │   │
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
   │ (C 原生)│      │ (lofty等)   │     │ (Windows)  │
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
│   │   ├── cloud_audio_player.dart   # 云音频播放（流式/下载）
│   │   ├── cloud_cache_manager.dart  # 云缓存管理器
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
 │    ├── CloudCacheManager.init()         # 初始化云缓存管理器
 │    ├── PlatformDependencyManager.initialize()  # 平台依赖初始化
 │    └── 检查播放器引擎兼容性
 ├── loadPrefFont()                        # 加载自定义字体
 ├── AppPreference.read()                  # 读取页面偏好
 ├── initWindow()                          # 初始化窗口
 └── runApp(App(welcome: welcome))         # 启动应用
```

#### App 类

`App` 是最外层 StatefulWidget，混入 `WindowListener` 和 `TrayListener`，负责：

- 初始化系统托盘（图标、菜单：显示主窗口 / 退出）
- 监听窗口关闭事件（隐藏到托盘而非退出）
- 处理托盘图标点击（显示/聚焦窗口）

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

| 方法 | 说明 |
|------|------|
| `PlayService.instance` | 获取单例 |
| `close()` | 关闭服务：停止桌面歌词 + 释放播放引擎 |

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
| `position` / `length` / `buffer` | 当前位置 / 总时长 / 缓冲（秒） |
| `wasapiExclusive` | WASAPI 独占模式标志 (`ValueNotifier<bool>`) |
| `play(index, playlist, httpHeaders?)` | 播放指定曲目并设置播放列表 |
| `playIndexOfPlaylist(index)` | 播放当前列表的第 index 首 |
| `shuffleAndPlay(audios)` | 随机播放 |
| `nextAudio()` / `lastAudio()` | 下一曲 / 上一曲 |
| `start()` / `pause()` / `seek()` | 播放控制 |
| `playAgain()` | 重新播放当前曲目 |
| `addToNext(audio)` | 将曲目插入到当前播放位置之后 |
| `isInPlaylist(path)` | 检查曲目是否在播放列表中 |
| `switchEngine(type)` | 运行时切换播放引擎 |
| `setVolumeDsp(volume)` | 设置音量 |
| `useExclusiveMode(exclusive)` | 切换 WASAPI 独占模式 |
| `refreshNowPlaying()` | 强制通知 UI 刷新 |

**播放流程** (`_loadAndPlay`):

1. 更新播放索引和 `nowPlaying`
2. 判断是否为云音频：
   - **云音频 + MediaKit 引擎**：优先使用缓存文件，否则解析流式 URL 播放，并在后台缓存
   - **云音频 + BASS 引擎**：提示用户切换引擎（BASS 不支持网络流）
   - **本地音频**：直接设置文件路径
3. 设置音量
4. 调用 `lyricService.updateLyric()` 获取歌词
5. 调用 `_player.play()` 开始播放
6. 通知 UI 更新 + 更新主题色
7. 更新 SMTC / macOS 媒体控制
8. 向桌面歌词发送状态
9. 云音频元数据异步更新（标题/艺术家/封面等）

**引擎切换** (`switchEngine`):

1. 保存当前播放位置和曲目信息
2. 取消流订阅，释放旧引擎
3. 创建并初始化新引擎
4. 重新订阅播放状态和位置流
5. 恢复播放：对云音频使用缓存或流式 URL，对本地音频直接设置路径
6. 保存设置

**自动播放下一曲** (`_autoNextAudio`):

根据 `playMode` 选择策略：
- `forward`：顺序播放到列表末尾停止
- `loop`：循环播放
- `singleLoop`：单曲循环

#### 播放引擎抽象层

**文件**: [engine/](lib/play_service/engine/)

采用**策略模式**，通过 `PlayerEngine` 抽象接口支持多引擎：

```dart
abstract class PlayerEngine {
  Future<void> initialize();
  Future<void> setSource(String path, {bool isAsset, bool isNetwork, Map<String, String>? httpHeaders});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  void setVolume(double volume);
  void setSpeed(double speed);
  PlayerState get state;
  Duration get position;
  Duration get duration;
  Duration get buffer;
  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get bufferStream;
  Stream<Duration> get durationStream;
  Future<void> dispose();
}
```

**引擎类型** (`PlayerEngineType`):

| 引擎 | 实现类 | 底层 | 平台 | 特性 |
|------|--------|------|------|------|
| `bass` | `BassPlayerEngine` | BASS 音频库 (FFI) | Windows, macOS | WASAPI 独占模式、低延迟 |
| `mediaKit` | `MediaKitPlayerEngine` | libmpv (media_kit) | 全平台 | 网络流支持、HTTP Headers、跨平台 |

**BassPlayerEngine** 特性：
- 封装 `BassPlayer`，不支持网络流 (`isNetwork` 参数被忽略)
- 不支持变速播放 (`setSpeed` 为空实现)
- 缓冲流和时长流在 `setSource` 时一次性触发

**MediaKitPlayerEngine** 特性：
- 使用 `media_kit` 的 `Player` 类
- 支持网络流播放（`Media(path, httpHeaders: headers)`）
- 通过 100ms 定时器轮询位置（`_positionTimer`）
- 监听 `playing`、`completed`、`duration`、`position`、`buffer`、`error`、`log` 事件流
- 音量范围 0-100（内部将 0.0-1.0 映射到 0-100）

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

**歌词同步机制**：

1. 订阅 `PlaybackService.positionStream`
2. 当播放位置超过下一行歌词的起始时间时，推进歌词行索引
3. 通过 `_lyricLineStreamController` 广播当前行号
4. 同时向桌面歌词进程发送当前歌词行

歌词获取优先级：
1. 如果用户指定了默认歌词来源 → 按指定来源获取
2. 否则按 `AppSettings.localLyricFirst` 配置：本地优先或在线优先

#### DesktopLyricService（桌面歌词服务）

**文件**: [desktop_lyric_service.dart](lib/play_service/desktop_lyric_service.dart)

继承 `ChangeNotifier`，管理桌面歌词独立进程的生命周期和 IPC 通信。

- 通过 `Process.start` 启动 desktop_lyric 可执行文件
- 通过 stdin/stdout JSON 消息进行双向通信
- stdout 消息经过严格过滤：空行、命令提示符、非 JSON 格式均被丢弃
- 启动时传入 `InitArgsMessage`（播放状态、曲目信息、主题模式、主题色）

**支持的消息类型**:

| 方向 | 消息类型 | 说明 |
|------|----------|------|
| 主进程 → 桌面歌词 | `PlayerStateChangedMessage` | 播放/暂停状态 |
| 主进程 → 桌面歌词 | `NowPlayingChangedMessage` | 当前曲目信息 |
| 主进程 → 桌面歌词 | `LyricLineChangedMessage` | 当前歌词行（含逐字时长和翻译） |
| 主进程 → 桌面歌词 | `ThemeChangedMessage` | 主题色变更 |
| 主进程 → 桌面歌词 | `ThemeModeChangedMessage` | 亮/暗模式变更 |
| 主进程 → 桌面歌词 | `UnlockMessage` | 解锁桌面歌词 |
| 桌面歌词 → 主进程 | `ControlEventMessage` | 控制事件（暂停/播放/上一曲/下一曲/锁定/关闭） |

#### MacosMediaControlService（macOS 媒体控制）

**文件**: [macos_media_control_service.dart](lib/play_service/macos_media_control_service.dart)

继承 `BaseAudioHandler`（来自 `audio_service` 包），仅在 macOS 平台激活。

- 通过 `AudioService.init` 初始化系统媒体控制
- 使用 `just_audio` 的 `AudioPlayer` 监听播放状态
- 在系统通知栏显示播放控件（上一曲/播放暂停/下一曲）
- 通过回调函数与 `PlaybackService` 交互
- 更新媒体项信息（标题、艺术家、专辑、时长）

---

### 4.3 音乐库 (library)

**文件**: [library/](lib/library/)

#### AudioLibrary（音乐库）

**文件**: [audio_library.dart](lib/library/audio_library.dart)

继承 `ChangeNotifier`，单例模式。从 `index.json` 加载音乐索引，构建三个集合：

| 集合 | 类型 | 说明 |
|------|------|------|
| `audioCollection` | `List<Audio>` | 所有音乐（本地 + 云端） |
| `artistCollection` | `Map<String, Artist>` | 艺术家名 → 艺术家 |
| `albumCollection` | `Map<String, Album>` | 专辑名 → 专辑 |

**初始化流程** (`initFromIndex`):

1. 读取 `index.json`，解析文件夹和音频数据
2. 调用 `_buildCollections()` 建立艺术家-专辑-曲目关联
3. 调用 `_loadCloudAudios()` 加载云音频持久化数据

**云音频管理**:

| 方法 | 说明 |
|------|------|
| `addCloudAudios(cloudAudios)` | 添加云音频到库并持久化 |
| `removeAudio(audio)` | 移除音频（自动清理关联关系） |
| `saveCloudAudios()` | 持久化云音频到 `cloud_audios.json` |
| `rebuildCollections()` | 重建艺术家/专辑集合 |

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
| `path` | String | 绝对路径（本地文件路径或 WebDAV 路径） |
| `modified` / `created` | int | UNIX 时间戳 |
| `by` | String? | 标签来源 (Lofty / Windows API / Cloud) |
| `connectionId` | String? | 云连接 ID（仅云音频） |
| `cover` | Future\<ImageProvider?\> | 48×48 缩略图（带缓存） |
| `mediumCover` | Future\<ImageProvider?\> | 200×200 封面 |
| `largeCover` | Future\<ImageProvider?\> | 400×400 大封面 |
| `isCloudAudio` | bool | 是否为云音频（`by == 'Cloud'`） |
| `subtitleText` | String | 副标题文本（艺术家 - 专辑） |

**封面获取策略**:
- 云音频：优先从缓存文件读取封面
- 本地音频：通过 Rust 层 `getPictureFromPath` 读取
- 缓存 `ImageProvider` 而非 `Uint8List`，避免重复解码（内存从 700MB 降至 250MB）

**Artist** — 艺术家

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | String | 艺术家名 |
| `albumsMap` | Map\<String, Album\> | 关联专辑 |
| `works` | List\<Audio\> | 所有作品 |
| `picture` | Future\<ImageProvider?\> | 200×200 头像（取首首作品封面） |

**Album** — 专辑

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | String | 专辑名 |
| `artistsMap` | Map\<String, Artist\> | 参与的艺术家 |
| `works` | List\<Audio\> | 所有作品 |
| `cover` | Future\<ImageProvider?\> | 200×200 封面（取首首作品封面） |

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

| 类型 | 枚举值 | 说明 |
|------|--------|------|
| `LyricSourceType.qq` | "qq" | QQ 音乐 |
| `LyricSourceType.kugou` | "kugou" | 酷狗 |
| `LyricSourceType.netease` | "netease" | 网易云 |
| `LyricSourceType.local` | "local" | 本地歌词 |

全局变量 `LYRIC_SOURCES` 存储 `Map<String, LyricSource>`（key 为文件路径）。

#### MusicMatcher（在线歌词匹配）

**文件**: [music_matcher.dart](lib/music_matcher.dart)

通过 `music_api` 包同时搜索 QQ 音乐、酷狗、网易云三个平台，按标题/艺术家/专辑的字符相似度评分排序，返回最佳匹配的歌词。

| 函数 | 说明 |
|------|------|
| `uniSearch(audio)` | 多平台统一搜索，每个平台最多取 5 条，按评分排序 |
| `getMostMatchedLyric(audio)` | 获取最佳匹配歌词 |
| `getOnlineLyric(qqSongId, kugouSongHash, neteaseSongId)` | 按 ID 获取指定平台歌词 |

**评分算法** (`_computeScore`): 逐字符比较标题、艺术家、专辑，计算匹配分数占总字符数的比例。

**在线歌词获取策略**:
- QQ 音乐 → `Qrc`（逐字歌词）
- 酷狗 → `Krc`（逐字歌词）
- 网易云 → `Lrc`（非逐字歌词，支持翻译合并）

---

### 4.5 云服务 (cloud_service)

**文件**: [cloud_service/](lib/cloud_service/)

#### CloudConnection（连接模型）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | String | 唯一标识 |
| `name` | String | 连接名称 |
| `type` | CloudServiceType | 服务类型（目前仅 webdav，可扩展 s3/ftp/onedrive/googledrive） |
| `serverUrl` | String | 服务器地址 |
| `username` / `password` | String | 认证信息 |
| `displayName` | String? | 显示名称 |
| `lastSync` | DateTime | 最后同步时间 |
| `isActive` | bool | 是否启用 |

支持 `copyWith` 方法进行不可变复制。

#### CloudServiceManager（连接管理器）

**文件**: [cloud_service_manager.dart](lib/cloud_service/cloud_service_manager.dart)

继承 `ChangeNotifier`，管理所有云连接的 CRUD 操作。

**持久化策略**:
- 连接元信息（不含密码）存储在 `SharedPreferences`（key: `cloud_connections`）
- 密码单独存储在 `FlutterSecureStorage`（key: `cloud_password_{id}`）
- 加载时优先从安全存储读取密码，回退到 SharedPreferences 中的旧密码并迁移

| 方法 | 说明 |
|------|------|
| `addConnection(connection)` | 添加连接（同 ID 则替换） |
| `updateConnection(connection)` | 更新连接 |
| `removeConnection(id)` / `deleteConnection(id)` | 删除连接 |
| `getService(connectionId)` | 获取 WebDavService 实例（懒加载，缓存复用） |
| `getConnection(id)` | 获取连接信息 |
| `ready` | Future，连接加载完成后的 Completer |

#### WebDavService（WebDAV 协议实现）

**文件**: [webdav_service.dart](lib/cloud_service/webdav_service.dart)

| 方法 | 说明 |
|------|------|
| `testConnection()` | 测试连接（HTTP HEAD） |
| `listFiles(directoryPath)` | 列出目录文件（PROPFIND Depth:1） |
| `downloadFile(filePath)` | 下载文件到内存 |
| `getFileUrl(filePath)` | 获取文件直链 URL |
| `getStreamingUrl(filePath)` | 获取流式播放 URL（处理 CDN 重定向） |
| `getAuthHeadersForStreaming(filePath)` | 获取流式播放认证头 |
| `getAuthHeaders()` | 获取 Basic Auth 认证头 |
| `scanAudioFiles(directoryPath)` | 递归扫描目录中的音频文件 |

**WebDavFile 数据模型**:

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | String | 文件路径 |
| `name` | String | 文件名 |
| `isDirectory` | bool | 是否为目录 |
| `size` | int | 文件大小 |
| `lastModified` | DateTime | 最后修改时间 |
| `contentType` | String? | 内容类型 |
| `isAudioFile` | bool | 是否为音频文件（按扩展名判断） |

使用正则解析 WebDAV XML 响应（非 XML DOM），自动过滤隐藏文件和当前目录节点。

**流式播放 URL 解析**:
1. 发送 Range 请求检测 CDN 重定向
2. 如果返回 302/301 且有 Location 头，使用 CDN URL
3. CDN URL 含 `X-Amz-Signature` 时不附加认证头
4. 否则使用原始 URL + Basic Auth

#### CloudAudioPlayer（云音频播放）

**文件**: [cloud_audio_player.dart](lib/cloud_service/cloud_audio_player.dart)

静态工具类，处理云音频的播放、元数据更新和库管理。

**播放策略**:

| 引擎 | 策略 |
|------|------|
| MediaKit | 创建流式 Audio 对象，直接播放网络流，后台缓存 |
| BASS | 下载文件到临时目录，读取元数据后播放，延迟清理 |

| 方法 | 说明 |
|------|------|
| `playCloudFile(service, filePath, fileName, folderFiles, ...)` | 播放云文件（含整个文件夹） |
| `addCloudFolderToPlaylist(service, folderPath, ...)` | 将云文件夹添加到播放列表 |
| `addCloudFilesToPlaylist(service, files, ...)` | 将多个云文件添加到播放列表 |
| `addCloudFolderToLibrary(service, folderPath, ...)` | 将云文件夹扫描到音乐库 |
| `resolveStreamingUrl(webdavPath)` | 解析流式播放 URL 和认证头 |
| `updateMetadataFromCache(audio)` | 从缓存更新云音频元数据 |

**元数据异步更新**:
1. 播放云音频时，先创建占位 Audio 对象（`by: 'Cloud'`）
2. 后台等待缓存完成或下载文件
3. 调用 Rust 层 `buildIndexFromFoldersRecursively` 读取标签
4. 更新 `nowPlaying` 的元数据和封面
5. 同步更新音乐库中的对应记录

**路径-服务映射**: `_pathToService` 静态 Map 缓存 WebDAV 路径到服务的映射，避免重复查找。

#### CloudCacheManager（云缓存管理器）

**文件**: [cloud_cache_manager.dart](lib/cloud_service/cloud_cache_manager.dart)

单例模式，管理云音频文件的本地缓存。

| 方法/属性 | 说明 |
|-----------|------|
| `init()` | 初始化缓存目录和索引 |
| `cacheDir` | 当前缓存目录（支持自定义） |
| `setCacheDirAndPersist(newDir)` | 设置缓存目录并迁移旧缓存 |
| `getCachedFilePath(webdavPath)` | 获取缓存文件路径 |
| `isCached(webdavPath)` | 是否已缓存 |
| `saveToCache(webdavPath, bytes, originalName?)` | 保存字节到缓存 |
| `saveStreamToCache(webdavPath, stream, originalName?)` | 保存流到缓存 |
| `getCacheSize()` | 获取缓存总大小 |
| `getCacheFileCount()` | 获取缓存文件数量 |
| `clearCache()` | 清空缓存 |
| `removeCache(webdavPath)` | 移除指定缓存 |
| `formatSize(bytes)` | 格式化文件大小 |

**缓存索引**:
- 使用 MD5 哈希 WebDAV 路径作为缓存 key
- 索引存储在 `{cacheDir}/cache_index.json`
- 缓存文件命名：`{md5_hash}.{原始扩展名}`

**缓存目录配置**:
- 默认目录：`{用户文档目录}/coriander_player/cloud_cache`
- 自定义目录：持久化到 `cloud_cache_config.json`
- 切换目录时自动迁移缓存文件

#### CloudScanner（云文件扫描）

**文件**: [cloud_scanner.dart](lib/cloud_service/cloud_scanner.dart)

静态工具类，将云文件夹扫描到本地索引。

| 方法 | 说明 |
|------|------|
| `scanCloudFolder(service, folderPath, ...)` | 扫描云文件夹并构建索引 |
| `rescanCloudConnection(service, rootPath, ...)` | 重新扫描云连接 |
| `getSupportedAudioExtensions()` | 获取支持的音频扩展名列表 |

扫描流程：下载云文件到缓存目录 → 调用 Rust 层构建索引 → 更新本地 `index.json`

---

### 4.6 Rust 原生层 (rust)

**文件**: [rust/src/api/](rust/src/api/)

通过 `flutter_rust_bridge` 暴露给 Dart 的 API：

| 模块 | 文件 | 主要功能 |
|------|------|----------|
| **tag_reader** | tag_reader.rs | 音乐标签读取、封面提取、歌词提取、索引构建与增量更新 |
| **smtc_flutter** | smtc_flutter.rs | Windows System Media Transport Controls 集成 |
| **system_theme** | system_theme.rs | 获取系统主题色和暗色模式 |
| **installed_font** | installed_font.rs | 枚举系统已安装字体 |
| **logger** | logger.rs | Rust → Dart 日志桥接 |
| **utils** | utils.rs | 通用工具函数 |

#### tag_reader.rs 详解

**核心数据结构**:

- `Audio` (Rust): 音乐文件元数据（title, artist, album, track, duration, bitrate, sample_rate, path, modified, created, by）
- `AudioFolder` (Rust): 文件夹索引
- `IndexActionState`: 索引操作进度状态（progress + message）

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

- 版本兼容：`index version < LOWEST_VERSION` 时走旧版更新路径
- 删除不存在的文件夹记录
- 对比 `modified` 时间戳跳过未修改的文件夹
- 删除不存在的文件记录
- 重新读取被修改文件的标签
- 添加 `created > latest` 的新文件

#### smtc_flutter.rs 详解

采用条件编译实现平台差异：

| 平台 | 实现 | 说明 |
|------|------|------|
| Windows | `windows_impl` 模块 | 完整的 SMTC 功能 |
| 非 Windows | `non_windows_impl` 模块 | 空实现（所有方法为 no-op） |

**Windows 实现**:
- 使用 `MediaPlayer` + `SystemMediaTransportControls` API
- 支持按钮事件监听（Play/Pause/Next/Previous）
- 支持更新播放状态、时间线属性、显示信息（标题/艺术家/专辑/封面）
- 封面优先从 Lofty 读取，回退到 Windows 缩略图

#### system_theme.rs 详解

| 平台 | 实现 | 说明 |
|------|------|------|
| Windows | `UISettings.GetColorValue()` | 获取系统前景色和强调色 |
| 非 Windows | 硬编码默认值 | 前景色黑色，强调色蓝色 (#007AFF) |

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
- UniDetailPage 通用框架

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
- `CurrentPlaylistView`: 当前播放列表视图
- `PlayerEngineIndicator`: 播放引擎指示器

#### SettingsPage 子页面

| 子页面 | 文件 | 说明 |
|--------|------|------|
| 主题设置 | theme_settings.dart | 亮/暗模式、动态主题、系统主题 |
| 主题选择器 | theme_picker_dialog.dart | 种子色选择 |
| 播放引擎选择 | player_engine_selector.dart | BASS / MediaKit 切换 |
| 缓存设置 | cache_settings.dart | 云缓存目录和大小管理 |
| 艺术家分隔符 | artist_separator_editor.dart | 自定义艺术家分隔符 |
| 检查更新 | check_update.dart | GitHub Release 检查 |
| 提交 Issue | create_issue.dart | GitHub Issue 创建 |

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
| `HorizontalLyricView` | 水平歌词视图（迷你播放条用） |

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
| `artistSplitPattern` | String | "/\|、" | 分隔符正则模式 |
| `localLyricFirst` | bool | true | 本地歌词优先 |
| `windowSize` | Size | 1280×756 | 窗口尺寸 |
| `isWindowMaximized` | bool | false | 窗口最大化 |
| `fontFamily` / `fontPath` | String? | null | 自定义字体 |
| `playerEngineType` | PlayerEngineType? | null | 播放器引擎类型 |

**版本兼容**: 支持 `_readFromJson_old` 读取旧版格式（数值型布尔值），新版使用原生布尔值。

**数据迁移**: `migrateAppData()` 将旧目录（`AppData/Roaming/com.example/coriander_player`）的数据迁移到新目录（`Documents/coriander_player`）。

#### AppPreference

**文件**: [app_preference.dart](lib/app_preference.dart)

单例模式，持久化到 `app_preference.json`。存储各页面的排序方式、排序顺序、内容视图偏好以及播放偏好（播放模式、音量）。

| 偏好类 | 字段 | 说明 |
|--------|------|------|
| `PagePreference` | sortMethod, sortOrder, contentView | 页面排序和视图偏好 |
| `NowPlayingPagePreference` | nowPlayingViewMode, lyricTextAlign, lyricFontSize, translationFontSize | 正在播放页面偏好 |
| `PlaybackPreference` | playMode, volumeDsp | 播放偏好 |

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

**主题变更联动**:
- 通知桌面歌词进程（主题色 + 主题模式）
- `applyThemeFromAudio` 同时生成亮色和暗色两套主题

**系统主题获取**:
- Windows：通过 Rust 层 `SystemTheme.getSystemTheme()` 获取
- macOS：硬编码默认蓝色 (#3B82F6)，暗色模式通过 `PlatformHelper.getSystemThemeMode()` 获取

---

### 4.12 平台适配 (platform_helper / platform_dependency_manager)

#### PlatformHelper

**文件**: [platform_helper.dart](lib/platform_helper.dart)

纯静态工具类，提供跨平台路径、BASS 库路径、桌面歌词路径等平台相关逻辑。

| 属性/方法 | 说明 |
|-----------|------|
| `isMacOS` / `isWindows` / `isLinux` / `isDesktop` | 平台判断 |
| `bassLibraryExtension` | BASS 库扩展名（dll/dylib/so） |
| `bassLibraryPath` | BASS 主库路径 |
| `bassWasapiLibraryPath` | WASAPI 库路径（仅 Windows） |
| `bassPluginPaths` | BASS 插件路径列表 |
| `desktopLyricExecutablePath` | 桌面歌词可执行文件路径 |
| `normalizePath(filePath)` | 路径标准化 |
| `joinPaths(paths)` | 跨平台路径拼接 |
| `pathSeparator` | 路径分隔符 |
| `supportsWasapi()` / `isWasapiSupported` | 是否支持 WASAPI |
| `getSystemTheme()` | 获取系统主题信息 |
| `getSystemThemeMode()` | 获取系统主题模式 |
| `getDefaultSystemThemeColor()` | 获取默认系统主题色 |

**桌面歌词路径**:
- Windows: `{exe目录}/desktop_lyric/desktop_lyric.exe`
- macOS: `{exe目录}/../Frameworks/desktop_lyric/desktop_lyric.app/Contents/MacOS/desktop_lyric`

#### PlatformDependencyManager

**文件**: [platform_dependency_manager.dart](lib/platform_dependency_manager.dart)

单例模式，管理平台特定依赖的初始化和查询。

| 方法 | 说明 |
|------|------|
| `initialize()` | 初始化平台依赖（加载设备和包信息） |
| `getSupportedPlayerEngines()` | 获取当前平台支持的引擎列表 |
| `isPlayerEngineSupported(type)` | 检查引擎是否受支持 |
| `getRecommendedPlayerEngine()` | 获取推荐引擎 |
| `checkRuntimePermissions()` | 检查运行时权限 |
| `getPlatformInfo()` | 获取平台信息字符串 |

**引擎支持矩阵**:

| 平台 | BASS | MediaKit |
|------|------|----------|
| Windows | ✅ | ✅ |
| macOS | ✅ | ✅ |
| Linux | ✅ | ✅ |
| Android | ❌ | ✅ |
| iOS | ❌ | ✅ |

**推荐引擎**: Windows/macOS → BASS，其他 → MediaKit

---

### 4.13 快捷键系统 (hotkeys_helper)

**文件**: [hotkeys_helper.dart](lib/hotkeys_helper.dart)

静态工具类，管理应用内快捷键的注册和注销。

| 快捷键 | 作用域 | 功能 |
|--------|--------|------|
| `Space` | inapp | 播放/暂停 |
| `Escape` | inapp | 关闭弹窗/返回上一级 |
| `Ctrl + ←` | inapp | 上一曲 |
| `Ctrl + →` | inapp | 下一曲 |

**焦点管理**: 当文本框获得焦点时注销快捷键，失去焦点时重新注册（`onFocusChanges`）。

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
| `CloudCacheManager` | `CloudCacheManager.instance` | 云缓存管理 |
| `MacosMediaControlService` | `MacosMediaControlService()` | macOS 媒体控制（工厂构造） |

### ChangeNotifier 提供者

| 类 | 通知时机 | Provider 位置 |
|----|----------|---------------|
| `ThemeProvider` | 主题色/模式变更 | Entry (MultiProvider) |
| `CloudServiceManager` | 云连接增删改 | Entry (MultiProvider) |
| `PlaybackService` | nowPlaying 变更 | 直接监听 |
| `LyricService` | 歌词变更 | 直接监听 |
| `DesktopLyricService` | 桌面歌词状态变更 | 直接监听 |
| `AudioLibrary` | 音乐库变更 | 直接监听 |

### Rust API (通过 flutter_rust_bridge)

| Dart 函数 | Rust 函数 | 说明 |
|-----------|-----------|------|
| `buildIndexFromFoldersRecursively()` | `build_index_from_folders_recursively()` | 构建音乐索引 |
| `updateIndex()` | `update_index()` | 增量更新索引 |
| `getPictureFromPath()` | `get_picture_from_path()` | 获取封面图片 |
| `getLyricFromPath()` | `get_lyric_from_path()` | 获取歌词文本 |
| `getSystemTheme()` | `get_system_theme()` | 获取系统主题色 |
| `initRustLogger()` | `init_rust_logger()` | 初始化日志流 |

### 全局变量与工具

| 变量/函数 | 文件 | 说明 |
|-----------|------|------|
| `LOGGER` | utils.dart | 全局日志器 (logger 包) |
| `SCAFFOLD_MESSAGER` | utils.dart | 全局 ScaffoldMessengerKey |
| `ROUTER_KEY` | utils.dart | 全局 GoRouter NavigatorKey |
| `LYRIC_SOURCES` | lyric_source.dart | 歌词来源映射表 |
| `getAppDataDir()` | app_settings.dart | 获取应用数据目录 |
| `migrateAppData()` | app_settings.dart | 迁移旧版数据 |
| `readLyricSources()` / `saveLyricSources()` | lyric_source.dart | 歌词来源读写 |

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
  │         │    │    │    ├── bass_player_engine.dart
  │         │    │    │    │    └── src/bass/* (BassPlayer)
  │         │    │    │    └── media_kit_player_engine.dart
  │         │    │    │         └── media_kit (外部包)
  │         │    │    ├── src/rust/api/smtc_flutter.dart (Windows)
  │         │    │    └── macos_media_control_service.dart (macOS)
  │         │    │         └── audio_service + just_audio
  │         │    ├── lyric_service.dart
  │         │    │    ├── lyric/* (Lrc/Qrc/Krc)
  │         │    │    └── music_matcher.dart
  │         │    │         └── music_api (外部包)
  │         │    └── desktop_lyric_service.dart
  │         │         └── desktop_lyric (外部包)
  │         ├── library/* (AudioLibrary, Playlist)
  │         │    └── src/rust/api/tag_reader.dart
  │         └── cloud_service/* (WebDavService)
  │              ├── cloud_audio_player.dart
  │              │    └── cloud_cache_manager.dart
  │              └── cloud_scanner.dart
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
    │    ├── 判断是否云音频
    │    │    ├── 云 + MediaKit → CloudCacheManager.getCachedFilePath()
    │    │    │    ├── 有缓存 → _player.setSource(cachedPath)
    │    │    │    └── 无缓存 → CloudAudioPlayer.resolveStreamingUrl()
    │    │    │         └── _player.setSource(url, isNetwork: true)
    │    │    │         └── _cacheStreamInBackground()  ← 后台缓存
    │    │    ├── 云 + BASS → 提示切换引擎
    │    │    └── 本地 → _player.setSource(path)
    │    ├── PlayerEngine.play()              ← 开始播放
    │    ├── LyricService.updateLyric()       ← 获取歌词
    │    │    ├── Lrc.fromAudioPath()         ← 本地歌词
    │    │    └── getMostMatchedLyric()        ← 在线歌词
    │    │         └── music_api (QQ/Kugou/Netease)
    │    ├── ThemeProvider.applyThemeFromAudio() ← 动态主题
    │    ├── SMTC.updateDisplay()             ← 系统媒体控制 (Windows)
    │    ├── MacosMediaControl.updateCurrentMediaItem() ← macOS 媒体控制
    │    └── DesktopLyricService.send*()      ← 桌面歌词
    │
    ▼
PlayerEngine.positionStream ──→ LyricService (歌词同步)
                              ──→ SMTC (进度更新)
                              ──→ MacosMediaControl (进度更新)
                              ──→ DesktopLyricService (歌词行推送)
```

### 云音频数据流

```
用户浏览云文件
    │
    ▼
CloudFileBrowser
    ├── WebDavService.listFiles(path)     ← PROPFIND 请求
    └── 用户点击播放
         │
         ▼
    CloudAudioPlayer.playCloudFile()
         ├── MediaKit 引擎:
         │    ├── _createStreamingAudio()   ← 创建占位 Audio
         │    ├── PlaybackService.play()    ← 流式播放
         │    └── _updateMetadataAsync()    ← 后台更新元数据
         │         ├── 等待缓存完成
         │         ├── buildIndexFromFoldersRecursively() ← Rust 读取标签
         │         ├── 更新 nowPlaying 元数据
         │         └── _updateLibraryAudioMetadata() ← 同步到音乐库
         └── BASS 引擎:
              ├── _downloadToTempDir()      ← 下载到临时目录
              ├── _createAudioWithMetadata() ← 读取元数据
              └── PlaybackService.play()    ← 本地文件播放
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
| `cloud_audios.json` | JSON | 云音频持久化数据 |
| `cloud_connections` | SharedPreferences | 云连接元信息 |
| `cloud_password_*` | FlutterSecureStorage | 云连接密码（加密） |
| `cloud_cache/` | 目录 | 云音频缓存文件 |
| `cloud_cache/cache_index.json` | JSON | 云缓存索引 |
| `cloud_cache_config.json` | JSON | 云缓存目录配置 |

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

### cloud_audios.json 结构

```json
[
  {
    "title": "Cloud Song",
    "artist": "",
    "album": "",
    "track": 0,
    "duration": 0,
    "bitrate": null,
    "sample_rate": null,
    "path": "/music/cloud_song.flac",
    "modified": 1700000000,
    "created": 1700000000,
    "by": "Cloud",
    "connection_id": "conn_abc123"
  }
]
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

**必需的 BASS 库文件**:

| Windows | macOS | 说明 |
|---------|-------|------|
| bass.dll | libbass.dylib | 主库 |
| bassape.dll | libbassape.dylib | APE 格式 |
| bassdsd.dll | libbassdsd.dylib | DSD 格式 |
| bassflac.dll | libbassflac.dylib | FLAC 格式 |
| bassmidi.dll | libbassmidi.dylib | MIDI 格式 |
| bassopus.dll | libbassopus.dylib | Opus 格式 |
| basswv.dll | libbasswv.dylib | WavPack 格式 |
| basswasapi.dll | — | WASAPI（仅 Windows） |

### flutter_rust_bridge 代码生成

```bash
# 配置文件: flutter_rust_bridge.yaml
# rust_input: rust/src/api/**/*.rs
# dart_output: lib/src/rust

# 重新生成绑定代码
flutter_rust_bridge_codegen generate
```

### 桌面歌词构建

**Windows**:
```bash
# Release 模式（默认）
powershell -ExecutionPolicy Bypass -File .\windows\build_desktop_lyric.ps1
# Debug 模式
powershell -ExecutionPolicy Bypass -File .\windows\build_desktop_lyric.ps1 -BuildMode Debug
```

**macOS**:
```bash
# Debug 模式（默认）
chmod +x ./macos/build_desktop_lyric.sh && ./macos/build_desktop_lyric.sh
# Release 模式
./macos/build_desktop_lyric.sh --build-mode release
# 构建并安装到应用包
./macos/build_desktop_lyric.sh --build-mode debug --install-to-app
```

---

## 9. 平台差异说明

| 特性 | Windows | macOS |
|------|---------|-------|
| **默认播放引擎** | BASS | BASS |
| **WASAPI 独占模式** | ✅ 支持 | ❌ 不支持 |
| **系统媒体控制** | SMTC (WinRT) | audio_service + just_audio |
| **系统主题色获取** | WinRT API (UISettings) | 硬编码蓝色 (#3B82F6) |
| **BASS 库格式** | .dll | .dylib |
| **BASS 库路径** | exe目录/BASS/ | app/Frameworks/BASS/ |
| **桌面歌词** | .exe 可执行文件 | .app 包 |
| **文件选择器** | filepicker_windows | file_picker |
| **全局快捷键** | hotkey_manager | hotkey_manager |
| **标签读取回退** | Windows API (StorageFile) | 仅 Lofty |
| **封面获取回退** | Windows API (Thumbnail) | 仅 Lofty |
| **窗口标题栏** | 隐藏 (自定义) | 系统标准 |
| **云音频流式播放** | MediaKit 引擎支持 | MediaKit 引擎支持 |
| **密码安全存储** | FlutterSecureStorage | FlutterSecureStorage |
| **多窗口** | — | desktop_multi_window |
