import WidgetKit
import SwiftUI

// 小组件数据提供者
struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let hasAudio: Bool
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(
            date: Date(),
            title: "音乐标题",
            artist: "艺术家",
            album: "专辑",
            isPlaying: false,
            hasAudio: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> ()) {
        let entry = readNowPlayingEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> ()) {
        let entry = readNowPlayingEntry()
        // 每5分钟刷新一次
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func readNowPlayingEntry() -> NowPlayingEntry {
        let defaults = UserDefaults(suiteName: "group.com.senyepss.corianderPlayer")
        return NowPlayingEntry(
            date: Date(),
            title: defaults?.string(forKey: "now_playing_title") ?? "",
            artist: defaults?.string(forKey: "now_playing_artist") ?? "",
            album: defaults?.string(forKey: "now_playing_album") ?? "",
            isPlaying: defaults?.bool(forKey: "now_playing_is_playing") ?? false,
            hasAudio: defaults?.bool(forKey: "now_playing_has_audio") ?? false
        )
    }
}

// 小组件视图
struct NowPlayingWidgetEntryView: View {
    var entry: NowPlayingProvider.Entry

    var body: some View {
        if entry.hasAudio {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // 播放/暂停图标
                    Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(entry.artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if !entry.album.isEmpty {
                    Text(entry.album)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding()
            .containerBackground(for: .widget) {
                Color.clear
            }
        } else {
            VStack {
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("Coriander Player")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .containerBackground(for: .widget) {
                Color.clear
            }
        }
    }
}

// 小组件定义
struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("正在播放")
        .description("显示当前播放的音乐信息")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// 小组件预览
#Preview(as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: Date(), title: "测试歌曲", artist: "测试艺术家", album: "测试专辑", isPlaying: true, hasAudio: true)
    NowPlayingEntry(date: Date(), title: "", artist: "", album: "", isPlaying: false, hasAudio: false)
}
