# Coriander Player 代码文档

> 版本: 1.5.1  
> 最后更新: 2025-08-03

## 目录

- [项目概述](#项目概述)
- [整体架构](#整体架构)
- [主要模块职责](#主要模块职责)
- [核心类与函数说明](#核心类与函数说明)
- [依赖关系](#依赖关系)
- [数据模型](#数据模型)
- [项目运行方式](#项目运行方式)
- [编译构建](#编译构建)

---

## 项目概述

**Coriander Player** 是一款使用 Material You 配色的本地音乐播放器，采用 Flutter + Rust 混合开发架构。主要功能包括：

- 本地音乐库管理与索引
- 多格式音频播放（BASS 音频库）
- LRC/逐字歌词解析与显示
- 桌面歌词组件集成
- 动态主题色（跟随专辑封面）
- Windows 系统媒体控制集成（SMTC）
- 在线歌词匹配（QQ/网易云/酷狗）

---

## 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter UI Layer                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │  Pages   │ │Component  │ │ Services │ │   Play Services  │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                     Business Logic Layer                        │
│  ┌──────────────┐ ┌──────────────┐ ┌────────────────────────┐ │
│  │AudioLibrary  │ │LyricService  │ │    MusicMatcher         │ │
│  └──────────────┘ └──────────────┘ └────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                       Native Bridge Layer                       │
│  ┌─────────────────────┐    ┌─────────────────────────────┐  │
│  │   BASS Audio (FFI)   │    │  Rust API (flutter_rust_bridge) │ │
│  └─────────────────────┘    └─────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                         Rust Backend                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │TagReader │ │SystemTheme│ │  SMTC   │ │  InstalledFont   │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 技术栈

| 层级 | 技术 |
|------|------|
| UI框架 | Flutter 3.29.0 |
| 状态管理 | Provider |
| 路由 | go_router |
| 音频播放 | BASS Library (FFI) |
| 原生功能 | Rust + flutter_rust_bridge |
| 音乐标签 | Lofty (Rust) |
| 窗口管理 | window_manager |
| 热键 | hotkey_manager |

---

## 主要模块职责

### 目录结构

```
lib/
├── main.dart              # 应用入口
├── entry.dart             # 根组件与路由配置
├── app_settings.dart      # 应用设置管理
├── app_preference.dart    # 用户偏好设置
├── app_paths.dart         # 路由路径常量
├── theme_provider.dart    # 主题状态管理
├── hotkeys_helper.dart    # 全局快捷键
├── music_matcher.dart     # 在线音乐匹配
├── utils.dart             # 工具函数
│
├── component/             # 可复用UI组件
│   ├── app_shell.dart         # 应用外壳（响应式布局）
│   ├── title_bar.dart         # 自定义标题栏
│   ├── side_nav.dart          # 侧边导航
│   ├── mini_now_playing.dart  # 迷你播放器
│   ├── album_tile.dart        # 专辑列表项
│   ├── artist_tile.dart       # 艺术家列表项
│   ├── audio_tile.dart        # 音频列表项
│   └── ...
│
├── page/                  # 页面
│   ├── audios_page.dart         # 音乐库页面
│   ├── artists_page.dart       # 艺术家列表页
│   ├── albums_page.dart        # 专辑列表页
│   ├── folders_page.dart       # 文件夹浏览页
│   ├── playlists_page.dart     # 播放列表页
│   ├── search_page/            # 搜索功能
│   ├── now_playing_page/       # 正在播放页面
│   ├── settings_page/          # 设置页面
│   └── ...
│
├── play_service/          # 播放服务
│   ├── play_service.dart       # 播放服务主入口
│   ├── playback_service.dart   # 播放控制服务
│   ├── lyric_service.dart      # 歌词服务
│   └── desktop_lyric_service.dart  # 桌面歌词服务
│
├── library/               # 数据模型
│   ├── audio_library.dart      # 音乐库模型
│   └── playlist.dart          # 播放列表模型
│
├── lyric/                 # 歌词解析
│   ├── lyric.dart             # 歌词基类
│   ├── lrc.dart               # LRC歌词解析
│   ├── krc.dart               # KRC歌词解析（酷狗）
│   ├── qrc.dart               # QRC歌词解析（QQ）
│   └── lyric_source.dart      # 歌词来源管理
│
└── src/
    ├── bass/              # BASS音频库绑定
    │   ├── bass.dart          # BASS FFI绑定
    │   ├── bass_player.dart   # 播放器封装
    │   └── bass_wasapi.dart   # WASAPI独占模式
    │
    └── rust/              # Rust API绑定
        ├── frb_generated.dart    # 自动生成的桥接代码
        └── api/                  # Rust API接口
            ├── tag_reader.dart
            ├── system_theme.dart
            ├── smtc_flutter.dart
            ├── installed_font.dart
            └── logger.dart
```

### 模块职责详解

#### 1. 播放服务 (play_service/)

| 模块 | 职责 |
|------|------|
| `play_service.dart` | 服务容器，管理 PlaybackService、LyricService、DesktopLyricService |
| `playback_service.dart` | 核心播放控制：播放/暂停/上一曲/下一曲/进度/音量/WASAPI独占模式 |
| `lyric_service.dart` | 歌词管理：加载歌词、同步歌词行、处理歌词来源切换 |
| `desktop_lyric_service.dart` | 桌面歌词进程管理、消息通信 |

#### 2. 歌词模块 (lyric/)

| 模块 | 职责 |
|------|------|
| `lyric.dart` | 定义歌词抽象基类：`Lyric`、`LyricLine`、`SyncLyricLine`、`UnsyncLyricLine` |
| `lrc.dart` | LRC歌词文件解析，支持内嵌歌词和外挂歌词 |
| `krc.dart` | 酷狗KRC逐字歌词解析 |
| `qrc.dart` | QQ QRC逐字歌词解析 |
| `lyric_source.dart` | 歌词来源管理（本地/在线） |

#### 3. 音乐库 (library/)

| 模块 | 职责 |
|------|------|
| `audio_library.dart` | 音乐库数据模型：`Audio`、`AudioFolder`、`Artist`、`Album` |
| `playlist.dart` | 播放列表管理 |

#### 4. Rust API (src/rust/)

| 模块 | 职责 |
|------|------|
| `tag_reader.rs` | 音乐标签读取（使用Lofty库）、音乐库索引构建与更新、图片缩略图获取 |
| `system_theme.rs` | Windows系统主题色获取 |
| `smtc_flutter.rs` | Windows系统媒体传输控制（SMTC）集成 |
| `installed_font.rs` | 系统已安装字体枚举 |
| `logger.rs` | 日志输出到Flutter端 |

---

## 核心类与函数说明

### Flutter 核心类

#### PlaybackService

```dart
class PlaybackService extends ChangeNotifier
```

**职责**: 管理音频播放的核心服务

**主要属性**:
| 属性 | 类型 | 说明 |
|------|------|------|
| `nowPlaying` | `Audio?` | 当前播放的音频 |
| `playlist` | `ValueNotifier<List<Audio>>` | 播放列表 |
| `playMode` | `ValueNotifier<PlayMode>` | 播放模式 |
| `shuffle` | `ValueNotifier<bool>` | 随机播放状态 |
| `volumeDsp` | `double` | 解码音量（不影响系统音量） |
| `wasapiExclusive` | `ValueNotifier<bool>` | WASAPI独占模式 |

**主要方法**:
| 方法 | 说明 |
|------|------|
| `play(int audioIndex, List<Audio> playlist)` | 播放指定曲目 |
| `pause()` | 暂停播放 |
| `start()` | 恢复播放 |
| `nextAudio()` | 下一曲 |
| `lastAudio()` | 上一曲 |
| `seek(double position)` | 跳转到指定位置 |
| `setPlayMode(PlayMode mode)` | 设置播放模式 |
| `useShuffle(bool flag)` | 切换随机播放 |

**播放模式枚举**:
```dart
enum PlayMode {
  forward,    // 顺序播放到结尾
  loop,       // 循环播放列表
  singleLoop, // 单曲循环
}
```

#### BassPlayer

```dart
class BassPlayer
```

**职责**: BASS音频库的Dart封装，处理底层音频播放

**主要方法**:
| 方法 | 说明 |
|------|------|
| `BassPlayer()` | 初始化BASS库和插件 |
| `setSource(String path)` | 设置音频源 |
| `start()` | 开始/恢复播放 |
| `pause()` | 暂停播放 |
| `seek(double position)` | 跳转播放位置 |
| `setVolumeDsp(double volume)` | 设置解码音量 |
| `useExclusiveMode(bool exclusive)` | 切换WASAPI独占模式 |
| `free()` | 释放资源 |

**播放器状态**:
```dart
enum PlayerState {
  stopped,      // 停止
  playing,      // 播放中
  paused,       // 暂停
  pausedDevice, // 设备暂停
  stalled,      // 数据不足
  completed,   // 播放完成
  unknown,      // 未知
}
```

#### LyricService

```dart
class LyricService extends ChangeNotifier
```

**职责**: 管理歌词的加载和同步

**主要方法**:
| 方法 | 说明 |
|------|------|
| `updateLyric()` | 根据设置更新歌词 |
| `useLocalLyric()` | 使用本地歌词 |
| `useOnlineLyric()` | 使用在线歌词 |
| `useSpecificLyric(Lyric lyric)` | 使用指定歌词 |
| `findCurrLyricLine()` | 重新计算当前歌词行 |
| `lyricLineStream` | 歌词行变更流 |

#### ThemeProvider

```dart
class ThemeProvider extends ChangeNotifier
```

**职责**: 管理应用主题和颜色方案

**主要方法**:
| 方法 | 说明 |
|------|------|
| `applyTheme(Color seedColor)` | 应用指定主题色 |
| `applyThemeFromImage(ImageProvider image, ThemeMode themeMode)` | 从图片生成主题 |
| `applyThemeFromAudio(Audio audio)` | 从音频封面生成主题 |
| `applyThemeMode(ThemeMode themeMode)` | 切换主题模式 |
| `changeFontFamily(String? fontFamily)` | 更换字体 |

#### AudioLibrary

```dart
class AudioLibrary
```

**职责**: 管理本地音乐库数据

**主要类型**:

```dart
class Audio {
  String title;           // 标题
  String artist;          // 艺术家
  String album;           // 专辑
  int track;              // 曲目号
  int duration;          // 时长（秒）
  int? bitrate;          // 比特率
  int? sampleRate;        // 采样率
  String path;            // 文件路径
  int modified;          // 修改时间戳
  int created;            // 创建时间戳
  String? by;             // 标签来源
  List<String> splitedArtists; // 分割后的艺术家列表
}

class AudioFolder {
  List<Audio> audios;
  String path;            // 文件夹路径
  int modified;           // 文件夹修改时间
  int latest;             // 最新文件时间
}

class Artist {
  String name;
  Map<String, Album> albumsMap;  // 所属专辑
  List<Audio> works;             // 作品列表
}

class Album {
  String name;
  Map<String, Artist> artistsMap; // 参与艺术家
  List<Audio> works;              // 作品列表
}
```

### Rust 核心函数

#### tag_reader.rs

```rust
// 构建音乐库索引（递归扫描文件夹）
pub fn build_index_from_folders_recursively(
    folders: Vec<String>,
    index_path: String,
    sink: StreamSink<IndexActionState>,
) -> Result<(), io::Error>

// 更新音乐库索引（增量更新）
pub fn update_index(
    index_path: String,
    sink: StreamSink<IndexActionState>,
) -> anyhow::Result<()>

// 从音乐文件获取图片（支持Lofty和Windows API）
pub fn get_picture_from_path(path: String, width: u32, height: u32) -> Option<Vec<u8>>

// 从音乐文件或LRC文件获取歌词
pub fn get_lyric_from_path(path: String) -> Option<String>
```

#### smtc_flutter.rs

```rust
// 订阅SMTC控制事件
pub fn subscribe_to_control_events(&self, sink: StreamSink<SMTCControlEvent>)

// 更新播放状态
pub fn update_state(&self, state: SMTCState)

// 更新时间属性
pub fn update_time_properties(&self, progress: u32)

// 更新显示信息
pub fn update_display(
    &self,
    title: String,
    artist: String,
    album: String,
    duration: u32,
    path: String,
)
```

#### system_theme.rs

```rust
// 获取Windows系统主题色
pub fn get_system_theme() -> SystemTheme

struct SystemTheme {
    fore: (u8, u8, u8, u8),    // 前景色 a,r,g,b
    accent: (u8, u8, u8, u8),  // 强调色 a,r,g,b
}
```

### 歌词解析类

#### Lrc

```dart
class Lrc extends Lyric {
  LrcSource source;  // 歌词来源：local(本地) 或 web(网络)

  // 从LRC文本解析
  static Lrc? fromLrcText(String lrc, LrcSource source, {String? separator})

  // 从音频文件读取歌词
  static Future<Lrc?> fromAudioPath(Audio belongTo, {String? separator})
}
```

#### LrcLine

```dart
class LrcLine extends UnsyncLyricLine {
  bool isBlank;    // 是否为空行（用于间奏识别）
  Duration length; // 持续时长

  // 从行文本解析
  static LrcLine? fromLine(String line, [int? offset])
}
```

---

## 依赖关系

### pubspec.yaml 依赖

```yaml
dependencies:
  flutter:
    sdk: flutter

  # 路由
  go_router: ^14.0.1

  # UI
  material_color_utilities: ^0.11.1
  material_symbols_icons: ^4.2719.1
  flex_color_picker: ^3.5.0

  # 窗口管理
  window_manager: ^0.3.8

  # 状态管理
  provider: ^6.1.1

  # 文件处理
  path_provider: ^2.0.15
  path: ^1.8.3
  filepicker_windows: ^2.1.4

  # FFI
  ffi: ^2.1.0

  # 本地化
  flutter_localizations:
    sdk: flutter

  # GitHub
  github: ^9.24.0

  # Markdown
  flutter_markdown: ^0.7.1

  # 拼音
  pinyin: ^3.3.0

  # 热键
  hotkey_manager: ^0.2.3

  # 日志
  logger: ^2.4.0

  # Rust 桥接
  flutter_rust_bridge: 2.8.0
  rust_lib_coriander_player:
    path: rust_builder

  # 外部组件
  desktop_lyric:  # 桌面歌词组件（独立仓库）
  music_api:      # 在线音乐API（独立仓库）
```

### Rust Cargo.toml 依赖

```toml
[dependencies]
flutter_rust_bridge = "=2.8.0"      # Flutter-Rust桥接
lofty = "0.21.1"                     # 音乐标签读取
serde_json = "1.0.117"               # JSON序列化
phf = "0.11"                         # 静态Map
image = "0.25.2"                     # 图片处理
ttf-parser = "0.24.1"                # 字体解析
anyhow = "1.0.86"                    # 错误处理

# Windows API
windows = "0.57.0"  # 包含特性:
  # Media_Playback, Storage, Storage_Streams
  # Storage_FileProperties, Storage_Pickers
  # Foundation, UI_ViewManagement
```

### 外部依赖库

| 库名 | 用途 | 仓库 |
|------|------|------|
| BASS | 音频播放 | un4seen.com |
| Lofty | 音乐标签读取 | crates.io/crates/lofty |
| music_api | 在线音乐搜索/歌词 | github.com/Ferry-200/music_api_dart |
| desktop_lyric | 桌面歌词组件 | github.com/Ferry-200/desktop_lyric |

---

## 数据模型

### 应用设置 (AppSettings)

```dart
class AppSettings {
  ThemeMode themeMode;        // 主题模式：亮/暗/系统
  int defaultTheme;           // 默认主题色
  bool dynamicTheme;          // 是否启用动态主题
  bool useSystemTheme;        // 是否跟随系统主题色
  bool useSystemThemeMode;    // 是否跟随系统主题模式
  List artistSeparator;       // 艺术家分隔符
  bool localLyricFirst;       // 本地歌词优先
  Size windowSize;            // 窗口大小
  String? fontFamily;         // 自定义字体
  String? fontPath;           // 字体文件路径
}
```

### 用户偏好 (AppPreference)

存储播放相关的用户偏好设置，如播放模式、音量等。

### 歌词来源 (LyricSource)

```dart
enum LyricSourceType { local, web }

class LyricSource {
  LyricSourceType source;
  int? qqSongId;        // QQ音乐ID
  String? kugouSongHash; // 酷狗音乐Hash
  String? neteaseSongId; // 网易云音乐ID
}
```

### 搜索结果 (SongSearchResult)

```dart
class SongSearchResult {
  ResultSource source;  // 来源：qq/kugou/netease
  String title;
  String artists;
  String album;
  double score;         // 匹配分数
  int? qqSongId;
  String? neteaseSongId;
  String? kugouSongHash;
}
```

---

## 项目运行方式

### 开发环境要求

1. Flutter SDK 3.1.4+
2. Rust 工具链
3. Windows 10/11

### 目录布局

```
coriander_player/
├── lib/                    # Flutter Dart 代码
├── rust/                   # Rust 后端代码
├── rust_builder/           # Rust 库构建配置
├── windows/                # Windows 平台配置
├── test_driver/            # 集成测试
├── desktop_lyric/          # 桌面歌词（需单独编译）
│   └── desktop_lyric.exe
├── BASS/                   # BASS 音频库
│   ├── bass.dll
│   ├── bassape.dll
│   ├── bassdsd.dll
│   ├── bassflac.dll
│   ├── bassmidi.dll
│   ├── bassopus.dll
│   ├── basswv.dll
│   └── basswasapi.dll
├── pubspec.yaml
└── Cargo.toml
```

### 数据存储

应用数据存储在用户文档目录下：
```
C:\Users\<username>\Documents\coriander_player\
├── settings.json      # 应用设置
├── app_preference.json # 用户偏好
├── index.json         # 音乐库索引
└── playlists/         # 播放列表
```

---

## 编译构建

### 1. 编译主程序

```bash
# 开发模式
flutter run -d windows

# 发布模式
flutter build windows --release
```

### 2. 编译桌面歌词组件

桌面歌词是独立项目，需要单独编译：

```bash
git clone https://github.com/Ferry-200/desktop_lyric.git
cd desktop_lyric
flutter build windows --release
```

将编译产物 `desktop_lyric.exe` 放在主程序目录下：
```
coriander_player/
└── desktop_lyric/
    └── desktop_lyric.exe
```

### 3. 配置 BASS 音频库

下载 BASS 库（64位版本），将以下文件放在程序目录下：
```
coriander_player/
└── BASS/
    ├── bass.dll
    ├── bassape.dll
    ├── bassdsd.dll
    ├── bassflac.dll
    ├── bassmidi.dll
    ├── bassopus.dll
    ├── basswv.dll
    └── basswasapi.dll
```

### 4. 运行应用

编译完成后直接运行可执行文件。

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Esc` | 返回上一级 |
| `空格` | 暂停/播放 |
| `Ctrl + 左方向键` | 上一曲 |
| `Ctrl + 右方向键` | 下一曲 |

---

## 支持的音频格式

| 格式 | 支持情况 | 标签来源 |
|------|----------|----------|
| mp3/mp2/mp1 | ✓ | Lofty/Windows |
| ogg | ✓ | Lofty |
| wav/wave | ✓ | Lofty |
| aif/aiff/aifc | ✓ | Lofty |
| asf/wma | ✓ | Windows |
| aac/adts | ✓ | Lofty |
| m4a | ✓ | Lofty |
| ac3 | ✓ | - |
| amr/3ga | ✓ | - |
| flac | ✓ | Lofty |
| mpc | ✓ | Lofty |
| mid | ✓ | BASS插件 |
| wv/wvc | ✓ | BASS插件 |
| opus | ✓ | Lofty |
| dsf/dff | ✓ | - |
| ape | ✓ | BASS插件 |

---

## 支持的歌词格式

### 内嵌歌词（直接读取）
- AAC、AIFF、FLAC、M4A、MP3、OGG、Opus、WAV

### 外挂歌词（LRC文件）
- 编码支持：UTF-8、UTF-16

---

## 架构亮点

### 1. Flutter-Rust 混合架构
使用 `flutter_rust_bridge` 实现 Flutter 与 Rust 的高效通信，将标签读取、图片处理等耗时操作放在 Rust 后端。

### 2. BASS 音频库 FFI 封装
通过 Dart FFI 直接调用 BASS 音频库，支持多种音频格式和 WASAPI 独占模式。

### 3. 动态主题
支持从专辑封面图片提取主题色，实现 Material You 动态配色效果。

### 4. 桌面歌词集成
独立的桌面歌词进程，通过标准输入/输出进行进程间通信。

### 5. SMTC 集成
深度集成 Windows 系统媒体传输控制，支持系统媒体键和通知中心控制。

### 6. 增量索引更新
音乐库索引支持增量更新，只重新扫描修改过的文件，提高启动速度。

---

## 文件清单

| 文件路径 | 说明 |
|----------|------|
| [main.dart](lib/main.dart) | 应用入口，初始化窗口、Rust、日志 |
| [entry.dart](lib/entry.dart) | 根组件，配置 GoRouter 路由 |
| [app_settings.dart](lib/app_settings.dart) | 应用设置管理 |
| [play_service/playback_service.dart](lib/play_service/playback_service.dart) | 播放服务核心 |
| [play_service/lyric_service.dart](lib/play_service/lyric_service.dart) | 歌词服务 |
| [library/audio_library.dart](lib/library/audio_library.dart) | 音乐库数据模型 |
| [src/bass/bass_player.dart](lib/src/bass/bass_player.dart) | BASS播放器封装 |
| [rust/src/api/tag_reader.rs](rust/src/api/tag_reader.rs) | Rust音乐标签读取 |
| [rust/src/api/smtc_flutter.rs](rust/src/api/smtc_flutter.rs) | Rust SMTC控制 |
