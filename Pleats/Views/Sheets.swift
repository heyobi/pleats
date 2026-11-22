import SwiftUI

struct SongsSheet: View {
    @EnvironmentObject var inst: Instrument
    @EnvironmentObject var store: Store
    @ObservedObject private var progress = SongProgress.shared
    @Binding var sheet: Sheet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SongBook.all.filter(\.isFree)) { row($0) }
                } header: {
                    Text("Free songs")
                } footer: {
                    Text("Pick a song and the next button lights up. Play it with air from the bellows and the song moves on. Tap the ear to hear it first.")
                }
                Section {
                    ForEach(SongBook.all.filter { !$0.isFree }) { row($0) }
                } header: {
                    Text(store.pro ? LocalizedStringKey("Pro songs") : LocalizedStringKey("More with Pro"))
                }
            }
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } }
            }
        }
    }

    private func row(_ s: Song) -> some View {
        let locked = !s.isFree && !store.pro
        let playable = LessonPlan.make(song: s, buttons: inst.treble, bisonoric: inst.layout.bisonoric) != nil
        return Button {
            if locked { sheet = .paywall; return }
            inst.startLesson(s)
            sheet = nil
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.title).font(.system(.body, design: .serif).weight(.medium)).foregroundStyle(.primary)
                    Text(s.origin).font(.caption).foregroundStyle(.secondary)
                    if !playable {
                        Text("Needs the chromatic layout").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(0..<3) { i in
                        Circle().fill(i < s.difficulty ? Color.secondary : Color.secondary.opacity(0.2)).frame(width: 5, height: 5)
                    }
                }
                .accessibilityLabel(Text("Difficulty \(s.difficulty) of 3"))
                if locked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                } else if let st = progress.stars[s.id] {
                    HStack(spacing: 1) {
                        ForEach(0..<3) { i in Image(systemName: i < st ? "star.fill" : "star").font(.caption2) }
                    }
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("\(st) of 3 stars"))
                }
            }
        }
        .disabled(!playable && !locked)
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var inst: Instrument
    @EnvironmentObject var store: Store
    @Binding var sheet: Sheet?
    @AppStorage("haptics") private var haptics = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Keyboard") {
                    Picker("Treble layout", selection: $inst.layoutRaw) {
                        Text("Chromatic buttons").tag(TrebleLayout.chromatic.rawValue)
                        Text("Diatonic G/C (push–pull)").tag(TrebleLayout.diatonic.rawValue)
                    }
                    Toggle("Note names on buttons", isOn: $inst.noteNames)
                }
                Section {
                    ForEach(Voice.allCases) { v in
                        let locked = !v.isFree && !store.pro
                        Button {
                            if locked { sheet = .paywall } else { inst.voiceRaw = v.rawValue }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name).foregroundStyle(.primary)
                                    Text(v.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                                else if inst.voice == v { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                } header: { Text("Voice") }
                Section {
                    VStack(alignment: .leading) {
                        Text("Bellows sensitivity")
                        Slider(value: $inst.sensitivity, in: 0.5...2.0)
                    }
                    VStack(alignment: .leading) {
                        Text("Bass volume")
                        Slider(value: $inst.bassLevel, in: 0.2...1.2)
                    }
                    Toggle("Steady air", isOn: $inst.steadyAir)
                    if !inst.pumpsWithHinge {
                        Toggle("Easy air (buttons sound without pumping)", isOn: $inst.easyAir)
                    }
                    Toggle("Haptics", isOn: $haptics)
                } header: {
                    Text("Bellows")
                } footer: {
                    Text("Steady air keeps the reeds sounding without pumping, for practice or if moving the bellows is hard. With Easy air off, the bellows work like a real accordion: drag them open and closed to play, faster is louder.")
                }
                Section {
                    if store.pro {
                        Label("Pleats Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                    } else {
                        Button { sheet = .paywall } label: { Label("Get Pleats Pro", systemImage: "sparkles") }
                    }
                    Button("Restore purchase") { Task { await store.restore() } }
                } footer: {
                    if let m = store.message { Text(m) }
                }
                Section {
                    Link(destination: URL(string: "https://heyobi.github.io/pleats/")!) { Label("Website and privacy", systemImage: "globe") }
                    Button { inst.testSound() } label: { Label("Test sound", systemImage: "speaker.wave.2") }
                    LabeledContent("Audio", value: ReedEngine.shared.isRunning ? String(localized: "Running") : (ReedEngine.shared.lastError ?? String(localized: "Stopped")))
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                } footer: {
                    Text("No accounts, no ads, no tracking. Every sound is synthesized on your device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        }
    }
}

struct RecordingsSheet: View {
    @EnvironmentObject var recorder: Recorder
    @EnvironmentObject var store: Store
    @Binding var sheet: Sheet?

    var body: some View {
        NavigationStack {
            List {
                if recorder.clips.isEmpty {
                    ContentUnavailableView("No recordings yet", systemImage: "waveform",
                                           description: Text("Tap the record button, play, and tap it again. Your clip appears here."))
                }
                ForEach(recorder.clips) { c in
                    HStack(spacing: 12) {
                        Button { recorder.play(c) } label: {
                            Image(systemName: recorder.playing == c.url ? "stop.circle.fill" : "play.circle.fill").font(.title)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(recorder.playing == c.url ? Text("Stop") : Text("Play"))
                        VStack(alignment: .leading) {
                            Text(c.date, style: .date) + Text(" ") + Text(c.date, style: .time)
                            Text(Duration.seconds(c.duration).formatted(.time(pattern: .minuteSecond)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.pro {
                            ShareLink(item: c.url) { Image(systemName: "square.and.arrow.up") }
                                .accessibilityLabel(Text("Share"))
                        } else {
                            Button { sheet = .paywall } label: {
                                Label("Share", systemImage: "lock.fill").labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(Text("Share with Pro"))
                        }
                    }
                    .swipeActions { Button(role: .destructive) { recorder.delete(c) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { recorder.stopPlayback(); sheet = nil } } }
        }
        .onAppear { recorder.reload() }
    }
}

struct PaywallSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var inst: Instrument
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let theme = Theme.of(scheme)
        ScrollView {
            VStack(spacing: 18) {
                Text("Pleats Pro")
                    .font(.system(size: 34, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(theme.trim)
                    .padding(.top, 28)
                Text("Everything in Pleats, with one purchase.")
                    .font(.system(.headline, design: .serif))
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 12) {
                    feature("circle.grid.cross", "Five more registers: Violin, Bassoon, Piccolo, Organ and Master")
                    feature("waveform.path", "Three more voices: Cassotto, Harmonium and Folk")
                    feature("music.note.list", "Ten more songs: an original tango, The Entertainer, Greensleeves, Sarı Gelin and more")
                    feature("square.and.arrow.up", "Share and export your recordings")
                    feature("heart", "One purchase, yours for good. No subscription, no ads.")
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.thinMaterial))
                Text("The free instrument stays complete: three registers, the classic voice, nine songs and recording.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if store.pro && !inst.shotPaywall {
                    Label("Unlocked. Enjoy!", systemImage: "checkmark.seal.fill").font(.headline)
                } else {
                    Button {
                        Task { await store.buy() }
                    } label: {
                        Group {
                            if store.busy { ProgressView() }
                            else if let p = store.priceText { Text("Unlock for \(p)") }
                            else { Text("Unlock Pleats Pro") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.trim)
                    .controlSize(.large)
                    .disabled(store.busy)
                    Button("Restore purchase") { Task { await store.restore() } }
                        .font(.subheadline)
                }
                if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                Button("Not now") { dismiss() }.font(.subheadline).padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: store.pro) { _, pro in if pro { Task { try? await Task.sleep(nanoseconds: 900_000_000); dismiss() } } }
    }

    private func feature(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(Theme.of(scheme).trim)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}
