import SwiftUI
import QuartzCore

/// The playing state of the accordion: settings, bellows, held buttons, the song lesson and the link to the audio
/// engine and haptics. Views read it; touch surfaces and the hinge write to it.
@MainActor
final class Instrument: ObservableObject {
    // Settings (persisted)
    @AppStorage("layout") var layoutRaw = TrebleLayout.chromatic.rawValue { didSet { rebuild() } }
    @AppStorage("register") var registerRaw = Register.musette.rawValue { didSet { applySound() } }
    @AppStorage("voice") var voiceRaw = Voice.classic.rawValue { didSet { applySound() } }
    @AppStorage("noteNames") var noteNames = true
    @AppStorage("steadyAir") var steadyAir = false
    /// Easy air: without a working hinge, pressing a button supplies air by itself and dragging the bellows only adds
    /// dynamics. Off, the bellows work like a real accordion: no movement, no sound. On by default for a first run.
    @AppStorage("easyAir") var easyAir = true
    @AppStorage("sensitivity") var sensitivity = 1.0 { didSet { bellows.fullScale = 110 / max(0.3, sensitivity) } }
    @AppStorage("bassLevel") var bassLevel = 0.8 { didSet { ReedEngine.shared.setBassLevel(bassLevel) } }

    var layout: TrebleLayout { TrebleLayout(rawValue: layoutRaw) ?? .chromatic }
    var register: Register { Register(rawValue: registerRaw) ?? .musette }
    var voice: Voice { Voice(rawValue: voiceRaw) ?? .classic }

    // Board
    @Published private(set) var treble: [TrebleButton] = []
    @Published private(set) var bass: [BassButton] = []
    private var perRow = 8
    private var bassColumns = 7
    private var visibleRows = 5

    // Bellows / hinge
    @Published private(set) var hasHinge = false
    @Published private(set) var hingeClosed = false
    @Published private(set) var angle: Double = 120          // degrees, real or virtual
    @Published private(set) var extension01: Double = 0.55   // how far the bellows are drawn, for the picture
    @Published private(set) var pressure: Double = 0
    @Published private(set) var direction: BellowsDirection = .pull
    private var bellows = BellowsModel()
    private var virtualPosition = 0.0
    private var link: CADisplayLink?
    /// Screenshot tour: a fixed bellows picture and pressure.
    var frozen = false

    // Held buttons
    @Published private(set) var pressedTreble: Set<Int> = []
    @Published private(set) var pressedBass: Set<Int> = []
    private var sounding: Set<Int> = []

    // Lesson
    @Published var lesson: LessonProgress?
    @Published var lessonFeedback: LessonProgress.Result?
    @Published var finishedLesson: LessonProgress?
    @Published private(set) var demoPlaying = false
    /// The button hit last in Play along, and when, for a one-shot pulse on the board.
    @Published private(set) var lastHit: (button: Int, at: Double)?
    @AppStorage("seenLessonHint") var seenLessonHint = false
    private var demoTask: Task<Void, Never>?
    @Published private(set) var demoButton: Int?

    // Screenshot tour only.
    @Published var forcedScheme: ColorScheme?
    @Published var shotRegisters = false
    @Published var shotSheet: Sheet?

    // Hinge sample log for the simulator probe (screenshots workflow).
    var hingeLog: [(t: Double, a: Double)] = []
    var logHinge = false

    static let trebleIDBase = 0
    static let bassIDBase = 10_000
    static let demoIDBase = 20_000

    init() {
        bellows.fullScale = 110 / max(0.3, sensitivity)
        rebuild()
    }

    func start() {
        ReedEngine.shared.start()
        applySound()
        ReedEngine.shared.setBassLevel(bassLevel)
        if link == nil {
            let l = CADisplayLink(target: LinkTarget { [weak self] in self?.frame() }, selector: #selector(LinkTarget.fire))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    private func applySound() {
        ReedEngine.shared.setRegister(register)
        ReedEngine.shared.setVoice(voice)
    }

    // MARK: Board

    /// Called by the board views when their size gives room for a different number of buttons.
    func configure(perRow: Int, bassColumns: Int, rows: Int? = nil) {
        let r = rows ?? visibleRows
        guard perRow != self.perRow || bassColumns != self.bassColumns || r != visibleRows || treble.isEmpty else { return }
        self.perRow = perRow
        self.bassColumns = bassColumns
        self.visibleRows = r
        rebuild()
    }

    var trebleRows: Int { min(layout.rows, visibleRows) }

    private func rebuild() {
        releaseAll()
        let span = 3 * (perRow - 1) + 4
        let low = max(48, 72 - span / 2)
        treble = layout.buttons(perRow: perRow, low: low).filter { $0.row < visibleRows }
        bass = Stradella.buttons(columns: bassColumns)
        if let l = lesson { startLesson(l.plan.song, keepProgress: l.index) }
    }

    // MARK: Hinge and bellows

    func hingeChanged(angle a: Double, closed: Bool, present: Bool) {
        if present { hasHinge = true }
        hingeClosed = closed
        let now = CACurrentMediaTime()
        if logHinge { hingeLog.append((now, a)) }
        guard !frozen else { return }
        angle = a
        extension01 = max(0, min(1, (a - 20) / 160))
        if bellows.feed(position: a, at: now) { directionChanged() }
        updateAir()
    }

    /// Drag on the bellows strip (no hinge, or by choice). `delta` in points along the pull direction.
    /// Points of drag for the full travel of the manual bellows, closed to fully drawn.
    static let bellowsTravel = 280.0

    /// Drag on the bellows strip (no hinge, or by choice). `delta` in points; positive draws the bellows open.
    /// Like a real accordion the bellows have ends: at fully closed or fully drawn, more drag moves no air, so the
    /// player has to turn around. The bellows model sees the travel as degrees, the same unit as the hinge.
    func dragBellows(by delta: Double) {
        guard !frozen else { return }
        let manual = !pumpsWithHinge
        if manual {
            extension01 = max(0, min(1, extension01 + delta / Self.bellowsTravel))
            virtualPosition = extension01 * 160
        } else {
            virtualPosition += delta * 0.45
        }
        if bellows.feed(position: virtualPosition, at: CACurrentMediaTime()) { directionChanged() }
        updateAir()
    }

    private func frame() {
        guard !frozen else { return }
        if bellows.tick(at: CACurrentMediaTime()) { directionChanged() }
        updateAir()
    }

    private func directionChanged() {
        direction = bellows.direction
        guard layout.bisonoric else { return }
        // Bisonoric: the held buttons now sound their other reed.
        for id in pressedTreble {
            if let b = treble.first(where: { $0.id == id }) {
                ReedEngine.shared.retune(Self.trebleIDBase + id, notes: [b.pitch(direction)])
            }
        }
        if !pressedTreble.isEmpty { Haptics.shared.reverse() }
        sounding.removeAll()     // new pitches: let the lesson hear them
    }

    /// True when air comes from the hinge: an iPhone Duo that is open.
    var pumpsWithHinge: Bool { hasHinge && !hingeClosed }

    /// Air arrives without moving anything: steady air, or a device without a usable hinge.
    var automaticAir: Bool { steadyAir || (!pumpsWithHinge && easyAir) }

    /// Shown when buttons are held on an open iPhone Duo but the hinge has not moved for a while.
    @Published private(set) var needsPumpHint = false
    private var silentHoldSince: Double?

    private func updateAir() {
        let holding = !pressedTreble.isEmpty || !pressedBass.isEmpty
        var p = bellows.pressure
        if automaticAir { p = max(p, 0.58) }
        if demoPlaying { p = max(p, 0.6) }
        if frozen { return }
        if abs(p - pressure) > 0.004 { pressure = p }
        ReedEngine.shared.pressure = p
        Haptics.shared.air(holding && !automaticAir ? p : 0)
        // On a Duo, a held button with a still hinge for over a second earns a gentle hint.
        let now = CACurrentMediaTime()
        if holding && p < 0.04 {
            if silentHoldSince == nil { silentHoldSince = now }
            if !needsPumpHint, let s = silentHoldSince, now - s > 1.0 { needsPumpHint = true }
        } else {
            silentHoldSince = nil
            if needsPumpHint && p > 0.1 { needsPumpHint = false }
        }
        listen()
    }

    // MARK: Buttons

    func setTreble(_ ids: Set<Int>) {
        guard ids != pressedTreble else { return }
        let added = ids.subtracting(pressedTreble)
        let removed = pressedTreble.subtracting(ids)
        for id in removed { ReedEngine.shared.release(Self.trebleIDBase + id) }
        for id in added {
            guard let b = treble.first(where: { $0.id == id }) else { continue }
            ReedEngine.shared.press(Self.trebleIDBase + id, notes: [b.pitch(direction)], side: .treble)
        }
        if !added.isEmpty { Haptics.shared.button() }
        pressedTreble = ids
        listen()
    }

    func setBass(_ ids: Set<Int>) {
        guard ids != pressedBass else { return }
        let added = ids.subtracting(pressedBass)
        let removed = pressedBass.subtracting(ids)
        for id in removed { ReedEngine.shared.release(Self.bassIDBase + id) }
        for id in added {
            guard let b = bass.first(where: { $0.id == id }) else { continue }
            ReedEngine.shared.press(Self.bassIDBase + id, notes: b.notes, side: .bass)
        }
        if !added.isEmpty { Haptics.shared.button() }
        pressedBass = ids
    }

    func releaseAll() {
        ReedEngine.shared.allOff()
        pressedTreble = []
        pressedBass = []
        sounding = []
    }

    /// Pitch a treble button sounds right now.
    func pitch(of b: TrebleButton) -> Int { b.pitch(direction) }

    // MARK: Lesson

    /// The lesson hears a note when its button is down and air flows.
    private func listen() {
        let air = pressure > 0.05
        let now: Set<Int> = air ? Set(pressedTreble.compactMap { id in treble.first { $0.id == id }.map { $0.pitch(direction) } }) : []
        let new = now.subtracting(sounding)
        sounding = now
        guard var l = lesson, !demoPlaying, !new.isEmpty, !l.finished else { return }
        for p in new.sorted() {
            let target = l.current
            let r = l.sounded(pitch: p)
            if r != .ignored { lessonFeedback = r }
            if r == .advanced, let t = target {
                lastHit = (t.buttonID, CACurrentMediaTime())
                Haptics.shared.hit()
                seenLessonHint = true
            }
            if l.finished { break }
        }
        lesson = l
        if l.finished {
            finishedLesson = l
            SongProgress.shared.record(song: l.plan.song.id, stars: l.stars)
        }
    }

    func startLesson(_ song: Song, keepProgress: Int = 0) {
        stopDemo()
        guard let plan = LessonPlan.make(song: song, buttons: treble, bisonoric: layout.bisonoric) else {
            lesson = nil
            return
        }
        var l = LessonProgress(plan: plan)
        for _ in 0..<min(keepProgress, plan.steps.count) { _ = l.sounded(pitch: l.current!.pitch) }
        lesson = l
        finishedLesson = nil
    }

    func restartLesson() {
        guard var l = lesson else { return }
        stopDemo()
        l.restart()
        lesson = l
        finishedLesson = nil
    }

    func endLesson() {
        stopDemo()
        lesson = nil
        finishedLesson = nil
        lessonFeedback = nil
    }

    /// Plays the song once, lighting the buttons, at the song's tempo.
    func playDemo() {
        guard let l = lesson else { return }
        stopDemo()
        releaseAll()
        demoPlaying = true
        let plan = l.plan
        let beat = 60.0 / plan.song.tempo
        demoTask = Task { @MainActor [weak self] in
            var stepIndex = 0
            for n in plan.song.notes {
                guard let self, !Task.isCancelled else { return }
                let dur = n.beats * beat
                if n.pitch != nil, stepIndex < plan.steps.count {
                    let f = plan.steps[stepIndex]
                    stepIndex += 1
                    if let d = f.direction, d != self.direction { self.direction = d }
                    self.demoButton = f.buttonID
                    Haptics.shared.note(long: dur >= 0.6)
                    ReedEngine.shared.press(Self.demoIDBase, notes: [f.pitch], side: .treble)
                    try? await Task.sleep(nanoseconds: UInt64(dur * 0.88 * 1e9))
                    ReedEngine.shared.release(Self.demoIDBase)
                    try? await Task.sleep(nanoseconds: UInt64(dur * 0.12 * 1e9))
                } else {
                    self.demoButton = nil
                    try? await Task.sleep(nanoseconds: UInt64(dur * 1e9))
                }
            }
            self?.stopDemo()
        }
    }

    /// Settings › Test sound: a short C major chord with air, whatever the bellows are doing.
    func testSound() {
        start()
        demoPlaying = true
        ReedEngine.shared.press(Self.demoIDBase + 1, notes: [60, 64, 67], side: .treble)
        updateAir()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            ReedEngine.shared.release(Self.demoIDBase + 1)
            self?.demoPlaying = false
        }
    }

    func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        ReedEngine.shared.release(Self.demoIDBase)
        demoButton = nil
        if demoPlaying {
            demoPlaying = false
            direction = bellows.direction
        }
    }

    // MARK: Screenshot tour

    func showShot(angle a: Double, pressure p: Double, direction d: BellowsDirection) {
        frozen = true
        angle = a
        extension01 = max(0, min(1, (a - 20) / 160))
        pressure = p
        direction = d
    }

    func showPressed(treble t: Set<Int>, bass b: Set<Int>) {
        pressedTreble = t
        pressedBass = b
    }
}

/// CADisplayLink needs an NSObject target; this one forwards to a closure without retaining the instrument.
private final class LinkTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

/// Stars per song, and how many songs were finished (for the review prompt).
@MainActor
final class SongProgress: ObservableObject {
    static let shared = SongProgress()
    @Published private(set) var stars: [String: Int]

    private init() {
        stars = (UserDefaults.standard.dictionary(forKey: "stars") as? [String: Int]) ?? [:]
    }

    func record(song: String, stars s: Int) {
        stars[song] = max(stars[song] ?? 0, s)
        UserDefaults.standard.set(stars, forKey: "stars")
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "songsFinished") + 1, forKey: "songsFinished")
    }

    var finishedCount: Int { UserDefaults.standard.integer(forKey: "songsFinished") }
}
