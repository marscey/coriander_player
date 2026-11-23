import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;

class ArtistTile extends StatelessWidget {
  const ArtistTile({
    super.key,
    required this.artist,
  });

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useGlass = AppPreference.instance.glassActive;

    final placeholder = Icon(
      Symbols.person,
      color: scheme.onSurface,
      size: 36,
    );

    if (useGlass) {
      return _GlassArtistTile(
        artist: artist,
        scheme: scheme,
        placeholder: placeholder,
      );
    }

    return Tooltip(
      message: artist.name,
      child: Semantics(
        identifier: "artist_tile",
        button: true,
        child: InkWell(
          onTap: () => context.push(app_paths.ARTIST_DETAIL_PAGE, extra: artist),
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                FutureBuilder(
                  future: artist.works.first.cover,
                  builder: (context, snapshot) {
                    if (snapshot.data == null) {
                      return placeholder;
                    }
                    return ClipOval(
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
                      artist.name,
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

class _GlassArtistTile extends StatelessWidget {
  const _GlassArtistTile({
    required this.artist,
    required this.scheme,
    required this.placeholder,
  });

  final Artist artist;
  final ColorScheme scheme;
  final Icon placeholder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
      child: InkWell(
        onTap: () => context.push(app_paths.ARTIST_DETAIL_PAGE, extra: artist),
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
                future: artist.works.first.cover,
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
                  return ClipOval(
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
                      artist.name,
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
                      '${artist.works.length} 首作品',
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
