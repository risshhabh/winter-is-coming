import AVFoundation
import WinterCore

/// Plays the sleigh bells. All sound is synthesized at start-up by `BellSynth`; there are no audio
/// files and no network use.
///
/// The engine only runs while there is something to hear: it starts on the first movement after
/// sound is switched on and stops a few seconds after the cursor comes to rest, so the app does not
/// hold the output device open. It plays through the normal system mix and never changes the system
/// volume, the output device, or any other app's audio.
final class BellAudio {
    static let voices = 4
    static let variants = 8

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: BellSynth.sampleRate, channels: 1)!
    private let shimmer = AVAudioPlayerNode()
    private var players: [AVAudioPlayerNode] = []
    private var bells: [AVAudioPCMBuffer] = []
    private var loop: AVAudioPCMBuffer!
    private var running = false
    private var idle = 0.0
    private var next = 0

    /// 0...1 from the volume slider. Full volume is still quiet by design.
    var volume = 0.5 { didSet { engine.mainMixerNode.outputVolume = Float(volume * 0.7) } }

    init() {
        loop = buffer(BellSynth.shimmerLoop())
        bells = (0..<BellAudio.variants).map { buffer(BellSynth.bell(variant: $0)) }
        engine.attach(shimmer)
        engine.connect(shimmer, to: engine.mainMixerNode, format: format)
        for _ in 0..<BellAudio.voices {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = Float(volume * 0.7)
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            b.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return b
    }

    private func start() -> Bool {
        if running { return true }
        do { try engine.start() } catch {
            print("❄︎ Sleigh bells unavailable: \(error.localizedDescription)")
            return false
        }
        shimmer.volume = 0
        shimmer.scheduleBuffer(loop, at: nil, options: .loops)
        shimmer.play()
        running = true
        return true
    }

    /// Silence now: used when sound is switched off, muted, or the cursor effect is disabled
    func stop() {
        guard running else { return }
        shimmer.stop()
        for p in players { p.stop() }
        engine.stop()
        running = false
        idle = 0
    }

    /// Called every simulation step with the sequencer's output
    func update(dt: Double, shimmerGain: Double, event: BellEvent?) {
        if shimmerGain <= 0, event == nil {
            idle += dt
            if idle > 4 { stop() }
            if running { shimmer.volume = 0 }
            return
        }
        idle = 0
        guard start() else { return }
        shimmer.volume = Float(shimmerGain * 0.22)
        if let e = event {
            // Four voices, each capped well below full scale, so overlaps cannot add up to anything loud
            let p = players[next]
            next = (next + 1) % players.count
            p.volume = Float(e.gain * 0.4)
            p.pan = Float(e.pan)
            p.scheduleBuffer(bells[e.variant % bells.count], at: nil, options: .interrupts)
            p.play()
        }
    }

    /// Plays every bell in turn, then the shimmer rising and falling, for listening tests
    func audition(done: @escaping () -> Void) {
        guard start() else { done(); return }
        for i in 0..<BellAudio.variants {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.6) { [self] in
                update(dt: 0.01, shimmerGain: 0, event: BellEvent(variant: i, gain: 0.8, pan: Double(i % 3 - 1) * 0.5))
                idle = 0
            }
        }
        let t0 = 0.5 + Double(BellAudio.variants) * 0.6
        for k in 0..<120 {
            DispatchQueue.main.asyncAfter(deadline: .now() + t0 + Double(k) * 0.05) { [self] in
                let x = Double(k) / 120
                update(dt: 0.05, shimmerGain: sin(x * .pi), event: nil)
                idle = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + t0 + 6.5) { [self] in
            stop()
            done()
        }
    }
}
