import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/unified_list_tile.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/genre_service.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/glass_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final artistCount = AudioLibrary.instance.artistCollection.length;
    final albumCount = AudioLibrary.instance.albumCollection.length;
    final genreCount = GenreService.instance.genres.length;
    final totalCount = artistCount + albumCount + genreCount;
    final subtitle = totalCount > 0 ? "$totalCount 个分类项" : null;

    final tileList = [
      UnifiedListTile(
        icon: CupertinoIcons.person_2,
        title: "艺术家",
        subtitle: "$artistCount 位艺术家",
        onTap: () => context.push(app_paths.ARTISTS_PAGE),
      ),
      UnifiedListTile(
        icon: CupertinoIcons.music_albums,
        title: "专辑",
        subtitle: "$albumCount 张专辑",
        onTap: () => context.push(app_paths.ALBUMS_PAGE),
      ),
      UnifiedListTile(
        icon: CupertinoIcons.music_note_list,
        title: "流派",
        subtitle: "$genreCount 个流派",
        onTap: () => context.push(app_paths.GENRES_PAGE),
      ),
    ];

    final useGlass = AppPreference.instance.glassActive;

    if (useGlass) {
      return GlassPageScaffold(
        title: "类别",
        subtitle: subtitle,
        menuItems: const [],
        showBackButton: false,
        showSettingsButton: true,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: GlassPageHeader(
                title: "类别",
                subtitle: subtitle,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 140.0),
              sliver: SliverList.separated(
                itemCount: tileList.length,
                itemBuilder: (context, i) => tileList[i],
                separatorBuilder: (context, i) => const SizedBox(height: 8.0),
              ),
            ),
          ],
        ),
      );
    }

    // 普通模式
    return PageScaffold(
      title: "类别",
      subtitle: subtitle,
      actions: const [],
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 96.0),
        itemCount: tileList.length,
        itemExtent: 64,
        itemBuilder: (context, i) => tileList[i],
      ),
    );
  }
}
