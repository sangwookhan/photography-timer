// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import AudioToolbox
import Foundation

/// App-owned audible timer-alarm playback (PTIMER-73).
///
/// A completion plays through an `AVAudioSession` with the `.playback` category,
/// which overrides the hardware silent switch — so the alarm is audible even in
/// silent mode, the way field shooting needs.
@MainActor
protocol TimerAlarmAudioPlaying: AnyObject {
    func playCompletionAlarm()
    func stop()
}

/// Keeps the app alive in the background while a timer is running, so the
/// RunLoop tick keeps firing and the completion alarm can sound at the exact end
/// instant even when the app is backgrounded / the device is locked (PTIMER-73).
///
/// This is the only way a normal third-party iOS app can make a loud sound in
/// silent mode at a scheduled time without the Apple-gated Critical Alerts
/// entitlement: it requires the `audio` background mode and a continuously
/// "playing" (near-silent) audio session. It costs battery while a timer runs
/// and is defeated if the user force-quits the app.
@MainActor
protocol TimerBackgroundAudioKeeping: AnyObject {
    func startKeepAlive()
    func stopKeepAlive()
}

@MainActor
final class AVAudioTimerAlarmPlayer: NSObject, TimerAlarmAudioPlaying, TimerBackgroundAudioKeeping, AVAudioPlayerDelegate {
    private var alarmPlayer: AVAudioPlayer?
    private var keepAlivePlayer: AVAudioPlayer?

    // Touches no main-actor state, so it is safe (and convenient for default
    // arguments) to construct from a nonisolated context.
    nonisolated override init() {
        super.init()
    }

    // MARK: TimerAlarmAudioPlaying

    func playCompletionAlarm() {
        guard activateSession() else {
            // Best-effort fallback. AudioServices obeys the silent switch, so it
            // is inaudible in silent mode — but better than nothing if the audio
            // session cannot be configured.
            AudioServicesPlaySystemSound(1005)
            return
        }
        let player = try? AVAudioPlayer(data: Self.alarmToneData)
        player?.delegate = self
        player?.volume = 1.0
        player?.prepareToPlay()
        player?.play()
        alarmPlayer = player
    }

    func stop() {
        alarmPlayer?.stop()
        alarmPlayer = nil
        deactivateSessionIfIdle()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if player === self.alarmPlayer {
                self.stop()
            }
        }
    }

    // MARK: TimerBackgroundAudioKeeping

    func startKeepAlive() {
        guard keepAlivePlayer == nil, activateSession() else {
            return
        }
        // A continuously looping, near-silent buffer keeps the app from being
        // suspended while a timer runs, so the tick fires in the background.
        let player = try? AVAudioPlayer(data: Self.keepAliveData)
        player?.numberOfLoops = -1
        player?.volume = 0.01
        player?.prepareToPlay()
        player?.play()
        keepAlivePlayer = player
    }

    func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        deactivateSessionIfIdle()
    }

    // MARK: Session

    /// `.mixWithOthers` lets music keep playing while the near-silent keep-alive
    /// loop runs; `.playback` still overrides the silent switch for the alarm.
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
        guard alarmPlayer == nil, keepAlivePlayer == nil else {
            return
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Tone data

    /// A short three-beep alarm tone, generated once as in-memory 16-bit PCM
    /// WAV so the app needs no bundled audio asset.
    private static let alarmToneData: Data = WAVToneGenerator.alarmTone()
    /// A half-second near-silent loop used only to keep the audio session alive.
    private static let keepAliveData: Data = WAVToneGenerator.nearSilentLoop()
}

/// Minimal in-memory WAV (16-bit PCM mono) generator so the app ships no audio
/// asset and exposes no user-facing sound choice.
private enum WAVToneGenerator {
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

    static func nearSilentLoop() -> Data {
        // Very low amplitude (inaudible) rather than pure zeros: a non-zero
        // signal is the more reliable way to keep the session from being
        // treated as "not playing" and suspended.
        let duration = 0.5
        let frequency = 40.0
        let count = Int(sampleRate * duration)
        var samples: [Int16] = []
        samples.reserveCapacity(count)
        for sample in 0..<count {
            let time = Double(sample) / sampleRate
            let value = sin(2 * Double.pi * frequency * time) * 0.0005
            samples.append(Int16(value * Double(Int16.max)))
        }
        return wav(from: samples)
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
