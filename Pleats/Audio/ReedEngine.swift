import AVFoundation

/// A free-reed synthesizer on AVAudioEngine. Everything is synthesized here: band-limited wavetables per voice,
/// several detuned reeds per note (the register), a pressure-driven level and brightness, a little breath noise,
/// a soft saturation and a short room reverb. No samples, so no licences to worry about.
///
/// Threading: the main thread writes note gates, frequencies and parameters into shared memory; the audio render
/// block reads them. Single aligned Float/Int32 writes are atomic on arm64, which is all this needs.
final class ReedEngine {
    static let shared = ReedEngine()

    static let maxVoices = 40
    static let maxReeds = 4
    static let tableSize = 2048
    static let bands = 9

    enum Side: Int32 { case treble = 0, bass = 1 }

    struct VoiceShared {
        var gate: Float = 0         // 1 while the button is held
        var freq: Float = 440
        var side: Int32 = 0
        var busy: Float = 0         // written by the render block: 1 while still sounding
    }

    struct VoiceRT {
        var phase: (Double, Double, Double, Double) = (0, 0, 0, 0)
        var env: Float = 0
        var lp: Float = 0
        var lp2: Float = 0
        var drift: Float = 0        // slow random tuning wander, as a fraction of pitch
    }

    struct Params {
        var pressure: Float = 0                   // target, 0…1
        var trebleFactor: (Float, Float, Float, Float) = (1, 1, 1, 1)
        var trebleGain: (Float, Float, Float, Float) = (1, 0, 0, 0)
        var trebleCount: Int32 = 1
        var bassFactor: (Float, Float, Float, Float) = (1, 0.5, 1, 1)
        var bassGain: (Float, Float, Float, Float) = (0.8, 0.5, 0, 0)
        var bassCount: Int32 = 2
        var voice: Int32 = 0
        var brightness: Float = 7500
        var air: Float = 0.01
        var master: Float = 0.2
        var bassLevel: Float = 0.8
    }

    let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let reverb = AVAudioUnitReverb()
    private let body = AVAudioUnitEQ(numberOfBands: 4)
    private let voices: UnsafeMutablePointer<VoiceShared>
    private let rt: UnsafeMutablePointer<VoiceRT>
    private let params: UnsafeMutablePointer<Params>
    private let tables: UnsafeMutablePointer<Float>
    private var sampleRate: Double = 48_000

    /// Button id → voices it holds.
    private var held: [Int: [Int]] = [:]
    private var started = false

    // Recording
    private var recordFile: AVAudioFile?
    private let recordLock = NSLock()
    private(set) var recordingURL: URL?

    private init() {
        voices = .allocate(capacity: Self.maxVoices)
        voices.initialize(repeating: VoiceShared(), count: Self.maxVoices)
        rt = .allocate(capacity: Self.maxVoices)
        rt.initialize(repeating: VoiceRT(), count: Self.maxVoices)
        params = .allocate(capacity: 1)
        params.initialize(to: Params())
        let count = Voice.allCases.count * Self.bands * Self.tableSize
        tables = .allocate(capacity: count)
        tables.initialize(repeating: 0, count: count)
        buildTables(sampleRate: 48_000)
    }

    // MARK: Wavetables

    /// One table per voice and per frequency band; band b serves fundamentals up to 27.5·2^(b+1) Hz and holds only
    /// the harmonics that stay below 45 % of the sample rate there, so nothing aliases.
    private func buildTables(sampleRate sr: Double) {
        let n = Self.tableSize
        for (vi, voice) in Voice.allCases.enumerated() {
            for b in 0..<Self.bands {
                let top = 27.5 * pow(2, Double(b + 1))
                let maxH = max(1, Int(sr * 0.45 / top))
                let base = tables + (vi * Self.bands + b) * n
                var peak: Float = 0
                for i in 0..<n {
                    let x = Double(i) / Double(n) * 2 * .pi
                    var s = 0.0
                    for h in 1...min(maxH, 80) {
                        // Alternate phases a little so the wave is not a pure sawtooth spike.
                        s += voice.harmonic(h) * sin(Double(h) * x + Double(h % 3) * 0.7)
                    }
                    base[i] = Float(s)
                    peak = max(peak, abs(Float(s)))
                }
                if peak > 0 { for i in 0..<n { base[i] /= peak } }
            }
        }
    }

    // MARK: Engine

    func start() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.004)
        try? session.setActive(true)

        let hwRate = session.sampleRate > 0 ? session.sampleRate : 48_000
        if abs(hwRate - sampleRate) > 1 {
            sampleRate = hwRate
            buildTables(sampleRate: hwRate)
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let render = Self.makeRender(voices: voices, rt: rt, params: params, tables: tables, sampleRate: sampleRate)
        source = AVAudioSourceNode(format: format, renderBlock: render)
        engine.attach(source)
        engine.attach(body)
        engine.attach(reverb)
        // The wooden body and reed blocks: a little warmth, the nasal "box" resonance around 1.2 kHz, a softer top.
        let bands: [(AVAudioUnitEQFilterType, Float, Float, Float)] = [
            (.highPass, 55, 0, 0.7), (.parametric, 240, 1.5, 1.0), (.parametric, 1250, 2.5, 1.4), (.highShelf, 6500, -5, 0.7),
        ]
        for (i, b) in bands.enumerated() {
            let band = body.bands[i]
            band.filterType = b.0
            band.frequency = b.1
            band.gain = b.2
            band.bandwidth = b.3
            band.bypass = false
        }
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 18
        engine.connect(source, to: body, format: format)
        engine.connect(body, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        try? engine.start()
        started = true

        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended { self.resume() } else { self.allOff() }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.resume()
        }
    }

    func resume() {
        guard started, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        try? engine.start()
    }

    // MARK: Notes

    /// Starts the notes of a button. `id` must be unique per button (treble, bass and demo use separate ranges).
    func press(_ id: Int, notes: [Int], side: Side) {
        if held[id] != nil { retune(id, notes: notes); return }
        var got: [Int] = []
        for note in notes {
            guard let v = freeVoice(excluding: got) else { break }
            voices[v].side = side.rawValue
            voices[v].freq = Float(Pitch.frequency(Double(note)))
            voices[v].busy = 1
            voices[v].gate = 1
            got.append(v)
        }
        held[id] = got
    }

    func release(_ id: Int) {
        guard let vs = held.removeValue(forKey: id) else { return }
        for v in vs { voices[v].gate = 0 }
    }

    /// Changes the pitch of a held button (a bisonoric button when the bellows turn around).
    func retune(_ id: Int, notes: [Int]) {
        guard let vs = held[id] else { return }
        for (i, v) in vs.enumerated() where i < notes.count {
            voices[v].freq = Float(Pitch.frequency(Double(notes[i])))
        }
    }

    func allOff() {
        for id in Array(held.keys) { release(id) }
    }

    var holding: Bool { !held.isEmpty }

    private func freeVoice(excluding: [Int]) -> Int? {
        let taken = Set(held.values.flatMap { $0 }).union(excluding)
        // A silent voice first, then a released one that is still ringing out.
        if let v = (0..<Self.maxVoices).first(where: { !taken.contains($0) && voices[$0].gate == 0 && voices[$0].busy == 0 }) { return v }
        return (0..<Self.maxVoices).first(where: { !taken.contains($0) && voices[$0].gate == 0 })
    }

    // MARK: Parameters

    var pressure: Double {
        get { Double(params.pointee.pressure) }
        set { params.pointee.pressure = Float(max(0, min(1, newValue))) }
    }

    func setRegister(_ r: Register) {
        let reeds = r.reeds
        var f: [Float] = [1, 1, 1, 1], g: [Float] = [0, 0, 0, 0]
        for (i, reed) in reeds.prefix(Self.maxReeds).enumerated() {
            f[i] = Float(reed.ratio * pow(2, reed.cents / 1200))
            g[i] = Float(reed.gain)
        }
        params.pointee.trebleFactor = (f[0], f[1], f[2], f[3])
        params.pointee.trebleGain = (g[0], g[1], g[2], g[3])
        params.pointee.trebleCount = Int32(min(reeds.count, Self.maxReeds))
    }

    func setVoice(_ v: Voice) {
        params.pointee.voice = Int32(Voice.allCases.firstIndex(of: v) ?? 0)
        params.pointee.brightness = Float(v.brightness)
        params.pointee.air = Float(v.air)
    }

    func setBassLevel(_ l: Double) { params.pointee.bassLevel = Float(l) }

    // MARK: Recording

    var isRecording: Bool { recordLock.lock(); defer { recordLock.unlock() }; return recordFile != nil }

    func startRecording(to url: URL) throws {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 160_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        recordLock.lock(); recordFile = file; recordLock.unlock()
        recordingURL = url
        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recordLock.lock()
            try? self.recordFile?.write(from: buffer)
            self.recordLock.unlock()
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        engine.mainMixerNode.removeTap(onBus: 0)
        recordLock.lock(); recordFile = nil; recordLock.unlock()   // releasing the file finishes the AAC stream
        let url = recordingURL
        recordingURL = nil
        return url
    }

    // MARK: Render

    private static func makeRender(voices: UnsafeMutablePointer<VoiceShared>, rt: UnsafeMutablePointer<VoiceRT>,
                                   params: UnsafeMutablePointer<Params>, tables: UnsafeMutablePointer<Float>,
                                   sampleRate: Double) -> AVAudioSourceNodeRenderBlock {
        let sr = Float(sampleRate)
        // Reeds take a moment to speak and stop a little softer than they start.
        let attack = 1 - exp(-1 / (0.016 * sr))
        let releaseK = 1 - exp(-1 / (0.05 * sr))
        let pressK = 1 - exp(-1 / (0.008 * sr))
        let tableSize = ReedEngine.tableSize
        let tableMask = tableSize - 1
        let bands = ReedEngine.bands
        let maxVoices = ReedEngine.maxVoices
        let voiceCount = Voice.allCases.count
        var smoothP: Float = 0
        var noiseSeed: UInt32 = 22222
        var noiseLP: Float = 0
        var dcPrev: Float = 0
        var dcOut: Float = 0

        // Per-reed state computed once per block.
        var incs = [Double](repeating: 0, count: maxVoices * 4)
        var offs = [Int](repeating: 0, count: maxVoices * 4)
        var gains = [Float](repeating: 0, count: maxVoices * 4)
        var counts = [Int](repeating: 0, count: maxVoices)

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            let p = params.pointee
            let voiceBase = Int(max(0, min(Int32(voiceCount - 1), p.voice))) * bands * tableSize

            // Block setup: phase increments and table bands for every sounding reed.
            var anyActive = false
            for v in 0..<maxVoices {
                let sh = voices[v]
                if sh.gate == 0 && rt[v].env < 0.00005 {
                    counts[v] = 0
                    if sh.busy != 0 { voices[v].busy = 0; rt[v].env = 0 }
                    continue
                }
                anyActive = true
                let treble = sh.side == 0
                let n = Int(treble ? p.trebleCount : p.bassCount)
                counts[v] = n
                noiseSeed = noiseSeed &* 1664525 &+ 1013904223
                let jitter = (Float(noiseSeed >> 8) / Float(1 << 24) - 0.5) * 0.00003
                rt[v].drift = max(-0.0004, min(0.0004, rt[v].drift * 0.999 + jitter))
                let wander = 1 + rt[v].drift
                for r in 0..<n {
                    let f = Double(sh.freq * (treble ? el(p.trebleFactor, r) : el(p.bassFactor, r)) * (r == 1 ? wander : 1 / wander))
                    incs[v * 4 + r] = f / Double(sr)
                    var b = Int(floor(log2(max(f, 27.5) / 27.5)))
                    b = max(0, min(bands - 1, b))
                    offs[v * 4 + r] = voiceBase + b * tableSize
                    gains[v * 4 + r] = treble ? el(p.trebleGain, r) : el(p.bassGain, r) * p.bassLevel
                }
            }

            if !anyActive {
                for i in 0..<frames { out[i] = 0 }
                smoothP += (p.pressure - smoothP) * min(1, pressK * Float(frames))
                for b in 1..<abl.count { if let d = abl[b].mData { memcpy(d, out, frames * 4) } }
                return noErr
            }

            for i in 0..<frames {
                smoothP += (p.pressure - smoothP) * pressK
                let amp = smoothP * smoothP.squareRoot() * 1.15      // p^1.5: soft dynamics
                let fc = p.brightness * (0.22 + 0.78 * smoothP)
                let lpK = min(0.99, 1 - exp(-2 * Float.pi * fc / sr))
                var mix: Float = 0
                var envSum: Float = 0
                for v in 0..<maxVoices {
                    let n = counts[v]
                    if n == 0 { continue }
                    let gate = voices[v].gate
                    var env = rt[v].env
                    env += (gate - env) * (gate > env ? attack : releaseK)
                    rt[v].env = env
                    var s: Float = 0
                    for r in 0..<n {
                        let k = v * 4 + r
                        var ph: Double
                        switch r {
                        case 0: ph = rt[v].phase.0
                        case 1: ph = rt[v].phase.1
                        case 2: ph = rt[v].phase.2
                        default: ph = rt[v].phase.3
                        }
                        let pos = ph * Double(tableSize)
                        let i0 = Int(pos) & tableMask
                        let frac = Float(pos - floor(pos))
                        let t = tables + offs[k]
                        let a = t[i0], b = t[(i0 + 1) & tableMask]
                        s += (a + (b - a) * frac) * gains[k]
                        ph += incs[k]
                        if ph >= 1 { ph -= 1 }
                        switch r {
                        case 0: rt[v].phase.0 = ph
                        case 1: rt[v].phase.1 = ph
                        case 2: rt[v].phase.2 = ph
                        default: rt[v].phase.3 = ph
                        }
                    }
                    // Two one-pole low-passes: softer pressure, darker reed.
                    var lp = rt[v].lp
                    lp += (s - lp) * lpK
                    var lp2 = rt[v].lp2
                    lp2 += (lp - lp2) * lpK
                    rt[v].lp = lp
                    rt[v].lp2 = lp2
                    let bassTrim: Float = voices[v].side == 1 ? 0.9 : 1
                    mix += lp2 * env * bassTrim
                    envSum += env
                }
                // Breath noise while air flows through open reeds.
                noiseSeed = noiseSeed &* 1664525 &+ 1013904223
                let white = Float(Int32(bitPattern: noiseSeed)) / Float(Int32.max)
                noiseLP += (white - noiseLP) * 0.18
                mix += noiseLP * p.air * min(1, envSum) * 6

                var x = mix * amp * p.master
                // Remove DC, then soft-saturate (rational tanh).
                dcOut = x - dcPrev + 0.995 * dcOut
                dcPrev = x
                x = dcOut
                let x2 = x * x
                x = x * (27 + x2) / (27 + 9 * x2)
                out[i] = max(-1, min(1, x))
            }
            for b in 1..<abl.count { if let d = abl[b].mData { memcpy(d, out, frames * 4) } }
            return noErr
        }
    }
}

@inline(__always)
private func el(_ t: (Float, Float, Float, Float), _ i: Int) -> Float {
    switch i {
    case 0: return t.0
    case 1: return t.1
    case 2: return t.2
    default: return t.3
    }
}
