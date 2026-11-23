# 封面刷新逻辑分析文档

## 问题描述

播放音频时，即使封面已正常显示在列表中，当前播放条目和迷你播放器的封面仍会闪烁刷新。所有格式（m4a、wav、mp3、flac）均受影响。

## 期望逻辑（用户定义）

一首音频有两个独立维度：**封面** 和 **元数据**。

```
播放时：
1. 有封面 → 不走封面相关逻辑
2. 没封面 → 抓封面（内嵌 → 刮削）
3. 有元数据 → 不抓元数据
4. 没元数据 → 抓元数据
5. 两个都没有 → 串行处理（先封面再元数据，或先元数据再封面）
6. 封面变动 → 触发主题颜色变化
7. 已有的不重复抓
```

## 当前代码流程

### 入口：`_loadAndPlay` (playback_service.dart:460)

```dart
// 第409行：播放完成后通知
notifyListeners();
ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);

// 第460行：后台刮削（无前置检查）
_autoScrapeMetadata(nowPlaying!);
```

**问题**：无论音频是否已有封面、元数据是否完整，都会无条件调用 `_autoScrapeMetadata`。

---

### `_autoScrapeMetadata` (playback_service.dart:507-590)

```dart
void _autoScrapeMetadata(Audio audio) {
  final metadataIncomplete = _isMetadataIncomplete(audio);  // ① 判断元数据是否缺失

  MetadataService.instance.autoScrape(
    audio,
    forceScrape: metadataIncomplete,                        // ② 元数据缺失时强制重新刮削
    onScraped: (isExactMatch, output) async {               // ③ 网络回调
      if (!isExactMatch) return;

      playService.lyricService.updateLyric();                // ④ 刷新歌词

      if (output?.bestMatch != null) {
        _applyScrapedMetadata(audio, output!.bestMatch);    // ⑤ 元数据回写
      }

      final hasEmbeddedCover = await _hasEmbeddedCover(audio); // ⑥ IO操作：检查内嵌封面

      if (hasEmbeddedCover) {
        // ⑦ 有内嵌封面
        if (audio.coverImage == null) {
          audio.clearCoverCache();                           // ⑧ 清空封面缓存（递增generation）
        }
        notifyListeners();                                   // ⑨ 无条件通知
        AudioLibrary.instance.notifyUpdated();               // ⑩ 无条件通知
        if (nowPlaying?.path == audio.path) {
          ThemeProvider.instance.applyThemeFromAudio(audio); // ⑪ 主题更新
        }
        return;
      }

      // ⑫ 无内嵌封面，尝试刮削封面
      Uint8List? coverBytes = output?.coverData;
      if (coverBytes == null) {
        coverBytes = await MetadataService.instance.getOrScrapeCover(audio, autoScrape: false);
      }
      if (coverBytes == null) {
        coverBytes = await MetadataService.instance.getOrScrapeCover(audio, autoScrape: true);
      }

      if (coverBytes != null) {
        audio.setCover(MemoryImage(coverBytes));             // ⑬ 设置新封面
        await audio.setCoverSource('scraped');
        // ... 保存到 MediaCache ...
      } else {
        audio.clearCoverCache();                             // ⑭ 没拿到封面也清空
      }

      notifyListeners();                                     // ⑮ 无条件通知
      AudioLibrary.instance.notifyUpdated();                 // ⑯ 无条件通知
      if (nowPlaying?.path == audio.path) {
        ThemeProvider.instance.applyThemeFromAudio(audio);   // ⑰ 主题更新
      }
    },
  );
}
```

---

### `autoScrape` 内部 (metadata_service.dart:361-436)

| 场景 | scrapedAt | forceScrape | 行为 | onScraped 回调 |
|------|-----------|-------------|------|----------------|
| 之前没刮削过 | null | false | 执行网络刮削 | `(exactMatch, output)` output有值 |
| 之前没刮削过 | null | true | 执行网络刮削 | `(exactMatch, output)` output有值 |
| 之前刮削过 | 有值 | false | **跳过网络请求** | `(true, null)` **output为null** |
| 之前刮削过 | 有值 | true | 重新网络刮削 | `(exactMatch, output)` output有值 |

---

### 五条执行路径分析

#### 路径A：已刮削过 + 元数据完整 + 有内嵌封面 + 封面已在内存

```
metadataIncomplete=false → forceScrape=false
autoScrape: scrapedAt!=null, 跳过网络 → onScraped(true, null)
output==null → 跳过元数据回写
_hasEmbeddedCover()=true (IO操作)
coverImage != null → 跳过 clearCoverCache
notifyListeners()          ★不必要（无数据变化）
AudioLibrary.notifyUpdated() ★不必要（无数据变化）
applyThemeFromAudio()      被_path去重跳过
```

**问题**：没有任何数据变化，却触发了2次全局通知，导致 UI 重建。

#### 路径B：已刮削过 + 元数据完整 + 有内嵌封面 + 封面还没加载到内存

```
metadataIncomplete=false → forceScrape=false
autoScrape: scrapedAt!=null, 跳过网络 → onScraped(true, null)
output==null → 跳过元数据回写
_hasEmbeddedCover()=true (IO操作)
coverImage == null → clearCoverCache()  ★无意义（_cover本来就是null），但递增generation
notifyListeners()          ★不必要
AudioLibrary.notifyUpdated() ★不必要
applyThemeFromAudio()      cover.then返回null，不执行
```

**问题**：`clearCoverCache` 无意义（_cover 本来就是 null），但递增了 generation。如果此时恰好有 `cover` getter 正在 in-flight，会被打断。通知了3次但实际没有任何数据变化。

#### 路径C：已刮削过 + 元数据不完整 + 有内嵌封面

```
metadataIncomplete=true → forceScrape=true
autoScrape: 重新网络刮削 → onScraped(true, output) output有值
_applyScrapedMetadata()  填充缺失字段
_hasEmbeddedCover()=true
notifyListeners()          合理（元数据变了）
AudioLibrary.notifyUpdated() 合理
applyThemeFromAudio()      合理
```

**这条路径合理**。

#### 路径D：未刮削过 + 无内嵌封面 + 刮削成功

```
autoScrape: 执行网络刮削 → onScraped(true, output)
_applyScrapedMetadata()
_hasEmbeddedCover()=false
获取封面: output.coverData → getOrScrapeCover(false) → getOrScrapeCover(true)
setCover(MemoryImage(coverBytes))  合理（新封面）
notifyListeners()          合理
AudioLibrary.notifyUpdated() 合理
applyThemeFromAudio()      合理
```

**这条路径合理**。

#### 路径E：无内嵌封面 + 刮削失败

```
coverBytes == null
clearCoverCache()          ★不必要（_cover本来就是null）
notifyListeners()          ★不必要（无变化）
AudioLibrary.notifyUpdated() ★不必要
applyThemeFromAudio()      cover为null，不执行
```

**问题**：无数据变化却触发刷新。

---

## 问题汇总

| # | 问题 | 位置 | 影响 |
|---|------|------|------|
| 1 | 缺少前置短路检查 | `_autoScrapeMetadata` 入口 | 元数据完整+封面已有仍调用 autoScrape，发起网络请求 |
| 2 | onScraped 回调中无条件通知 | 第536-537行、第581-583行 | 即使无数据变化也触发全局UI刷新 |
| 3 | coverImage==null 时调用 clearCoverCache | 第533-534行 | 打断可能在进行的 cover 加载，封面闪烁 |
| 4 | 没拿到封面也调用 clearCoverCache + 通知 | 第577行、第581-583行 | 无数据变化却触发刷新 |
| 5 | _hasEmbeddedCover 重复IO | 第528行 | 封面已显示在UI上，还要读文件确认 |

## 竞态条件状态

已通过 generation 机制基本消除：
- `_getResizedPic` 开始时记录 generation，设置 `_cover` 前检查 `gen == _coverGeneration`
- `setCover`/`clearCoverCache` 递增 generation，使旧任务失效
- `cover` getter 的 then 回调检查 generation，变化时不操作 `_coverFuture`

---

## 修复方案（已实施）

### 修复文件

- [playback_service.dart](file:///Users/xiaof/AppData/code/senyepss/coriander_player_solo/lib/play_service/playback_service.dart) — `_autoScrapeMetadata` 和 `_applyScrapedMetadata`

### 修复内容

#### 1. 前置短路检查（解决问题1）

在 `_autoScrapeMetadata` 入口处，检查元数据是否完整且封面是否已有：

```dart
void _autoScrapeMetadata(Audio audio) {
  final metadataIncomplete = _isMetadataIncomplete(audio);
  final hasCover = audio.coverImage != null;

  // 前置短路：元数据完整 + 封面已有 → 无需任何操作
  if (!metadataIncomplete && hasCover) {
    return;
  }
  // ... 后续逻辑
}
```

#### 2. `_applyScrapedMetadata` 返回是否有变化（解决问题2）

```dart
bool _applyScrapedMetadata(Audio audio, ScrapeResult result) {
  var changed = false;
  // ... 每次实际写入字段时设置 changed = true
  return changed;
}
```

#### 3. onScraped 回调中有条件通知（解决问题2、4）

- 封面已存在时：只在 `metadataChanged == true` 时才通知
- 没拿到封面时：只在 `metadataChanged == true` 时才通知
- 拿到新封面时：无条件通知（封面确实变了）

#### 4. 移除不必要的 clearCoverCache（解决问题3）

- 有内嵌封面但 `coverImage == null` 时：改为 `audio.cover` 触发异步加载，不再调用 `clearCoverCache()`
- 没拿到刮削封面时：不再调用 `clearCoverCache()`

#### 5. 封面已有时跳过 _hasEmbeddedCover IO（解决问题5）

在 onScraped 回调中，`audio.coverImage != null` 时直接 return，不执行 `_hasEmbeddedCover()` IO 操作。

### 修复后流程

```
播放音频
  ├─ notifyListeners()                    ← 必要（更新播放指示器）
  ├─ applyThemeFromAudio()                ← 主题更新（有_path去重保护）
  └─ _autoScrapeMetadata()
      ├─ 元数据完整 + 封面已有 → 直接 return（零开销）
      ├─ 元数据完整 + 封面缺失 → autoScrape(forceScrape=false)
      │   └─ onScraped:
      │       ├─ 封面已存在（可能加载完成）→ metadataChanged? 通知 : 跳过
      │       └─ 封面缺失 → 检查内嵌 → 刮削封面 → 有变化才通知
      └─ 元数据缺失 → autoScrape(forceScrape=true)
          └─ onScraped:
              ├─ 元数据回写（返回 changed）
              ├─ 封面已存在 → changed? 通知 : 跳过
              └─ 封面缺失 → 检查内嵌 → 刮削封面 → 有变化才通知
```

### 修复后的通知次数对比

| 场景 | 修复前 | 修复后 |
|------|--------|--------|
| 元数据完整+封面已有 | 2次通知（路径A） | **0次**（短路返回） |
| 元数据完整+封面缺失+有内嵌 | 3次通知+clearCoverCache（路径B） | **0-1次**（cover getter 自行加载通知） |
| 元数据不完整+有内嵌 | 2次通知（路径C） | **1次**（仅 metadataChanged 时） |
| 无内嵌+刮削成功 | 2次通知（路径D） | **1次**（封面变动通知） |
| 无内嵌+刮削失败 | 2次通知+clearCoverCache（路径E） | **0-1次**（仅 metadataChanged 时） |
