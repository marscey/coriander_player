import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/genre_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final artistCount = AudioLibrary.instance.artistCollection.length;
    final albumCount = AudioLibrary.instance.albumCollection.length;
    final genreCount = GenreService.instance.genres.length;

    return Scaffold(
      appBar: AppBar(title: const Text("类别"), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        children: [
          _CategoryTile(
            icon: Symbols.artist,
            title: "艺术家",
            subtitle: "$artistCount 位艺术家",
            colorScheme: scheme,
            onTap: () => context.push(app_paths.ARTISTS_PAGE),
          ),
          _CategoryTile(
            icon: Symbols.album,
            title: "专辑",
            subtitle: "$albumCount 张专辑",
            colorScheme: scheme,
            onTap: () => context.push(app_paths.ALBUMS_PAGE),
          ),
          _CategoryTile(
            icon: Symbols.genres,
            title: "流派",
            subtitle: "$genreCount 个流派",
            colorScheme: scheme,
            onTap: () => context.push(app_paths.GENRES_PAGE),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorScheme,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: title,
      child: Semantics(
        identifier: "category_tile_$title",
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                  width: 56.0,
                  height: 56.0,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Icon(
                    icon,
                    color: colorScheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          softWrap: false,
                          maxLines: 1,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(
                  Symbols.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
