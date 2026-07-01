// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import AudioToolbox
import Combine
import Foundation

/// Best-effort, passive silent-mode probe (PTIMER-73). It reports whether the
/// device is *likely* muted; it is never a guaranteed diagnosis of the hardware
/// silent switch.
@MainActor
protocol MuteLikelihoodProbing {
    func probe(completion: @escaping @MainActor (Bool) -> Void)
}

/// Timing-based mute probe (Option 3A). It plays a short, fully silent clip
/// through the system-sound server: when the device is muted the system culls
/// the clip and the completion fires near-instantly, whereas with sound on it
/// fires only after the clip's full duration. The elapsed time is the
/// muted-likely signal.
///
/// It deliberately uses `AudioServices` rather than `AVAudioSession`, so it
/// never mutates the shared session the foreground completion alarm relies on,
/// and the clip is silent so the probe is never itself audible.
@MainActor
final class SystemSoundMuteProbe: MuteLikelihoodProbing {
    private var soundID: SystemSoundID?

    /// Below this elapsed playback time the clip was culled (muted-likely);
    /// above it the silent clip played in full (switch off). Timing-based and
    /// best-effort, never a guarantee.
    private static let mutedElapsedThreshold: TimeInterval = 0.1
    private static let probeClipDuration: TimeInterval = 0.5

    // Touches no main-actor state, so it is safe to construct from the
    // nonisolated context of `SilentModeAdvisoryController.shared`.
    nonisolated init() {}

    func probe(completion: @escaping @MainActor (Bool) -> Void) {
        guard let soundID = ensureSoundID() else {
            // Cannot probe: never assert muted.
            completion(false)
            return
        }

        let start = DispatchTime.now()
        AudioServicesPlaySystemSoundWithCompletion(soundID) {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds)
                / 1_000_000_000
            let mutedLikely = elapsed < Self.mutedElapsedThreshold
            Task { @MainActor in completion(mutedLikely) }
        }
    }

    private func ensureSoundID() -> SystemSoundID? {
        if let soundID {
            return soundID
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptimer-mute-probe.wav")
        do {
            try WAVToneGenerator.silence(duration: Self.probeClipDuration).write(to: url, options: .atomic)
        } catch {
            return nil
        }

        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else {
            return nil
        }
        soundID = id
        return id
    }
}

/// Owns the passive silent-mode advisory policy (PTIMER-73).
///
/// Hard rules it enforces: it never blocks or delays Start, never shows a modal
/// or requires confirmation, runs only on a foreground entry, and shows at most
/// a small non-blocking banner at most once per app session. It is suppressed
/// when a completion alarm is sounding or when the entry came from tapping a
/// timer notification. The copy never claims the device *is* muted.
@MainActor
final class SilentModeAdvisoryController: ObservableObject {
    static let shared = SilentModeAdvisoryController()

    /// Short, non-diagnostic copy.
    static let advisoryText = String(localized: "Silent mode may be on. Turn it off and check volume before long exposures.")

    @Published private(set) var isAdvisoryVisible = false

    private let probe: MuteLikelihoodProbing
    private var hasProbedThisSession = false
    private var openedFromNotification = false

    // Constructs no main-actor state beyond storing the probe, so it is safe as
    // the initializer for the nonisolated `shared` static (mirrors
    // `AVAudioTimerAlarmPlayer`).
    nonisolated init(probe: MuteLikelihoodProbing = SystemSoundMuteProbe()) {
        self.probe = probe
    }

    /// Records that this foreground entry came from tapping a timer
    /// notification, so the advisory is suppressed for it.
    func noteOpenedFromNotification() {
        openedFromNotification = true
    }

    func dismissAdvisory() {
        isAdvisoryVisible = false
    }

    /// Runs the passive probe on a foreground entry when policy allows. This is
    /// called from the scene becoming active — never from Start — so it can
    /// neither block nor delay starting a timer.
    func handleAppBecameActive(isAlarmSounding: Bool) {
        guard !hasProbedThisSession else {
            return
        }
        // Never compete with a sounding completion alarm. Leave the session
        // un-burned so a later quiet entry can still probe once.
        guard !isAlarmSounding else {
            return
        }
        // Entry from a timer notification (the timer already finished): the
        // advisory would be noise. Consume the flag; don't burn the session.
        if openedFromNotification {
            openedFromNotification = false
            return
        }

        hasProbedThisSession = true
        probe.probe { [weak self] mutedLikely in
            guard let self else {
                return
            }
            // A notification tap can land while the async probe is in flight
            // (cold-launch race): re-check and stay silent if so.
            if self.openedFromNotification {
                self.openedFromNotification = false
                return
            }
            guard mutedLikely else {
                return
            }
            self.isAdvisoryVisible = true
        }
    }
}
