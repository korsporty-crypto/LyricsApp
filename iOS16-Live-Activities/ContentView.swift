import SwiftUI
import ActivityKit
import AuthenticationServices
import CommonCrypto

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
    @State private var codeVerifier: String = ""
    
    let clientID = "f6798a7d1f8846cbab15fd5d641b5e97"
    let redirectURI = "lyricsapp://callback"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // 상단 네비게이션 헤더
                HStack {
                    Image(systemName: "music.mic")
                        .font(.title3)
                        .foregroundColor(.yellow)
                    Text("Live Lyric")
                        .font(.headline)
                        .bold()
                        .foregroundColor(.white)
                    Spacer()
                    
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
                
                // 메인 플레이어 카드
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
                            .multilineTextAlignment(.center)
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
                        Button(action: loginWithSpotifyPKCE) {
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
    
    // --- Spotify PKCE 보안 인증 로직 ---
    func generateRandomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    func sha256(_ input: String) -> Data {
        let inputData = Data(input.utf8)
        var hashedData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = hashedData.withUnsafeMutableBytes { hashedBytes in
            inputData.withUnsafeBytes { inputBytes in
                CC_SHA256(inputBytes.baseAddress, CC_LONG(inputData.count), hashedBytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return hashedData
    }
    
    func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    func loginWithSpotifyPKCE() {
        let verifier = generateRandomString(length: 64)
        self.codeVerifier = verifier
        let challenge = base64URLEncode(sha256(verifier))
        
        let encodedRedirect = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let authURLString = "https://accounts.spotify.com/authorize?client_id=\(clientID)&response_type=code&redirect_uri=\(encodedRedirect)&code_challenge_method=S256&code_challenge=\(challenge)&scope=user-read-playback-state"
        
        guard let url = URL(string: authURLString) else { return }
        
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lyricsapp") { callbackURL, error in
            guard error == nil, let callbackURL = callbackURL else { return }
            
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                  let queryItems = components.queryItems,
                  let code = queryItems.first(where: { $0.name == "code" })?.value else {
                return
            }
            
            self.exchangeCodeForToken(code: code)
        }
        session.presentationContextProvider = TransitionProvider.shared
        session.start()
    }
    
    func exchangeCodeForToken(code: String) {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String {
                DispatchQueue.main.async {
                    self.accessToken = token
                    self.currentSong = "연동 성공!"
                    self.currentArtist = "스포티파이에서 음악을 재생하세요"
                }
            }
        }.resume()
    }
    
    // --- 실시간 가사 싱크 및 위젯 구동 로직 ---
    func startRealtimeSync() {
        syncTimer?.invalidate()
        self.currentArtist = "스포티파이 재생 상태 확인 중..."
        
        fetchCurrentlyPlaying { title, artist, progressMs in
            guard let title = title, let artist = artist, let progressMs = progressMs else {
                DispatchQueue.main.async {
                    self.currentSong = "재생 중인 곡 없음"
                    self.currentArtist = "Spotify에서 음악을 재생 중인지 확인하세요"
                }
                return
            }
            self.currentSong = title
            self.currentArtist = artist
            
            self.fetchLyrics(title: title, artist: artist) { lyrics in
                self.syncedLyrics = lyrics
                
                let success = self.startLiveActivity(title: title, artist: artist, progressMs: progressMs)
                guard success else { return }
                
                AudioKeepAlive.shared.start(until: Date().addingTimeInterval(300)) {
                    // 타이머 종료 시 처리
                }
                
                self.syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    // 💡 [진단 추적] 타이머 돌 때마다 시스템이 실제로 위젯을 살려두고 있는지 검사
                    let activeActivities = Activity<LyricsAttributes>.activities
                    if activeActivities.isEmpty {
                        DispatchQueue.main.async {
                            self.currentArtist = "🚨 iOS 시스템이 위젯을 강제 차단함 (서명/권한 거부)"
                        }
                    }
                    
                    self.fetchCurrentlyPlaying { t, a, pMs in
                        guard let pMs = pMs else { return }
                        if let t = t { self.currentSong = t }
                        if let a = a { self.currentArtist = a }
                        
                        let currentSeconds = Double(pMs) / 1000.0
                        let activeLine = self.syncedLyrics.last(where: { $0.time <= currentSeconds })?.text ?? "가사 싱크 대기 중..."
                        
                        Task {
                            let state = LyricsAttributes.ContentState(currentLyric: activeLine)
                            await self.currentActivity?.update(using: state)
                        }
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                DispatchQueue.main.async { self.currentArtist = "스포티파이 통신 에러 발생" }
                completion(nil, nil, nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 {
                DispatchQueue.main.async { self.currentArtist = "스포티파이 재생 상태 아님 (204 No Content)" }
                completion(nil, nil, nil)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { self.currentArtist = "Spotify JSON 파싱 실패" }
                completion(nil, nil, nil)
                return
            }
            
            guard let item = json["item"] as? [String: Any],
                  let name = item["name"] as? String,
                  let progressMs = json["progress_ms"] as? Int else {
                DispatchQueue.main.async { self.currentArtist = "재생 중인 트랙 없음 (광고 또는 미디어 형식 제한)" }
                completion(nil, nil, nil)
                return
            }
            
            let artistName: String
            if let artists = item["artists"] as? [[String: Any]], let firstArtist = artists.first?["name"] as? String {
                artistName = firstArtist
            } else if let show = item["show"] as? [String: Any], let showName = show["name"] as? String {
                artistName = showName
            } else {
                artistName = "Unknown Artist"
            }
            
            DispatchQueue.main.async { completion(name, artistName, progressMs) }
        }.resume()
    }
    
    func fetchLyrics(title: String, artist: String, completion: @escaping ([LyricLine]) -> Void) {
        let t = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let a = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://lrclib.net/api/search?track_name=\(t)&artist_name=\(a)") else {
            completion([])
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let bestMatch = jsonArray.first(where: { $0["syncedLyrics"] as? String != nil }),
                  let lrc = bestMatch["syncedLyrics"] as? String else {
                DispatchQueue.main.async { self.currentArtist = "LRCLIB 가사를 찾을 수 없음" }
                completion([])
                return
            }
            
            var lines: [LyricLine] = []
            let rows = lrc.components(separatedBy: "\n")
            let pattern = "\\[(\\d+):(\\d+)(?:\\.(\\d+))?\\](.*)"
            for row in rows {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) else { continue }
                
                let minStr = (row as NSString).substring(with: match.range(at: 1))
                let secStr = (row as NSString).substring(with: match.range(at: 2))
                let m = Double(minStr) ?? 0
                var s = Double(secStr) ?? 0
                
                if match.range(at: 3).location != NSNotFound && match.range(at: 3).length > 0 {
                    let fracStr = (row as NSString).substring(with: match.range(at: 3))
                    let frac = Double("0.\(fracStr)") ?? 0
                    s += frac
                }
                
                let text = (row as NSString).substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    lines.append(LyricLine(time: (m * 60) + s, text: text))
                }
            }
            DispatchQueue.main.async { completion(lines) }
        }.resume()
    }
    
    @discardableResult
    func startLiveActivity(title: String, artist: String, progressMs: Int) -> Bool {
        if !ActivityAuthorizationInfo().areActivitiesEnabled {
            DispatchQueue.main.async {
                self.currentArtist = "설정 -> Live Activities 권한이 꺼져있습니다."
            }
            return false
        }
        
        if currentActivity != nil { return true }
        let attributes = LyricsAttributes(songTitle: title, artistName: artist)
        let state = LyricsAttributes.ContentState(currentLyric: "싱크 시작")
        do {
            currentActivity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            
            // 💡 [진단 추적] 요청 직후 시스템에 실제 활성 활동이 등록되었는지 확인
            let activeCount = Activity<LyricsAttributes>.activities.count
            if activeCount == 0 {
                DispatchQueue.main.async {
                    self.currentArtist = "🚨 요청 직후 시스템이 위젯을 거부함 (권한/서명 불일치)"
                }
                return false
            }
            
            DispatchQueue.main.async {
                self.currentArtist = "위젯 생성 성공! (활성 수: \(activeCount))"
            }
            return true
        } catch {
            DispatchQueue.main.async {
                self.currentArtist = "위젯 생성 실패: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    func stopActivity() {
        syncTimer?.invalidate()
        AudioKeepAlive.shared.stop()
        Task {
            await currentActivity?.end(dismissalPolicy: .immediate)
            DispatchQueue.main.async {
                self.currentActivity = nil
                self.currentArtist = "위젯이 종료되었습니다."
            }
        }
    }
}

class TransitionProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = TransitionProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}