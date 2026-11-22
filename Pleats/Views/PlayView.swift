import SwiftUI
import StoreKit

enum Sheet: String, Identifiable {
    case songs, settings, recordings, paywall
    var id: String { rawValue }
}

/// The whole instrument on one screen: bass board, bellows across the fold, treble board, and a slim control bar.
struct PlayView: View {
    @EnvironmentObject var inst: Instrument
    @EnvironmentObject var store: Store
    @EnvironmentObject var recorder: Recorder
    @Environment(\.colorScheme) var scheme
    @Environment(\.requestReview) private var requestReview
    @State private var sheet: Sheet?
    @State private var showRegisters = false
    @AppStorage("seenHint") private var seenHint = false
    @State private var showHint = false

    var body: some View {
        let theme = Theme.of(scheme)
        GeometryReader { safe in
        let safeTop = safe.safeAreaInsets.top
        GeometryReader { proxy in
            let size = proxy.size
            let fold = foldFrame(proxy).flatMap { f -> CGRect? in (f.width > 0 || f.height > 0) ? f : nil }
            let vertical = fold.map { $0.height >= $0.width } ?? (size.width >= size.height)
            let splitAt: CGFloat = fold.map { vertical ? $0.midX : $0.midY } ?? (vertical ? size.width / 2 : size.height / 2)
            let top = max(safeTop, 8) + 52 + (inst.lesson != nil ? 60 : 0)
            let maxStrip: CGFloat = min(150, max(72, (vertical ? size.width : size.height) * 0.14))
            let strip = 24 + (maxStrip - 24) * CGFloat(inst.extension01)
            let pad: CGFloat = 6
            let inner = maxStrip / 2 + 4

            ZStack(alignment: .topLeading) {
                theme.bodyBottom.ignoresSafeArea()

                // Bass side.
                let bassRect = vertical
                    ? CGRect(x: pad, y: top, width: splitAt - inner - pad, height: size.height - top - pad)
                    : CGRect(x: pad, y: top, width: size.width - 2 * pad, height: splitAt - inner - top)
                let trebleRect = vertical
                    ? CGRect(x: splitAt + inner, y: top, width: size.width - splitAt - inner - pad, height: size.height - top - pad)
                    : CGRect(x: pad, y: splitAt + inner, width: size.width - 2 * pad, height: size.height - splitAt - inner - pad)

                panel(theme, rect: bassRect) {
                    BassBoard(near: vertical ? .trailing : .bottom).padding(10)
                }
                panel(theme, rect: trebleRect) {
                    TrebleBoard(near: vertical ? .leading : .top).padding(10)
                }

                // Bellows.
                let stripRect = vertical
                    ? CGRect(x: splitAt - strip / 2, y: top - 4, width: strip, height: size.height - top + 4)
                    : CGRect(x: 0, y: splitAt - strip / 2, width: size.width, height: strip)
                BellowsView(extension01: inst.extension01, pressure: inst.pressure, direction: inst.direction,
                            vertical: vertical, theme: theme)
                    .frame(width: stripRect.width, height: stripRect.height)
                    .offset(x: stripRect.minX, y: stripRect.minY)
                    .allowsHitTesting(false)
                    .shadow(color: .black.opacity(0.4), radius: 6)

                let padRect = vertical ? stripRect.insetBy(dx: -14, dy: 0) : stripRect.insetBy(dx: 0, dy: -14)
                BellowsPad(vertical: !vertical) { d in inst.dragBellows(by: Double(vertical ? d : -d)) }
                    .frame(width: padRect.width, height: padRect.height)
                    .offset(x: padRect.minX, y: padRect.minY)
                    .accessibilityLabel(Text("Bellows"))
                    .accessibilityHint(Text("Drag back and forth to pump air."))

                if !inst.hasHinge || inst.hingeClosed {
                    dragHint(theme, vertical: vertical)
                        .position(x: stripRect.midX, y: stripRect.midY)
                        .allowsHitTesting(false)
                }
                if inst.needsPumpHint && inst.lesson == nil {
                    Label(inst.pumpsWithHinge ? LocalizedStringKey("Open and close the hinge to play") : LocalizedStringKey("Drag the bellows to play"),
                          systemImage: vertical ? "arrow.left.and.right" : "arrow.up.and.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().stroke(theme.trim.opacity(0.6), lineWidth: 1))
                        .position(x: stripRect.midX, y: vertical ? size.height * 0.62 : stripRect.midY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Controls.
                VStack(spacing: 8) {
                    ControlBar(sheet: $sheet, showRegisters: $showRegisters)
                        .padding(.horizontal, 10)
                        .padding(.top, max(safeTop, 8))
                    if inst.lesson != nil {
                        LessonBar()
                            .frame(height: 52)
                            .padding(.horizontal, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if showRegisters {
                        RegisterTray(show: $showRegisters, sheet: $sheet)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .frame(width: size.width, height: size.height)

                if showHint {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { dismissHint() }
                    HintCard(hasHinge: inst.hasHinge) { dismissHint() }
                        .frame(maxWidth: 420)
                        .position(x: size.width / 2, y: size.height / 2)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                if let done = inst.finishedLesson {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ResultCard(progress: done, sheet: $sheet) { askForReview(done.stars) }
                        .frame(maxWidth: 400)
                        .position(x: size.width / 2, y: size.height / 2)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: showRegisters)
            .animation(.spring(duration: 0.35), value: inst.lesson?.plan.song.id)
            .animation(.spring(duration: 0.4), value: inst.finishedLesson != nil)
        }
        .ignoresSafeArea()
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .modifier(HingeReader(instrument: inst))
        .sheet(item: $sheet) { s in
            Group {
                switch s {
                case .songs: SongsSheet(sheet: $sheet)
                case .settings: SettingsSheet(sheet: $sheet)
                case .recordings: RecordingsSheet(sheet: $sheet)
                case .paywall: PaywallSheet()
                }
            }
            .environmentObject(inst).environmentObject(store).environmentObject(recorder)
        }
        .onAppear {
            inst.start()
            if !seenHint && !ShotsTour.active { showHint = true }
        }
        .onChange(of: inst.shotRegisters) { _, v in showRegisters = v }
        .onChange(of: inst.shotSheet) { _, v in sheet = v }
        .onChange(of: store.pro) { _, pro in
            if !pro {
                if !inst.register.isFree { inst.registerRaw = Register.musette.rawValue }
                if !inst.voice.isFree { inst.voiceRaw = Voice.classic.rawValue }
            }
        }
    }

    private func panel<C: View>(_ theme: Theme, rect: CGRect, @ViewBuilder content: () -> C) -> some View {
        ZStack {
            BodyPanel(theme: theme)
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.trim.opacity(0.35), lineWidth: 1))
        .frame(width: max(0, rect.width), height: max(0, rect.height))
        .offset(x: rect.minX, y: rect.minY)
    }

    private func dragHint(_ theme: Theme, vertical: Bool) -> some View {
        Image(systemName: vertical ? "arrow.left.and.right" : "arrow.up.and.down")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.bellowsEdge.opacity(0.85))
            .padding(8)
            .background(Circle().fill(.black.opacity(0.35)))
    }

    private func dismissHint() {
        withAnimation { showHint = false }
        seenHint = true
    }

    private func askForReview(_ stars: Int) {
        if ReviewGate.shouldAsk(stars: stars) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                requestReview()
            }
        }
    }
}

// MARK: - Control bar

struct ControlBar: View {
    @EnvironmentObject var inst: Instrument
    @EnvironmentObject var recorder: Recorder
    @Environment(\.colorScheme) var scheme
    @Binding var sheet: Sheet?
    @Binding var showRegisters: Bool

    var body: some View {
        let theme = Theme.of(scheme)
        HStack(spacing: 10) {
            Button { sheet = .songs } label: { Image(systemName: "music.note.list").brassControl(theme, active: inst.lesson != nil) }
                .accessibilityLabel(Text("Songs"))
            Button { recorder.toggle() } label: {
                Image(systemName: recorder.recording ? "stop.fill" : "record.circle")
                    .foregroundStyle(recorder.recording ? Color.red : theme.ink)
                    .brassControl(theme)
            }
            .accessibilityLabel(recorder.recording ? Text("Stop recording") : Text("Record"))
            if recorder.recording {
                Text(timeString(recorder.elapsed))
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Button { sheet = .recordings } label: { Image(systemName: "waveform").brassControl(theme) }
                    .accessibilityLabel(Text("Recordings"))
            }
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                VStack(spacing: 0) {
                    if let l = inst.lesson {
                        Text(l.plan.song.title)
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                        ProgressView(value: l.fraction).tint(theme.trim).frame(width: 120)
                    } else {
                        Text("Pleats")
                            .font(.system(size: 22, weight: .semibold, design: .serif).italic())
                            .foregroundStyle(theme.trim)
                        Text(inst.register.name)
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(theme.subtle)
                    }
                }
                .fixedSize()
                Color.clear.frame(width: 1, height: 1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Group {
                // One switch for air without pumping: Easy air without a hinge, Steady air on an open iPhone Duo.
                let on = inst.pumpsWithHinge ? inst.steadyAir : inst.easyAir
                Button {
                    if inst.pumpsWithHinge { inst.steadyAir.toggle() } else { inst.easyAir.toggle() }
                    Haptics.shared.button()
                } label: {
                    Text(inst.pumpsWithHinge ? LocalizedStringKey("Steady air") : LocalizedStringKey("Easy air"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? theme.bodyBottom : theme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Capsule().fill(on ? AnyShapeStyle(theme.trim) : AnyShapeStyle(.ultraThinMaterial)))
                        .overlay(Capsule().stroke(theme.trim.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Easy air"))
                .accessibilityValue(on ? Text("On: buttons sound without pumping") : Text("Off: move the bellows to play"))
            }
            Button { showRegisters.toggle() } label: {
                RegisterSymbol(register: inst.register, theme: theme).frame(width: 26, height: 26).brassControl(theme, active: showRegisters)
            }
            .accessibilityLabel(Text("Registers"))
            .accessibilityValue(Text(inst.register.name))
            Button { sheet = .settings } label: { Image(systemName: "slider.horizontal.3").brassControl(theme) }
                .accessibilityLabel(Text("Settings"))
        }
        .frame(height: 44)
    }

    private func timeString(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The classic register symbol: a circle with dots for the reed banks that sound.
struct RegisterSymbol: View {
    var register: Register
    var theme: Theme

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 1
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(theme.ink), lineWidth: 1.4)
            var l1 = Path(); l1.move(to: CGPoint(x: c.x - r * 0.94, y: c.y - r * 0.33)); l1.addLine(to: CGPoint(x: c.x + r * 0.94, y: c.y - r * 0.33))
            var l2 = Path(); l2.move(to: CGPoint(x: c.x - r * 0.94, y: c.y + r * 0.33)); l2.addLine(to: CGPoint(x: c.x + r * 0.94, y: c.y + r * 0.33))
            ctx.stroke(l1, with: .color(theme.ink.opacity(0.5)), lineWidth: 0.8)
            ctx.stroke(l2, with: .color(theme.ink.opacity(0.5)), lineWidth: 0.8)
            let d = r * 0.3
            func dot(_ x: CGFloat, _ y: CGFloat) {
                ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(theme.ink))
            }
            let dots = register.dots
            if dots.high { dot(c.x, c.y - r * 0.64) }
            if dots.low { dot(c.x, c.y + r * 0.64) }
            switch dots.middle {
            case 1: dot(c.x, c.y)
            case 2: dot(c.x - r * 0.3, c.y); dot(c.x + r * 0.3, c.y)
            case 3: dot(c.x - r * 0.5, c.y); dot(c.x, c.y); dot(c.x + r * 0.5, c.y)
            default: break
            }
        }
    }
}

struct RegisterTray: View {
    @EnvironmentObject var inst: Instrument
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) var scheme
    @Binding var show: Bool
    @Binding var sheet: Sheet?

    var body: some View {
        let theme = Theme.of(scheme)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Register.allCases) { r in
                    let locked = !r.isFree && !store.pro
                    Button {
                        if locked { sheet = .paywall; return }
                        inst.registerRaw = r.rawValue
                        Haptics.shared.button()
                    } label: {
                        VStack(spacing: 5) {
                            RegisterSymbol(register: r, theme: theme)
                                .frame(width: 34, height: 34)
                                .padding(7)
                                .background(Circle().fill(inst.register == r ? AnyShapeStyle(theme.trim.opacity(0.35)) : AnyShapeStyle(.clear)))
                                .overlay(alignment: .topTrailing) {
                                    if locked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(theme.trim) }
                                }
                            Text(r.name).font(.system(size: 11, weight: .medium, design: .serif)).foregroundStyle(theme.ink)
                        }
                        .opacity(locked ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(r.name))
                    .accessibilityAddTraits(inst.register == r ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.trim.opacity(0.5), lineWidth: 1))
        .frame(maxWidth: 640)
        .padding(.horizontal, 12)
    }
}

// MARK: - Lesson banner

/// The song row under the control bar. It has its own space, so it never covers buttons.
struct LessonBar: View {
    @EnvironmentObject var inst: Instrument
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) var sizeClass
    /// Narrow screens (iPhone in portrait): the mode labels stay whole; the hint and Start over make room.
    private var compact: Bool { sizeClass == .compact && UIScreen.main.bounds.width < 500 }

    var body: some View {
        let theme = Theme.of(scheme)
        if let l = inst.lesson {
            HStack(spacing: 8) {
                // Two clearly named modes.
                HStack(spacing: 0) {
                    modeButton("Play along", icon: "hand.point.up.left", on: !inst.demoPlaying, theme: theme) { inst.stopDemo() }
                    modeButton("Listen", icon: "ear", on: inst.demoPlaying, theme: theme) { inst.playDemo() }
                }
                .fixedSize()
                .background(Capsule().fill(.black.opacity(0.25)))
                .overlay(Capsule().stroke(theme.trim.opacity(0.5), lineWidth: 1))
                ZStack(alignment: .leading) {
                    RhythmStrip(progress: l, theme: theme)
                    if !inst.seenLessonHint && !inst.demoPlaying && !compact {
                        Text("Press the glowing button. Listen plays the song for you first.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else if inst.needsPumpHint {
                        Text(inst.pumpsWithHinge ? LocalizedStringKey("Pump the hinge") : LocalizedStringKey("Move the bellows"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                }
                .frame(maxWidth: .infinity)
                if !compact {
                    Button { inst.restartLesson() } label: { Image(systemName: "arrow.counterclockwise").brassControl(theme) }
                        .accessibilityLabel(Text("Start over"))
                }
                Button { inst.endLesson() } label: { Image(systemName: "xmark").brassControl(theme) }
                    .accessibilityLabel(Text("Close song"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.trim.opacity(0.4), lineWidth: 1))
            .sensoryFeedback(.error, trigger: inst.lessonFeedback == .wrong ? l.mistakes : 0)
        }
    }

    private func modeButton(_ title: LocalizedStringKey, icon: String, on: Bool, theme: Theme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .foregroundStyle(on ? theme.bodyBottom : theme.ink)
                .background(Capsule().fill(on ? AnyShapeStyle(theme.trim) : AnyShapeStyle(Color.clear)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The notes ahead as bars: the length shows how long to hold, a gap and a dot mark a repeated note, the current
/// note glows.
struct RhythmStrip: View {
    let progress: LessonProgress
    let theme: Theme

    private var currentNote: Int {
        var step = 0
        for (i, n) in progress.plan.song.notes.enumerated() where n.pitch != nil {
            if step == progress.index { return i }
            step += 1
        }
        return progress.plan.song.notes.count
    }

    var body: some View {
        let notes = progress.plan.song.notes
        let current = currentNote
        let start = max(0, current - 1)
        let end = min(notes.count, start + 14)
        GeometryReader { geo in
            let unit = max(18, min(34, geo.size.width / 9))
            HStack(spacing: 3) {
                ForEach(start..<end, id: \.self) { i in
                    bar(notes: notes, i: i, current: current, unit: unit)
                }
            }
            .frame(height: geo.size.height, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: progress.index)
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(Text("Upcoming notes"))
    }

    @ViewBuilder
    private func bar(notes: [SongNote], i: Int, current: Int, unit: CGFloat) -> some View {
        let n = notes[i]
        let w = max(16, CGFloat(n.beats) * unit)
        if let p = n.pitch {
            let isCurrent = i == current
            let past = i < current
            let repeated = i > 0 && notes[i - 1].pitch == p
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isCurrent ? AnyShapeStyle(theme.glow) : AnyShapeStyle(theme.ink.opacity(past ? 0.12 : 0.28)))
                .overlay(alignment: .leading) {
                    Text(Pitch.name(p + progress.plan.transpose))
                        .font(.system(size: 11, weight: .bold, design: .serif))
                        .foregroundStyle(isCurrent ? theme.bodyBottom : theme.ink.opacity(past ? 0.4 : 0.9))
                        .padding(.leading, 4)
                        .lineLimit(1)
                        .fixedSize()
                }
                .overlay(alignment: .topTrailing) {
                    if repeated && !past {
                        Circle().fill(theme.ink.opacity(0.8)).frame(width: 4, height: 4).padding(3)
                    }
                }
                .frame(width: w, height: isCurrent ? 30 : 24)
        } else {
            Color.clear.frame(width: w, height: 24)
        }
    }
}

// MARK: - Cards

struct ResultCard: View {
    @EnvironmentObject var inst: Instrument
    @Environment(\.colorScheme) var scheme
    let progress: LessonProgress
    @Binding var sheet: Sheet?
    var onShown: () -> Void

    var body: some View {
        let theme = Theme.of(scheme)
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Image(systemName: i < progress.stars ? "star.fill" : "star")
                        .font(.system(size: 34))
                        .foregroundStyle(theme.glow)
                        .symbolEffect(.bounce, value: progress.stars)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("\(progress.stars) of 3 stars"))
            Text(progress.stars == 3 ? LocalizedStringKey("Beautifully played!") : LocalizedStringKey("Song complete!"))
                .font(.system(.title2, design: .serif).weight(.semibold))
            Text(progress.plan.song.title)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.secondary)
            Text(progress.mistakes == 0 ? LocalizedStringKey("Not a single slip.") : LocalizedStringKey("\(progress.mistakes) slips"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { inst.restartLesson() } label: { Label("Again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button { inst.endLesson(); sheet = .songs } label: { Label("More songs", systemImage: "music.note.list").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.trim)
            }
            Button("Free play") { inst.endLesson() }
                .font(.subheadline)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(theme.trim.opacity(0.6), lineWidth: 1))
        .padding(20)
        .sensoryFeedback(.success, trigger: progress.plan.song.id)
        .onAppear(perform: onShown)
    }
}

struct HintCard: View {
    @Environment(\.colorScheme) var scheme
    var hasHinge: Bool
    var done: () -> Void

    var body: some View {
        let theme = Theme.of(scheme)
        VStack(alignment: .leading, spacing: 14) {
            Text("How to play")
                .font(.system(.title2, design: .serif).weight(.semibold))
            row("book", hasHinge ? "Hold iPhone Duo like a book, half open. The fold is the bellows."
                                 : "Just press a button to play. The strip in the middle is the bellows.")
            row("arrow.left.and.right", hasHinge ? "Open and close the hinge to pump air. Faster is louder; both directions sound."
                                                 : "Drag it back and forth to pump air. Faster is louder; both directions sound.")
            row("circle.grid.3x3.fill", "Treble buttons on one side, bass and chords on the other. Play as many as you like at once.")
            row("music.note.list", "Songs light up the next button for you. Take your time; the song waits.")
            Button(action: done) { Text("Start playing").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .tint(theme.trim)
                .controlSize(.large)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(theme.trim.opacity(0.6), lineWidth: 1))
        .padding(20)
    }

    private func row(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(Theme.of(scheme).trim)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}
