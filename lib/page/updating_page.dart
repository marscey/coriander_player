import 'dart:async';
import 'dart:io';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/cloud_service/cloud_audio_player.dart';
import 'package:coriander_player/cloud_service/cloud_service_manager.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;

class UpdatingPage extends StatelessWidget {
  const UpdatingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: FutureBuilder(
          future: getAppDataDir(),
          builder: (context, snapshot) {
            if (snapshot.data == null) {
              return const Center(
                child: Text("Fail to get app data dir."),
              );
            }

            return UpdatingStateView(indexPath: snapshot.data!);
          },
        ),
      ),
    );
  }
}

class UpdatingStateView extends StatefulWidget {
  const UpdatingStateView({super.key, required this.indexPath});

  final Directory indexPath;

  @override
  State<UpdatingStateView> createState() => _UpdatingStateViewState();
}

class _UpdatingStateViewState extends State<UpdatingStateView> {
  late final Stream<IndexActionState> updateIndexStream;
  StreamSubscription? _subscription;

  void whenIndexUpdated() async {
    await Future.wait([
      AudioLibrary.initFromIndex(),
      readPlaylists(),
      readLyricSources(),
    ]);

    // TODO: 测试用自动扫描，稳定后移除
    if (AppSettings.instance.autoTestConfig) {
      _autoScanTestFolder();
    }

    _subscription?.cancel();
    final ctx = context;
    if (ctx.mounted) {
      ctx.go(app_paths.START_PAGES[AppPreference.instance.startPage]);
    }
  }

  /// 测试用：音乐库为空时自动扫描云连接中的测试文件夹
  void _autoScanTestFolder() async {
    final library = AudioLibrary.instance;
    if (library.audioCollection.isNotEmpty) return;

    try {
      await CloudServiceManager.instance.ready;
      final manager = CloudServiceManager.instance;
      if (manager.connections.isEmpty) return;

      final connection = manager.connections.first;
      final service = manager.getService(connection.id);
      if (service == null) return;

      LOGGER.i('[Test] Auto-scanning test folders into library...');
      // 扫描周杰伦专辑
      final testFolders = [
        '歌单/周杰伦Hi-Res全集（2024年环球音乐官方新版）/[2004-08-03] 周杰伦《七里香》[Hi-Res／44.1kHz／24bit／FLAC]',
        '歌单/周杰伦Hi-Res全集（2024年环球音乐官方新版）/[2016-06-24] 周杰伦《周杰伦的床边故事》[Hi-Res／96kHz／24bit／FLAC]',
      ];
      for (final folderPath in testFolders) {
        LOGGER.i('[Test] Scanning: $folderPath');
        await CloudAudioPlayer.addCloudFolderToLibrary(
          service: service,
          folderPath: folderPath,
          connectionId: connection.id,
          onProgress: (count) {
            LOGGER.i('[Test] Auto-scan progress: $count files added');
          },
          onStatus: (status) {
            LOGGER.i('[Test] Auto-scan status: $status');
          },
        );
      }
      LOGGER.i('[Test] Auto-scan completed');

      // 后台更新元数据（封面等），不阻塞主线程
      final cloudAudios = library.audioCollection
          .where((a) => a.isCloudAudio)
          .toList();
      if (cloudAudios.isNotEmpty) {
        LOGGER.i('[Test] Starting background metadata update for ${cloudAudios.length} audios...');
        CloudAudioPlayer.updateAudioMetadataInBackground(
          audios: cloudAudios,
          onProgress: (completed, total) {
            if (completed % 5 == 0 || completed == total) {
              LOGGER.i('[Test] Metadata update progress: $completed/$total');
            }
          },
          onComplete: () {
            LOGGER.i('[Test] Background metadata update completed');
          },
        );

        // 自动播放第一首歌曲
        LOGGER.i('[Test] Auto-playing first song...');
        PlayService.instance.playbackService.play(0, cloudAudios);
      }
    } catch (e) {
      LOGGER.e('[Test] Auto-scan failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    updateIndexStream = updateIndex(
      indexPath: widget.indexPath.path,
    ).asBroadcastStream();

    _subscription = updateIndexStream.listen(
      (action) {
        LOGGER.i("[update index] ${action.progress}: ${action.message}");
      },
      onDone: whenIndexUpdated,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 400.0,
      child: StreamBuilder(
        stream: updateIndexStream,
        builder: (context, snapshot) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              LinearProgressIndicator(
                value: snapshot.data?.progress,
                borderRadius: BorderRadius.circular(2.0),
              ),
              const SizedBox(height: 8.0),
              Text(
                snapshot.data?.message ?? "正在更新音乐索引...",
                style: TextStyle(color: scheme.onSurface),
              ),
            ],
          );
        },
      ),
    );
  }
}
