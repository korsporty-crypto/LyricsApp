//
//  DeliveryKeepAlive.swift
//  iOS16-Live-Activities
//
//  Audio keep-alive strategy for keeping the app runnable in the background
//  via an active AVAudioSession playing silent audio on a .playback loop.
//

import ActivityKit
import AVFoundation
import Foundation

// MARK: - Location keep-alive (Stub to prevent build errors)
final class LocationKeepAlive {
    static let shared = LocationKeepAlive()
    private init() {}
    func requestAuthorizationIfNeeded() {}
    func start(until endDate: Date, midpoint: Date? = nil, midpointFire: (() -> Void)? = nil, fire: @escaping () -> Void) {
        // Fallback to Audio keep-alive internally if location was called
        AudioKeepAlive.shared.start(until: endDate, midpoint: midpoint, midpointFire: midpointFire, fire: fire)
    }
    func stop() {
        AudioKeepAlive.shared.stop()
    }
}

// MARK: - Audio keep-alive

/// Keeps the app runnable in background by holding an active `AVAudioSession`
/// that plays a programmatically-generated silent WAV on loop.
final class AudioKeepAlive {
    static let shared = AudioKeepAlive()

    private var player: AVAudioPlayer?
    private var endTimer: DispatchSourceTimer?
    private var midpointTimer: DispatchSourceTimer?
    private var onFire: (() -> Void)?

    private init() {}

    func start(
        until endDate: Date,
        midpoint: Date? = nil,
        midpointFire: (() -> Void)? = nil,
        fire: @escaping () -> Void
    ) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let silent = Self.silentWAV(durationSeconds: 1.0)
            let p = try AVAudioPlayer(data: silent, fileTypeHint: AVFileType.wav.rawValue)
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            print("AudioKeepAlive start failed: \(error)")
        }

        onFire = fire

        if let midpoint = midpoint, let midpointFire = midpointFire {
            midpointTimer?.cancel()
            let mid = DispatchSource.makeTimerSource(queue: .main)
            mid.schedule(deadline: .now() + max(0, midpoint.timeIntervalSinceNow))
            mid.setEventHandler { midpointFire() }
            mid.resume()
            midpointTimer = mid
        }

        endTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let delay = max(0, endDate.timeIntervalSinceNow)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.onFire?()
            self?.stop()
        }
        timer.resume()
        endTimer = timer
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        midpointTimer?.cancel()
        midpointTimer = nil
        endTimer?.cancel()
        endTimer = nil
        onFire = nil
    }

    private static func silentWAV(durationSeconds: Double) -> Data {
        let sampleRate: UInt32 = 8000
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let numSamples = UInt32(Double(sampleRate) * durationSeconds)
        let dataSize = numSamples * UInt32(blockAlign)
        let chunkSize = 36 + dataSize

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.appendLE(UInt32(chunkSize))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.appendLE(UInt32(16))            // PCM header size
        wav.appendLE(UInt16(1))             // format: PCM
        wav.appendLE(channels)
        wav.appendLE(sampleRate)
        wav.appendLE(byteRate)
        wav.appendLE(blockAlign)
        wav.appendLE(bitsPerSample)
        wav.append("data".data(using: .ascii)!)
        wav.appendLE(UInt32(dataSize))
        wav.append(Data(count: Int(dataSize))) // actual silence
        return wav
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}