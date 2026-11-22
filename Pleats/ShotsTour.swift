import SwiftUI
import QuartzCore

/// App Store screenshot tour, only when launched with `-shots` (scripts/sim-shots.sh). Sets each screen up, writes
/// its name to Documents/shots/ready and waits for the script's answer in Documents/shots/next. A name ending in
/// "@<degrees>" asks the script to set the iPhone Duo simulator's hinge first; "@sweep" asks it to move the hinge
/// smoothly so the app can measure how often hinge angles arrive (written to hinge-rate.json).
@MainActor
struct ShotsTour {
    nonisolated static var active: Bool { ProcessInfo.processInfo.arguments.contains("-shots") }
    nonisolated static var outer: Bool { ProcessInfo.processInfo.arguments.contains("-shotsOuter") }

    let inst: Instrument

    private var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shots")
    }

    func run() async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("next"))
        UserDefaults.standard.set(true, forKey: "seenHint")
        try? await Task.sleep(for: .seconds(2))

        // Measure the hinge while the script sweeps it (iPhone Duo inner display only).
        if inst.hasHinge && !Self.outer {
            inst.logHinge = true
            inst.hingeLog = []
            await step("0-probe@sweep")
            inst.logHinge = false
            writeRate()
        }

        inst.registerRaw = Register.musette.rawValue
        inst.layoutRaw = TrebleLayout.chromatic.rawValue
        try? await Task.sleep(for: .seconds(1))

        // 1. Free play: a C major chord on both sides, bellows drawn.
        inst.forcedScheme = .dark
        inst.showShot(angle: 128, pressure: 0.7, direction: .pull)
        let chord = inst.treble.filter { [60, 64, 67].contains($0.push) && $0.row < 3 }
        var picked: [Int: TrebleButton] = [:]
        for b in chord where picked[b.push] == nil { picked[b.push] = b }
        let cMajor = inst.bass.filter { $0.root == 0 && ($0.row == .bass || $0.row == .major) }
        inst.showPressed(treble: Set(picked.values.map(\.id)), bass: Set(cMajor.map(\.id)))
        await step("1-play@128")

        // 2. Song lesson: Üsküdar'a Gider İken, a few notes in.
        inst.showPressed(treble: [], bass: [])
        if let s = SongBook.song("uskudar") {
            inst.startLesson(s, keepProgress: 9)
        }
        inst.showShot(angle: 140, pressure: 0.55, direction: .push)
        await step("2-lesson@140")

        // 3. Registers, in the light finish.
        inst.endLesson()
        inst.forcedScheme = .light
        inst.registerRaw = Register.master.rawValue
        inst.shotRegisters = true
        inst.showShot(angle: 115, pressure: 0.5, direction: .pull)
        await step("3-registers@115")
        inst.shotRegisters = false

        // 4. Song book.
        inst.forcedScheme = .dark
        inst.endLesson()
        inst.shotSheet = .songs
        await step("4-songs")
        inst.shotSheet = nil
        try? await Task.sleep(for: .seconds(1))

        // 5. A finished song.
        inst.forcedScheme = .light
        if let s = SongBook.song("yemen"), let plan = LessonPlan.make(song: s, buttons: inst.treble, bisonoric: false) {
            var p = LessonProgress(plan: plan)
            while let c = p.current { _ = p.sounded(pitch: c.pitch) }
            inst.lesson = p
            inst.finishedLesson = p
        }
        await step("5-done")
        inst.endLesson()

        // 6. Paywall, for the in-app purchase review image (not part of the store screenshots).
        inst.forcedScheme = .dark
        inst.shotPaywall = true
        inst.shotSheet = .paywall
        await step("6-paywall")
        inst.shotSheet = nil
        inst.shotPaywall = false
        write("ready", "done")
    }

    private func step(_ name: String) async {
        try? await Task.sleep(for: .seconds(2.5))
        write("ready", name)
        for _ in 0..<1200 {
            if let s = try? String(contentsOf: dir.appendingPathComponent("next"), encoding: .utf8), s == name { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// How often hinge angles arrived during the sweep: count, span, median gap and distinct values.
    private func writeRate() {
        let log = inst.hingeLog
        var json = "{\"samples\":\(log.count)"
        if log.count > 2 {
            let gaps = zip(log.dropFirst(), log).map { $0.t - $1.t }.sorted()
            let span = log.last!.t - log.first!.t
            let median = gaps[gaps.count / 2]
            let distinct = Set(log.map { ($0.a * 10).rounded() }).count
            let lo = log.map(\.a).min()!, hi = log.map(\.a).max()!
            json += String(format: ",\"spanSeconds\":%.3f,\"medianGapMs\":%.2f,\"maxGapMs\":%.2f,\"ratePerSecond\":%.1f,\"distinctAngles\":%d,\"minAngle\":%.2f,\"maxAngle\":%.2f",
                           span, median * 1000, gaps.last! * 1000, Double(log.count - 1) / max(span, 0.001), distinct, lo, hi)
            let firstAngles = log.prefix(40).map { String(format: "%.2f", $0.a) }.joined(separator: ",")
            json += ",\"firstAngles\":[\(firstAngles)]"
        }
        json += "}"
        write("hinge-rate.json", json)
    }

    private func write(_ file: String, _ text: String) {
        try? text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }
}
