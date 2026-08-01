import Foundation
import AVFoundation

/// Cap-independent EV drive hum — loops from Cap www `public/assets/audio/loops/`.
/// Cap AudioEngine remains preferred when warm; this covers demo / cold Cap.
/// All AVAudioPlayer work stays on the main queue (AVFoundation requirement).
final class EtubuNativeDriveAudio {
    static let shared = EtubuNativeDriveAudio()

    private var bodyPlayer: AVAudioPlayer?
    private var humPlayer: AVAudioPlayer?
    private var running = false
    private var muted = false
    private var currentVoice = "calm-ev"
    private var lastKmh: Double = 0
    private var lastPower: Double = 0

    private init() {}

    /// Engine loaded (may be muted). Used so flushDrive doesn't restart/unmute.
    var isEngineAlive: Bool { running }

    /// Audible output (running and not muted).
    var isAudible: Bool { running && !muted }

    /// Legacy alias — means engine alive, not necessarily unmuted.
    var isRunning: Bool { isEngineAlive }

    func start(voice: String = "calm-ev") {
        let work = { [weak self] in
            guard let self else { return }
            let key = (voice.isEmpty || voice == "silent-mode") ? "calm-ev" : voice
            if self.running, self.currentVoice == key {
                if !self.muted {
                    self.applyParams(kmh: self.lastKmh, powerKw: self.lastPower)
                }
                return
            }
            self.stopPlayers()
            self.currentVoice = key
            // Do not clear mute here — caller decides via setMuted.
            AppDelegate.activateDriveAudioSession()
            let files = self.loopFiles(for: key)
            self.bodyPlayer = self.makeLoopPlayer(file: files.body, volume: 0.55)
            self.humPlayer = self.makeLoopPlayer(file: files.hum, volume: 0.28)
            self.running = self.bodyPlayer != nil || self.humPlayer != nil
            if self.muted {
                self.bodyPlayer?.volume = 0
                self.humPlayer?.volume = 0
                self.bodyPlayer?.pause()
                self.humPlayer?.pause()
            } else {
                self.bodyPlayer?.play()
                self.humPlayer?.play()
                self.applyParams(kmh: max(self.lastKmh, 28), powerKw: self.lastPower)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func setMuted(_ on: Bool) {
        let work = { [weak self] in
            guard let self else { return }
            self.muted = on
            if on {
                self.bodyPlayer?.volume = 0
                self.humPlayer?.volume = 0
                self.bodyPlayer?.pause()
                self.humPlayer?.pause()
            } else if self.running {
                self.bodyPlayer?.play()
                self.humPlayer?.play()
                self.applyParams(kmh: self.lastKmh, powerKw: self.lastPower)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func setSpeed(kmh: Int, powerKw: Int?) {
        let work = { [weak self] in
            guard let self else { return }
            self.lastKmh = Double(max(0, kmh))
            if let powerKw { self.lastPower = Double(powerKw) }
            guard self.running, !self.muted else { return }
            self.applyParams(kmh: self.lastKmh, powerKw: self.lastPower)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func stop() {
        let work = { [weak self] in
            guard let self else { return }
            self.stopPlayers()
            self.running = false
            self.muted = false
            self.lastKmh = 0
            self.lastPower = 0
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Internals

    private func stopPlayers() {
        bodyPlayer?.stop()
        humPlayer?.stop()
        bodyPlayer = nil
        humPlayer = nil
    }

    private func loopFiles(for voice: String) -> (body: String, hum: String) {
        switch voice {
        case "sport-ev", "asphalt-roar":
            return ("ev_modely_rev_body_loop.wav", "ev_hum_sport_loop.wav")
        case "model-y", "modely":
            return ("ev_modely_body_loop.wav", "ev_hum_soft_loop.wav")
        default:
            return ("ev_id3_body_loop.wav", "ev_hum_soft_loop.wav")
        }
    }

    private func makeLoopPlayer(file: String, volume: Float) -> AVAudioPlayer? {
        guard let url = urlForLoop(file) else { return nil }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.enableRate = true
            p.prepareToPlay()
            p.volume = volume
            p.rate = 1.0
            return p
        } catch {
            return nil
        }
    }

    private func urlForLoop(_ file: String) -> URL? {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension.isEmpty ? "wav" : (file as NSString).pathExtension
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "public/assets/audio/loops"),
            Bundle.main.resourceURL?.appendingPathComponent("public/assets/audio/loops/\(file)"),
            Bundle.main.bundleURL.appendingPathComponent("public/assets/audio/loops/\(file)"),
        ]
        for c in candidates {
            if let u = c, FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    private func applyParams(kmh: Double, powerKw: Double) {
        let feel = max(0, kmh)
        let rate = Float(min(1.22, max(0.86, 0.88 + feel / 220)))
        bodyPlayer?.rate = rate
        humPlayer?.rate = min(1.15, max(0.9, rate * 0.97))

        let throttle = max(0, min(1, powerKw / 160))
        let regen = powerKw < -2 ? min(1, abs(powerKw) / 90) : 0
        let moving = feel >= 5

        if muted {
            bodyPlayer?.volume = 0
            humPlayer?.volume = 0
            return
        }
        if !moving {
            bodyPlayer?.volume = 0.08
            humPlayer?.volume = 0.12
            return
        }
        bodyPlayer?.volume = baseBodyGain(kmh: feel, powerKw: powerKw) * Float(0.75 + throttle * 0.45 - regen * 0.2)
        humPlayer?.volume = baseHumGain(kmh: feel) * Float(0.85 + throttle * 0.2)
    }

    private func baseBodyGain(kmh: Double, powerKw: Double) -> Float {
        let speed = Float(min(1, kmh / 120))
        let load = Float(max(0, min(1, abs(powerKw) / 180)))
        return 0.22 + speed * 0.45 + load * 0.2
    }

    private func baseHumGain(kmh: Double) -> Float {
        let speed = Float(min(1, kmh / 100))
        return 0.14 + speed * 0.22
    }
}
