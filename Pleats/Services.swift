import SwiftUI
import StoreKit
import AVFoundation

/// One-time Pro unlock (StoreKit 2): all registers and voices, the whole song book and recording export.
@MainActor
final class Store: ObservableObject {
    static let productID = "com.heyobi.pleats.pro"

    @Published private(set) var pro = UserDefaults.standard.bool(forKey: "pro")
    @Published private(set) var product: Product?
    @Published var busy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    init() {
        if ShotsTour.active { pro = true }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish(); await self?.refresh() }
            }
        }
        Task { await load(); await refresh() }
    }

    func load() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { owned = true }
        }
        if ShotsTour.active { owned = true }
        set(owned)
    }

    private func set(_ owned: Bool) {
        pro = owned
        UserDefaults.standard.set(owned, forKey: "pro")
    }

    func buy() async {
        if product == nil { await load() }
        guard let product else { message = String(localized: "The App Store is not reachable right now. Try again later."); return }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v { await t.finish(); set(true) }
            case .pending: message = String(localized: "The purchase is waiting for approval.")
            default: break
            }
        } catch {
            message = String(localized: "The purchase did not go through. Nothing was charged.")
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = pro ? String(localized: "Pleats Pro is unlocked.") : String(localized: "No earlier purchase was found for this Apple Account.")
    }

    /// Price text, hidden when StoreKit reports a currency that does not match the storefront (TestFlight quirk).
    var priceText: String? {
        guard let p = product else { return nil }
        return p.displayPrice
    }
}

/// Asks for an App Store rating only after a happy moment: a song finished with at least two stars, after the
/// second finished song, at most once per app version and never more than every four months.
enum ReviewGate {
    static func shouldAsk(stars: Int) -> Bool {
        guard !ShotsTour.active, stars >= 2 else { return false }
        let d = UserDefaults.standard
        guard d.integer(forKey: "songsFinished") >= 2 else { return false }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        if d.string(forKey: "reviewVersion") == version { return false }
        let last = d.double(forKey: "reviewAskedAt")
        if last > 0, Date().timeIntervalSince1970 - last < 120 * 86_400 { return false }
        d.set(version, forKey: "reviewVersion")
        d.set(Date().timeIntervalSince1970, forKey: "reviewAskedAt")
        return true
    }
}

/// Recorded clips (AAC in Documents/Recordings, also visible in the Files app).
@MainActor
final class Recorder: ObservableObject {
    struct Clip: Identifiable, Equatable {
        let url: URL
        let date: Date
        let duration: Double
        var id: URL { url }
        var title: String { url.deletingPathExtension().lastPathComponent }
    }

    @Published private(set) var recording = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var clips: [Clip] = []
    @Published private(set) var playing: URL?

    static let maxSeconds = 300.0
    private var startedAt: Date?
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var playerDelegate: PlayerDelegate?

    private var folder: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    init() { reload() }

    func toggle() { recording ? stop() : start() }

    func start() {
        stopPlayback()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = folder.appendingPathComponent("Pleats \(f.string(from: Date())).m4a")
        do {
            try ReedEngine.shared.startRecording(to: url)
        } catch {
            return
        }
        recording = true
        startedAt = Date()
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(s)
                if self.elapsed >= Self.maxSeconds { self.stop() }
            }
        }
    }

    func stop() {
        guard recording else { return }
        timer?.invalidate()
        timer = nil
        ReedEngine.shared.stopRecording()
        recording = false
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        clips = urls.filter { $0.pathExtension == "m4a" }.compactMap { u in
            let date = (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let dur = (try? AVAudioPlayer(contentsOf: u).duration) ?? 0
            return dur > 0.2 ? Clip(url: u, date: date, duration: dur) : nil
        }.sorted { $0.date > $1.date }
    }

    func play(_ c: Clip) {
        if playing == c.url { stopPlayback(); return }
        stopPlayback()
        player = try? AVAudioPlayer(contentsOf: c.url)
        let d = PlayerDelegate { [weak self] in Task { @MainActor in self?.playing = nil } }
        playerDelegate = d
        player?.delegate = d
        player?.play()
        playing = c.url
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playing = nil
    }

    func delete(_ c: Clip) {
        if playing == c.url { stopPlayback() }
        try? FileManager.default.removeItem(at: c.url)
        reload()
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let done: () -> Void
    init(_ done: @escaping () -> Void) { self.done = done }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { done() }
}
