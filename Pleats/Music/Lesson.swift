import Foundation

/// Where to play one song note: which button, and on a bisonoric board which bellows direction.
struct Fingering: Equatable {
    let buttonID: Int
    let pitch: Int
    let direction: BellowsDirection?    // nil: either direction (unisonoric)
}

/// A song mapped onto the buttons the player has: the transposition that fits the board and a fingering for
/// every note to play.
struct LessonPlan: Equatable {
    let song: Song
    let transpose: Int
    let steps: [Fingering]
    let chords: [String?]               // chord hint per step

    static func make(song: Song, buttons: [TrebleButton], bisonoric: Bool) -> LessonPlan? {
        let notes = song.playable
        let available = Set(buttons.flatMap { [$0.push, $0.pull] })
        // Unisonoric boards keep the key and move by octaves; a diatonic board only has a few keys, so any
        // transposition is allowed there, smallest first.
        var shifts = [0, 12, -12, 24, -24]
        // A small board may not hold a song in its own key; then the nearest key that fits.
        for k in 1...6 { shifts += [k, -k, k + 12, -k - 12] }
        if bisonoric {
            shifts = [0]
            for k in 1...11 { shifts += [k, -k] }
            shifts += [12, -12]
        }
        guard let shift = shifts.first(where: { s in notes.allSatisfy { available.contains($0.pitch! + s) } }) else { return nil }
        var steps: [Fingering] = []
        var prev: TrebleButton?
        var prevDir: BellowsDirection?
        for n in notes {
            let p = n.pitch! + shift
            let candidates = buttons.filter { $0.push == p || $0.pull == p }
            func cost(_ b: TrebleButton) -> Double {
                var c = Double(b.row) * (bisonoric ? 0.6 : 2.5)           // inner rows first
                if let pv = prev { c += Double(abs(b.column - pv.column)) * 0.8 + Double(abs(b.row - pv.row)) * 0.4 }
                if bisonoric, let d = prevDir {
                    let dir: BellowsDirection = b.push == p ? .push : .pull
                    if dir != d { c += 1.5 }                               // fewer bellows changes
                }
                return c
            }
            guard let best = candidates.min(by: { cost($0) < cost($1) }) else { return nil }
            var dir: BellowsDirection? = nil
            if bisonoric {
                if best.push == p && best.pull == p { dir = nil }
                else if best.push == p && best.pull != p { dir = .push }
                else { dir = .pull }
            }
            steps.append(Fingering(buttonID: best.id, pitch: p, direction: dir))
            prev = best
            if let d = dir { prevDir = d }
        }
        return LessonPlan(song: song, transpose: shift, steps: steps, chords: notes.map(\.chord))
    }
}

/// Progress through a lesson. The player sets the pace: the next note waits until it sounds.
struct LessonProgress: Equatable {
    let plan: LessonPlan
    private(set) var index = 0
    private(set) var mistakes = 0
    private(set) var startedAt: Date?

    init(plan: LessonPlan) { self.plan = plan }

    var current: Fingering? { index < plan.steps.count ? plan.steps[index] : nil }
    var upcoming: Fingering? { index + 1 < plan.steps.count ? plan.steps[index + 1] : nil }
    var finished: Bool { index >= plan.steps.count }
    var fraction: Double { plan.steps.isEmpty ? 1 : Double(index) / Double(plan.steps.count) }

    /// Stars: three for at most 2 slips, two for up to 6, otherwise one.
    var stars: Int { mistakes <= 2 ? 3 : (mistakes <= 6 ? 2 : 1) }

    enum Result { case advanced, wrong, ignored }

    /// A note started sounding.
    mutating func sounded(pitch: Int) -> Result {
        guard let c = current else { return .ignored }
        if startedAt == nil { startedAt = Date() }
        if pitch == c.pitch { index += 1; return .advanced }
        // A neighbouring note of the previous step (still ringing from a slide) is not a slip.
        if index > 0, plan.steps[index - 1].pitch == pitch { return .ignored }
        mistakes += 1
        return .wrong
    }

    mutating func restart() { index = 0; mistakes = 0; startedAt = nil }
}
