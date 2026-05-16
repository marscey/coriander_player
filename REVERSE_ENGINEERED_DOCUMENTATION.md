# Coriander Player 逆向工程文档

## 1. 项目概述

Coriander Player 是一款使用 Material You 配色的跨平台音乐播放器，支持本地音乐播放和 WebDAV 私有云集成。项目基于 Flutter 框架开发，目前已支持 Windows 和 macOS 平台。

### 1.1 项目背景

该项目是基于 [Ferry-200](https://github.com/Ferry-200/coriander_player) 的开源项目 fork 而来，目标是开发一款跨平台的本地及网盘音乐播放器，新增了对 WebDAV 私有云和 macOS 平台的支持。

### 1.2 核心价值

- 提供美观、易用的音乐播放体验
- 支持多种音频格式和歌词格式
- 支持本地音乐管理和 WebDAV 云音乐集成
- 提供个性化主题和桌面歌词功能
- 跨平台支持（Windows、macOS）

## 2. 功能需求

### 2.1 核心播放器功能

| 功能项 | 描述 | 状态 |
|-------|------|------|
| 音频格式支持 | 支持多种音频格式播放（mp3, flac, aac, m4a, wav, ogg等） | 已实现 |
| 本地音乐管理 | 本地音乐文件扫描与管理 | 已实现 |
| 播放列表管理 | 支持创建、编辑和删除播放列表 | 已实现 |
| 分类浏览 | 支持按艺术家、专辑分类浏览音乐 | 已实现 |
| 歌词显示 | 支持内嵌歌词和 LRC 文件，支持逐字歌词和间奏识别 | 已实现 |
| 桌面歌词 | 集成桌面歌词组件，支持个性化设置 | 已实现 |
| 主题切换 | 支持日间/夜间模式切换，支持基于专辑封面的动态主题 | 已实现 |
| 全局快捷键 | 支持全局快捷键控制播放、上一曲、下一曲等 | 已实现 |

### 2.2 WebDAV 私有云集成

| 功能项 | 描述 | 状态 |
|-------|------|------|
| WebDAV 连接管理 | 支持添加、编辑和删除 WebDAV 服务器连接 | 已实现 |
| 云文件浏览 | 支持 WebDAV 目录结构的解析与展示 | 已实现 |
| 云音乐播放 | 支持 WebDAV 音乐文件下载播放 | 已实现 |
| 流式播放 | 支持 WebDAV 音频文件流式播放（待实现） | 待实现 |
| 边缓存边播放 | 支持 WebDAV 音乐文件边缓存边播放（待实现） | 待实现 |

### 2.3 跨平台支持

| 功能项 | 描述 | 状态 |
|-------|------|------|
| Windows 支持 | 完整支持 Windows 平台 | 已实现 |
| macOS 支持 | 完整支持 macOS 平台 | 已实现 |
| Linux 支持 | 待实现 | 待实现 |

### 2.4 高级功能

| 功能项 | 描述 | 状态 |
|-------|------|------|
| 缓存管理系统 | 实现音乐文件缓存管理（待实现） | 待实现 |
| 音频信息自动刮削 | 集成音频信息自动刮削功能（待实现） | 待实现 |
| 歌词搜索与匹配 | 增强歌词搜索与匹配能力（待实现） | 待实现 |

## 3. 技术架构

### 3.1 整体架构

Coriander Player 采用分层架构设计，主要分为以下几层：

1. **UI 层**：负责用户界面展示和交互
2. **业务逻辑层**：处理核心业务逻辑，如播放控制、音乐库管理等
3. **服务层**：提供各种服务支持，如 WebDAV 服务、主题服务等
4. **数据层**：负责数据存储和管理
5. **原生层**：通过 Rust 绑定提供原生功能支持，如音频解码、标签读取等

### 3.2 核心技术栈

| 技术/框架 | 用途 | 版本 |
|----------|------|------|
| Flutter | 跨平台 UI 框架 | - |
| Dart | 主要开发语言 | - |
| Rust | 原生功能开发 | - |
| Flutter Rust Bridge | Dart 与 Rust 通信 | - |
| BASS | 音频播放引擎 | - |
| Lofty | 音频标签读取 | - |

### 3.3 项目结构

```
lib/
├── cloud_service/      # WebDAV 云服务相关
├── component/          # UI 组件
├── library/            # 音乐库管理
├── lyric/              # 歌词处理
├── page/               # 页面组件
├── platform/           # 平台相关代码
├── play_service/       # 播放服务
├── src/                # 原生绑定（Rust）
├── app_paths.dart      # 应用路径管理
├── app_preference.dart # 应用偏好设置
├── app_settings.dart   # 应用设置
├── entry.dart          # 应用入口组件
├── hotkeys_helper.dart # 快捷键管理
├── main.dart           # 应用主入口
├── music_matcher.dart  # 音乐匹配
├── platform_helper.dart # 平台辅助工具
├── theme_provider.dart # 主题管理
└── utils.dart          # 通用工具函数
```

## 4. 核心模块设计

### 4.1 播放服务模块

#### 4.1.1 模块概述

播放服务模块是应用的核心，负责音频播放控制、歌词同步和桌面歌词管理。

#### 4.1.2 核心类设计

```dart
class PlayService {
  late final playbackService = PlaybackService(this);  // 播放控制服务
  late final lyricService = LyricService(this);        // 歌词服务
  late final desktopLyricService = DesktopLyricService(this); // 桌面歌词服务
  
  // 单例模式实现
  static PlayService get instance;
  
  void close(); // 关闭所有服务
}
```

#### 4.1.3 工作流程

1. 应用启动时初始化 PlayService 单例
2. PlaybackService 负责音频播放控制
3. LyricService 负责歌词解析和同步
4. DesktopLyricService 负责桌面歌词的显示和控制

### 4.2 音乐库模块

#### 4.2.1 模块概述

音乐库模块负责本地音乐文件的管理、组织和检索。

#### 4.2.2 核心类设计

```dart
class AudioLibrary {
  List<AudioFolder> folders;          // 音乐文件夹列表
  List<Audio> audioCollection;        // 所有音乐文件
  Map<String, Artist> artistCollection; // 艺术家集合
  Map<String, Album> albumCollection;  // 专辑集合
  
  static AudioLibrary get instance;   // 单例模式
  static Future<void> initFromIndex(); // 从索引文件初始化
  void _buildCollections();           // 构建音乐集合
}

class Audio {
  String title;           // 标题
  String artist;          // 艺术家
  List<String> splitedArtists; // 分割后的艺术家列表
  String album;           // 专辑
  int track;              // 曲目号
  int duration;           // 时长（秒）
  int? bitrate;           // 比特率
  int? sampleRate;        // 采样率
  String path;            // 文件路径
  // 其他属性和方法
}

class Artist {
  String name;            // 艺术家名称
  Map<String, Album> albumsMap; // 关联的专辑
  List<Audio> works;      // 作品列表
  // 其他属性和方法
}

class Album {
  String name;            // 专辑名称
  Map<String, Artist> artistsMap; // 关联的艺术家
  List<Audio> works;      // 作品列表
  // 其他属性和方法
}
```

#### 4.2.3 数据结构

音乐库数据存储在 JSON 格式的索引文件中，结构如下：

```json
{
    "folders": [
        {
            "audios": [
                {...},  // Audio 对象
                ...
            ],
            "path": "...",  // 文件夹路径
            "modified": 1234567890,  // 修改时间
            "latest": 1234567890     // 最新修改时间
        },
        ...
    ],
    "version": 110  // 索引版本
}
```

### 4.3 WebDAV 云服务模块

#### 4.3.1 模块概述

WebDAV 云服务模块负责与 WebDAV 服务器交互，实现云音乐的浏览和播放。

#### 4.3.2 核心类设计

```dart
class WebDavService {
  final String serverUrl;  // 服务器 URL
  final String username;   // 用户名
  final String password;   // 密码
  
  Future<bool> testConnection();  // 测试连接
  Future<List<WebDavFile>> listFiles(String directoryPath);  // 列出文件
  Future<List<int>> downloadFile(String filePath);  // 下载文件
  String getFileUrl(String filePath);  // 获取文件 URL
  Future<List<WebDavFile>> scanAudioFiles(String directoryPath);  // 扫描音频文件
}

class WebDavFile {
  final String path;           // 文件路径
  final String name;           // 文件名
  final bool isDirectory;      // 是否为目录
  final int size;              // 文件大小
  final DateTime lastModified; // 最后修改时间
  final String? contentType;   // 内容类型
  
  bool get isAudioFile;        // 是否为音频文件
}
```

#### 4.3.3 工作流程

1. 用户添加 WebDAV 服务器连接
2. 应用测试连接有效性
3. 用户浏览 WebDAV 目录结构
4. 应用识别音频文件并提供播放选项
5. 用户选择播放时，应用下载或流式播放音频文件

### 4.4 主题管理模块

#### 4.4.1 模块概述

主题管理模块负责应用的主题切换和个性化设置，支持基于专辑封面的动态主题。

#### 4.4.2 核心类设计

```dart
class ThemeProvider extends ChangeNotifier {
  ColorScheme lightScheme;  // 浅色主题
  ColorScheme darkScheme;   // 深色主题
  String? fontFamily;       // 字体
  ThemeMode themeMode;      // 主题模式
  
  static ThemeProvider get instance;  // 单例模式
  
  void applyTheme({required Color seedColor});  // 应用主题
  void applyThemeFromImage(ImageProvider image, ThemeMode themeMode);  // 从图片应用主题
  void applyThemeMode(ThemeMode themeMode);  // 应用主题模式
  void applyThemeFromAudio(Audio audio);  // 从音频应用主题
  void changeFontFamily(String? fontFamily);  // 更改字体
}
```

#### 4.4.3 主题生成机制

1. 支持基于种子颜色生成主题
2. 支持从图片（如专辑封面）提取颜色生成主题
3. 支持动态主题切换
4. 主题变更会同步到桌面歌词

## 5. 数据结构设计

### 5.1 音频数据模型

| 字段名 | 类型 | 描述 |
|-------|------|------|
| title | String | 音频标题 |
| artist | String | 艺术家（原始字符串） |
| splitedArtists | List<String> | 分割后的艺术家列表 |
| album | String | 专辑名称 |
| track | int | 曲目号 |
| duration | int | 时长（秒） |
| bitrate | int? | 比特率 |
| sampleRate | int? | 采样率 |
| path | String | 文件路径 |
| modified | int | 修改时间（Unix 时间戳） |
| created | int | 创建时间（Unix 时间戳） |
| by | String? | 标签来源 |

### 5.2 应用设置模型

| 字段名 | 类型 | 描述 |
|-------|------|------|
| windowSize | Size | 窗口大小 |
| defaultTheme | int | 默认主题颜色 |
| themeMode | ThemeMode | 主题模式 |
| fontFamily | String? | 字体名称 |
| fontPath | String? | 字体文件路径 |
| dynamicTheme | bool | 是否启用动态主题 |
| artistSplitPattern | String | 艺术家分割正则表达式 |

## 6. 界面设计

### 6.1 整体布局

应用采用侧边导航 + 主内容区的布局模式，支持响应式设计，适配不同屏幕尺寸。

### 6.2 主要页面

1. **欢迎页**：首次启动时引导用户添加音乐文件夹
2. **音乐页**：展示所有音乐文件，支持搜索和筛选
3. **艺术家页**：按艺术家分类浏览音乐
4. **专辑页**：按专辑分类浏览音乐
5. **文件夹页**：按文件夹结构浏览音乐
6. **正在播放页**：显示当前播放的音乐和歌词
7. **搜索页**：搜索音乐、艺术家和专辑
8. **设置页**：应用设置和主题设置
9. **WebDAV 连接页**：管理 WebDAV 连接
10. **WebDAV 文件浏览器**：浏览 WebDAV 服务器上的文件

### 6.3 桌面歌词

桌面歌词支持以下功能：
- 实时歌词显示
- 个性化设置（字体、颜色、大小等）
- 夜间模式
- 操作栏控制

## 7. 技术实现细节

### 7.1 音频播放引擎

应用使用 BASS 库作为音频播放引擎，支持多种音频格式。BASS 库文件需要根据平台放置在指定目录：

- Windows：`windows/bass/` 目录
- macOS：`macos/bass/` 目录

### 7.2 歌词处理

应用支持多种歌词格式，包括：
- LRC 歌词（支持间奏识别）
- 逐字歌词（支持 KRC、QRC 格式）
- 内嵌歌词

### 7.3 桌面歌词集成

桌面歌词组件是一个独立的 Flutter 应用，需要单独编译并集成到主应用中：

- Windows：使用 `build_desktop_lyric.ps1` 或 `build_desktop_lyric.bat` 脚本构建
- macOS：使用 `build_desktop_lyric.sh` 脚本构建

### 7.4 跨平台适配

应用通过平台辅助工具类 `PlatformHelper` 处理平台差异，主要适配点包括：
- 窗口管理
- 文件路径处理
- 快捷键注册
- 媒体键支持（macOS）

## 8. 未来规划

根据项目的 TO DO LIST，未来将实现以下功能：

1. WebDAV 增强功能
   - 音频文件流式播放
   - 边缓存边播放
   - WebDAV 文件元数据直接读取

2. 缓存管理系统
3. 音频信息自动刮削功能
4. 增强歌词搜索与匹配能力
5. 提升跨平台兼容性与稳定性
6. 优化大文件处理性能
7. 完善错误处理与用户反馈机制

## 9. 总结

Coriander Player 是一款功能丰富、设计精美的跨平台音乐播放器，支持本地音乐播放和 WebDAV 云音乐集成。项目采用现代技术栈，具有良好的扩展性和可维护性。

通过逆向工程分析，我们了解了项目的整体架构、核心模块设计和技术实现细节，为后续的开发和维护提供了参考。

该项目具有良好的发展前景，未来将继续增强 WebDAV 功能、优化性能和用户体验，为用户提供更好的音乐播放服务。