import SwiftUI

/// Where the buttons of one side go. Rows run along the panel's long side; row 0 is nearest the bellows, the lowest
/// note at the top (or the left), like the keyboard of a button accordion.
struct BoardLayout {
    enum Near { case leading, trailing, top, bottom }

    let size: CGSize
    let rows: Int
    let perRow: Int
    let spacing: CGFloat
    let diameter: CGFloat
    let vertical: Bool
    let near: Near
    let stagger: CGFloat        // along-row offset per row, in spacings
    let wrapStagger: Bool       // alternate offsets (lattice) instead of a cumulative slant

    static func treble(_ size: CGSize, layout: TrebleLayout, near: Near) -> BoardLayout {
        // Rows run parallel to the bellows, like on the instrument.
        let vertical = near == .leading || near == .trailing
        let major = vertical ? size.height : size.width
        let minor = vertical ? size.width : size.height
        var rows: Int
        var s: CGFloat
        switch layout {
        case .chromatic:
            // Five rows when the panel is deep enough for buttons as large as the length allows; else three.
            let along = min(82, major / 7.6)
            rows = minor >= 5 * 0.9 * along ? 5 : 3
            s = min(max(min(minor / CGFloat(rows) / 0.9, 82), 46), major / 7.6)
        case .diatonic:
            rows = 2
            s = min(max(min(minor / 2.6, 92), 50), major / 8.6)
        }
        s = max(s, 42)
        let maxN = layout == .chromatic ? 14 : 10
        let n = max(5, min(maxN, Int(major / s - 0.6)))
        return BoardLayout(size: size, rows: rows, perRow: n, spacing: s, diameter: s * 0.8, vertical: vertical, near: near,
                           stagger: 0.5, wrapStagger: true)
    }

    static func bass(_ size: CGSize, near: Near) -> BoardLayout {
        let vertical = near == .leading || near == .trailing
        let major = vertical ? size.height : size.width
        let minor = vertical ? size.width : size.height
        var s = min(max(min(minor / 4 / 0.9, 66), 40), major / 7.4)
        s = max(s, 38)
        let n = max(3, min(12, Int((major - 1.2 * s) / s)))
        return BoardLayout(size: size, rows: 4, perRow: n, spacing: s, diameter: s * 0.74, vertical: vertical, near: near,
                           stagger: 0.33, wrapStagger: false)
    }

    func center(row: Int, column: Int) -> CGPoint {
        let major = vertical ? size.height : size.width
        let minor = vertical ? size.width : size.height
        let maxOffset = wrapStagger ? stagger : stagger * CGFloat(rows - 1)
        let length = CGFloat(perRow - 1) * spacing + maxOffset * spacing
        let start = (major - length) / 2
        let off = wrapStagger ? (row % 2 == 1 ? stagger : 0) : stagger * CGFloat(row)
        let along = start + (CGFloat(column) + off) * spacing
        let gap = spacing * 0.9
        let block = CGFloat(rows - 1) * gap
        let first = (minor - block) / 2
        let nearLow = (near == .leading || near == .top)
        let across = nearLow ? first + CGFloat(row) * gap : minor - first - CGFloat(row) * gap
        return vertical ? CGPoint(x: across, y: along) : CGPoint(x: along, y: across)
    }

    /// Index of the button under a point, if the point is close enough to its centre.
    func hit<T>(_ p: CGPoint, in items: [T], position: (T) -> CGPoint) -> Int? {
        var best: (Int, CGFloat)?
        let limit = spacing * 0.52
        for (i, it) in items.enumerated() {
            let c = position(it)
            let d = hypot(c.x - p.x, c.y - p.y)
            if d < limit, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }
}

/// The treble (right hand) side.
struct TrebleBoard: View {
    @EnvironmentObject var inst: Instrument
    @Environment(\.colorScheme) var scheme
    let near: BoardLayout.Near

    var body: some View {
        GeometryReader { geo in
            let lay = BoardLayout.treble(geo.size, layout: inst.layout, near: near)
            let buttons = inst.treble
            let theme = Theme.of(scheme)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: inst.lesson == nil && inst.demoButton == nil)) { tl in
                let pulse = (sin(tl.date.timeIntervalSinceReferenceDate * 5) + 1) / 2
                Canvas { ctx, _ in
                    let target = inst.lesson?.current
                    let next = inst.lesson?.upcoming
                    for b in buttons where b.column < lay.perRow {
                        let c = lay.center(row: b.row, column: b.column)
                        let pitch = inst.pitch(of: b)
                        let pressed = inst.pressedTreble.contains(b.id) || inst.demoButton == b.id
                        let ebony = inst.layout == .chromatic && Pitch.isAccidental(pitch)
                        PearlPainter.draw(&ctx, center: c, diameter: lay.diameter, ebony: ebony, pressed: pressed, theme: theme)
                        if inst.noteNames {
                            let label = Text(Pitch.name(pitch))
                                .font(.system(size: lay.diameter * 0.3, weight: .semibold, design: .serif))
                                .foregroundColor(ebony ? Color(white: 0.85) : Color(red: 0.35, green: 0.27, blue: 0.22))
                            ctx.draw(label, at: c)
                        }
                        if let t = target, t.buttonID == b.id {
                            let color = t.direction == .push ? theme.pushGlow : theme.glow
                            PearlPainter.glow(&ctx, center: c, diameter: lay.diameter, color: color, strength: 1, pulse: pulse)
                        } else if let n = next, n.buttonID == b.id {
                            PearlPainter.glow(&ctx, center: c, diameter: lay.diameter, color: theme.glow, strength: 0.28, pulse: 0)
                        }
                        if inst.demoButton == b.id {
                            PearlPainter.glow(&ctx, center: c, diameter: lay.diameter, color: theme.glow, strength: 0.9, pulse: 0.5)
                        }
                    }
                }
            }
            .overlay(TouchPad { points in
                var ids = Set<Int>()
                let visible = buttons.filter { $0.column < lay.perRow }
                for p in points {
                    if let i = lay.hit(p, in: visible, position: { lay.center(row: $0.row, column: $0.column) }) { ids.insert(visible[i].id) }
                }
                inst.setTreble(ids)
            })
            .onAppear { inst.configure(perRow: lay.perRow, bassColumns: inst.bass.isEmpty ? 7 : inst.bass.count / 4, rows: lay.rows) }
            .onChange(of: lay.perRow) { _, n in inst.configure(perRow: n, bassColumns: inst.bass.count / 4, rows: lay.rows) }
            .onChange(of: lay.rows) { _, r in inst.configure(perRow: lay.perRow, bassColumns: inst.bass.count / 4, rows: r) }
            .accessibilityElement()
            .accessibilityLabel(Text("Treble buttons"))
            .accessibilityHint(Text("Touch buttons while moving the bellows to play notes."))
        }
    }
}

/// The bass (left hand) side: bass notes and chords.
struct BassBoard: View {
    @EnvironmentObject var inst: Instrument
    @Environment(\.colorScheme) var scheme
    let near: BoardLayout.Near

    var body: some View {
        GeometryReader { geo in
            let lay = BoardLayout.bass(geo.size, near: near)
            let buttons = inst.bass
            let theme = Theme.of(scheme)
            let hint = inst.lesson.flatMap { l -> String? in
                // The chord in force at the current step.
                var c: String?
                for i in 0...min(l.index, max(0, l.plan.chords.count - 1)) where i < l.plan.chords.count {
                    if let x = l.plan.chords[i] { c = x }
                }
                return c
            }
            let hintButton = hint.flatMap { Stradella.button(for: transposed($0, by: inst.lesson?.plan.transpose ?? 0), in: buttons) }
            Canvas { ctx, _ in
                for b in buttons where b.column < lay.perRow {
                    let c = lay.center(row: b.row.rawValue, column: b.column)
                    let pressed = inst.pressedBass.contains(b.id)
                    PearlPainter.draw(&ctx, center: c, diameter: lay.diameter, ebony: false, pressed: pressed, theme: theme)
                    if b.row == .bass && (b.root == 0 || b.root == 4 || b.root == 8) {
                        // Guide studs: a jewel on C, small rings on E and A♭, as on real bass boards.
                        let r: CGFloat = b.root == 0 ? lay.diameter * 0.07 : lay.diameter * 0.045
                        let dot = CGRect(x: c.x - r, y: c.y + lay.diameter * 0.3 - r, width: 2 * r, height: 2 * r)
                        if b.root == 0 {
                            ctx.fill(Path(ellipseIn: dot), with: .color(theme.trim))
                        } else {
                            ctx.stroke(Path(ellipseIn: dot), with: .color(theme.trimDark.opacity(0.8)), lineWidth: 1)
                        }
                    }
                    if inst.noteNames {
                        let label = Text(b.label)
                            .font(.system(size: lay.diameter * (b.row == .bass ? 0.34 : 0.27), weight: b.row == .bass ? .bold : .medium, design: .serif))
                            .foregroundColor(Color(red: 0.35, green: 0.27, blue: 0.22))
                        ctx.draw(label, at: CGPoint(x: c.x, y: c.y - (b.row == .bass && b.root % 4 == 0 ? lay.diameter * 0.07 : 0)))
                    }
                    if let h = hintButton, h.id == b.id {
                        PearlPainter.glow(&ctx, center: c, diameter: lay.diameter, color: Color(white: 0.92), strength: 0.55, pulse: 0)
                    }
                }
            }
            .overlay(TouchPad { points in
                var ids = Set<Int>()
                let visible = buttons.filter { $0.column < lay.perRow }
                for p in points {
                    if let i = lay.hit(p, in: visible, position: { lay.center(row: $0.row.rawValue, column: $0.column) }) { ids.insert(visible[i].id) }
                }
                inst.setBass(ids)
            })
            .onAppear { inst.configure(perRow: max(5, inst.treble.count / max(1, inst.trebleRows)), bassColumns: lay.perRow) }
            .onChange(of: lay.perRow) { _, n in inst.configure(perRow: max(5, inst.treble.count / max(1, inst.trebleRows)), bassColumns: n) }
            .accessibilityElement()
            .accessibilityLabel(Text("Bass and chord buttons"))
        }
    }

    private func transposed(_ chord: String, by k: Int) -> String {
        guard k % 12 != 0 else { return chord }
        var root = chord
        var suffix = ""
        if root.hasSuffix("7") || root.hasSuffix("m") { suffix = String(root.removeLast()) }
        guard let p = Pitch.parse(root + "4") else { return chord }
        return Pitch.name(p + k).replacingOccurrences(of: "♯", with: "#") + suffix
    }
}
