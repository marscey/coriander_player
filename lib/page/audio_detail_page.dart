import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/component/album_tile.dart';
import 'package:coriander_player/component/artist_tile.dart';
import 'package:coriander_player/src/rust/api/utils.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/page/cloud_service/cloud_file_browser.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class AudioDetailPage extends StatelessWidget {
  const AudioDetailPage({super.key, required this.audio});

  final Audio audio;

  static String _getShowInExplorerLabel() {
    if (PlatformHelper.isMacOS) return "在 Finder 中显示";
    if (PlatformHelper.isLinux) return "在文件管理器中显示";
    return "在文件资源管理器中显示";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final artists = List.generate(
      audio.splitedArtists.length,
      (i) {
        return AudioLibrary.instance.artistCollection[audio.splitedArtists[i]]!;
      },
    );
    final album = AudioLibrary.instance.albumCollection[audio.album]!;
    const space = SizedBox(height: 12.0);

    final coverSize = isMobile ? 120.0 : 200.0;
    final styleTitle = TextStyle(fontSize: isMobile ? 20 : 22, color: scheme.onSurface);
    final styleContent = TextStyle(fontSize: 16, color: scheme.onSurface);
    final placeholder = Icon(
      Symbols.broken_image,
      color: scheme.onSurface,
      size: coverSize,
    );

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 4.0, 16.0, 0),
              child: Row(
                children: [
                  if (context.canPop())
                    IconButton.filledTonal(
                      tooltip: "返回",
                      onPressed: () => context.pop(),
                      icon: const Icon(Symbols.arrow_back, size: 20.0),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    "音乐详情",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 12, 16.0, 96.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面 + 歌曲信息：手机横排紧凑布局，桌面横排
                  FutureBuilder(
                    future: audio.mediumCover,
                    builder: (context, snapshot) {
                      final coverWidget = switch (snapshot.connectionState) {
                        ConnectionState.done => snapshot.data == null
                            ? placeholder
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: Image(
                                  image: snapshot.data!,
                                  width: coverSize,
                                  height: coverSize,
                                  errorBuilder: (_, __, ___) => placeholder,
                                ),
                              ),
                        _ => SizedBox(
                            width: coverSize,
                            height: coverSize,
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                      };

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          coverWidget,
                          const SizedBox(width: 16),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(audio.title, style: styleTitle),
                                  const SizedBox(height: 8),
                                  if (audio.artist.isNotEmpty)
                                    Text(audio.artist,
                                        style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                                  if (audio.album.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(audio.album,
                                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  space,

                  /// artists
                  _AudioDetailTile(
                    title: "艺术家",
                    isMobile: isMobile,
                    detail: Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: List.generate(
                        artists.length,
                        (i) {
                          return SizedBox(
                            width: isMobile ? double.infinity : 300,
                            child: ArtistTile(artist: artists[i]),
                          );
                        },
                      ),
                    ),
                  ),

                  /// album
                  _AudioDetailTile(
                    title: "专辑",
                    isMobile: isMobile,
                    detail: AlbumTile(album: album),
                  ),
                  _AudioDetailTile(
                    title: "音轨",
                    isMobile: isMobile,
                    detail: Text(audio.track > 0 ? audio.track.toString() : "—"),
                  ),
                  _AudioDetailTile(
                    title: "时长",
                    isMobile: isMobile,
                    detail: Text(Duration(
                      milliseconds: (audio.duration * 1000).toInt(),
                    ).toStringHMMSS()),
                  ),
                  _AudioDetailTile(
                    title: "码率",
                    isMobile: isMobile,
                    detail: Text("${audio.bitrate} kbps"),
                  ),
                  _AudioDetailTile(
                    title: "采样率",
                    isMobile: isMobile,
                    detail: Text("${audio.sampleRate} hz"),
                  ),

                  /// path
                  _AudioDetailTile(
                    title: "路径",
                    isMobile: isMobile,
                    detail: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (audio.isCloudAudio)
                          TextButton(
                            onPressed: () {
                              final connectionId = audio.connectionId;
                              if (connectionId == null) return;
                              final playingPath = audio.path;
                              final dirPath = playingPath.contains('/')
                                  ? playingPath.substring(
                                      0, playingPath.lastIndexOf('/'))
                                  : '';
                              context.push(
                                '${app_paths.CLOUD_BROWSER_PAGE}/$connectionId',
                                extra: CloudBrowserArgs(dirPath, playingPath),
                              );
                            },
                            child: const Text("在云服务中显示"),
                          )
                        else
                          TextButton(
                            onPressed: () async {
                              final result =
                                  await showInExplorer(path: audio.path);
                              if (!result && context.mounted) {
                                showTextOnSnackBar("打开失败");
                              }
                            },
                            child: Text(_getShowInExplorerLabel()),
                          ),
                        Text(audio.path, style: styleContent),
                      ],
                    ),
                  ),

                  /// modified
                  _AudioDetailTile(
                    title: "修改时间",
                    isMobile: isMobile,
                    detail: Text(
                      DateTime.fromMillisecondsSinceEpoch(
                        audio.modified * 1000,
                      ).toString(),
                    ),
                  ),

                  /// created
                  _AudioDetailTile(
                    title: "创建时间",
                    isMobile: isMobile,
                    detail: Text(
                      DateTime.fromMillisecondsSinceEpoch(
                        audio.created * 1000,
                      ).toString(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioDetailTile extends StatelessWidget {
  const _AudioDetailTile({
    required this.title,
    required this.detail,
    this.isMobile = false,
  });

  final String title;
  final Widget detail;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: isMobile ? 20 : 22, color: scheme.onSurface)),
          const SizedBox(height: 4.0),
          detail,
        ],
      ),
    );
  }
}
