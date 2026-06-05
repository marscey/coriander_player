# 云服务音乐（在线音乐）元数据读取方案

## 1. 方案概述

云音频文件存储在 WebDAV 服务器上，无法像本地文件一样直接读取完整内容。本项目采用 **基于 HTTP Range 请求的字节范围元数据读取** 方案，仅下载文件头部和尾部共约 192KB 数据，即可解析出完整的音频元数据（标题、艺术家、专辑、时长、码率、采样率等），避免下载完整文件。

### 核心原则

| 原则 | 说明 |
|------|------|
| **最小数据传输** | 仅下载头 64KB + 尾 128KB，而非完整文件（通常 3~30MB） |
| **格式感知** | FLAC 仅需头部元数据块；MP3/M4A 等需头部+尾部 |
| **缓存优先** | 有本地缓存文件时从缓存读内嵌数据，无缓存时跳过内嵌直接走缓存/在线 |
| **优雅降级** | Range 请求失败 → 文件名解析；元数据缺失 → fileSize/bitrate 估算 |

---

## 2. 整体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                        云音频元数据读取流程                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────┐    PROPFIND     ┌──────────────┐                      │
│  │ WebDAV   │ ──────────────→ │ WebDavFile   │                      │
│  │ 服务器    │   文件列表+大小  │ (path,name,  │                      │
│  └──────────┘                 │  size,...)   │                      │
│                               └──────┬───────┘                      │
│                                      │                              │
│                    ┌─────────────────┴─────────────────┐            │
│                    │                                   │            │
│              ┌─────▼─────┐                     ┌───────▼───────┐    │
│              │ 扫描入库    │                     │ 播放时异步更新  │    │
│              │(首次添加)   │                     │(已有记录)     │    │
│              └─────┬─────┘                     └───────┬───────┘    │
│                    │                                   │            │
│                    └─────────────┬─────────────────────┘            │
│                                  │                                  │
│                    ┌─────────────▼──────────────┐                   │
│                    │  _createAudioViaRange /     │                   │
│                    │  _updateMetadataViaRange    │                   │
│                    └─────────────┬──────────────┘                   │
│                                  │                                  │
│              ┌───────────────────┼───────────────────┐              │
│              │                   │                   │              │
│     ┌────────▼────────┐  ┌──────▼──────┐  ┌────────▼────────┐     │
│     │ 1. 获取文件大小   │  │ 2. Range   │  │ 3. Rust 解析    │     │
│     │ (PROPFIND/HEAD) │  │  请求头尾   │  │ readMetadata    │     │
│     │ fileSize        │  │ 64KB+128KB │  │ FromBytes       │     │
│     └─────────────────┘  └────────────┘  └─────────────────┘     │
│                                                                  │
│              ┌───────────────────┼───────────────────┐            │
│              │                   │                   │            │
│     ┌────────▼────────┐  ┌──────▼──────┐  ┌────────▼────────┐   │
│     │ 4a. FLAC 专用    │  │ 4b. 通用格式 │  │ 4c. 回退       │   │
│     │ 仅头部元数据块   │  │ head+zeros  │  │ 文件名解析     │   │
│     │ 修正 last 标志   │  │ +tail       │  │               │   │
│     └─────────────────┘  └─────────────┘  └───────────────┘   │
│                                                                  │
│              ┌───────────────────┼───────────────────┐            │
│              │                   │                   │            │
│     ┌────────▼────────┐  ┌──────▼──────┐  ┌────────▼────────┐   │
│     │ 5. 元数据补全    │  │ 6. 创建     │  │ 7. 封面/歌词    │   │
│     │ duration/bitrate │  │   Audio对象  │  │ 优先级加载      │   │
│     │ 互相估算         │  │             │  │               │   │
│     └─────────────────┘  └─────────────┘  └───────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. 字节范围元数据读取原理

### 3.1 音频文件结构

不同音频格式的元数据分布位置不同：

```
FLAC 文件结构:
┌──────────┬──────────────────────────────────┬──────────────────┐
│ "fLaC"   │ 元数据块 (STREAMINFO/VORBIS...)  │ 音频帧数据       │
│ 4 bytes  │ 全部在文件头部                    │ 不需要读取       │
└──────────┴──────────────────────────────────┴──────────────────┘
 ↑ 仅需头部

MP3 文件结构:
┌──────────────┬─────────────────────┬──────────────┐
│ ID3v2 标签   │ MPEG 音频帧数据      │ ID3v1/APE   │
│ 文件头部     │ (不需要读取)         │ 文件尾部     │
└──────────────┴─────────────────────┴──────────────┘
 ↑ 需要头部                                ↑ 需要尾部

M4A/AAC 文件结构:
┌──────────────┬─────────────────────┬──────────────┐
│ ftyp/moov    │ mdat (音频数据)      │ 可选尾部标签  │
│ 文件头部     │ (不需要读取)         │              │
└──────────────┴─────────────────────┴──────────────┘
 ↑ 需要头部
```

### 3.2 HTTP Range 请求

通过 HTTP `Range` 头部请求文件的指定字节范围，服务器返回 `206 Partial Content`：

```http
GET /path/to/audio.flac HTTP/1.1
Range: bytes=0-65535        ← 请求头部 64KB

GET /path/to/audio.flac HTTP/1.1
Range: bytes=26336188-26467259  ← 请求尾部 128KB
```

### 3.3 虚拟文件构造

将下载的头尾字节拼接成与原始文件等大的"虚拟文件"，供 lofty 解析：

**FLAC 专用方式** (`construct_flac_virtual_file`)：
- FLAC 元数据块全部在头部，不需要零填充+尾部
- 解析元数据块链，找到最后一个完整块
- 设置其 "last metadata block flag"（bit 7），截断后续数据
- 虚拟文件从 26MB 缩减到约 32KB（仅元数据部分）

**通用方式** (`construct_full_virtual_file`)：
- 适用于 MP3/M4A/OGG 等格式
- 构造：`[head_bytes] + [零填充] + [tail_bytes]`
- 零填充使虚拟文件与原始文件等大，lofty 可正确计算时长等属性

---

## 4. 本项目实现详解

### 4.1 Rust 端：元数据解析核心

#### `read_metadata_from_bytes`

```rust
pub fn read_metadata_from_bytes(
    head_bytes: Vec<u8>,    // 文件头部字节（至少 64KB）
    tail_bytes: Vec<u8>,    // 文件尾部字节（至少 128KB）
    file_size: u32,         // 文件总大小（字节）
    file_name: String,      // 文件名（用于格式推断）
) -> Option<String>         // 返回 JSON 字符串
```

**关键设计决策**：

1. **根据文件扩展名推断 FileType**：`Probe::new()` 从 Cursor 读取时无法自动检测文件类型（Cursor 没有文件路径），必须用 `Probe::with_file_type()` 指定
2. **FLAC 走专用路径**：避免零填充导致 FLAC 解析器将零误读为元数据块
3. **回退机制**：指定类型解析失败时，回退到 `Probe::new()` 重试

返回 JSON 结构：
```json
{
  "title": "Tequila Sunrise",
  "artist": "88rising",
  "album": "Head in the Clouds II",
  "track": null,
  "duration": 243,
  "bitrate": 0,
  "sample_rate": 44100
}
```

#### `construct_flac_virtual_file`

FLAC 文件元数据块结构：
```
Offset  Size  Description
0       4     "fLaC" magic
4       1     Block Header: [last:1bit][type:7bit]
5       3     Block Size (24-bit big-endian)
8       N     Block Data
8+N     ...   Next Block Header...
```

处理逻辑：
1. 验证 `fLaC` magic
2. 遍历元数据块链，找到最后一个完整块
3. 若某块已有 `last` 标志，直接截断返回
4. 否则截断到最后一个完整块，设置其 `last` 标志（`byte |= 0x80`）

### 4.2 Dart 端：扫描入库

#### `_createAudioViaRange` — 扫描入库时使用

```
WebDavFile → Range 请求 → readMetadataFromBytes → Audio 对象
```

**流程**：
1. 优先使用 `file.size`（PROPFIND 已返回），避免额外 HEAD 请求
2. 并行下载头部 64KB 和尾部 128KB
3. 调用 Rust 端 `readMetadataFromBytes` 解析
4. 元数据补全：
   - `duration=0` 且 `bitrate>0` → `duration = fileSize * 8 / (bitrate * 1000)`
   - `bitrate=0` 且 `duration>0` → `bitrate = fileSize * 8 / (duration * 1000)`（FLAC 场景）
5. 失败时回退到文件名解析（`_parseFileName`）

#### `_updateMetadataViaRange` — 播放时异步更新

与 `_createAudioViaRange` 类似，但更新的是当前播放中的 `Audio` 对象，并额外：
- 更新播放界面的封面（从缓存文件读取内嵌封面）
- 触发主题色更新（`ThemeProvider.applyThemeFromAudio`）
- 同步更新音乐库中的元数据（`_updateLibraryAudioMetadata`）

### 4.3 Dart 端：WebDAV 服务层

#### `downloadRange`

```dart
Future<Uint8List?> downloadRange(String filePath, int start, int end) async {
  final response = await http.get(Uri.parse(url), headers: {
    'Range': 'bytes=$start-$end',
  });
  // 206 → 返回部分内容
  // 200 → 服务器不支持 Range，从完整响应中截取
}
```

#### `getFileSize`

```dart
Future<int?> getFileSize(String filePath) async {
  final response = await http.head(Uri.parse(url));
  // 从 Content-Length 头获取文件大小
}
```

**注意**：扫描入库时优先使用 PROPFIND 返回的 `file.size`，避免额外的 HEAD 请求。

#### HTML 实体解码

WebDAV PROPFIND 响应是 XML，特殊字符被编码为 HTML 实体。在解析 `href` 和 `displayname` 时必须解码：

```dart
href = href
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");
```

### 4.4 Dart 端：数据模型

#### `Audio.fileSize` 字段

```dart
/// 文件大小（字节），云音频从 WebDAV 获取，本地音频从文件读取
int? fileSize;
```

- 云音频：从 `WebDavFile.size`（PROPFIND）或 `getFileSize`（HEAD）获取
- 本地音频：通过 `File(path).lengthSync()` 实时读取
- 序列化：`toMap` 写入 `"file_size"`，`fromMap` 读取

#### `Audio.isCloudAudio` 属性

```dart
bool get isCloudAudio => by == 'Cloud';
```

### 4.5 Dart 端：封面/歌词优先级

云音频的封面和歌词加载遵循统一的优先级策略：

```
┌─────────────────────────────────────────────────────────────────┐
│                    云音频封面/歌词优先级                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  有本地缓存文件（已播放过）：                                      │
│  ┌──────────────────┐   ┌──────────────────┐   ┌─────────────┐ │
│  │ 1. 缓存文件内嵌   │ → │ 2. MediaCache    │ → │ 3. 在线刮削  │ │
│  │ (getPictureFrom  │   │ (刮削缓存)       │   │ (网易云等)   │ │
│  │  Path/FromPath)  │   │                  │   │             │ │
│  └──────────────────┘   └──────────────────┘   └─────────────┘ │
│                                                                 │
│  无本地缓存文件（未播放过）：                                      │
│  ┌──────────────────┐   ┌──────────────────┐                   │
│  │ 1. MediaCache    │ → │ 2. 在线刮削       │                   │
│  │ (刮削缓存)       │   │ (网易云等)        │                   │
│  └──────────────────┘   └──────────────────┘                   │
│  （跳过内嵌步骤，避免无谓的网络请求）                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**涉及位置**：

| 组件 | 方法 | 文件 |
|------|------|------|
| 封面加载 | `Audio._getResizedPic` | `audio_library.dart` |
| 歌词加载 | `LyricService._getLyricDefault` | `lyric_service.dart` |
| 歌词获取 | `MetadataService.getOrScrapeLyric` | `metadata_service.dart` |
| 封面获取 | `MetadataService.getOrScrapeCover` | `metadata_service.dart` |
| 标签编辑 | `EditTagDialog._loadCurrentCover` | `edit_tag_dialog.dart` |

**缓存判断**：通过 `CloudCacheManager.getCachedFilePath(path)` 检查本地缓存文件是否存在。

### 4.6 Dart 端：UI 显示

#### `audio_tile.dart` — 文件大小显示

```dart
static String? _getFileSize(Audio audio) {
  if (audio.isCloudAudio) {
    if (audio.fileSize != null && audio.fileSize! > 0) {
      return _formatFileSize(audio.fileSize!);
    }
    return null;
  }
  // 本地音频：File(path).lengthSync()
}
```

---

## 5. 各音频格式元数据读取能力

| 格式 | 头部元数据 | 尾部元数据 | duration | bitrate | sample_rate | title/artist/album | 备注 |
|------|-----------|-----------|----------|---------|-------------|-------------------|------|
| **FLAC** | STREAMINFO + Vorbis Comment | 无 | ✅ 从 STREAMINFO | ⚠️ 需估算 | ✅ 从 STREAMINFO | ✅ 从 Vorbis Comment | 仅需头部，虚拟文件极小 |
| **MP3** | ID3v2 | ID3v1/APE | ⚠️ 需估算 | ✅ 从帧头 | ✅ 从帧头 | ✅ 从 ID3v2 | 虚拟文件零填充可能影响帧扫描 |
| **M4A/AAC** | ftyp + moov | 无 | ✅ 从 moov | ✅ 从 moov | ✅ 从 moov | ✅ 从 moov | moov 通常在头部 |
| **OGG/Opus** | OGG 页面头 | 无 | ⚠️ 需估算 | ✅ 从头部 | ✅ 从头部 | ✅ 从 Vorbis Comment | 零填充可能影响页面遍历 |
| **APE** | APE Header | APE Tag | ✅ 从头部 | ✅ 从头部 | ✅ 从头部 | ✅ 从 APE Tag | 通常可靠 |
| **WAV** | RIFF 头 | 无 | ✅ 从 RIFF | ✅ 从 fmt | ✅ 从 fmt | ⚠️ 可能无标签 | 依赖 LIST/INFO 块 |

**图例**：✅ 可靠读取 | ⚠️ 需要估算或可能不完整

---

## 6. 已知限制与应对

### 6.1 FLAC bitrate 为 0

**问题**：FLAC 虚拟文件无音频帧数据，lofty 返回 `bitrate=0`。

**应对**：用 `fileSize / duration` 估算平均码率：
```dart
if ((bitrate == null || bitrate == 0) && duration > 0) {
  bitrate = ((fileSize * 8) / (duration * 1000)).round();
}
```

### 6.2 MP3 duration 可能为 0

**问题**：MP3 需要扫描所有帧计算 duration，虚拟文件中间是零填充，帧不连续。

**应对**：用 `fileSize / bitrate` 估算时长：
```dart
if (duration == 0 && bitrate != null && bitrate > 0) {
  duration = ((fileSize * 8) / (bitrate * 1000)).round();
}
```

### 6.3 WebDAV 服务器不支持 Range

**问题**：部分 WebDAV 服务器不支持 Range 请求，返回 200 + 完整文件。

**应对**：`downloadRange` 中处理 200 响应，从完整响应中截取需要的字节范围。

### 6.4 WebDAV XML 中的 HTML 实体

**问题**：PROPFIND 响应是 XML，`&` 被编码为 `&amp;`，导致文件路径错误（404）。

**应对**：解析 `href` 和 `displayname` 后进行 HTML 实体解码。

### 6.5 大文件内存占用

**问题**：`file_size` 参数类型为 `u32`，最大支持约 4GB。

**应对**：当前音频文件极少超过 4GB，暂不需要修改。如需支持，可改为 `u64`。

---

## 7. 性能对比

| 方案 | 每个文件数据传输 | 每个文件耗时 | 元数据质量 | 磁盘 IO |
|------|---------------|------------|-----------|---------|
| 下载完整文件 | 3~30 MB | 3~10s | 完整 | 有（临时文件） |
| **Range 请求（当前）** | **~192 KB** | **~1s** | **完整** | **无** |
| 仅解析文件名 | 0 KB | <0.1s | 仅有 title | 无 |

Range 请求方案相比下载完整文件，速度提升约 **15~50 倍**，同时元数据质量相当。

---

## 8. 文件索引

| 文件 | 职责 |
|------|------|
| `rust/src/api/tag_reader.rs` | Rust 端元数据解析核心：`read_metadata_from_bytes`、`construct_flac_virtual_file`、`construct_full_virtual_file` |
| `lib/cloud_service/cloud_audio_player.dart` | 云音频播放/扫描：`_createAudioViaRange`、`_updateMetadataViaRange`、`addCloudFolderToLibrary`、`addCloudFilesToLibrary` |
| `lib/cloud_service/webdav_service.dart` | WebDAV 协议层：`downloadRange`、`getFileSize`、PROPFIND 解析（含 HTML 实体解码） |
| `lib/cloud_service/cloud_cache_manager.dart` | 云音频本地缓存管理：`getCachedFilePath` |
| `lib/library/audio_library.dart` | 数据模型：`Audio.fileSize`、`Audio.isCloudAudio`、`Audio._getResizedPic` |
| `lib/component/audio_tile.dart` | UI 显示：`_getFileSize` |
| `lib/play_service/lyric_service.dart` | 歌词加载：`_getLyricDefault`（云音频优先级） |
| `lib/metadata/metadata_service.dart` | 元数据服务：`getOrScrapeLyric`、`getOrScrapeCover`（云音频优先级） |
| `lib/page/settings_page/edit_tag_dialog.dart` | 标签编辑：`_loadCurrentCover`（云音频优先级） |
