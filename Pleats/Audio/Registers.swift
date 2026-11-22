import Foundation

/// One reed in a register: the octave it sounds in (16′ = 0.5, 8′ = 1, 4′ = 2), its tuning offset and level.
struct Reed: Equatable {
    var ratio: Double
    var cents: Double
    var gain: Double
}

/// Treble registers, named after the classic switches. The dot symbol shows which reed banks sound:
/// low (16′), middle (8′, up to three detuned), high (4′).
enum Register: String, CaseIterable, Identifiable {
    case clarinet, bandoneon, musette, violin, bassoon, piccolo, organ, master

    var id: String { rawValue }

    var name: String {
        switch self {
        case .clarinet: return String(localized: "Clarinet")
        case .bandoneon: return String(localized: "Bandoneon")
        case .musette: return String(localized: "Musette")
        case .violin: return String(localized: "Violin")
        case .bassoon: return String(localized: "Bassoon")
        case .piccolo: return String(localized: "Piccolo")
        case .organ: return String(localized: "Organ")
        case .master: return String(localized: "Master")
        }
    }

    /// The three free registers cover the classic sounds; the rest come with Pro.
    var isFree: Bool { [.clarinet, .bandoneon, .musette].contains(self) }

    var reeds: [Reed] {
        switch self {
        case .clarinet: return [Reed(ratio: 1, cents: 0, gain: 1)]
        case .bandoneon: return [Reed(ratio: 0.5, cents: 0, gain: 0.8), Reed(ratio: 1, cents: 0, gain: 0.75)]
        case .musette: return [Reed(ratio: 1, cents: -14, gain: 0.62), Reed(ratio: 1, cents: 0, gain: 0.62), Reed(ratio: 1, cents: 15, gain: 0.62)]
        case .violin: return [Reed(ratio: 1, cents: 0, gain: 0.75), Reed(ratio: 1, cents: 9, gain: 0.72)]
        case .bassoon: return [Reed(ratio: 0.5, cents: 0, gain: 1)]
        case .piccolo: return [Reed(ratio: 2, cents: 0, gain: 0.85)]
        case .organ: return [Reed(ratio: 0.5, cents: 0, gain: 0.7), Reed(ratio: 2, cents: 0, gain: 0.55)]
        case .master: return [Reed(ratio: 0.5, cents: 0, gain: 0.5), Reed(ratio: 1, cents: -12, gain: 0.45),
                              Reed(ratio: 1, cents: 12, gain: 0.45), Reed(ratio: 2, cents: 0, gain: 0.38)]
        }
    }

    /// Dots for the register symbol: (bank, count) where bank 0 = low, 1 = middle, 2 = high.
    var dots: (low: Bool, middle: Int, high: Bool) {
        let r = reeds
        return (r.contains { $0.ratio < 1 }, r.filter { $0.ratio == 1 }.count, r.contains { $0.ratio > 1 })
    }
}

/// The character of the reeds: the harmonic spectrum of one reed and the tone chamber around it.
enum Voice: String, CaseIterable, Identifiable {
    case classic, cassotto, harmonium, folk

    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: return String(localized: "Classic")
        case .cassotto: return String(localized: "Cassotto")
        case .harmonium: return String(localized: "Harmonium")
        case .folk: return String(localized: "Folk")
        }
    }

    var blurb: String {
        switch self {
        case .classic: return String(localized: "Bright, open reeds")
        case .cassotto: return String(localized: "Reeds in a tone chamber: warm and round")
        case .harmonium: return String(localized: "Soft and breathy, like a pump organ")
        case .folk: return String(localized: "Raw and reedy, for dances")
        }
    }

    var isFree: Bool { self == .classic }

    /// Amplitude of harmonic `n` (1-based) for one reed of this voice. A free reed's tone is a bright, buzzy
    /// spectrum; these curves were tuned by ear, not sampled from any instrument.
    func harmonic(_ n: Int) -> Double {
        let x = Double(n)
        switch self {
        case .classic:
            // Slow roll-off with a gentle presence bump around the 4th–7th harmonics.
            return pow(x, -1.05) * (1 + 0.35 * exp(-pow((x - 5.5) / 2.2, 2)))
        case .cassotto:
            // Steeper roll-off: the chamber swallows the highs.
            return pow(x, -1.6) * (n == 2 ? 1.25 : 1)
        case .harmonium:
            // Mostly the lower harmonics, even ones a little stronger: a hollow, soft tone.
            return pow(x, -1.9) * (n % 2 == 0 ? 1.15 : 1)
        case .folk:
            // Strong odd harmonics and a bright top: a nasal, cutting reed.
            return pow(x, -0.85) * (n % 2 == 1 ? 1.2 : 0.8)
        }
    }

    /// Low-pass corner (Hz) at full pressure; the engine lowers it at soft pressure.
    var brightness: Double {
        switch self {
        case .classic: return 7_500
        case .cassotto: return 3_600
        case .harmonium: return 2_600
        case .folk: return 9_500
        }
    }

    /// Breath noise level.
    var air: Double {
        switch self {
        case .classic: return 0.010
        case .cassotto: return 0.006
        case .harmonium: return 0.018
        case .folk: return 0.012
        }
    }
}
