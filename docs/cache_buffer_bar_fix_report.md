# 云音频缓存进度条问题复盘报告

> 日期：2026-06-25
> 涉及平台：macOS（桌面端）、iOS（移动端）
> 涉及引擎：MediaKit Player Engine

---

## 1. 问题描述

播放**已缓存**的云音频时，播放器底部的**缓存进度条（buffer bar）** 不是瞬间满格，而是缓慢向前推进，给人一种"还在下载"的错觉。而实际上文件已经完整缓存在本地磁盘了。

### 预期行为
- 已缓存的云音频（本地文件）：缓存进度条瞬间满格
- 未缓存的云音频（网络流）：缓存进度条随缓冲进度逐步推进

### 实际行为
- 桌面端（macOS）和移动端（iOS）均表现为进度条缓慢推进

---

## 2. 技术背景

### 2.1 buffer 的含义

进度条上的 "缓存进度" 实际上是**播放器内部的解码缓冲区进度**，不等同于云缓存下载进度：

| 场景 | buffer 代表什么 |
|---|---|
| 网络流播放（首次播云音频） | 播放器已下载到内存、可随时解码的数据时长 |
| 本地文件播放（含已缓存云音频） | 整个文件都在本地，buffer 应等于总时长（满格） |

### 2.2 云缓存与播放缓冲的关系

```
播放云音频（cache MISS）
  ├── 播放器：拿 URL 流式播放 → buffer 反映"播放缓冲了多少秒"（内存级）
  └── 后台独立下载：HttpClient 把整个文件下载到磁盘 → 这才是云缓存（磁盘级）
```

播放器的 buffer 有上限（通常几十秒够连续播放就行），不会涨到整首歌长度。后台缓存会把整首歌下完存到本地。

### 2.3 相关代码结构

```
PlaybackService
  └── MediaKitPlayerEngine
        ├── _player (media_kit Player)
        ├── _currentBuffer (本地缓存的 buffer 值)
        ├── _currentDuration (当前音频总时长)
        ├── _isNetworkSource (是否为网络源)
        ├── bufferStream (buffer 变化流)
        └── buffer getter (供外部读取当前 buffer)
```

---

## 3. 排查过程

### 3.1 第一轮：桌面端修复

**思路**：在 `_onDurationChanged` 回调中，对本地文件直接把 `_currentBuffer` 设为 `duration`，并通过 stream 推送给 UI。

```dart
void _onDurationChanged(Duration duration) {
  if (duration.inMilliseconds > 0) {
    _currentDuration = duration;
    if (!_isNetworkSource) {
      _currentBuffer = duration;       // 本地文件：buffer 直接 = 总时长
      _bufferStreamController?.add(_currentBuffer);
    }
  }
}
```

**结果**：macOS 上测试有效，进度条瞬间满格。

### 3.2 第二轮：iOS 端无效

同样的代码安装到 iPhone 真机后，进度条仍然缓慢推进。

**排查步骤**：
1. 在 `buffer` getter 中添加 `debugLog` 输出
2. 通过设置页的调试入口查看日志
3. 确认 `_onDurationChanged` 被调用（duration updated 日志出现）
4. 但 `buffer getter` 中 "local file, returning duration" 日志**未出现**

### 3.3 根本原因定位

最终发现：`PlaybackService.buffer` 属性直接访问 `_player.buffer.inSeconds`（MediaKit 的 state），**完全绕过了引擎的 `buffer` getter**：

```dart
// PlaybackService 中的代码：
double get buffer => _player.buffer.inSeconds.toDouble();
// 这直接访问了 _player!.state.buffer
// 没有经过 MediaKitPlayerEngine.buffer getter
```

因此引擎中设置 `_currentBuffer` 的逻辑在 iOS 上被 `PlaybackService.buffer` 完全忽略——UI 层读的是 MediaKit 原生的 buffer state，不是我们计算的值。

---

## 4. 最终修复方案

在引擎的 `buffer` getter 中做判断：**本地文件 + duration 已知 → 直接返回 duration**，不依赖 stream 时序，也不受外部访问方式影响：

```dart
@override
Duration get buffer {
  if (_isDisposed || _player == null) return Duration.zero;
  // 本地文件：直接返回 duration，绕过 stream 时序问题
  if (!_isNetworkSource && _currentDuration.inMilliseconds > 0) {
    return _currentDuration;
  }
  final b = _currentBuffer;
  return b.inMilliseconds >= 0 ? b : Duration.zero;
}
```

同时：
- `_onBufferChanged` 中对本地文件忽略 mpv 的预读取 buffer 报告
- `_onDurationChanged` 中对本地文件设置 `_currentBuffer = duration` 并推送到 stream

### 修复关键点

| 要点 | 说明 |
|---|---|
| `_isNetworkSource` 标志 | `setSource` 时根据 `isNetwork` 参数设置 |
| buffer getter 直接返回 duration | 不依赖 stream 初始值为 0 的时序问题 |
| 本地文件忽略 `_onBufferChanged` | 避免 mpv 的预读取 buffer 干扰本地文件的满格状态 |

---

## 5. 经验教训

### 5.1 Stream 初始值陷阱

`positionStream`、`bufferStream`、`durationStream` 的初始 `snapshot.data` 为 0（而不是 null），导致 UI 层的 `snapshot.data ?? defaultValue` 逻辑失效——`??` 永远走不到。

**应对**：对于关键显示数据，在 getter 中直接返回计算值，不依赖 stream 的初始值。

### 5.2 代理模式的一致性问题

`PlaybackService` 作为代理层，部分属性直接透传 `_player` 的 state（如 `buffer`），部分走引擎 getter，导致行为不一致。

**应对**：确保所有状态读取都经过统一的入口（引擎的 getter），避免绕过自定义逻辑。

### 5.3 跨平台验证重要性

桌面端（macOS）验证通过不代表移动端（iOS）也正常——不同平台上 media_kit 的底层行为（mpv vs avplayer）可能有差异，且调用链路可能不同。

**应对**：修复后必须在目标平台真机验证。

---

## 6. 关联修改记录

| 文件 | 修改内容 |
|---|---|
| `lib/play_service/engine/media_kit_player_engine.dart` | 添加 `_isNetworkSource` 标志，buffer getter 对本地文件直接返回 duration，_onBufferChanged 忽略本地文件 |
| `lib/play_service/playback_service.dart` | 自动保存定时器仅在播放中触发，移除调试 print |
| `lib/component/glass_app_shell.dart` | 移除 GlassMiniProgress 调试 print |
| `lib/utils.dart` | 添加 DebugLogger 文件日志工具 |
| `lib/page/settings_page/page.dart` | 添加调试日志查看入口 |

---

## 7. 验收标准

- [x] macOS 端：已缓存云音频播放时缓存进度条瞬间满格
- [x] iOS 端：已缓存云音频播放时缓存进度条瞬间满格
- [x] 网络流云音频：缓存进度条正常推进（缓慢增长）
- [x] 本地文件：缓存进度条满格
- [x] 快进到已缓存位置：立即播放，无缓冲等待
