import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/play_service/recent_play_service.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class RecentPlaysPage extends StatelessWidget {
  const RecentPlaysPage({super.key});

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
