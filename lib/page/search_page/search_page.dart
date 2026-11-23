import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/glass_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class UnionSearchResult {
  String query;

  List<Audio> audios = [];
  List<Artist> artists = [];
  List<Album> album = [];

  UnionSearchResult(this.query);

  static UnionSearchResult search(String query) {
    final result = UnionSearchResult(query);

    final queryInLowerCase = query.toLowerCase();
    final library = AudioLibrary.instance;

    for (int i = 0; i < library.audioCollection.length; i++) {
      if (library.audioCollection[i].title
          .toLowerCase()
          .contains(queryInLowerCase)) {
        result.audios.add(library.audioCollection[i]);
      }
    }

    for (Artist item in library.artistCollection.values) {
      if (item.name.toLowerCase().contains(queryInLowerCase)) {
        result.artists.add(item);
      }
    }

    for (Album item in library.albumCollection.values) {
      if (item.name.toLowerCase().contains(queryInLowerCase)) {
        result.album.add(item);
      }
    }
    return result;
  }
}

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final useGlass = AppPreference.instance.glassActive &&
        (Theme.of(context).platform == TargetPlatform.iOS ||
            Theme.of(context).platform == TargetPlatform.android);

    if (useGlass) {
      return const _GlassSearchPage();
    }
    return const _MaterialSearchPage();
  }
}

class _MaterialSearchPage extends StatelessWidget {
  const _MaterialSearchPage();

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: "搜索",
      actions: const [],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Symbols.search,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 24),
              Text(
                "在底部搜索栏输入关键词",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "支持搜索歌曲、艺术家、专辑",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassSearchPage extends StatelessWidget {
  const _GlassSearchPage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassPageScaffold(
      title: "搜索",
      subtitle: "在底部搜索栏输入关键词",
      showSettingsButton: true,
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary.withValues(alpha: 0.35),
                          scheme.primary.withValues(alpha: 0.15),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      Symbols.search,
                      size: 44,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "开始搜索",
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "在底部搜索栏输入关键词\n支持搜索歌曲、艺术家、专辑",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 200),
          ),
        ],
      ),
    );
  }
}
