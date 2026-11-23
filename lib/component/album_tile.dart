import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;

class AlbumTile extends StatelessWidget {
  const AlbumTile({
    super.key,
    required this.album,
  });

  final Album album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.liquidGlassEnabled;

    final placeholder = Icon(
      Symbols.album,
      size: 36,
      color: scheme.onSurface,
    );

    if (useGlass) {
      return _GlassAlbumTile(
        album: album,
        scheme: scheme,
        placeholder: placeholder,
      );
    }

    return Tooltip(
      message: album.name,
      child: Semantics(
        identifier: "album_tile",
        button: true,
        child: InkWell(
          onTap: () => context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album),
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                FutureBuilder(
                  future: album.works.first.cover,
                  builder: (context, snapshot) {
                    if (snapshot.data == null) {
                      return placeholder;
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image(
                        image: snapshot.data!,
                        width: 48.0,
                        height: 48.0,
                        errorBuilder: (_, __, ___) => placeholder,
                      ),
                    );
                  },
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      album.name,
                      softWrap: false,
                      maxLines: 2,
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassAlbumTile extends StatelessWidget {
  const _GlassAlbumTile({
    required this.album,
    required this.scheme,
    required this.placeholder,
  });

  final Album album;
  final ColorScheme scheme;
  final Icon placeholder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
      child: InkWell(
        onTap: () => context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album),
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.05),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              FutureBuilder(
                future: album.works.first.cover,
                builder: (context, snapshot) {
                  if (snapshot.data == null) {
                    return Container(
                      width: 48.0,
                      height: 48.0,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: placeholder,
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image(
                      image: snapshot.data!,
                      width: 48.0,
                      height: 48.0,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48.0,
                        height: 48.0,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: placeholder,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      '${album.works.length} 首作品',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
