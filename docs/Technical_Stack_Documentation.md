# Coriander Player 技术栈详细文档

## 项目概述

**Coriander Player** 是一个基于 **Flutter 4.0+** 构建的现代化音乐播放器，专为Windows桌面平台设计。项目采用 **Flutter + Rust** 的混合架构，结合 **BASS音频引擎** 实现高性能音频处理，通过 **Material You** 设计语言提供优雅的视觉体验。

### 核心特性
- **跨平台音频引擎**：基于BASS音频库，支持20+音频格式
- **智能主题系统**：Material You动态主题，支持从专辑封面提取主题色
- **多格式歌词支持**：LRC、KRC、QRC等主流歌词格式
- **桌面级体验**：原生窗口控制、系统托盘、全局快捷键
- **高性能架构**：Rust处理音频元数据，Flutter负责UI渲染
- **私有云服务集成**：基于WebDAV协议实现云音乐播放和管理功能

## 核心技术架构

### 前端框架
- **Flutter**: 4.0.0+ (稳定版)
- **Dart**: 3.0.0+ (支持空安全)
- **Material Design 3**: 完整的Material You实现

### 后端技术栈
- **Rust**: 1.89.0 (2025-06-23)
- **flutter_rust_bridge**: 2.8.0 (高性能FFI桥接)
- **BASS音频库**: 2.4.17.0 (专业音频处理)

### 状态管理
- **Provider**: 6.1.2 (轻量级状态管理)
- **ChangeNotifier**: Flutter原生状态通知机制

### UI/UX设计系统
- **Material You**: 动态颜色生成算法
- **Fluent UI**: Windows 11原生设计语言适配
- **自适应布局**: 响应式设计，支持多窗口尺寸

## 技术栈详细清单

### 核心技术栈
| 技术类别 | 技术名称 | 版本 | 作用描述 | 许可证 |
|---------|----------|------|----------|--------|
| **跨平台框架** | Flutter | 4.0.0+ | UI框架与渲染引擎 | BSD-3-Clause |
| **编程语言** | Dart | 3.0.0+ | 前端开发语言 | BSD-3-Clause |
| **系统语言** | Rust | 1.89.0 | 高性能后端处理 | MIT/Apache-2.0 |
| **音频引擎** | BASS音频库 | 2.4.17.0 | 专业音频播放处理 | BASS License |
| **FFI桥接** | flutter_rust_bridge | 2.8.0 | Rust与Flutter通信 | MIT |

### Flutter依赖库清单
| 包名 | 版本 | 功能分类 | 具体用途 |
|------|------|----------|----------|
| **provider** | ^6.1.2 | 状态管理 | 轻量级状态管理解决方案 |
| **flutter_rust_bridge** | ^2.8.0 | 跨语言调用 | Rust与Flutter高性能FFI通信 |
| **fluent_ui** | ^4.8.7 | UI组件库 | Windows 11 Fluent Design实现 |
| **fluentui_system_icons** | ^1.1.245 | 图标库 | Microsoft官方系统图标 |
| **path_provider** | ^2.1.2 | 文件系统 | 跨平台文件路径访问 |
| **extended_image** | ^8.2.1 | 图片处理 | 高级图片加载与缓存 |
| **image** | ^4.1.7 | 图片解码 | 多格式图片编解码 |
| **intl** | ^0.19.0 | 国际化 | 多语言支持 |
| **ffi** | ^2.1.2 | 底层接口 | Dart与原生代码交互 |
| **win32** | ^5.5.1 | Windows API | Windows特定功能调用 |
| **http** | ^1.2.1 | 网络请求 | HTTP客户端，用于WebDAV协议通信 |
| **webdav_client** | ^3.0.0 | 云存储 | WebDAV客户端实现，支持连接云服务 |
| **xml** | ^6.5.0 | 数据解析 | XML解析，用于处理WebDAV响应数据 |

### Rust依赖库清单
| Crate名称 | 版本 | 功能描述 | 关键特性 |
|-----------|------|----------|----------|
| **flutter_rust_bridge** | 2.8.0 | FFI代码生成 | 自动生成FFI绑定代码 |
| **lofty** | 0.20.0 | 音频元数据 | 支持20+音频格式元数据提取 |
| **image** | 0.24.9 | 图片处理 | 支持PNG/JPEG/WebP等格式 |
| **serde** | 1.0.0 | 序列化 | JSON/二进制数据序列化 |
| **anyhow** | 1.0.0 | 错误处理 | Rust错误处理简化 |

### 音频格式支持矩阵
| 音频格式 | 文件扩展名 | 支持状态 | 技术实现 |
|----------|------------|----------|----------|
| **MP3** | .mp3 | ✅ 完全支持 | BASS原生支持 |
| **FLAC** | .flac | ✅ 无损支持 | BASSFLAC插件 |
| **WAV** | .wav | ✅ 完全支持 | BASS原生支持 |
| **AAC** | .aac/.m4a | ✅ 完全支持 | BASS_AAC插件 |
| **OGG** | .ogg | ✅ 完全支持 | BASS原生支持 |
| **OPUS** | .opus | ✅ 完全支持 | BASS_OPUS插件 |
| **APE** | .ape | ✅ 无损支持 | BASS_APE插件 |
| **WMA** | .wma | ✅ 完全支持 | BASS_WMA插件 |

### 开发环境与工具链
| 工具类别 | 工具名称 | 版本要求 | 安装指南 |
|----------|----------|----------|----------|
| **Flutter SDK** | Flutter | 4.0.0+ | [官方安装文档](https://flutter.dev/docs/get-started/install) |
| **Dart SDK** | Dart | 3.0.0+ | 随Flutter捆绑安装 |
| **Rust工具链** | Rust | 1.89.0+ | [rustup安装](https://rustup.rs/) |
| **Windows构建** | Visual Studio 2022 | 最新版 | C++桌面开发工作负载 |
| **IDE支持** | IntelliJ IDEA | 2024.1+ | Flutter/Dart插件 |
| **调试工具** | Flutter DevTools | 最新版 | 性能分析与调试 |

### 平台兼容性
| 平台 | 支持状态 | 构建方式 | 特殊要求 |
|------|----------|----------|----------|
| **Windows** | ✅ 主要支持 | `flutter build windows` | Visual Studio 2022 |
| **macOS** | ⚠️ 正在适配 | `flutter build macos` | Xcode 15+ |
| **Linux** | ⚠️ 实验支持 | `flutter build linux` | GCC/Clang |
| **Android** | ❌ 未适配 | - | - |
| **iOS** | ❌ 未适配 | - | - |

## 项目结构详解

### 目录架构
```
lib/                    # Flutter主代码目录
├── component/          # 可复用UI组件
│   ├── album_tile.dart
│   ├── audio_tile.dart
│   └── side_nav.dart
├── page/              # 页面级组件
│   ├── now_playing_page/
│   ├── settings_page/
│   └── search_page/
├── play_service/      # 播放服务层
│   ├── play_service.dart
│   ├── playback_service.dart
│   ├── lyric_service.dart
│   └── desktop_lyric_service.dart
├── library/           # 媒体库管理
│   ├── audio_library.dart
│   └── playlist.dart
├── lyric/             # 歌词处理
│   ├── lrc.dart
│   ├── krc.dart
│   └── qrc.dart
├── cloud_service/     # 云服务集成
│   ├── cloud_service.dart
│   ├── cloud_service_manager.dart
│   ├── cloud_connection.dart
│   ├── webdav_service.dart
│   ├── cloud_audio_player.dart
│   └── cloud_scanner.dart
└── theme_provider.dart # 主题系统

rust/                  # Rust后端代码
├── src/
│   ├── api/          # FFI接口定义
│   └── lib.rs       # 主库文件
└── Cargo.toml        # Rust依赖配置

windows/               # Windows平台特定代码
├── runner/           # 原生窗口实现
└── CMakeLists.txt    # Windows构建配置
```

## 音频播放引擎

### BASS音频库集成
- **核心功能**：
  - 支持20+音频格式 (MP3, FLAC, WAV, AAC, OGG, OPUS等)
  - 32-bit浮点音频处理
  - 低延迟音频输出 (DirectSound/WASAPI)
  - 硬件加速音频解码

- **插件系统**：
  - BASSFLAC: 无损音频格式支持
  - BASS_AAC: AAC/MP4格式支持
  - BASS_OPUS: OPUS编解码器支持

### 音频处理管线
```
音频文件 → Rust元数据提取 → BASS解码 → 音频输出 → Flutter UI更新
    ↓
封面图片 → 主题色提取 → Material You主题更新
```

## 歌词系统架构

### 支持的歌词格式
- **LRC格式**: 标准逐行歌词，支持时间标签
- **KRC格式**: 酷狗逐字歌词，支持精确到字符的时间轴
- **QRC格式**: QQ音乐增强歌词，支持翻译和音译

### 歌词处理流程
```
歌词文件 → 格式解析 → 时间轴校准 → 渲染引擎 → 桌面歌词/主界面歌词
```

### 高级特性
- **逐字渲染**: KRC格式支持字符级高亮
- **智能对齐**: 根据播放进度自动调整歌词位置
- **多语言支持**: 原文/翻译/音译切换
- **桌面悬浮**: 独立的桌面歌词窗口

## 主题与视觉系统

### Material You实现
- **动态主题色**: 从专辑封面提取主色调
- **自动明暗**: 跟随系统深色模式切换
- **个性化配色**: 12种预设主题色
- **字体定制**: 支持系统字体和用户自定义字体

### 响应式设计
- **窗口适配**: 300px-3000px宽度自适应
- **布局断点**: 
  - 紧凑模式: < 600px
  - 标准模式: 600px-1200px
  - 扩展模式: > 1200px

## 构建与部署指南

### 开发环境要求
```bash
# Flutter环境
flutter --version  # 4.0.0+
dart --version     # 3.0.0+

# Rust环境
cargo --version    # 1.89.0+

# Windows开发工具
Visual Studio 2022 (含C++桌面开发工作负载)
```

### 构建步骤
```bash
# 1. 克隆项目
git clone [repository-url]
cd coriander_player

# 2. 获取Flutter依赖
flutter pub get

# 3. 构建Rust库
cd rust
cargo build --release
cd ..

# 4. 运行应用
flutter run -d windows

# 5. 构建发布版本
flutter build windows --release
```

### 运行时依赖
- **BASS音频库**: 需要放置bass.dll到可执行文件目录
- **BASS插件**: 根据支持的格式放置相应插件
- **字体文件**: 支持自定义字体，放置到fonts目录

## 性能优化策略

### 音频性能
- **预解码缓存**: 提前解码下一首歌曲
- **内存管理**: 音频数据流式加载，避免内存溢出
- **多线程处理**: 音频解码与UI渲染分离

### UI性能
- **懒加载列表**: 虚拟滚动处理大量媒体文件
- **图片缓存**: 三级缓存策略 (内存/磁盘/网络)
- **Widget复用**:  const构造函数减少重建开销

### 内存优化
- **大文件处理**: 音频文件分块读取
- **缓存策略**: LRU算法管理图片和元数据缓存
- **及时释放**: 播放完成后及时释放音频资源

## 云服务集成

### WebDAV服务支持
Coriander Player现已集成私有云服务支持，基于WebDAV协议实现云音乐播放和管理功能。主要特性包括：

- **云服务连接管理**：支持添加、编辑、删除WebDAV连接
- **云文件浏览**：类似文件管理器的界面，支持文件夹导航和音频文件识别
- **音频播放**：直接播放云端音频文件，自动下载到临时目录
- **批量操作**：支持下载文件、添加到播放列表、扫描文件夹到音乐库等操作

详细使用说明请参阅 [云服务集成文档](docs/webdav_integrated_guide.md)

## 开源许可证

### 项目许可证
- **GPL-3.0 License**: 完整开源，允许自由修改和分发

### 第三方依赖许可证
- **BASS音频库**: 需遵守BASS许可证条款
- **Flutter**: BSD-3-Clause License
- **Rust**: MIT/Apache-2.0双许可证
- **webdav_client**: MIT License

## 社区与贡献

### 代码规范
- **Flutter**: 遵循Effective Dart风格指南
- **Rust**: 遵循Rust官方编码规范
- **Git**: 使用Conventional Commits规范

### 贡献指南
1. Fork项目仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交变更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建Pull Request

---

*本文档基于Coriander Player v2.0.0版本编写，最后更新于2025年*

*云服务集成功能更新于2025年10月*