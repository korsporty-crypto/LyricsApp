import SwiftUI
import ActivityKit

// 가사 분해기 (시간과 텍스트 분리)
struct LyricLine {
    let time: TimeInterval
    let text: String
}

class LRCParser {
    static func parse(lrcString: String) -> [LyricLine] {
        var lines = [LyricLine]()
        let pattern = "\\[(\\d{2}):(\\d{2}\\.\\d{2,3})\\](.*)"
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsString = lrcString as NSString
        let matches = regex.matches(in: lrcString, range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let minStr = nsString.substring(with: match.range(at: 1))
            let secStr = nsString.substring(with: match.range(at: 2))
            let text = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            
            if let min = Double(minStr), let sec = Double(secStr) {
                lines.append(LyricLine(time: (min * 60) + sec, text: text))
            }
        }
        return lines
    }
}

// 앱 메인 화면 및 실행 로직
struct ContentView: View {
    @State private var currentActivity: Activity<LyricsAttributes>? = nil
    @State private var lyricTimer: Timer?
    
    // 테스트용 가사 (아이브 - I AM)
    let sampleLRC = """
    [00:00.00] 음악 재생 준비
    [00:03.00] 다른 문을 열어 걸어갈까
    [00:06.50] 흐려진 길을 거슬러
    [00:10.00] 내일로 향하는 길을 찾을까
    """

    var body: some View {
        VStack(spacing: 30) {
            Text("실시간 가사 테스트")
                .font(.title)
                .bold()
            
            Button(action: startLyricsSync) {
                Text("잠금화면 가사 띄우기 (실행)")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            
            Button(action: stopActivity) {
                Text("가사 끄기 (종료)")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
            }
        }
    }
    
    func startLyricsSync() {
        let attributes = LyricsAttributes(songTitle: "I AM", artistName: "IVE")
        let initialContentState = LyricsAttributes.ContentState(currentLyric: "음악 재생 준비")
        
        do {
            currentActivity = try Activity.request(attributes: attributes, contentState: initialContentState, pushType: nil)
        } catch {
            print("오류: \(error)")
            return
        }
        
        let parsedLyrics = LRCParser.parse(lrcString: sampleLRC)
        var simulatedTime: TimeInterval = 0.0
        
        lyricTimer?.invalidate()
        lyricTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            simulatedTime += 1.0
            let currentLyric = parsedLyrics.last(where: { $0.time <= simulatedTime })?.text ?? "..."
            
            Task {
                let updatedState = LyricsAttributes.ContentState(currentLyric: currentLyric)
                await currentActivity?.update(using: updatedState)
            }
            
            if simulatedTime > 15.0 { stopActivity() }
        }
    }
    
    func stopActivity() {
        lyricTimer?.invalidate()
        Task {
            await currentActivity?.end(dismissalPolicy: .immediate)
        }
    }
}