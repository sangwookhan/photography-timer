// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import AudioToolbox
import Foundation

/// App-owned audible timer-alarm playback (PTIMER-73).
///
/// A foreground completion plays through an `AVAudioSession` configured with the
/// `.playback` category, which overrides the hardware silent switch — so the
/// alarm is audible even with the phone in silent mode, the way field shooting
/// needs. This is the foreground path only; iOS does not let a third-party app
/// guarantee sound for a *background/locked* local notification in silent mode
/// without the Critical Alerts entitlement, so that case still relies on the
/// scheduled notification (audible only when the ringer is on).
@MainActor
protocol TimerAlarmAudioPlaying: AnyObject {
    func playCompletionAlarm()
    func stop()
}

@MainActor
final class AVAudioTimerAlarmPlayer: NSObject, TimerAlarmAudioPlaying, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    // Touches no main-actor state, so it is safe (and convenient for default
    // arguments) to construct from a nonisolated context.
    nonisolated override init() {
        super.init()
    }

    func playCompletionAlarm() {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.playback` ignores the silent switch; `.duckOthers` briefly lowers
            // any other audio rather than stopping it outright.
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.alarmToneData)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            // Best-effort fallback. AudioServices obeys the silent switch, so it
            // is inaudible in silent mode — but it is better than nothing if the
            // audio session cannot be configured.
            AudioServicesPlaySystemSound(1005)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }

    /// A short three-beep alarm tone, generated once as in-memory 16-bit PCM
    /// WAV so the app needs no bundled audio asset.
    private static let alarmToneData: Data = makeAlarmToneData()

    private static func makeAlarmToneData() -> Data {
        let sampleRate = 44_100.0
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
        return wavData(from: samples, sampleRate: Int(sampleRate))
    }

    private static func wavData(from samples: [Int16], sampleRate: Int) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
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
        appendUInt32LE(16)                       // PCM fmt chunk size
        appendUInt16LE(1)                        // PCM format
        appendUInt16LE(UInt16(channels))
        appendUInt32LE(UInt32(sampleRate))
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
