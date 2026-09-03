import WidgetKit
import SwiftUI
import ActivityKit

@main
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in
            // 잠금화면 실시간 현황 UI
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(.yellow)
                    Text("\(context.attributes.songTitle) - \(context.attributes.artistName)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Text(context.state.currentLyric)
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white) // 💡 텍스트 색상을 흰색으로 강제 지정
                    .lineLimit(1)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85)) // 💡 위젯 배경색 지정
            .activitySystemActionForegroundColor(.white)
            
        } dynamicIsland: { context in
            // 다이내믹 아일랜드 UI
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.currentLyric)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundColor(.yellow)
            } compactTrailing: {
                Text("가사")
                    .foregroundColor(.white)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundColor(.yellow)
            }
        }
    }
}