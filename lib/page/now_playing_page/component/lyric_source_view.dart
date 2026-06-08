import 'dart:math';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/metadata/media_cache.dart';
import 'package:coriander_player/metadata/metadata_service.dart';
import 'package:coriander_player/metadata/metadata_store.dart';
import 'package:coriander_player/music_matcher.dart';
import 'package:coriander_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class SetLyricSourceBtn extends StatelessWidget {
  const SetLyricSourceBtn({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayService.instance.lyricService,
      builder: (context, _) => FutureBuilder(
        future: PlayService.instance.lyricService.currLyricFuture,
        builder: (context, snapshot) {
          const loadingWidget = IconButton(
            onPressed: null,
            icon: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(),
            ),
          );
          final lyricNullable = snapshot.data;
          final isLocal = lyricNullable == null
              ? null
              : (lyricNullable is Lrc &&
                  lyricNullable.source == LrcSource.local);
          return switch (snapshot.connectionState) {
            ConnectionState.none => loadingWidget,
            ConnectionState.waiting => loadingWidget,
            ConnectionState.active => loadingWidget,
            ConnectionState.done => _SetLyricSourceBtn(isLocal: isLocal),
          };
        },
      ),
    );
  }
}

class _SetLyricSourceBtn extends StatelessWidget {
  final bool? isLocal;
  const _SetLyricSourceBtn({this.isLocal});

  void _showMobileSheet(BuildContext context) {
    final lyricService = PlayService.instance.lyricService;
    final scheme = Theme.of(context).colorScheme;
    ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = true;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '歌词来源',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: Icon(Symbols.search, color: scheme.onSurface),
              title: const Text('指定默认歌词'),
              onTap: () {
                Navigator.pop(context);
                final nowPlaying =
                    PlayService.instance.playbackService.nowPlaying;
                final scaffoldContext = context;
                Navigator.of(scaffoldContext).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) =>
                        _SetLyricSourcePage(audio: nowPlaying!),
                  ),
                );
              },
            ),
            ListTile(
              leading: isLocal == false
                  ? Icon(Symbols.check, color: scheme.primary)
                  : Icon(Symbols.language, color: scheme.onSurface),
              title: const Text('在线歌词'),
              onTap: () {
                Navigator.pop(context);
                lyricService.useOnlineLyric();
              },
            ),
            ListTile(
              leading: isLocal == true
                  ? Icon(Symbols.check, color: scheme.primary)
                  : Icon(Symbols.folder, color: scheme.onSurface),
              title: const Text('本地歌词'),
              onTap: () {
                Navigator.pop(context);
                lyricService.useLocalLyric();
              },
            ),
            const SizedBox(height: 8.0),
          ],
        ),
      ),
    ).whenComplete(() {
      ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricService = PlayService.instance.lyricService;

    // 移动端：点击直接弹出 BottomSheet
    if (PlatformHelper.isMobile) {
      return IconButton(
        onPressed: PlayService.instance.playbackService.nowPlaying == null
            ? null
            : () => _showMobileSheet(context),
        icon: const Icon(Symbols.lyrics),
        color: scheme.onSecondaryContainer,
      );
    }

    // 桌面端：MenuAnchor 下拉菜单
    return MenuAnchor(
      onOpen: () {
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = true;
      },
      onClose: () {
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = false;
      },
      menuChildren: [
        MenuItemButton(
          onPressed: () {
            final nowPlaying = PlayService.instance.playbackService.nowPlaying;
            showDialog<String>(
              context: context,
              builder: (context) => _SetLyricSourceDialog(audio: nowPlaying!),
            );
          },
          child: const Text("指定默认歌词"),
        ),
        MenuItemButton(
          onPressed: lyricService.useOnlineLyric,
          leadingIcon: isLocal == false ? const Icon(Symbols.check) : null,
          child: const Text("在线"),
        ),
        MenuItemButton(
          onPressed: lyricService.useLocalLyric,
          leadingIcon: isLocal == true ? const Icon(Symbols.check) : null,
          child: const Text("本地"),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        onPressed: PlayService.instance.playbackService.nowPlaying == null
            ? null
            : () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
        icon: const Icon(Symbols.lyrics),
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

/// 移动端全屏页面：歌词检索与选择
class _SetLyricSourcePage extends StatelessWidget {
  const _SetLyricSourcePage({required this.audio});

  final Audio audio;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('默认歌词'),
      ),
      body: _SetLyricSourceBody(audio: audio),
    );
  }
}

/// 桌面端弹窗：歌词检索与选择
class _SetLyricSourceDialog extends StatefulWidget {
  const _SetLyricSourceDialog({required this.audio});

  final Audio audio;

  @override
  State<_SetLyricSourceDialog> createState() => _SetLyricSourceDialogState();
}

class _SetLyricSourceDialogState extends State<_SetLyricSourceDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 384, maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _SetLyricSourceBody(audio: widget.audio),
        ),
      ),
    );
  }
}

/// 歌词检索与选择的通用内容组件（被全屏页面和桌面弹窗共用）
class _SetLyricSourceBody extends StatefulWidget {
  const _SetLyricSourceBody({required this.audio});

  final Audio audio;

  @override
  State<_SetLyricSourceBody> createState() => _SetLyricSourceBodyState();
}

class _SetLyricSourceBodyState extends State<_SetLyricSourceBody> {
  final TextEditingController _searchController = TextEditingController();
  String? _customQuery;
  late Future<List<SongSearchResult>> _searchFuture;

  @override
  void initState() {
    super.initState();
    _searchController.text = buildSearchQuery(widget.audio);
    _searchFuture = uniSearch(widget.audio);
  }

  void _performSearch() {
    setState(() {
      _customQuery = _searchController.text.trim();
      _searchFuture = uniSearch(widget.audio, customQuery: _customQuery);
    });
  }

  Widget _buildInfoRow(String label, String value, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前音频信息，方便与搜索结果对比
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow("歌名", widget.audio.title, scheme),
              if (widget.audio.artist.isNotEmpty)
                _buildInfoRow("艺术家", widget.audio.artist, scheme),
              if (widget.audio.album.isNotEmpty)
                _buildInfoRow("专辑", widget.audio.album, scheme),
            ],
          ),
        ),
        const SizedBox(height: 12.0),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: "搜索关键词",
            hintText: "输入歌词搜索关键词",
            suffixIcon: IconButton(
              icon: const Icon(Symbols.search),
              onPressed: _performSearch,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
          onSubmitted: (_) => _performSearch(),
        ),
        const SizedBox(height: 16.0),
        ListTile(
          title: const Text("使用本地歌词"),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          onTap: () {
            LYRIC_SOURCES[widget.audio.path] =
                LyricSource(LyricSourceType.local);
            saveLyricSources();
            PlayService.instance.lyricService.useLocalLyric();
            Navigator.of(context).pop();
          },
        ),
        const Divider(),
        Expanded(
          child: FutureBuilder(
            future: _searchFuture,
            builder: (context, snapshot) {
              if (snapshot.data == null) {
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, i) => _LyricSourceTile(
                  audio: widget.audio,
                  searchResult: snapshot.data![i],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LyricSourceTile extends StatefulWidget {
  const _LyricSourceTile({
    required this.searchResult,
    required this.audio,
  });

  final Audio audio;
  final SongSearchResult searchResult;

  @override
  State<_LyricSourceTile> createState() => _LyricSourceTileState();
}

class _LyricSourceTileState extends State<_LyricSourceTile> {
  late final lyric = getOnlineLyric(
    qqSongId: widget.searchResult.qqSongId,
    kugouSongHash: widget.searchResult.kugouSongHash,
    neteaseSongId: widget.searchResult.neteaseSongId,
  );
  @override
  Widget build(BuildContext context) {
    const loadingWidget = Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(),
        ),
      ),
    );
    return FutureBuilder(
      future: lyric,
      builder: (context, lyricSnapshot) =>
          switch (lyricSnapshot.connectionState) {
        ConnectionState.none => loadingWidget,
        ConnectionState.waiting => loadingWidget,
        ConnectionState.active => loadingWidget,
        ConnectionState.done =>
          lyricSnapshot.data == null || lyricSnapshot.data!.lines.isEmpty
              ? const SizedBox.shrink()
              : buildTile(
                  context,
                  widget.audio,
                  widget.searchResult,
                  lyricSnapshot.data!,
                ),
      },
    );
  }

  Widget buildTile(
    BuildContext context,
    Audio audio,
    SongSearchResult searchResult,
    Lyric lyric,
  ) {
    return ListTile(
      onTap: () {
        LyricSourceType source = switch (searchResult.source) {
          ResultSource.qq => LyricSourceType.qq,
          ResultSource.kugou => LyricSourceType.kugou,
          ResultSource.netease => LyricSourceType.netease,
        };
        LYRIC_SOURCES[audio.path] = LyricSource(
          source,
          qqSongId: searchResult.qqSongId,
          kugouSongHash: searchResult.kugouSongHash,
          neteaseSongId: searchResult.neteaseSongId,
        );
        saveLyricSources();
        PlayService.instance.lyricService.useSpecificLyric(lyric);

        // 同步缓存歌词到 MetadataStore（下次播放可直接从缓存加载）
        _cacheLyricForAudio(audio, lyric);

        Navigator.of(context).pop();
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      leading: Text(lyric is Lrc ? "LRC" : "逐字"),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            searchResult.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            [
              if (searchResult.artists.isNotEmpty) searchResult.artists,
              if (searchResult.album.isNotEmpty) searchResult.album,
            ].join(' - '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      subtitle: StreamBuilder(
        stream: PlayService.instance.playbackService.positionStream,
        builder: (context, positionSnapshot) {
          final currLineIndex = max(lyric.lines.lastIndexWhere(
            (element) {
              return element.start.inMilliseconds <
                  (positionSnapshot.data ?? 0) * 1000;
            },
          ), 0);

          final LyricLine currLine = lyric.lines[currLineIndex];
          if (currLine is LrcLine) {
            return Text(
              "当前：${currLine.content}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          } else {
            final syncLine = currLine as SyncLyricLine;

            return Text(
              "当前：${syncLine.content}${syncLine.translation != null ? "┃${syncLine.translation}" : ""}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          }
        },
      ),
    );
  }
}

/// 后台缓存歌词到 MetadataStore（不阻塞 UI）
Future<void> _cacheLyricForAudio(Audio audio, Lyric lyric) async {
  try {
    final audioId = await MetadataService.instance.computeAudioId(audio);
    if (audioId == null) return;

    // 将歌词导出为 LRC 文本
    final buf = StringBuffer();
    for (final line in lyric.lines) {
      if (line is LrcLine) {
        final startMs = line.start.inMilliseconds;
        final min = (startMs ~/ 60000).toString().padLeft(2, '0');
        final sec = ((startMs % 60000) ~/ 1000).toString().padLeft(2, '0');
        final ms = (startMs % 1000).toString().padLeft(3, '0');
        buf.writeln('[$min:$sec.$ms]${line.content}');
      }
    }
    final lyricText = buf.toString();
    if (lyricText.isEmpty) return;

    // 保存到本地缓存文件
    await MediaCache.instance.saveLyric(audioId, lyricText, synced: true);
    // 保存到数据库
    await MetadataStore.instance.updateLyric(audioId, lyricText, synced: true);
    LOGGER.i("[LyricSourceView] Cached lyric for: ${audio.title}");
  } catch (e) {
    LOGGER.e("[LyricSourceView] Failed to cache lyric: $e");
  }
}
