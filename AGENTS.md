# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Coriander Player is a cross-platform music player built with Flutter (Dart) and Rust, using Material Design 3 / Material You theming. It supports local music playback and WebDAV cloud streaming. Forked from [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player), with added WebDAV, macOS, iOS support, dual-engine playback, and metadata scraping.

**Targets**: Windows, macOS, iOS, Android, Linux

## Tech Stack

- **Frontend**: Flutter >= 3.1.4 (Dart SDK >= 3.1.4 < 4.0.0), Material 3 / Material You
- **State Management**: Provider 6.x + ChangeNotifier
- **Routing**: go_router 14.x (`StatefulShellRoute.indexedStack` for tab navigation)
- **Audio Playback**: Dual-engine architecture
  - `BassPlayerEngine` — desktop only, wraps BASS native library via Dart FFI (`lib/src/bass/`)
  - `MediaKitPlayerEngine` — cross-platform fallback using `media_kit` 1.x (mpv-based)
  - Engine selection via `PlayerEngineFactory` + `PlatformDependencyManager`
- **Rust Bridge**: `flutter_rust_bridge` 2.12.0, generates Dart bindings from `rust/src/api/*.rs` to `lib/src/rust/`
  - Rust crates: `lofty` (audio tags), `sha2` (content hash), `image`, `ttf-parser`, `phf`
  - Windows-specific: `windows` crate (SMTC, Storage, Shell)
- **WebDAV**: `webdav_client` 1.x + custom `WebDavService` (PROPFIND, Range requests, streaming URL resolution)
- **Metadata Scraping**: Multi-source — MusicBrainz, NetEase, QQ Music, Kugou; orchestrated by `ScraperOrchestrator`
- **Lyric Formats**: LRC (line), KRC (Kugou char-by-char), QRC (QQ Music enhanced)
- **Persistence**: `shared_preferences` (settings), `sqflite` (metadata store), `flutter_secure_storage` (credentials)
- **Platform Integration**:
  - Windows: SMTC (System Media Transport Controls), WASAPI, tray, global hotkeys
  - macOS: system media keys, `MacosMediaControlService`, `desktop_multi_window`, tray
  - iOS: `NowPlayingWidget` (home widget), `audio_session`, bluetooth lyric
- **Desktop Lyric**: Separate Flutter app ([marscey/desktop_lyric](https://github.com/marscey/desktop_lyric.git)), built independently and bundled
- **Other**: `pinyin` (Chinese sorting), `github` (update check), `home_widget` 0.7, `flex_color_picker`, `material_symbols_icons`

## Build & Dev Commands

```bash
# Install dependencies (must run before first build or after pubspec changes)
flutter pub get

# Run in development
flutter run -d windows
flutter run -d macos
flutter run -d android
flutter run -d ios

# Build release
flutter build windows
flutter build macos
flutter build ios --simulator      # iOS simulator build
flutter build apk                  # Android release

# Static analysis (use flutter analyze, NOT dart analyze)
flutter analyze

# Unit tests
flutter test test/unit/            # all unit tests
flutter test test/unit/widget_test.dart  # single unit test

# Integration tests (require running simulator/emulator)
# NOTE: All integration tests must run in a single testWidgets block
# because flutter_rust_bridge can only initialize once per process.
flutter test integration_test/                          # all integration tests
flutter test integration_test/mobile_ui_test.dart       # single test
flutter test integration_test/metadata_store_test.dart  # metadata storage
flutter test integration_test/test_webdav_scan_e2e.dart # WebDAV scanning
flutter test integration_test/now_playing_ui_test.dart  # now playing UI

# Maestro declarative UI tests (requires Maestro CLI + app installed on simulator)
# Install: brew tap mobile-dev-inc/tap && brew install mobile-dev-inc/tap/maestro
maestro test test/maestro/                    # all Maestro flows
maestro test test/maestro/smoke_test.yaml     # single flow
maestro test test/maestro/audios_page_test.yaml

# Desktop lyric component (separate Flutter app, build after main app)
# Windows:
powershell -ExecutionPolicy Bypass -File .\windows\build_desktop_lyric.ps1
powershell -ExecutionPolicy Bypass -File .\windows\build_desktop_lyric.ps1 -BuildMode Debug
# macOS:
chmod +x ./macos/build_desktop_lyric.sh && ./macos/build_desktop_lyric.sh
./macos/build_desktop_lyric.sh --build-mode release --install-to-app
```

## Architecture

### Layer Structure

```
lib/
├── main.dart                  # App entry: init Rust, MediaKit, hotkeys, tray, window
├── entry.dart                 # MaterialApp + GoRouter config, Provider setup
├── play_service/              # Core playback service layer
│   ├── play_service.dart      # Singleton owning PlaybackService, LyricService, DesktopLyricService
│   ├── playback_service.dart  # Actual playback control, queue, play mode, cloud streaming
│   ├── engine/                # Player engine abstraction
│   │   ├── player_engine.dart       # Abstract PlayerEngine interface
│   │   ├── bass_player_engine.dart  # Desktop: BASS native library via FFI
│   │   ├── media_kit_player_engine.dart  # Cross-platform fallback via media_kit
│   │   ├── player_engine_factory.dart    # Engine selection by platform + settings
│   │   ├── player_engine_type.dart       # Engine type enum
│   │   └── platform_specific_initialization.dart
│   ├── lyric_service.dart     # Lyric loading & sync
│   ├── desktop_lyric_service.dart  # Desktop floating lyric window control
│   ├── macos_media_control_service.dart  # macOS system media control
│   ├── now_playing_widget.dart       # iOS home widget
│   └── recent_play_service.dart      # Recent play history
├── library/                   # Audio library data model (Audio, Artist, Album, Playlist, Genre)
│   ├── audio_library.dart     # AudioLibrary singleton, index loading, cloud audio merging
│   ├── playlist.dart
│   └── genre_service.dart
├── cloud_service/             # WebDAV cloud integration
│   ├── cloud_service.dart     # Abstract cloud service interface
│   ├── cloud_service_manager.dart  # Connection CRUD, credential management
│   ├── webdav_service.dart    # PROPFIND, Range, streaming URL resolution
│   ├── cloud_audio_player.dart     # Cloud audio streaming + caching
│   ├── cloud_cache_manager.dart    # Smart cache with size limit
│   ├── cloud_scanner.dart          # Recursive audio file scanning
│   └── cloud_connection.dart       # Connection data model
├── metadata/                  # Metadata scraping & caching
│   ├── metadata_service.dart  # Unified metadata read/write/scrape API
│   ├── scraper_orchestrator.dart  # Multi-source scraper dispatcher
│   ├── metadata_store.dart    # SQLite-backed metadata persistence
│   ├── media_cache.dart       # Lyric/cover cache
│   ├── musicbrainz_scraper.dart
│   ├── chinese_scrapers.dart  # NetEase, QQ, Kugou
│   └── metadata_scraper.dart  # Scraper interface + data models
├── lyric/                     # Lyric parsers: LRC, KRC, QRC formats
│   ├── lyric.dart
│   ├── lyric_source.dart
│   ├── lrc.dart
│   ├── krc.dart
│   └── qrc.dart
├── page/                      # Page-level widgets by feature
│   ├── now_playing_page/      # Now playing (large/small layouts, lyric views)
│   ├── settings_page/         # Settings sub-pages
│   ├── cloud_service/         # Cloud connection pages
│   └── search_page/           # Search + results
├── component/                 # Reusable UI widgets
├── src/bass/                  # Dart FFI bindings for BASS audio library
├── src/rust/                  # Auto-generated flutter_rust_bridge bindings (DO NOT EDIT)
├── app_settings.dart          # AppSettings singleton (settings.json)
├── app_preference.dart        # AppPreference singleton (playback prefs)
├── app_paths.dart             # Route path constants
├── theme_provider.dart        # ThemeProvider (Material You color schemes)
├── hotkeys_helper.dart        # Global hotkey registration
├── platform_helper.dart       # Cross-platform path & detection utilities
├── platform_dependency_manager.dart  # Engine availability per platform
├── music_matcher.dart         # Search query builder for scraping
└── utils.dart                 # Shared utilities, logger, globals
```

### Key Architectural Patterns

**Player Engine Abstraction**: Abstract `PlayerEngine` (`lib/play_service/engine/player_engine.dart`) with two implementations:
- `BassPlayerEngine` — desktop-only, wraps BASS native library via FFI; does NOT support network streaming (cloud audio falls back to MediaKit)
- `MediaKitPlayerEngine` — cross-platform, supports local files and network streaming (required for WebDAV playback)
- `PlayerEngineFactory` selects engine based on platform and user settings
- `PlatformDependencyManager` manages engine availability per platform

**State Management**: Provider + ChangeNotifier. Key providers: `ThemeProvider`, `CloudServiceManager`. Service singletons: `PlayService.instance`, `AppSettings.instance`, `AppPreference.instance`, `CloudCacheManager.instance`, `PlatformDependencyManager.instance`, `ScraperOrchestrator.instance`, `RecentPlayService.instance`.

**Routing**: `go_router` with `StatefulShellRoute.indexedStack` for tab navigation (7 branches: music library, playlists, categories, local folders, cloud connections, search, settings). `AppShell` adapts layout (mobile bottom nav vs. desktop side nav) via `ResponsiveBuilder`. Route paths defined in `lib/app_paths.dart`.

**Rust FFI Bridge**: `flutter_rust_bridge` v2.12.0 auto-generates Dart bindings from `rust/src/api/**/*.rs` to `lib/src/rust/`. Rust modules: `tag_reader` (audio tags via `lofty`, content hash, cover/lyric read/write), `system_theme`, `smtc_flutter` (Windows media controls), `installed_font`, `logger`, `utils`.

**Cloud Audio Flow**: `WebDavService` resolves streaming URLs (handles 302 redirects to CDN) -> `PlaybackService._loadAndPlay` calls `player.setSource(url, isNetwork: true)` with auth headers -> `CloudCacheManager` caches the stream in background via `HttpClient`.

**Metadata Flow**: `MetadataService` computes `contentHash` (local: SHA256 of file head; cloud: MD5 of path) as stable ID -> checks `MetadataStore` (SQLite) -> if miss, `ScraperOrchestrator` dispatches to enabled scrapers -> results cached in `MediaCache` + `MetadataStore`. Auto-scrape runs in background after playback; only exact matches are auto-saved.

### App Data & Logs

Single source of truth: `lib/app_storage.dart` (`getAppDataDir`, `getLogsDir`, `migrateAppData`). Never hardcode data paths elsewhere; `app_settings.dart` re-exports these helpers.

- **Data**:
  - macOS: `~/Library/Application Support/coriander_player/` (settings.json, app_preference.json, playback_state.json, index.json, playlists.json, recent_plays.json, lyric_source.json, cloud_audios.json, coriander_metadata.db)
  - Windows/Linux/Android/iOS: `getApplicationDocumentsDirectory()/coriander_player/` (unchanged legacy behavior)
  - Do **not** put app data in `~/Documents` on macOS: iCloud "optimize storage" turns files into `compressed,dataless` placeholders that fail to read and break startup.
- **Logs**: macOS `~/Library/Logs/coriander_player/app-YYYY-MM-DD.log` (Console.app searchable); other platforms `<appData>/logs/`. Daily rotation, 7 days retained. In-app: Settings → 缓存管理 →「查看运行日志」（可清除 / 打开目录）。
- **Legacy migration**: `migrateAppData()` runs at startup, one-shot (skipped when the target dir is non-empty), copies readable files and skips dataless placeholders.
- **Startup**: `main()` initializes `DebugLogger` first, installs `FlutterError.onError` + `PlatformDispatcher.onError`, then wraps every init step in `_guard` so one failing service logs and does not block the UI.


- **BASS library** (desktop only): Native audio libs must be present in `windows/bass/` or `macos/bass/`. CMake/build scripts copy them to the app bundle automatically.
- **WASAPI**: Windows-only audio output API. macOS/Linux do not need `basswasapi` files.
- **Swift Package Manager**: Multiple plugins do not yet support SPM. This will become a build error in future Flutter versions. Current workaround: use CocoaPods (Podfile).
- **`desktop_lyric`**: Separate Flutter app, built independently and placed in the app bundle's `desktop_lyric/` directory. Build scripts support `--build-mode release|debug` and `--install-to-app` options.

### Keyboard Shortcuts

- Esc: Go back
- Space: Toggle play/pause
- Ctrl + Left: Previous track
- Ctrl + Right: Next track

(Text input focus automatically disables shortcuts.)

### Testing Notes

- **Flutter Integration Tests** (`integration_test/`): Must be in project root (Flutter hardcodes this path). All tests must be in a single `testWidgets` block because `flutter_rust_bridge` can only initialize once.
- **Maestro Tests** (`test/maestro/`): YAML declarative UI tests. Requires Maestro CLI + app installed on simulator. Config in `test/maestro/config.yaml` (`appId: com.senyepss.corianderPlayer`).
- **Analyzer**: `rust_builder/cargokit/build_tool/` is a vendored build tool with unresolved dependencies; its analysis errors are expected and should be ignored. Focus on `lib/` errors only.

### Important Conventions

- The project UI is primarily in **Chinese** (simplified). All user-facing strings are in Chinese.
- Audio formats supported: mp3, flac, aac, m4a, wav, ogg, opus, ape, wv, dsf, dff, mid, amr, ac3, wma, asf, aif, aiff, mpc, mp2, mp1.
- Lyric formats: LRC (line), KRC (Kugou character-by-character), QRC (QQ Music enhanced).
- `shared_preferences` and `sqflite` for local persistence. `flutter_secure_storage` for credentials (with SharedPreferences fallback if secure storage unavailable).
- `pinyin` package used for Chinese character sorting in artist/album lists.
- Artist splitting uses `AppSettings.instance.artistSplitPattern` (configurable regex).

## Liquid Glass 主题（mobile-ui 分支）

`mobile-ui-merged` 分支在 Material 3 之上叠加了一套 iOS 26 Liquid Glass 视觉，默认关闭：

- 开关：`AppPreference.instance.liquidGlassEnabled`（设置页「主题设置」打开，重启生效）
- 参数单一真相源：`lib/glass_theme/glass_presets.dart`（所有玻璃页面从此处引用，不要各自写死）
- 导航壳：`lib/component/glass_app_shell.dart`（含搜索历史、PlayBarPill、迷你播放条）
- 页面骨架：`lib/page/glass_page_scaffold.dart`，通用详情页 `lib/page/glass_audio_detail_page.dart`
- 艺术家详情：`ArtistDetailPageV3`（支持浅色/深色两套预设）；`album_detail_page.dart`、`artist_detail_page.dart`、`uni_detail_page.dart` 已删除，路由统一走 V3
- 依赖 `liquid_glass_widgets`，仅移动端生效（`PlatformHelper.isMobile` 判断）

## Prohibited Actions

- **NEVER** edit files under `lib/src/rust/` — these are auto-generated by `flutter_rust_bridge`. Modify `rust/src/api/*.rs` instead and regenerate with `flutter_rust_bridge_codegen generate`.
- **NEVER** edit `rust/src/frb_generated.rs` or `rust_builder/` contents — these are also auto-generated.
- **NEVER** use `dart analyze` for linting — use `flutter analyze` instead. The project uses `flutter_lints` via `analysis_options.yaml`.
- **NEVER** use `git reset --hard`, `git checkout --`, or other destructive git commands unless the user explicitly requests it.
- **NEVER** revert or modify changes you did not make. If unrelated changes exist in the worktree, leave them alone.
- **NEVER** commit WebDAV credentials or test connection info. The `CloudServiceManager` has a hardcoded test config guarded by `AppSettings.instance.autoTestConfig` — do not enable this in production.
- **NEVER** write integration tests that call `flutter_rust_bridge` initialization more than once per test process. All integration tests must share a single `testWidgets` block.
- **NEVER** add new dependencies without checking platform compatibility — this project targets 5 platforms and many packages are desktop-only or mobile-only.
- **DO NOT** put integration test files outside `integration_test/` — Flutter hardcodes this directory name.

## Pre-Modification Checklist

Before making any code changes, confirm the following:

1. **Read the existing code first.** Understand the module's current behavior, its callers, and its test coverage before editing. Use `rg` to find all references to any function or class you plan to modify.
2. **Check engine compatibility.** If your change touches playback: BASS engine does NOT support network streaming or `httpHeaders`. Cloud audio playback requires MediaKit engine. Verify your change works on both engines or guard with `PlatformHelper` checks.
3. **Verify generated files are current.** If modifying `rust/src/api/*.rs`, run `flutter_rust_bridge_codegen generate` after edits and confirm `lib/src/rust/` regenerated successfully before testing.
4. **Run `flutter analyze` on `lib/` only.** Ignore `rust_builder/cargokit/` errors. Resolve any new errors or warnings in `lib/` before committing.
5. **Check singleton initialization order.** `main()` initializes services in a specific sequence (Rust -> MediaKit -> hotkeys -> settings -> cloud cache -> platform deps -> font -> recent plays -> genre service -> scraper -> playback service). Adding new initialization must respect this order.
6. **Confirm platform guards.** Code that calls platform-specific APIs (SMTC, WASAPI, MacosMediaControlService, NowPlayingWidget) must be guarded by `PlatformHelper.isWindows`, `PlatformHelper.isMacOS`, `PlatformHelper.isIOS`, etc.
7. **Preserve Chinese UI strings.** All user-facing text must remain in simplified Chinese. Do not translate to English unless explicitly asked.
8. **Test on at least one platform.** After changes, run `flutter run -d <platform>` to verify the app starts and the affected feature works. Run relevant integration tests if available.
