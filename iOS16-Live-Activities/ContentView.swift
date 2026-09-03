import SwiftUI
import ActivityKit
import AuthenticationServices

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

struct ContentView: View {
    @State private var currentActivity: Activity<LyricsAttributes>? = nil
    @State private var accessToken: String = ""
    @State private var currentSong = "재생 중인 음악 없음"
    @State private var currentArtist = "Spotify 연동을 기다리는 중..."
    @State private var syncedLyrics: [LyricLine] = []
    @State private var syncTimer: Timer?
    
    // 입력해주신 Client ID 적용 완료
    let clientID = "f6798a7d1f8846cbab15fd5d641b5e97"
    let redirectURI = "lyricsapp://callback"

    var body: some View {
        ZStack {
            // Musixmatch 시그니처 다크 배경
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // 상단 네비게이션 헤더
                HStack {
                    Image(systemName: "music.mic")
                        .font(.title3)
                        .foregroundColor(.yellow)
                    Text("Musixmatch Sync")
                        .font(.headline)
                        .bold()
                        .foregroundColor(.white)
                    Spacer()
                    
                    // 상태 뱃지
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accessToken.isEmpty ? Color.gray : Color.green)
                            .frame(width: 6, height: 6)
                        Text(accessToken.isEmpty ? "OFF" : "LIVE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(accessToken.isEmpty ? .gray : .green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                
                Spacer()
                
                // 메인 플레이어 카드 (가사 미리보기 느낌)
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.yellow.opacity(0.3), .orange.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 90, height: 90)
                        Image(systemName: "waveform")
                            .font(.system(size: 36))
                            .foregroundColor(.yellow)
                    }
                    .padding(.top, 10)
                    
                    VStack(spacing: 6) {
                        Text(currentSong)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                        
                        Text(currentArtist)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6).opacity(0.08))
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                
                Spacer()
                
                // 하단 인터랙티브 버튼 영역
                VStack(spacing: 12) {
                    if accessToken.isEmpty {
                        Button(action: loginWithSpotify) {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                Text("Spotify 계정 연동하기")
                            }
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .cornerRadius(16)
                        }
                    } else {
                        Button(action: startRealtimeSync) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                Text("잠금화면 가사 위젯 띄우기")
                            }
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .cornerRadius(16)
                        }
                    }
                    
                    Button(action: stopActivity) {
                        Text("위젯 종료하기")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }
    
    // --- 기능 로직 ---
    func loginWithSpotify() {
        let authURLString = "https://accounts.spotify.com/authorize?client_id=\(clientID)&response_type=token&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&scope=user-read-playback-state"
        guard let url = URL(string: authURLString) else { return }
        
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lyricsapp") { callbackURL, error in
            guard error == nil, let callbackURL = callbackURL else { return }
            let fragment = callbackURL.fragment ?? ""
            let params = fragment.components(separatedBy: "&")
            for param in params {
                let pair = param.components(separatedBy: "=")
                if pair.first == "access_token", let token = pair.last {
                    self.accessToken = token
                    self.currentSong = "연동 성공!"
                    self.currentArtist = "스포티파이에서 음악을 재생하세요"
                }
            }
        }
        session.presentationContextProvider = ÜbergangProvider.shared
        session.start()
    }
    
    func startRealtimeSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            fetchCurrentlyPlaying { title, artist, progressMs in
                guard let title = title, let artist = artist, let progressMs = progressMs else {
                    self.currentSong = "재생 중인 곡 없음"
                    self.currentArtist = "스포티파이 앱을 확인해주세요"
                    return
                }
                self.currentSong = title
                self.currentArtist = artist
                
                if self.syncedLyrics.isEmpty {
                    self.fetchLyrics(title: title, artist: artist) { lyrics in
                        self.syncedLyrics = lyrics
                        self.startLiveActivity(title: title, artist: artist, progressMs: progressMs)
                    }
                } else {
                    let currentSeconds = Double(progressMs) / 1000.0
                    let activeLine = self.syncedLyrics.last(where: { $0.time <= currentSeconds })?.text ?? "..."
                    Task {
                        let state = LyricsAttributes.ContentState(currentLyric: activeLine)
                        await self.currentActivity?.update(using: state)
                    }
                }
            }
        }
    }
    
    func fetchCurrentlyPlaying(completion: @escaping (String?, String?, Int?) -> Void) {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else {
            completion(nil, nil, nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = json["item"] as? [String: Any],
                  let name = item["name"] as? String,
                  let artists = item["artists"] as? [[String: Any]],
                  let artistName = artists.first?["name"] as? String,
                  let progressMs = json["progress_ms"] as? Int else {
                DispatchQueue.main.async { completion(nil, nil, nil) }
                return
            }
            DispatchQueue.main.async { completion(name, artistName, progressMs) }
        }.resume()
    }
    
    func fetchLyrics(title: String, artist: String, completion: @escaping ([LyricLine]) -> Void) {
        let t = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let a = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://lrclib.net/api/get?track_name=\(t)&artist_name=\(a)") else {
            completion([])
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lrc = json["syncedLyrics"] as? String else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            var lines: [LyricLine] = []
            let rows = lrc.components(separatedBy: "\n")
            let pattern = "\\[(\\d{2}):(\\d{2}\\.\\d{2,3})\\](.*)"
            for row in rows {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) else { continue }
                let min = Double((row as NSString).substring(with: match.range(at: 1))) ?? 0
                let sec = Double((row as NSString).substring(with: match.range(at: 2))) ?? 0
                let text = (row as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                lines.append(LyricLine(time: (min * 60) + sec, text: text))
            }
            DispatchQueue.main.async { completion(lines) }
        }.resume()
    }
    
    func startLiveActivity(title: String, artist: String, progressMs: Int) {
        if currentActivity != nil { return }
        let attributes = LyricsAttributes(songTitle: title, artistName: artist)
        let state = LyricsAttributes.ContentState(currentLyric: "싱크 시작")
        do {
            currentActivity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
        } catch {
            print("위젯 에러: \(error)")
        }
    }
    
    func stopActivity() {
        syncTimer?.invalidate()
        Task { await currentActivity?.end(dismissalPolicy: .immediate) }
    }
}

class ÜbergangProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = ÜbergangProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}