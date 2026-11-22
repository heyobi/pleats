import Foundation

/// One melody note of a song (or a rest when `pitch` is nil), with an optional chord hint for the bass side.
struct SongNote: Equatable {
    var pitch: Int?
    var beats: Double
    var chord: String?
}

struct Song: Identifiable, Equatable {
    let id: String
    let title: String
    let origin: String
    let tempo: Double           // quarter notes per minute
    let isFree: Bool
    let notes: [SongNote]

    init(_ id: String, _ title: String, _ origin: String, tempo: Double, free: Bool, _ text: String) {
        self.id = id
        self.title = title
        self.origin = origin
        self.tempo = tempo
        self.isFree = free
        self.notes = SongParser.parse(text)
    }

    /// Notes that have to be played (rests skipped).
    var playable: [SongNote] { notes.filter { $0.pitch != nil } }

    var range: ClosedRange<Int> {
        let ps = notes.compactMap(\.pitch)
        return (ps.min() ?? 60)...(ps.max() ?? 60)
    }

    var difficulty: Int {
        let n = playable.count
        let span = range.upperBound - range.lowerBound
        let accidentals = playable.filter { Pitch.isAccidental($0.pitch!) }.count
        var d = 1
        if n > 40 || span > 9 { d += 1 }
        if n > 70 || accidentals > 4 || span > 13 { d += 1 }
        return d
    }
}

/// Compact song text: `C4:1` (note and beats, quarter = 1), `F#4:.5`, `Bb3:2`, `R:1` (rest), `[Am]` (chord hint
/// for the following notes), `|` (bar line, ignored). A note without `:beats` lasts one beat.
enum SongParser {
    static func parse(_ text: String) -> [SongNote] {
        var out: [SongNote] = []
        var chord: String?
        var pendingChord: String?
        for raw in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let tok = String(raw)
            if tok == "|" { continue }
            if tok.hasPrefix("[") && tok.hasSuffix("]") {
                chord = String(tok.dropFirst().dropLast())
                pendingChord = chord
                continue
            }
            let parts = tok.split(separator: ":", maxSplits: 1).map(String.init)
            let beats = parts.count > 1 ? (Double(parts[1]) ?? 1) : 1
            if parts[0].uppercased() == "R" {
                out.append(SongNote(pitch: nil, beats: beats, chord: nil))
            } else if let p = Pitch.parse(parts[0]) {
                out.append(SongNote(pitch: p, beats: beats, chord: pendingChord))
                pendingChord = nil
            }
        }
        _ = chord
        return out
    }
}

/// The song book. Every melody is public domain: anonymous folk tunes or works whose composers died long ago,
/// transcribed for this app (Turkish tunes rounded to equal temperament, as accordionists play them).
enum SongBook {
    static let all: [Song] = [
        Song("scale", String(localized: "First Steps: C Major Scale"), String(localized: "Warm-up"), tempo: 80, free: true, """
        [C] C4 D4 E4 F4 | [G] G4 A4 B4 [C] C5:2 | R:1 [C] C5 B4 A4 | [G] G4 F4 E4 D4 | [C] C4:3 R:1
        """),
        Song("valse", "Valse des Plis", String(localized: "Original musette waltz for Pleats"), tempo: 150, free: true, """
        [Am] E5:2 C5 | A4:2 C5 | [E7] B4 G#4 B4 | E5:3 | D5:2 B4 | G#4:2 B4 | [Am] A4 C5 E5 | A5:3 |
        [Dm] F5:2 D5 | A4:2 D5 | [Am] C5 E5 A5 | E5:3 | [E7] D5 C5 B4 | G#4 A4 B4 | [Am] A4:3 | R:3
        """),
        Song("ode", String(localized: "Ode to Joy"), String(localized: "L. van Beethoven, 1824"), tempo: 108, free: true, """
        [C] E4 E4 F4 G4 | [G] G4 F4 E4 D4 | [C] C4 C4 D4 E4 | [G] E4:1.5 D4:.5 D4:2 |
        [C] E4 E4 F4 G4 | [G] G4 F4 E4 D4 | [C] C4 C4 D4 E4 | [G] D4:1.5 [C] C4:.5 C4:2 |
        [G] D4 D4 E4 C4 | D4 E4:.5 F4:.5 E4 C4 | D4 E4:.5 F4:.5 E4 D4 | [C] C4 D4 [G] G3:2 |
        [C] E4 E4 F4 G4 | [G] G4 F4 E4 D4 | [C] C4 C4 D4 E4 | [G] D4:1.5 [C] C4:.5 C4:2
        """),
        Song("sailor", String(localized: "Drunken Sailor"), String(localized: "Sea shanty, traditional"), tempo: 116, free: true, """
        [Dm] A4:.5 A4:.25 A4:.25 A4:.5 A4:.25 A4:.25 | A4:.5 D4:.5 F4:.5 A4:.5 | [C] G4:.5 G4:.25 G4:.25 G4:.5 G4:.25 G4:.25 | G4:.5 C4:.5 E4:.5 G4:.5 |
        [Dm] A4:.5 A4:.25 A4:.25 A4:.5 A4:.25 A4:.25 | A4:.5 B4:.5 C5:.5 D5:.5 | [C] C5:.5 A4:.5 G4:.5 E4:.5 | [Dm] D4 D4 |
        [Dm] A4 A4 | A4:.5 D4:.5 F4:.5 A4:.5 | [C] G4 G4 | G4:.5 C4:.5 E4:.5 G4:.5 |
        [Dm] A4 A4 | A4:.5 B4:.5 C5:.5 D5:.5 | [C] C5:.5 A4:.5 G4:.5 E4:.5 | [Dm] D4 D4
        """),
        Song("uskudar", "Üsküdar'a Gider İken", String(localized: "Traditional, Türkiye"), tempo: 84, free: true, """
        [Gm] G4:.75 D5:.25 D5:.5 D5:.5 | [Cm] Eb5:.25 D5:.25 Eb5:.25 F5:.25 [Gm] D5:.5 D5:.5 | [Cm] C5:.5 C5:.25 C5:.25 Bb4:.5 C5:.5 | [D7] D5:.25 Eb5:.25 D5:.25 C5:.25 Bb4:.25 A4:.25 [Gm] G4:.5 |
        [Gm] G4:.75 D5:.25 D5:.5 D5:.5 | [Cm] Eb5:.25 D5:.25 Eb5:.25 F5:.25 [Gm] D5:.5 D5:.5 | [Cm] C5:.5 C5:.25 C5:.25 Bb4:.5 C5:.5 | [Gm] D5:.25 Eb5:.25 D5:.25 C5:.25 Bb4:.25 C5:.25 D5:.5 |
        [Gm] G4:.75 A4:.25 Bb4:.5 C5:.5 | [D7] D5:.25 Eb5:.25 D5:.25 C5:.25 Bb4:.25 A4:.25 [Gm] G4:.5 | [Cm] A4:.25 C5:.25 Bb4:.25 A4:.25 [D7] A4:.25 G4:.25 F#4:.25 G4:.25 | [D7] A4:1 R:1 |
        [Gm] G4:.75 A4:.25 Bb4:.5 C5:.5 | [D7] D5:.25 Eb5:.25 D5:.25 C5:.25 Bb4:.25 A4:.25 [Gm] G4:.5 | [Cm] A4:.25 C5:.25 Bb4:.25 A4:.25 [D7] A4:.25 G4:.25 G4:.25 F#4:.25 | [Gm] G4:2
        """),
        Song("yemen", "Havada Bulut Yok (Yemen Türküsü)", String(localized: "Traditional, Türkiye"), tempo: 150, free: false, """
        R:1 [Am] C5:.5 D5:1 E5:1 E5:1.5 | E5:2.5 E5:.25 [Dm] F5:.25 D5:.25 E5:.25 D5:.25 E5:.25 D5:.25 E5:.25 D5:.5 |
        [G] D5:.5 R:.5 G5:.5 G5:.5 D5:.5 D5:1 E5:.5 C5:.25 E5:.25 D5:.5 | [Am] D5:1 C5:.5 D5:1 E5:1 E5:1.5 |
        [Am] E5:2.5 E5:.25 [Dm] F5:.25 D5:.25 E5:.25 D5:.25 E5:.25 D5:.25 E5:.25 D5:.5 | [G] D5:.5 R:.5 G5:.5 G5:.5 D5:.5 D5:1 E5:.5 C5:.25 E5:.25 D5:.5 |
        [Dm] D5:.75 C5:.25 E5:.5 E5:.5 D5:.5 D5:1 E5:.5 C5:.25 E5:.25 D5:.5 | [G] D5:.75 C5:.25 D5:.5 D5:.5 B4:.5 C5:.5 B4:.5 D5:.5 B4:.25 D5:.25 C5:.5 |
        [Am] C5:.75 B4:.25 C5:.5 C5:.5 B4:.5 B4:.5 A4:.5 C5:1 B4:.5 | [E7] B4:.5 A4:.5 C5:.5 B4:.5 A4:.5 A4:1 B4:1 A4:.5 | [Am] A4:5
        """),
        Song("saints", String(localized: "When the Saints Go Marching In"), String(localized: "Traditional, USA"), tempo: 120, free: true, """
        R:1 [C] C4 E4 F4 | G4:4 | R:1 C4 E4 F4 | G4:4 | R:1 C4 E4 F4 | G4:2 E4:2 | C4:2 E4:2 | [G7] D4:4 |
        R:1 [C] E4 E4 D4 | C4:3 C4 | [C7] E4:2 G4:2 | [F] G4 F4:3 | R:1 [C] E4 F4 G4 | E4:2 C4:2 | [G7] D4:2 D4:2 | [C] C4:4
        """),
        Song("grace", String(localized: "Amazing Grace"), String(localized: "Traditional, USA"), tempo: 84, free: true, """
        [G] D4 | G4:2 B4:.5 G4:.5 | B4:2 A4 | [C] G4:2 E4 | [G] D4:2 D4 | G4:2 B4:.5 G4:.5 | B4:2 A4 | [D] D5:3 | D5:2 B4 |
        [G] D5:1.5 B4:.5 D5:.5 B4:.5 | G4:2 D4 | [C] E4:1.5 G4:.5 G4:.5 E4:.5 | [G] D4:2 D4 | G4:2 B4:.5 G4:.5 | [D7] B4:2 A4 | [G] G4:3
        """),
        Song("jingle", String(localized: "Jingle Bells"), String(localized: "J. L. Pierpont, 1857"), tempo: 132, free: false, """
        [C] E4 E4 E4:2 | E4 E4 E4:2 | E4 G4 C4:1.5 D4:.5 | E4:4 | [F] F4 F4 F4:1.5 F4:.5 | [C] F4 E4 E4 E4:.5 E4:.5 | [D7] E4 D4 D4 E4 | [G7] D4:2 G4:2 |
        [C] E4 E4 E4:2 | E4 E4 E4:2 | E4 G4 C4:1.5 D4:.5 | E4:4 | [F] F4 F4 F4 F4 | [C] F4 E4 E4 E4:.5 E4:.5 | [G7] G4 G4 F4 D4 | [C] C4:4
        """),
        // Pro
        Song("susanna", String(localized: "Oh! Susanna"), String(localized: "S. Foster, 1848"), tempo: 120, free: true, """
        [C] C4:.5 D4:.5 | E4 G4 G4:1.5 A4:.5 | G4 E4 C4:1.5 D4:.5 | E4 E4 D4 C4 | [G7] D4:3 C4:.5 D4:.5 |
        [C] E4 G4 G4:1.5 A4:.5 | G4 E4 C4:1.5 D4:.5 | [G7] E4 E4 D4 D4 | [C] C4:3
        """),
        Song("tango", "Tango de la Bisagra", String(localized: "Original tango for Pleats"), tempo: 108, free: false, """
        [Dm] A4:.75 A4:.25 A4:.5 Bb4:.5 A4 G4:.5 F4:.5 | E4:.75 F4:.25 G4:.5 A4:.5 D4:2 | [A7] C#5:.75 C#5:.25 C#5:.5 D5:.5 E5 D5:.5 C#5:.5 | [Dm] D5:2 A4:2 |
        [Gm] Bb4:.75 Bb4:.25 Bb4:.5 C5:.5 D5 C5:.5 Bb4:.5 | [Dm] A4:.75 Bb4:.25 A4:.5 G4:.5 F4 E4:.5 F4:.5 | [A7] E4 G4 C#5 E5 | [Dm] D5:3 R:1
        """),
        Song("entertainer", String(localized: "The Entertainer"), String(localized: "S. Joplin, 1902"), tempo: 84, free: false, """
        [C] D4:.25 D#4:.25 | E4:.25 C5:.5 E4:.25 C5:.5 E4:.25 C5:1.25 | C5:.25 D5:.25 D#5:.25 E5:.25 C5:.25 D5:.25 E5:.5 | [G7] B4:.25 D5:.5 [C] C5:1.25 D4:.25 D#4:.25 |
        [C] E4:.25 C5:.5 E4:.25 C5:.5 E4:.25 C5:1.25 | [F] A4:.25 G4:.25 F#4:.25 A4:.25 C5:.25 E5:.5 D5:.25 | [G7] C5:.25 A4:.25 D5:1.5 | [C] C5:2
        """),
        Song("sarigelin", "Sarı Gelin", String(localized: "Traditional, Anatolia"), tempo: 112, free: false, """
        R:1 [Em] E4:.5 E4:1 B4:1.5 | [Am] B4:1 A4:1.5 B4:.5 A4:.5 B4:1.5 | B4:1 B4:.25 C5:.25 B4:.75 A4:.25 A4:.75 G4:.25 A4:.5 B4:.5 R:.5 |
        [Am] B4:1 C#5:.5 A4:1 [Dm] G4:.75 F4:.25 G4:.25 A4:.25 A4:.5 R:.5 | [Dm] G4:1 A4:.5 F4:1 [Em] E4:1 E4:.25 G4:.25 G4:.5 R:.5 | [Dm] F4:1 G4:.5 [Em] E4:1 E4:2.5 |
        R:1 [G] G4:.5 G4:1 A4:1 A4:1.5 | [Am] A4:1 G4:1.5 A4:.5 G4:.5 A4:.5 B4:1 | [Em] B4:.5 R:.5 G4:.5 A4:1 B4:1 B4:1.5 | [Am] B4:1 B4:.25 C5:.25 A4:1 A4:.75 G4:.25 A4:.25 B4:.25 B4:.5 R:.5 |
        [Am] B4:1 C#5:.5 A4:1 [Dm] G4:.75 F4:.25 G4:.25 A4:.25 A4:.5 R:.5 | [Dm] G4:1 A4:.5 F4:1 [Em] E4:1 E4:.25 G4:.25 G4:.5 R:.5 | [Dm] F4:1 G4:.5 [Em] E4:1 E4:2.5
        """),
        Song("greensleeves", String(localized: "Greensleeves"), String(localized: "Traditional, England"), tempo: 100, free: false, """
        [Am] A4:.5 | C5:1 D5:.5 E5:.75 F5:.25 E5:.5 | [G] D5:1 B4:.5 G4:.75 A4:.25 B4:.5 | [Am] C5:1 A4:.5 A4:.75 G#4:.25 A4:.5 | [E] B4:1 G#4:.5 E4:1 A4:.5 |
        [Am] C5:1 D5:.5 E5:.75 F5:.25 E5:.5 | [G] D5:1 B4:.5 G4:.75 A4:.25 B4:.5 | [Am] C5:.75 B4:.25 A4:.5 [E] G#4:.75 F#4:.25 G#4:.5 | [Am] A4:1.5 A4:1 |
        [C] G5:1.5 G5:.75 F#5:.25 E5:.5 | [G] D5:1 B4:.5 G4:.75 A4:.25 B4:.5 | [Am] C5:1 A4:.5 A4:.75 G#4:.25 A4:.5 | [E] B4:1 G#4:.5 E4:1 |
        [C] G5:1.5 G5:.75 F#5:.25 E5:.5 | [G] D5:1 B4:.5 G4:.75 A4:.25 B4:.5 | [Am] C5:.75 B4:.25 A4:.5 [E] G#4:.75 F#4:.25 G#4:.5 | [Am] A4:1.5 A4:1
        """),
        Song("auldlang", String(localized: "Auld Lang Syne"), String(localized: "Traditional, Scotland"), tempo: 92, free: false, """
        [C] G3 | C4:1.5 C4:.5 C4 E4 | [G7] D4:1.5 C4:.5 D4 E4:.5 D4:.5 | [C] C4:1.5 C4:.5 E4 G4 | [F] A4:3 A4 |
        [C] G4:1.5 E4:.5 E4 C4 | [G7] D4:1.5 C4:.5 D4 E4:.5 D4:.5 | [Am] C4:1.5 A3:.5 [F] A3 G3 | [C] C4:3 A4 |
        [C] G4:1.5 E4:.5 E4 C4 | [G7] D4:1.5 C4:.5 D4 A4 | [C] G4:1.5 E4:.5 E4 G4 | [F] A4:3 C5 |
        [C] G4:1.5 E4:.5 E4 C4 | [G7] D4:1.5 C4:.5 D4 E4:.5 D4:.5 | [Am] C4:1.5 A3:.5 [F] A3 G3 | [C] C4:3
        """),
        Song("cancan", String(localized: "Can-Can"), String(localized: "J. Offenbach, 1858"), tempo: 132, free: false, """
        [C] C4 D4:.5 F4:.5 E4:.5 D4:.5 G4 | [G7] G4 G4:.5 A4:.5 E4:.5 F4:.5 D4 | D4 D4:.5 F4:.5 E4:.5 D4:.5 [C] C4:.5 C5:.5 | B4:.5 A4:.5 G4:.5 F4:.5 [G7] E4:.5 D4:.5 [C] C4 |
        [C] C4 D4:.5 F4:.5 E4:.5 D4:.5 G4 | [G7] G4 G4:.5 A4:.5 E4:.5 F4:.5 D4 | D4 D4:.5 F4:.5 E4:.5 D4:.5 [C] C4:.5 G4:.5 | [G7] D4:.5 E4:.5 D4:.5 E4:.5 [C] C4:2
        """),
        Song("cucaracha", String(localized: "La Cucaracha"), String(localized: "Traditional, Mexico"), tempo: 160, free: true, """
        [F] C4:.5 C4:.5 C4:.5 F4:1.5 A4 | C4:.5 C4:.5 C4:.5 F4:1.5 A4 | [C7] F4 F4:.5 E4:.5 E4:.5 D4:.5 D4:.5 C4:1.5 R:1 |
        [C7] C4:.5 C4:.5 C4:.5 E4:1.5 G4 | C4:.5 C4:.5 C4:.5 E4:1.5 G4 | [F] C5 D5:.5 C5:.5 Bb4:.5 A4:.5 G4:.5 F4:1.5 R:1
        """),
        Song("lullaby", String(localized: "Lullaby (Wiegenlied)"), String(localized: "J. Brahms, 1868"), tempo: 84, free: false, """
        [C] E4:.5 E4:.5 | G4:2 E4:.5 E4:.5 | G4:2 E4:.5 G4:.5 | [G7] C5 B4:1.5 A4:.5 | A4 G4 D4:.5 E4:.5 | F4 D4 D4:.5 E4:.5 | F4:2 D4:.5 F4:.5 |
        [G7] B4:.5 A4:.5 G4 B4 | [C] C5:2 C4:.5 C4:.5 | [F] C5:2 A4:.5 F4:.5 | [C] G4:2 E4:.5 C4:.5 | [G7] F4 G4 A4 | [C] G4:2 C4:.5 C4:.5 |
        [F] C5:2 A4:.5 F4:.5 | [C] G4:2 E4:.5 C4:.5 | [G7] F4 E4 D4 | [C] C4:2
        """),
        Song("elise", String(localized: "Für Elise"), String(localized: "L. van Beethoven, 1810"), tempo: 72, free: false, """
        [Am] E5:.5 D#5:.5 | E5:.5 D#5:.5 E5:.5 B4:.5 D5:.5 C5:.5 | A4:1 R:.5 C4:.5 E4:.5 A4:.5 | [E] B4:1 R:.5 E4:.5 G#4:.5 B4:.5 | [Am] C5:1 R:.5 E4:.5 E5:.5 D#5:.5 |
        E5:.5 D#5:.5 E5:.5 B4:.5 D5:.5 C5:.5 | A4:1 R:.5 C4:.5 E4:.5 A4:.5 | [E] B4:1 R:.5 E4:.5 C5:.5 B4:.5 | [Am] A4:2
        """),
    ]

    static func song(_ id: String) -> Song? { all.first { $0.id == id } }
}
