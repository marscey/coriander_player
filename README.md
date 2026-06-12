<div align="center">

# 🎵 Coriander Player

**一款使用 Material You 配色的跨平台音乐播放器**

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%203.0-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20iOS-green.svg)]()

</div>

> **本项目 Fork 自 [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player)**，在原项目基础上新增了 WebDAV 私有云播放、macOS/iOS 平台支持、双引擎播放架构、元数据自动刮削等功能，致力于打造一款跨平台的本地及网盘音乐播放器。

---

## 项目背景

**本项目 Fork 自 [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player)**，感谢原作者创建了一个优秀的本地音乐播放器。

### 原项目基础功能

原项目已实现以下核心功能：

- Windows 平台支持
- BASS 音频引擎，支持多种音频格式播放
- 本地音乐文件扫描与管理
- 播放列表管理
- 艺术家、专辑分类浏览
- LRC 和 KRC 歌词格式支持
- 桌面歌词组件
- Material You 主题系统
- 全局快捷键控制

### 本项目新增功能

在原项目基础上，本项目新增了以下功能：

- **多平台支持**：新增 macOS 和 iOS 平台支持，实现真正的跨平台体验
- **双引擎架构**：新增 MediaKit 引擎，桌面端使用 BASS，移动端使用 MediaKit，支持手动切换
- **WebDAV 私有云**：支持 WebDAV 服务器连接、文件浏览、流式播放与智能缓存
- **元数据刮削**：集成网易云音乐、QQ音乐、酷狗、MusicBrainz 多源元数据自动刮削
- **歌词扩展**：新增 QRC（QQ音乐逐字歌词）格式支持
- **标签编辑**：支持音频标签手动编辑与在线刮削更新
- **缓存管理**：云音频缓存、歌词缓存、封面缓存的统一管理
- **macOS 特性**：系统媒体键控制、通知栏播放控件、锁屏/蓝牙歌词显示
- **iOS 特性**：正在播放小组件、锁屏/蓝牙歌词显示

## 功能特性

### 核心播放

- 支持多种音频格式播放（mp3, flac, aac, m4a, wav, ogg, opus, ape, wv, dsf, dff 等 20+ 种格式）
- **双引擎播放架构**：桌面端使用 BASS 原生引擎，移动端使用 MediaKit 引擎，支持在设置中手动切换
- 本地音乐文件扫描与管理
- 播放列表管理
- 艺术家、专辑、流派、文件夹分类浏览
- 最近播放记录

### 歌词系统

- **三种歌词格式**：LRC（行歌词）、KRC（酷狗逐字歌词）、QRC（QQ音乐逐字歌词）
- 支持内嵌歌词和外挂 LRC 文件（UTF-8 / UTF-16 编码）
- 在线歌词自动匹配（QQ音乐、酷狗、网易多源搜索）
- 歌词间奏动画识别
- 默认歌词选择功能
- 桌面歌词组件（Windows / macOS）

### WebDAV 私有云

- WebDAV 服务器连接与认证管理
- 私有云音乐文件浏览与目录结构解析
- **流式播放**：支持边下载边播放，无需等待完整下载
- **智能缓存**：自动缓存已播放的云音频文件，支持缓存大小限制与清理
- 云端音频元数据提取

### 元数据刮削

- **多源刮削**：网易云音乐、QQ音乐、酷狗音乐、MusicBrainz
- 可配置刮削源优先级与启用状态
- 自动匹配歌曲封面、歌词、艺术家信息
- 元数据本地持久化存储（SQLite）
- 音频标签手动编辑与在线刮削更新

### 主题与个性化

- Material You / Material Design 3 主题系统
- 日间 / 夜间模式切换
- 自定义主题色选择器
- 桌面歌词个性化设置

### 平台特性

- **Windows**：BASS 原生引擎、WASAPI 音频输出、系统媒体控制 (SMTC)、桌面歌词
- **macOS**：BASS 原生引擎、系统媒体键控制、通知栏播放控件、锁屏/蓝牙歌词显示、桌面歌词
- **iOS**：MediaKit 引擎、正在播放小组件、锁屏/蓝牙歌词显示
- **Android**：MediaKit 引擎、系统媒体控制
- **Linux**：MediaKit 引擎

### 全局快捷键

页面中有文本框且处于输入状态时会自动忽略快捷键操作。如果要使用快捷键，可以点击输入框以外的地方，然后再次使用。

- `Esc`：返回上一级
- `Space`：暂停/播放
- `Ctrl + ←`：上一曲
- `Ctrl + →`：下一曲

---

## 安装

### Windows

1. 从 [Release](https://github.com/senyepss/coriander_player_solo/releases/latest) 页面下载安装包
2. 或通过 scoop 安装：

```sh
# 添加 bucket
scoop bucket add jin https://github.com/jinzhongjia/scoop-bucket
# 安装
scoop install jin/coriander_player
```

### macOS

1. 从 [Release](https://github.com/senyepss/coriander_player_solo/releases/latest) 页面下载 macOS 版本安装包
2. 或从源码构建（详见下方编译部分）

### iOS

从源码构建，详见下方编译部分。

---

## 支持播放的音乐格式

| 格式类别 | 支持格式 |
|----------|----------|
| MPEG | mp3, mp2, mp1 |
| 无损 | flac, ape, wv, wvc, dsf, dff |
| AAC | aac, adts, m4a |
| OGG | ogg, opus |
| WAV | wav, wave |
| AIFF | aif, aiff, aifc |
| Windows | asf, wma |
| 其他 | ac3, amr, 3ga, mpc, mid |

## 支持内嵌歌词的音乐格式

aac, aiff, flac, m4a, mp3, ogg, opus, wav（标签必须用 UTF-8 编码）

其他格式支持同目录的 LRC 文件或在线歌词。

## 外挂 LRC 支持编码

- UTF-8
- UTF-16

## 选择默认歌词

默认情况下，软件会先读取本地歌词。如果没有，则匹配在线歌词。你可以在正在播放界面的歌词切换按钮展开的菜单中进入选择默认歌词的页面。

![选择默认歌词](软件截图/选择默认歌词.png)

在这个界面中，你可以在本地歌词（如果有）和几个匹配程度高的在线歌词中选择一个作为默认歌词。之后再播放这首音乐时，软件会加载你指定的歌词。

---

## 编译

### 环境准备

1. Flutter 开发环境（SDK >= 3.1.4）
2. 对应平台的开发工具链（Xcode / Visual Studio 等）

### 构建主程序

```sh
# 安装依赖
flutter pub get

# Windows
flutter run -d windows
flutter build windows

# macOS
flutter run -d macos
flutter build macos

# iOS 模拟器
flutter build ios --simulator

# Android
flutter run -d android
```

### 构建桌面歌词组件

桌面歌词是独立的 Flutter 应用（[marscey/desktop_lyric](https://github.com/marscey/desktop_lyric.git)），需在主程序构建完成后单独构建。

**Windows：**

```powershell
# 默认 Release 模式
powershell -ExecutionPolicy Bypass -File .\windows\build_desktop_lyric.ps1
# 指定 Debug 模式
powershell -ExecutionPolicy Bypass -File .\windows\build_desktop_lyric.ps1 -BuildMode Debug
```

也可以直接双击 `windows\build_desktop_lyric.bat` 运行，脚本会提示选择构建模式。

**macOS：**

```sh
# 默认 Debug 模式
chmod +x ./macos/build_desktop_lyric.sh && ./macos/build_desktop_lyric.sh
# 指定 Release 模式
./macos/build_desktop_lyric.sh --build-mode release
# 构建并安装到应用包
./macos/build_desktop_lyric.sh --build-mode debug --install-to-app
```

> 手动构建方式：编译 desktop_lyric 后，将产物放在软件目录的 `desktop_lyric/` 目录下即可。

### BASS 库文件配置

桌面端播放引擎基于 BASS 库实现，需要配置对应的 BASS 库文件。

**Windows：**
- CMake 构建系统会自动将 `windows/bass` 目录下的库文件复制到输出目录
- 确保包含：`bass.dll`, `bassape.dll`, `bassdsd.dll`, `bassflac.dll`, `bassmidi.dll`, `bassopus.dll`, `basswv.dll`, `basswasapi.dll`

**macOS：**
- 构建脚本会自动将 `macos/bass` 目录下的库文件复制到应用包的 `Contents/Frameworks/BASS` 目录并完成签名
- 确保包含：`libbass.dylib`, `libbassape.dylib`, `libbassdsd.dylib`, `libbassflac.dylib`, `libbassmidi.dylib`, `libbassopus.dylib`, `libbasswv.dylib`
- 注意：WASAPI 是 Windows 特有 API，macOS 不需要 `basswasapi` 相关文件

BASS 库文件可从 [官方网站](https://www.un4seen.com/bass.html) 下载。

---

## 歌词特性解释

### LRC 歌词的间奏识别

在一些 LRC 歌词中，会使用**只有时间标签而内容为空**的一行来表示上一行的结束。如：

```
[02:32.57]光は やさしく抱きしめた
[02:32.57]那天没能放声大哭的我
[02:39.94]
[02:55.18]照らされた世界 咲き誇る大切な人
[02:55.18]光芒普照整个世界 珍重之人绽放于心
```

如果这一行（第三行）的时间戳和下一行的时间戳之间大于 5s，就把这两行之间的时间作为间奏时长。**所以，不是所有 LRC 歌词在间奏时都能显示间奏动画。**

### 逐字歌词的间奏识别

逐字歌词（KRC / QRC）会给出每一行的开始时间和持续时间，因此识别间奏更为准确。如：

```
[5905,5466]<0,217,0>世<217,383,0>界<600,495,0>は<1095,272,0>と<1367,328,0>て<1695,343,0>も<2038,616,0>綺<2654,752,0>麗<3406,276,0>だ<3682,276,0>っ<3958,504,0>た<4462,1004,0>な
[23037,5254]<0,255,0>書<255,280,0>架<535,312,0>の<847,592,0>隙<1439,312,0>間<1751,223,0>に<1974,160,0>住<2134,144,0>ま<2278,352,0>う<2630,640,0>一<3270,640,0>輪<3910,190,0>の<4100,680,0>花<4780,474,0>は
```

第一行开始时间 5905ms，持续 5466ms；第二行开始时间 23037ms。5905 + 5466 = 11371，与 23037 相差超过 5000ms，因此可插入间奏空白行。

---

## 技术栈

| 技术 | 用途 |
|------|------|
| [Flutter](https://flutter.dev) | 跨平台 UI 框架 |
| [Rust](https://www.rust-lang.org) | 原生交互（标签读取、系统主题、媒体控制等） |
| [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge) | Dart ↔ Rust 通信桥接 |
| [BASS](https://www.un4seen.com/bass.html) | 桌面端音频引擎 |
| [media_kit](https://pub.dev/packages/media_kit) | 跨平台音频引擎 |
| [Lofty](https://crates.io/crates/lofty) | Rust 音频标签读取 |
| [webdav_client](https://pub.dev/packages/webdav_client) | WebDAV 协议客户端 |
| [go_router](https://pub.dev/packages/go_router) | 声明式路由 |
| [Provider](https://pub.dev/packages/provider) | 状态管理 |

---

## 项目结构

```
lib/
├── main.dart                  # 应用入口
├── entry.dart                 # MaterialApp + 路由 + Provider 配置
├── play_service/              # 播放服务层
│   ├── play_service.dart      # 播放服务单例
│   ├── playback_service.dart  # 播放控制
│   ├── engine/                # 双引擎架构
│   │   ├── player_engine.dart       # 引擎抽象接口
│   │   ├── bass_player_engine.dart  # BASS 引擎（桌面端）
│   │   └── media_kit_player_engine.dart  # MediaKit 引擎（跨平台）
│   ├── lyric_service.dart     # 歌词加载与同步
│   └── desktop_lyric_service.dart  # 桌面歌词窗口控制
├── library/                   # 音频库数据模型
├── cloud_service/             # WebDAV 云端服务
│   ├── webdav_service.dart    # WebDAV 协议实现
│   ├── cloud_audio_player.dart # 云端音频播放
│   ├── cloud_cache_manager.dart # 云端缓存管理
│   └── cloud_scanner.dart     # 云端文件扫描
├── metadata/                  # 元数据刮削
│   ├── scraper_orchestrator.dart  # 刮削编排器
│   ├── chinese_scrapers.dart  # 网易云/QQ音乐/酷狗刮削
│   ├── musicbrainz_scraper.dart   # MusicBrainz 刮削
│   └── metadata_store.dart    # 元数据持久化
├── lyric/                     # 歌词解析器
│   ├── lrc.dart               # LRC 格式
│   ├── krc.dart               # KRC 格式（酷狗逐字）
│   └── qrc.dart               # QRC 格式（QQ音乐逐字）
├── page/                      # 页面级组件
├── component/                 # 可复用 UI 组件
├── src/bass/                  # BASS FFI 绑定
└── src/rust/                  # Rust 自动生成绑定（勿手动编辑）
```

---

## 贡献

欢迎提供建议、提交 Bug 或 PR！

1. 如果要提交 Bug，请创建一个新的 Issue，尽可能说明复现步骤并提供截图
2. 如果要提交 PR，请确保代码通过 `dart analyze` 检查

---

## 致谢

- [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player)：创建了原始的 Coriander Player 项目
- [Ferry-200/desktop_lyric](https://github.com/Ferry-200/desktop_lyric.git)：创建了桌面歌词组件项目
- [music_api](https://github.com/yhsj0919/music_api.git)：歌曲匹配与歌词获取
- [Lofty](https://crates.io/crates/lofty)：Rust 音频标签读取
- [BASS](https://www.un4seen.com/bass.html)：音频播放引擎
- [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge)：Dart ↔ Rust 通信
- [Silicon7921](https://github.com/Silicon7921)：绘制了新图标

---

## 软件截图

![音乐页](软件截图/音乐页.png)
![艺术家页](软件截图/艺术家页.png)
![艺术家详情页](软件截图/艺术家详情页.png)
![专辑详情页](软件截图/专辑详情页.png)
![主题选择器](软件截图/主题选择器.png)
![夜间模式](软件截图/夜间模式.png)
![正在播放：LRC歌词](软件截图/正在播放（LRC歌词）.png)
![正在播放：逐字歌词](软件截图/正在播放（逐字歌词）.png)
![正在播放：间奏动画](软件截图/正在播放（间奏动画）.png)
![正在播放：居中对齐](软件截图/正在播放（居中对齐）.png)
![桌面歌词](软件截图/桌面歌词.png)
![桌面歌词：操作栏](软件截图/桌面歌词（操作栏）.png)
![桌面歌词：个性化设置](软件截图/桌面歌词（个性化设置）.png)
![桌面歌词：夜间模式](软件截图/桌面歌词（夜间模式）.png)
