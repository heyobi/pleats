import Foundation

/// MIDI note numbers, names and frequencies (equal temperament, A4 = 440 Hz).
enum Pitch {
    static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    static func frequency(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    static func name(_ midi: Int, flats: Bool = false) -> String {
        let pc = ((midi % 12) + 12) % 12
        return (flats ? flatNames : sharpNames)[pc]
    }

    static func nameWithOctave(_ midi: Int) -> String { "\(name(midi))\(midi / 12 - 1)" }

    static func isAccidental(_ midi: Int) -> Bool { [1, 3, 6, 8, 10].contains(((midi % 12) + 12) % 12) }

    /// Parses "C4", "F#3", "Bb5", "c♯4" into a MIDI number.
    static func parse(_ s: String) -> Int? {
        var chars = Array(s.trimmingCharacters(in: .whitespaces))
        guard let first = chars.first else { return nil }
        let base: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let b = base[Character(first.uppercased())] else { return nil }
        chars.removeFirst()
        var acc = 0
        while let c = chars.first, "#♯b♭".contains(c) {
            acc += (c == "#" || c == "♯") ? 1 : -1
            chars.removeFirst()
        }
        guard let oct = Int(String(chars)) else { return nil }
        return (oct + 1) * 12 + b + acc
    }
}

/// Bellows direction. Opening the hinge draws air (pull); closing it pushes.
enum BellowsDirection: Equatable {
    case push, pull
}

/// One treble button: on a unisonoric layout both directions sound the same pitch.
struct TrebleButton: Identifiable, Equatable {
    let id: Int
    let row: Int        // 0 = row nearest the bellows
    let column: Int     // 0 = lowest
    let push: Int       // MIDI
    let pull: Int
    func pitch(_ d: BellowsDirection) -> Int { d == .push ? push : pull }
    var bisonoric: Bool { push != pull }
}

/// Treble keyboards. Chromatic is a five-row C-system button board; Diatonic is a two-row G/C club-style board
/// whose buttons play a different note on push and on pull.
enum TrebleLayout: String, CaseIterable, Identifiable {
    case chromatic, diatonic
    var id: String { rawValue }

    var bisonoric: Bool { self == .diatonic }

    /// Rows of the board.
    var rows: Int { self == .chromatic ? 5 : 2 }

    /// Buttons for a board that has room for `perRow` buttons in a row, starting at `low` (chromatic only).
    func buttons(perRow: Int, low: Int = 55) -> [TrebleButton] {
        var out: [TrebleButton] = []
        switch self {
        case .chromatic:
            // C-system: each row climbs in minor thirds; neighbouring rows are a semitone apart. Rows 4 and 5
            // repeat rows 1 and 2, as on a five-row board, so every note has a second fingering.
            for r in 0..<5 {
                for c in 0..<perRow {
                    let p = low + (r % 3) + 3 * c + (r >= 3 ? 3 : 0)
                    out.append(TrebleButton(id: r * 100 + c, row: r, column: c, push: p, pull: p))
                }
            }
        case .diatonic:
            let n = min(perRow, 10)
            // Inner row in C, outer row in G (a fifth up), Richter-style ten-button rows.
            let cPush = ["E3", "G3", "C4", "E4", "G4", "C5", "E5", "G5", "C6", "E6"]
            let cPull = ["G3", "B3", "D4", "F4", "A4", "B4", "D5", "F5", "A5", "B5"]
            let gPush = ["B2", "D3", "G3", "B3", "D4", "G4", "B4", "D5", "G5", "B5"]
            let gPull = ["D3", "F#3", "A3", "C4", "E4", "F#4", "A4", "C5", "E5", "F#5"]
            let start = max(0, (10 - n) / 2)
            for c in 0..<n {
                let i = start + c
                out.append(TrebleButton(id: c, row: 0, column: c, push: Pitch.parse(cPush[i])! + 12, pull: Pitch.parse(cPull[i])! + 12))
                out.append(TrebleButton(id: 100 + c, row: 1, column: c, push: Pitch.parse(gPush[i])! + 12, pull: Pitch.parse(gPull[i])! + 12))
            }
        }
        return out
    }
}

/// Stradella bass: columns follow the circle of fifths; rows are bass note, major, minor and seventh chords.
enum BassRow: Int, CaseIterable {
    case bass, major, minor, seventh

    var intervals: [Int] {
        switch self {
        case .bass: return [0]
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .seventh: return [0, 4, 10]
        }
    }

    var short: String {
        switch self {
        case .bass: return ""
        case .major: return "M"
        case .minor: return "m"
        case .seventh: return "7"
        }
    }
}

struct BassButton: Identifiable, Equatable {
    let id: Int
    let row: BassRow
    let column: Int
    let root: Int       // pitch class 0…11

    /// Notes that sound: a deep bass reed pair for the bass row, a compact chord around G3 for chords.
    var notes: [Int] {
        if row == .bass { return [36 + root, 48 + root] }
        return row.intervals.map { i in
            let p = 48 + ((root + i) % 12)
            return p < 52 ? p + 12 : p     // keep chords in E3…D#4, like the chord reeds of a real bass
        }
    }

    var label: String {
        let n = Pitch.name(root, flats: [1, 3, 8, 10].contains(root))
        return row == .bass ? n : n + row.short
    }
}

enum Stradella {
    /// Circle of fifths from D♭ to F♯; C sits in the middle.
    static let circle = [1, 8, 3, 10, 5, 0, 7, 2, 9, 4, 11, 6]

    /// `columns` buttons centred on C.
    static func buttons(columns: Int) -> [BassButton] {
        let n = max(3, min(columns, circle.count))
        let cIndex = 5
        var first = cIndex - (n - 1) / 2
        first = max(0, min(first, circle.count - n))
        var out: [BassButton] = []
        for (ci, k) in (first..<(first + n)).enumerated() {
            for row in BassRow.allCases {
                out.append(BassButton(id: row.rawValue * 100 + ci, row: row, column: ci, root: circle[k]))
            }
        }
        return out
    }

    /// The bass button that best accompanies a chord symbol like "C", "Am", "G7", "Dm".
    static func button(for chord: String, in buttons: [BassButton]) -> BassButton? {
        var s = chord
        var row = BassRow.major
        if s.hasSuffix("7") { row = .seventh; s.removeLast() }
        else if s.hasSuffix("m") { row = .minor; s.removeLast() }
        guard let p = Pitch.parse(s + "4") else { return nil }
        let pc = ((p % 12) + 12) % 12
        return buttons.first { $0.row == row && $0.root == pc }
    }
}
