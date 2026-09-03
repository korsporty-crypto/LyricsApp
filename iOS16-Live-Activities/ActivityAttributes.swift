import SwiftUI
import ActivityKit

struct LyricsAttributes: ActivityAttributes {
    // 고정 정보: 곡명과 아티스트
    var songTitle: String
    var artistName: String
    
    // 계속 바뀌는 정보: 실시간 가사
    public struct ContentState: Codable, Hashable {
        var currentLyric: String
    }
}