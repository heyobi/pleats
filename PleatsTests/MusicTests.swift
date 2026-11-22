import XCTest
@testable import Pleats

final class PitchTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(Pitch.parse("C4"), 60)
        XCTAssertEqual(Pitch.parse("A4"), 69)
        XCTAssertEqual(Pitch.parse("F#3"), 54)
        XCTAssertEqual(Pitch.parse("Bb4"), 70)
        XCTAssertEqual(Pitch.parse("Eb5"), 75)
        XCTAssertEqual(Pitch.parse("c♯4"), 61)
        XCTAssertNil(Pitch.parse("H2"))
        XCTAssertEqual(Pitch.frequency(69), 440, accuracy: 0.001)
        XCTAssertEqual(Pitch.frequency(81), 880, accuracy: 0.001)
    }
}

final class LayoutTests: XCTestCase {
    func testChromaticCoversEveryNoteInRange() {
        let buttons = TrebleLayout.chromatic.buttons(perRow: 8, low: 55)
        let pitches = Set(buttons.map(\.push))
        // Rows 0–2 alone cover a full chromatic run.
        for p in 55...(55 + 3 * 7) { XCTAssertTrue(pitches.contains(p), "missing \(p)") }
        XCTAssertTrue(buttons.allSatisfy { !$0.bisonoric })
    }

    func testDiatonicIsPushPull() {
        let buttons = TrebleLayout.diatonic.buttons(perRow: 10)
        XCTAssertEqual(buttons.count, 20)
        let c3 = buttons.first { $0.row == 0 && $0.column == 2 }!
        XCTAssertEqual(c3.push, Pitch.parse("C5"))
        XCTAssertEqual(c3.pull, Pitch.parse("D5"))
        XCTAssertTrue(buttons.allSatisfy(\.bisonoric))
    }

    func testStradellaCentredOnC() {
        let b = Stradella.buttons(columns: 7)
        XCTAssertEqual(b.count, 28)
        let bassRow = b.filter { $0.row == .bass }.sorted { $0.column < $1.column }
        XCTAssertEqual(bassRow[3].root, 0)          // C in the middle
        XCTAssertEqual(bassRow[4].root, 7)          // G to its right
        let am = Stradella.button(for: "Am", in: b)!
        XCTAssertEqual(am.row, .minor)
        XCTAssertEqual(Set(am.notes.map { $0 % 12 }), [9, 0, 4])
        XCTAssertEqual(Stradella.button(for: "G7", in: b)?.row, .seventh)
    }
}

final class BellowsTests: XCTestCase {
    func testOpeningIsPullAndSpeedIsPressure() {
        var m = BellowsModel()
        var t = 0.0
        var a = 90.0
        for _ in 0..<30 { t += 1.0 / 60; a += 1.5; m.feed(position: a, at: t) }   // 90°/s opening
        XCTAssertEqual(m.direction, .pull)
        XCTAssertGreaterThan(m.pressure, 0.6)
        let fast = m.pressure

        var slow = BellowsModel()
        t = 0; a = 90
        for _ in 0..<30 { t += 1.0 / 60; a += 0.3; slow.feed(position: a, at: t) }   // 18°/s
        XCTAssertLessThan(slow.pressure, fast)
        XCTAssertGreaterThan(slow.pressure, 0.05)
    }

    func testClosingIsPush() {
        var m = BellowsModel()
        var t = 0.0, a = 170.0
        for _ in 0..<20 { t += 0.02; a -= 2; m.feed(position: a, at: t) }
        XCTAssertEqual(m.direction, .push)
        XCTAssertGreaterThan(m.pressure, 0.5)
    }

    func testStopsWhenSamplesStop() {
        var m = BellowsModel()
        var t = 0.0, a = 90.0
        for _ in 0..<20 { t += 0.016; a += 1.6; m.feed(position: a, at: t) }
        XCTAssertGreaterThan(m.pressure, 0.5)
        for _ in 0..<30 { t += 0.016; m.tick(at: t) }
        XCTAssertLessThan(m.pressure, 0.02)
        XCTAssertEqual(m.direction, .pull)     // still bellows keep their direction
    }

    func testTremorIsSilent() {
        var m = BellowsModel()
        var t = 0.0
        for i in 0..<60 { t += 0.016; m.feed(position: 120 + (i % 2 == 0 ? 0.02 : -0.02), at: t) }
        XCTAssertLessThan(m.pressure, 0.01)
    }

    func testSparseSamplesStillWork() {
        // The system decides the sample rate; 10 Hz updates must still give pressure.
        var m = BellowsModel()
        var t = 0.0, a = 60.0
        for _ in 0..<8 { t += 0.1; a += 8; m.feed(position: a, at: t); m.tick(at: t) }
        XCTAssertGreaterThan(m.pressure, 0.4)
    }
}

final class SongTests: XCTestCase {
    func testParser() {
        let n = SongParser.parse("[C] C4 D4:.5 | R:1 [G7] F#4:2")
        XCTAssertEqual(n.count, 4)
        XCTAssertEqual(n[0], SongNote(pitch: 60, beats: 1, chord: "C"))
        XCTAssertEqual(n[1], SongNote(pitch: 62, beats: 0.5, chord: nil))
        XCTAssertNil(n[2].pitch)
        XCTAssertEqual(n[3].chord, "G7")
    }

    func testEverySongParsesAndFitsTheBoards() {
        let chromatic = TrebleLayout.chromatic.buttons(perRow: 8, low: 60).filter { $0.row < 3 }
        for s in SongBook.all {
            XCTAssertGreaterThan(s.playable.count, 10, s.id)
            XCTAssertLessThanOrEqual(s.range.upperBound - s.range.lowerBound, 22, s.id)
            XCTAssertNotNil(LessonPlan.make(song: s, buttons: chromatic, bisonoric: false), "\(s.id) does not fit")
            for chord in s.notes.compactMap(\.chord) {
                XCTAssertNotNil(Stradella.button(for: chord, in: Stradella.buttons(columns: 12)), "\(s.id): \(chord)")
            }
        }
        XCTAssertEqual(SongBook.all.filter(\.isFree).count, 9)
        XCTAssertEqual(Set(SongBook.all.map(\.id)).count, SongBook.all.count)
    }

    func testDiatonicTransposesIntoItsKeys() {
        let diatonic = TrebleLayout.diatonic.buttons(perRow: 10)
        let plan = LessonPlan.make(song: SongBook.song("ode")!, buttons: diatonic, bisonoric: true)
        XCTAssertNotNil(plan)
        XCTAssertTrue(plan!.steps.allSatisfy { $0.direction != nil })
        for st in plan!.steps {
            let b = diatonic.first { $0.id == st.buttonID }!
            XCTAssertEqual(b.pitch(st.direction!), st.pitch)
        }
    }

    func testLessonProgress() {
        let s = SongBook.song("scale")!
        let plan = LessonPlan.make(song: s, buttons: TrebleLayout.chromatic.buttons(perRow: 8, low: 55), bisonoric: false)!
        var p = LessonProgress(plan: plan)
        XCTAssertEqual(p.sounded(pitch: plan.steps[0].pitch), .advanced)
        XCTAssertEqual(p.sounded(pitch: plan.steps[0].pitch), .ignored)    // still ringing
        XCTAssertEqual(p.sounded(pitch: 30), .wrong)
        while let c = p.current { _ = p.sounded(pitch: c.pitch) }
        XCTAssertTrue(p.finished)
        XCTAssertEqual(p.stars, 3)
    }
}

/// Renders the real synth graph offline: a held note with air must be audible, and silent without air.
final class AudioTests: XCTestCase {
    func testNoteWithAirIsAudible() throws {
        let e = ReedEngine()
        try e.startOffline()
        e.setRegister(.musette)
        e.setVoice(.classic)
        e.pressure = 0.6
        e.press(1, notes: [60], side: .treble)
        _ = try e.renderOfflineRMS(frames: 4096)            // attack
        let rms = try e.renderOfflineRMS(frames: 4096)
        XCTAssertGreaterThan(rms, 0.01, "held note with air should sound (rms \(rms))")
        XCTAssertLessThan(rms, 0.9, "no clipping wall (rms \(rms))")
    }

    func testNoAirIsSilent() throws {
        let e = ReedEngine()
        try e.startOffline()
        e.pressure = 0
        e.press(1, notes: [60], side: .treble)
        _ = try e.renderOfflineRMS(frames: 4096)
        let rms = try e.renderOfflineRMS(frames: 4096)
        XCTAssertLessThan(rms, 0.003)
    }

    func testChordAndBassSound() throws {
        let e = ReedEngine()
        try e.startOffline()
        e.pressure = 0.5
        e.press(10_005, notes: [36, 48], side: .bass)
        e.press(1, notes: [60, 64, 67], side: .treble)
        _ = try e.renderOfflineRMS(frames: 4096)
        XCTAssertGreaterThan(try e.renderOfflineRMS(frames: 4096), 0.01)
    }
}

@MainActor
final class AirTests: XCTestCase {
    func testButtonsSoundWithoutAHinge() {
        UserDefaults.standard.removeObject(forKey: "pumpOnly")
        UserDefaults.standard.removeObject(forKey: "steadyAir")
        let inst = Instrument()
        XCTAssertFalse(inst.hasHinge)
        XCTAssertTrue(inst.automaticAir, "an iPhone without a hinge must not need pumping to make sound")
        inst.hingeChanged(angle: 120, closed: false, present: true)
        XCTAssertFalse(inst.automaticAir, "an open iPhone Duo pumps with the hinge")
        inst.hingeChanged(angle: 0, closed: true, present: true)
        XCTAssertTrue(inst.automaticAir, "a folded Duo plays like any iPhone")
    }
}
