<br />

# Fix : Range元数据对音乐库不生效

**文件**: `/Users/xiaof/AppData/code/senyepss/coriander_player/lib/cloud_service/cloud_audio_player.dart`

- `addCloudFolderToLibrary`: 将 fire-and-forget 的 `_updateMetadataViaRangeForLibrary` 调用改为每批3个顺序执行（`await Future.wait(batch)`），并更新进度状态
- 在所有元数据获取完成后，统一调用一次 `library.rebuildCollections()`、`library.saveCloudAudios()` 和 `library.notifyUpdated()`
- `_updateMetadataViaRangeForLibrary`: 移除了方法内部的 `library.rebuildCollections()`、`library.saveCloudAudios()` 和 `library.notifyUpdated()` 调用，由调用方统一处理

### Fix 3: 为WebDAV浏览器中的单个音频文件添加"添加到音乐库"选项

**文件**: `/Users/xiaof/AppData/code/senyepss/coriander_player/lib/cloud_service/cloud_audio_player.dart`

- 新增 `addCloudFilesToLibrary` 静态方法，支持直接传入 `List<WebDavFile>` 添加到音乐库（非递归扫描），同样使用批量3个的 Range 元数据获取策略

**文件**: `/Users/xiaof/AppData/code/senyepss/coriander_player/lib/page/cloud_service/cloud_file_browser.dart`

- 音频文件的弹出菜单新增"添加到音乐库"选项
- 新增 `_addAudioToLibrary` 方法处理单个文件添加
- 新增 `_addSelectedToLibrary` 方法处理多选模式下的批量添加
- AppBar 菜单在多选模式下新增"添加选中到音乐库"选项
- 新增 `_AddToLibraryDialog` widget，使用 `addCloudFilesToLibrary` 方法

<br />

***

# FIX. Range 元数据对音乐库不生效（时长仍为 0:00:00）

**文件**: [cloud\_audio\_player.dart](lib/cloud_service/cloud_audio_player.dart)

**根因**: 之前 `_updateMetadataViaRangeForLibrary` 是 fire-and-forget 调用，所有请求同时发出导致服务器过载，且每个请求单独调用 `library.rebuildCollections()` 造成大量重复重建。

**修复**:

- 改为每批 3 个顺序执行（`await Future.wait(batch)`）
- 所有元数据获取完成后，统一调用一次 `library.rebuildCollections()` + `library.saveCloudAudios()` + `library.notifyUpdated()`
- `_updateMetadataViaRangeForLibrary` 不再单独调用库更新方法
- 对话框显示实时进度："获取元数据中... (3/15)"

***

## 修改总结

### 2. 云音频时长仍为 0:00:00

**文件**: [cloud\_audio\_player.dart](lib/cloud_service/cloud_audio_player.dart)

**根因**: 之前使用 HTTP Range 请求下载头尾字节 + lofty 解析的方案**不可靠**——lofty 无法从零填充的虚拟文件中识别音频格式（"No format could be determined from the provided file"）。

**修复**: 改为**同步下载完整文件 → 读取元数据 → 添加到音乐库**的流程：

```
旧方案（不可靠）:
  创建占位 Audio(duration=0) → 添加到库 → 异步 Range 请求元数据 → 更新库

新方案（可靠）:
  下载文件到临时目录 → _createAudioWithMetadata() 读取完整元数据 → 修改路径为 WebDAV 路径 → 添加到库
```

关键改动：

- `addCloudFolderToLibrary` 和 `addCloudFilesToLibrary` 现在逐个下载文件并同步读取元数据
- `_createAudioWithMetadata` 使用 `buildIndexFromFoldersRecursively` 从本地文件读取完整标签
- 读取后将 `audio.path` 改回 WebDAV 路径，`audio.by` 设为 `'Cloud'`
- 下载失败时回退到文件名解析（标题+艺术家）
- 对话框显示实时进度："正在处理 (3/15): 任贤齐 - 橘子香水.flac"
- 删除了不可靠的 `_updateMetadataViaRangeForLibrary` 方法

