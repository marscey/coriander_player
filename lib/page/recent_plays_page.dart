import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/component/playing_indicator.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/page/cloud_service/cloud_file_browser.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/recent_play_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class RecentPlaysPage extends StatefulWidget {
  const RecentPlaysPage({super.key});

  @override
  State<RecentPlaysPage> createState() => _RecentPlaysPageState();
}

class _RecentPlaysPageState extends State<RecentPlaysPage> {
  final _playbackService = PlayService.instance.playbackService;

  @override
  void initState() {
    super.initState();
    _playbackService.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    _playbackService.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasPlayingAudioInRecent {
    final nowPlaying = _playbackService.nowPlaying;
    if (nowPlaying == null) return false;
    return RecentPlayService.instance.recentAudios
        .any((a) => a.path == nowPlaying.path);
  }

  void _locatePlaying() {
    final nowPlaying = _playbackService.nowPlaying;
    if (nowPlaying == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未在播放音频')),
      );
      return;
    }
    if (nowPlaying.isCloudAudio) {
      // 云音频跳转到对应的云服务连接
      final connectionId = nowPlaying.connectionId;
      if (connectionId == null) return;
      final playingPath = nowPlaying.path;
      final dirPath = playingPath.contains('/')
          ? playingPath.substring(0, playingPath.lastIndexOf('/'))
          : '';
      context.push(
        '/cloud/browser/$connectionId',
        extra: CloudBrowserArgs(dirPath, playingPath),
      );
    } else {
      // 本地音频跳转到音乐库页面并定位
      context.push('/audios', extra: nowPlaying);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RecentPlayService.instance,
      builder: (context, _) {
        final contentList = RecentPlayService.instance.recentAudios;
        final multiSelectController = MultiSelectController<Audio>();

        if (contentList.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('最近播放')),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Symbols.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无播放记录', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('播放音乐后会自动记录在这里',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          );
        }

        return UniPage<Audio>(
          pref: AppPreference.instance.recentPlaysPagePref,
          title: "最近播放",
          subtitle: "${contentList.length} 首乐曲",
          contentList: contentList,
          contentBuilder: (context, item, i, multiSelectController) =>
              AudioTile(
            audioIndex: i,
            playlist: contentList,
            multiSelectController: multiSelectController,
          ),
          enableShufflePlay: true,
          enableSortMethod: false,
          enableSortOrder: false,
          enableContentViewSwitch: true,
          primaryAction: LocatePlayingButton(
            hasPlayingAudio: _hasPlayingAudioInRecent,
            onLocate: _locatePlaying,
          ),
          multiSelectController: multiSelectController,
          multiSelectViewActions: [
            AddAllToPlaylist(multiSelectController: multiSelectController),
            MultiSelectSelectOrClearAll(
              multiSelectController: multiSelectController,
              contentList: contentList,
            ),
            MultiSelectExit(multiSelectController: multiSelectController),
          ],
        );
      },
    );
  }
}
