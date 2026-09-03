import WidgetKit
import SwiftUI
import ActivityKit

@main
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in
            // 잠금화면 실시간 현황 UI
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "music.note")
                    Text("\(context.attributes.songTitle) - \(context.attributes.artistName)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Text(context.state.currentLyric)
                    .font(.title3)
                    .bold()
                    .multilineTextAlignment(.leading)
            }
            .padding()
            
        } dynamicIsland: { context in
            // 다이내믹 아일랜드 UI
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.currentLyric)
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                Text("가사")
            } minimal: {
                Image(systemName: "music.note")
            }
        }
    }
}