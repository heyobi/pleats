import SwiftUI

@main
struct PleatsApp: App {
    @StateObject private var inst = Instrument()
    @StateObject private var store = Store()
    @StateObject private var recorder = Recorder()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            PlayView()
                .environmentObject(inst)
                .environmentObject(store)
                .environmentObject(recorder)
                .preferredColorScheme(inst.forcedScheme)
                .task {
                    if ShotsTour.active { await ShotsTour(inst: inst).run() }
                }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active: ReedEngine.shared.resume()
            case .background:
                inst.releaseAll()
                if recorder.recording { recorder.stop() }
            default: break
            }
        }
    }
}
