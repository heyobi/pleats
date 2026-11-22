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
        GeometryReader { proxy in
            let size = proxy.size
            let fold = foldFrame(proxy).flatMap { f -> CGRect? in (f.width > 0 || f.height > 0) ? f : nil }
            let vertical = fold.map { $0.height >= $0.width } ?? (size.width >= size.height)
            let splitAt: CGFloat = fold.map { vertical ? $0.midX : $0.midY } ?? (vertical ? size.width / 2 : size.height / 2)
            let top = max(proxy.safeAreaInsets.top, 8) + 52
            let maxStrip: CGFloat = min(112, max(58, (vertical ? size.width : size.height) * 0.09))
            let strip = maxStrip * CGFloat(0.55 + 0.45 * inst.extension01)
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

                // Controls.
                VStack(spacing: 8) {
                    ControlBar(sheet: $sheet, showRegisters: $showRegisters)
                        .padding(.horizontal, 10)
                        .padding(.top, max(proxy.safeAreaInsets.top, 8))
                    if showRegisters {
                        RegisterTray(show: $showRegisters, sheet: $sheet)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if inst.lesson != nil, !showRegisters {
                        LessonBanner()
                            .frame(maxWidth: 560)
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
            VStack(spacing: 0) {
                Text("Pleats")
                    .font(.system(size: 22, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(theme.trim)
                Text(inst.register.name)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(theme.subtle)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
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

struct LessonBanner: View {
    @EnvironmentObject var inst: Instrument
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let theme = Theme.of(scheme)
        if let l = inst.lesson {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.plan.song.title)
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    ProgressView(value: l.fraction).tint(theme.trim)
                }
                if let c = l.current {
                    HStack(spacing: 4) {
                        if let d = c.direction {
                            Image(systemName: d == .pull ? "arrow.left.and.right.square" : "arrow.right.and.line.vertical.and.arrow.left")
                                .foregroundStyle(d == .pull ? theme.glow : theme.pushGlow)
                        }
                        Text(Pitch.name(c.pitch))
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(theme.glow)
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Next note \(Pitch.name(c.pitch))"))
                    if inst.pressure < 0.05 && !inst.pressedTreble.isEmpty {
                        Text(inst.hasHinge && !inst.hingeClosed ? LocalizedStringKey("Pump the hinge") : LocalizedStringKey("Move the bellows"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.subtle)
                    }
                }
                Button { inst.demoPlaying ? inst.stopDemo() : inst.playDemo() } label: {
                    Image(systemName: inst.demoPlaying ? "stop.fill" : "ear").brassControl(theme)
                }
                .accessibilityLabel(inst.demoPlaying ? Text("Stop listening") : Text("Listen"))
                Button { inst.restartLesson() } label: { Image(systemName: "arrow.counterclockwise").brassControl(theme) }
                    .accessibilityLabel(Text("Start over"))
                Button { inst.endLesson() } label: { Image(systemName: "xmark").brassControl(theme) }
                    .accessibilityLabel(Text("Close song"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.trim.opacity(0.45), lineWidth: 1))
            .padding(.horizontal, 12)
            .sensoryFeedback(.error, trigger: inst.lessonFeedback == .wrong ? l.mistakes : 0)
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
                                 : "The strip in the middle is the bellows.")
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
