import CoreHaptics
import UIKit

/// Haptics: a soft, continuous rumble that follows bellows pressure while notes sound, a crisp tick for every
/// button and a small bump when the bellows turn around.
final class Haptics {
    static let shared = Haptics()

    var enabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var running = false
    private let tap = UIImpactFeedbackGenerator(style: .rigid)
    private let turn = UIImpactFeedbackGenerator(style: .soft)
    private var lastIntensity: Float = -1

    private init() {
        tap.prepare()
        turn.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in
            self?.player = nil
            self?.running = false
            try? self?.engine?.start()
        }
        engine?.stoppedHandler = { [weak self] _ in
            self?.player = nil
            self?.running = false
        }
    }

    func button() {
        guard enabled else { return }
        tap.impactOccurred(intensity: 0.55)
    }

    func reverse() {
        guard enabled else { return }
        turn.impactOccurred(intensity: 0.7)
    }

    /// 0…1 while reeds sound, 0 when silent.
    func air(_ level: Double) {
        guard enabled, let engine else { return }
        let target = Float(max(0, min(1, level)))
        if target < 0.03 {
            if running { try? player?.stop(atTime: CHHapticTimeImmediate); running = false; lastIntensity = -1 }
            return
        }
        if player == nil {
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.12),
            ], relativeTime: 0, duration: 30)
            guard let pattern = try? CHHapticPattern(events: [event], parameters: []) else { return }
            try? engine.start()
            player = try? engine.makeAdvancedPlayer(with: pattern)
            player?.loopEnabled = true
        }
        if !running {
            try? engine.start()
            try? player?.start(atTime: CHHapticTimeImmediate)
            running = true
        }
        guard abs(target - lastIntensity) > 0.04 else { return }
        lastIntensity = target
        let p = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0.15 + 0.55 * target, relativeTime: 0)
        try? player?.sendParameters([p], atTime: CHHapticTimeImmediate)
    }
}
