import Foundation

/// Turns bellows movement into air pressure and a direction.
///
/// On iPhone Duo every hinge angle sample feeds `feed(position:at:)`; elsewhere a drag on the bellows feeds a
/// virtual position in the same unit (degrees). Pressure follows the speed of the movement, as on a real accordion:
/// a slow, steady pull is soft, a quick push is loud. Samples arrive at the rate the system chooses, so the speed
/// is smoothed, and `tick(at:)` lets it fall away when the bellows stop and no new samples arrive.
struct BellowsModel {
    /// Degrees per second below which the reeds stay silent (hand tremor, sensor noise).
    var deadZone = 3.0
    /// Degrees per second that give full pressure. Settings scales this with the sensitivity slider.
    var fullScale = 110.0
    /// Low-pass time constant of the speed estimate, seconds.
    var smoothing = 0.045
    /// After this long without a sample the bellows count as stopped.
    var staleAfter = 0.09

    private(set) var position: Double?
    private(set) var speed = 0.0           // deg/s, positive while opening (pull)
    private(set) var direction: BellowsDirection = .pull
    private(set) var pressure = 0.0        // 0…1
    private var lastT: Double?
    private var lastSampleT: Double?

    /// Feeds one position sample (degrees) taken at time `t` (seconds). Returns true if the direction changed.
    @discardableResult
    mutating func feed(position p: Double, at t: Double) -> Bool {
        defer { position = p; lastT = t; lastSampleT = t }
        guard let old = position, let lt = lastT, let ls = lastSampleT else { return false }
        let dtSample = t - ls
        guard dtSample > 0.0005 else { return false }
        let raw = (p - old) / min(dtSample, 0.25)
        let k = min(1, max(t - lt, 0.0005) / max(smoothing, 1e-3))
        speed += (raw - speed) * k
        return update()
    }

    /// Called every frame. Lets the speed decay when no samples arrive, as when the hands stop moving.
    @discardableResult
    mutating func tick(at t: Double) -> Bool {
        guard let ls = lastSampleT, t - ls > staleAfter, let lt = lastT else { return false }
        let dt = t - lt
        guard dt > 0 else { return false }
        speed *= exp(-dt / 0.05)
        if abs(speed) < 0.5 { speed = 0 }
        lastT = t
        return update()
    }

    private mutating func update() -> Bool {
        let a = abs(speed)
        let x = max(0, (a - deadZone) / max(1, fullScale - deadZone))
        pressure = min(1, pow(x, 0.85))
        let before = direction
        // Only a clear movement flips the reeds; a still bellows keeps its last direction.
        if a > deadZone * 1.5 { direction = speed > 0 ? .pull : .push }
        return before != direction
    }

    mutating func reset() {
        position = nil; lastT = nil; lastSampleT = nil; speed = 0; pressure = 0
    }
}
