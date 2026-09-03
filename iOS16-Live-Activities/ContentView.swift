import SwiftUI
import ActivityKit
import MediaPlayer

// 가사 줄 구조체
struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

struct ContentView: View {
    @State private var currentActivity: Activity<LyricsAttributes>? = nil
    @State private var currentSongTitle = "재생 중인 음악 없음"
    @State private var currentArtist = "스포티파이 감지 대기 중"
    @State private var syncedLyrics: [LyricLine] = []
    @State private var playbackTimer: Timer?
    @State private var songStartTime = Date()

    var body: some View {
        VStack(spacing: 25) {
            Text("Spotify 실시간 가사 연동")
                .font(.title2)
                .bold()
            
            VStack(spacing: 8) {
                Text(currentSongTitle)
                    .font(.headline)
                Text(currentArtist)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            Button(action: startRealLyricsSync) {
                Text("잠금화면 실시간 가사 시작")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
            }
            
            Button(action: stopActivity) {
                Text("가사 종료")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
    
    // 1. 스포티파이 등 시스템 플레이어에서 현재 곡 정보 가져오기 & 가사 다운로드
    func startRealLyricsSync() {
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        
        guard let title = nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,
              let artist = nowPlayingInfo?[MPMediaItemPropertyArtist] as? String else {
            currentSongTitle = "음악을 먼저 재생해주세요!"
            currentArtist = "스포티파이에서 곡을 틀고 눌러주세요"
            return
        }
        
        currentSongTitle = title
        currentArtist = artist
        songStartTime = Date() // 재생 시작 시점 기록
        
        // LRCLIB 무료 API를 통해 실시간 가사(LRC) 조회
        fetchLyricsFromLRCLIB(title: title, artist: artist) { lyrics in
            self.syncedLyrics = lyrics
            
            // Live Activities 위젯 시작
            let attributes = LyricsAttributes(songTitle: title, artistName: artist)
            let initialState = LyricsAttributes.ContentState(currentLyric: "가사 싱크 준비 중...")
            
            do {
                self.currentActivity = try Activity.request(attributes: attributes, contentState: initialState, pushType: nil)
                self.startSyncTimer()
            } catch {
                print("위젯 시작 오류: \(error)")
            }
        }
    }
    
    // 2. 무료 오픈소스 가사 서버(LRCLIB)에서 LRC 데이터 받아오기
    func fetchLyricsFromLRCLIB(title: String, artist: String, completion: @escaping ([LyricLine]) -> Void) {
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let urlString = "https://lrclib.net/api/get?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let syncedLyricsString = json["syncedLyrics"] as? String else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            // LRC 형식 파싱
            let parsed = parseLRC(syncedLyricsString)
            DispatchQueue.main.async { completion(parsed) }
        }.resume()
    }
    
    // LRC 텍스트 파서 함수
    func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let rows = lrc.components(separatedBy: "\n")
        let pattern = "\\[(\\d{2}):(\\d{2}\\.\\d{2,3})\\](.*)"
        
        for row in rows {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) else { continue }
            
            let minStr = (row as NSString).substring(with: match.range(at: 1))
            let secStr = (row as NSString).substring(with: match.range(at: 2))
            let text = (row as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            
            if let min = Double(minStr), let sec = Double(secStr) {
                lines.append(LyricLine(time: (min * 60) + sec, text: text))
            }
        }
        return lines
    }
    
    // 3. 실제 재생 시간과 가사 타임스탬프를 매칭하여 위젯 갱신
    func startSyncTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let elapsedTime = Date().timeIntervalSince(songStartTime)
            
            // 현재 시간에 맞는 가사 라인 찾기
            let activeLine = syncedLyrics.last(where: { $0.time <= elapsedTime })?.text ?? "가사 대기 중..."
            
            Task {
                let updatedState = LyricsAttributes.ContentState(currentLyric: activeLine)
                await currentActivity?.update(using: updatedState)
            }
        }
    }
    
    func stopActivity() {
        playbackTimer?.invalidate()
        Task {
            await currentActivity?.end(dismissalPolicy: .immediate)
        }
    }
}