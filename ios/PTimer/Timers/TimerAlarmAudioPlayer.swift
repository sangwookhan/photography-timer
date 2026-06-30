// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import AudioToolbox
import Foundation

/// App-owned audible timer-alarm playback (PTIMER-73).
///
/// A foreground completion plays through an `AVAudioSession` with the
/// `.playback` category, which overrides the hardware silent switch — so the
/// alarm is audible even in silent mode while the app is active, the way field
/// shooting needs. Background/locked completions are handled by local
/// notifications, not by this player.
@MainActor
protocol TimerAlarmAudioPlaying: AnyObject {
    func playCompletionAlarm(for timerID: UUID)
    func stop()
}

@MainActor
final class AVAudioTimerAlarmPlayer: NSObject, ObservableObject, TimerAlarmAudioPlaying, AVAudioPlayerDelegate {
    /// Process-wide instance, so the completion path and the UI (which observes
    /// `soundingTimerID` to show a stop-alarm affordance) share one player.
    static let shared = AVAudioTimerAlarmPlayer()

    /// The timer whose completion alarm is currently sounding (or nil). The UI
    /// shows a stop-alarm state on the matching mini timer / row (PTIMER-73).
    @Published private(set) var soundingTimerID: UUID?

    private var alarmPlayer: AVAudioPlayer?

    /// How long the completion alarm sounds before it auto-stops; the user can
    /// stop it sooner by tapping the timer.
    private static let alarmWindow: TimeInterval = 8

    // Touches no main-actor state, so it is safe (and convenient for default
    // arguments) to construct from a nonisolated context.
    nonisolated override init() {
        super.init()
    }

    // MARK: TimerAlarmAudioPlaying

    func playCompletionAlarm(for timerID: UUID) {
        guard activateSession(), let player = try? AVAudioPlayer(data: Self.alarmToneData) else {
            // Best-effort fallback. AudioServices obeys the silent switch, so it
            // is inaudible in silent mode — but better than nothing if the audio
            // session cannot be configured.
            AudioServicesPlaySystemSound(1005)
            return
        }
        player.delegate = self
        player.volume = 1.0
        player.prepareToPlay()
        // Loop the short tone for a bounded window so it is a real, stoppable
        // alarm rather than a single beep that is gone before it can be silenced.
        if player.duration > 0 {
            player.numberOfLoops = max(0, Int((Self.alarmWindow / player.duration).rounded()) - 1)
        }
        player.play()
        alarmPlayer = player
        soundingTimerID = timerID
    }

    func stop() {
        alarmPlayer?.stop()
        alarmPlayer = nil
        soundingTimerID = nil
        deactivateSessionIfIdle()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if player === self.alarmPlayer {
                self.stop()
            }
        }
    }

    // MARK: Session

    /// `.playback` overrides the silent switch so the foreground alarm is heard
    /// in silent mode; `.mixWithOthers` lets any of the user's audio keep
    /// playing alongside the brief alarm rather than being stopped.
    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    private func deactivateSessionIfIdle() {
        guard alarmPlayer == nil else {
            return
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Tone data

    /// A short three-beep alarm tone, generated once as in-memory 16-bit PCM
    /// WAV so the app needs no bundled audio asset.
    private static let alarmToneData: Data = WAVToneGenerator.alarmTone()
}

/// Minimal in-memory WAV (16-bit PCM mono) generator so the app ships no audio
/// asset and exposes no user-facing sound choice.
enum WAVToneGenerator {
    private static let sampleRate = 44_100.0

    static func alarmTone() -> Data {
        let beepDuration = 0.18
        let gapDuration = 0.12
        let frequency = 1_046.5 // C6
        let beepCount = 3
        let fadeSamples = sampleRate * 0.005 // 5ms fade to avoid clicks

        var samples: [Int16] = []
        let beepSampleCount = Int(sampleRate * beepDuration)
        let gapSampleCount = Int(sampleRate * gapDuration)
        for beep in 0..<beepCount {
            for sample in 0..<beepSampleCount {
                let time = Double(sample) / sampleRate
                let envelope = min(1.0, min(Double(sample), Double(beepSampleCount - sample)) / fadeSamples)
                let value = sin(2 * Double.pi * frequency * time) * envelope * 0.6
                samples.append(Int16(value * Double(Int16.max)))
            }
            if beep < beepCount - 1 {
                samples.append(contentsOf: repeatElement(0, count: gapSampleCount))
            }
        }
        return wav(from: samples)
    }

    /// A fully silent clip of the given duration. Used by the silent-mode
    /// advisory probe (PTIMER-73): when the device is muted the system plays it
    /// back near-instantly, so the elapsed playback time is the best-effort
    /// muted-likely signal. It is silent, so it is never audible itself.
    static func silence(duration: TimeInterval) -> Data {
        let count = Int(sampleRate * duration)
        return wav(from: [Int16](repeating: 0, count: count))
    }

    private static func wav(from samples: [Int16]) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let rate = Int(sampleRate)
        let byteRate = rate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * bitsPerSample / 8

        var data = Data()
        func appendString(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func appendUInt32LE(_ value: UInt32) {
            data.append(contentsOf: [0, 8, 16, 24].map { UInt8((value >> $0) & 0xFF) })
        }
        func appendUInt16LE(_ value: UInt16) {
            data.append(contentsOf: [0, 8].map { UInt8((value >> $0) & 0xFF) })
        }

        appendString("RIFF")
        appendUInt32LE(UInt32(36 + dataSize))
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32LE(16)
        appendUInt16LE(1)
        appendUInt16LE(UInt16(channels))
        appendUInt32LE(UInt32(rate))
        appendUInt32LE(UInt32(byteRate))
        appendUInt16LE(UInt16(blockAlign))
        appendUInt16LE(UInt16(bitsPerSample))
        appendString("data")
        appendUInt32LE(UInt32(dataSize))
        for sample in samples {
            appendUInt16LE(UInt16(bitPattern: sample))
        }
        return data
    }
}
