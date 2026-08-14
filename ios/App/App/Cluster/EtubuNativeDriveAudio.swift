import Foundation
import AVFoundation

/// Cap-independent EV drive hum — loops from Cap www `public/assets/audio/loops/`.
/// Cap AudioEngine remains preferred when warm; this covers demo / cold Cap.
/// RevHeadz-inspired: powerKw primary (throttle/regen), kmh secondary pitch/ceiling.
/// Soft flywheel: accel rises fast, lift/coast decays slowly.
final class EtubuNativeDriveAudio {
    static let shared = EtubuNativeDriveAudio()

    private var bodyPlayer: AVAudioPlayer?
    private var humPlayer: AVAudioPlayer?
    private var regenPlayer: AVAudioPlayer?
    /// Keep fading players alive until stop — iOS 27 `finishedPlaying:` crash otherwise.
    private var retiringPlayers: [AVAudioPlayer] = []
    private var running = false
    private var muted = false
    private var currentVoice = "calm-ev"
    private var currentPack = "calm-ev"
    private var lastKmh: Double = 0
    private var lastPower: Double = 0
    private var lastAccel: Double = 0
    private var character = VoiceCharacter.evSoft

    /// Continuous engine RPM 0…1 (flywheel) — never snaps.
    private var engineRpm: Double = 0.12
    private var smoothThrottle: Double = 0
    private var smoothRegen: Double = 0
    private var smoothRate: Float = 1.0
    private var smoothHumRate: Float = 1.0
    private var smoothBodyVol: Float = 0.08
    private var smoothHumVol: Float = 0.1
    private var smoothRegenVol: Float = 0
    private var prevKmh: Double = 0

    private init() {}

    var isEngineAlive: Bool { running }
    var isAudible: Bool { running && !muted }
    var isRunning: Bool { isEngineAlive }

    func start(voice: String = "calm-ev") {
        let work = { [weak self] in
            guard let self else { return }
            let key = (voice.isEmpty || voice == "silent-mode") ? "calm-ev" : voice
            let pack = Self.resolvePack(key)
            if self.running, self.currentVoice == key, self.currentPack == pack {
                if !self.muted {
                    self.applyParams(kmh: self.lastKmh, powerKw: self.lastPower, accelKmhS: self.lastAccel)
                }
                return
            }
            // Soft voice swap: keep old audible briefly while new prepares
            let oldBody = self.bodyPlayer
            let oldHum = self.humPlayer
            let oldRegen = self.regenPlayer
            self.currentVoice = key
            self.currentPack = pack
            self.character = VoiceCharacter.forVoice(pack)
            AppDelegate.activateDriveAudioSession()
            let files = self.loopFiles(for: pack)
            let newBody = self.makeLoopPlayer(file: files.body, volume: 0.001)
            let newHum = self.makeLoopPlayer(file: files.hum, volume: 0.001)
            let newRegen = self.makeLoopPlayer(file: "ev_modely_rev_body_loop.wav", volume: 0.001)
            self.bodyPlayer = newBody
            self.humPlayer = newHum
            self.regenPlayer = newRegen
            self.running = newBody != nil || newHum != nil
            self.smoothRate = 1
            self.smoothHumRate = 1
            self.smoothRegenVol = 0
            if self.muted {
                self.bodyPlayer?.volume = 0
                self.humPlayer?.volume = 0
                self.regenPlayer?.volume = 0
                self.bodyPlayer?.pause()
                self.humPlayer?.pause()
                self.regenPlayer?.pause()
            } else {
                self.bodyPlayer?.play()
                self.humPlayer?.play()
                self.regenPlayer?.play()
                self.applyParams(kmh: max(self.lastKmh, 18), powerKw: self.lastPower, accelKmhS: self.lastAccel)
                if let oldBody { self.fadeOutAndStop(oldBody) }
                if let oldHum { self.fadeOutAndStop(oldHum) }
                if let oldRegen { self.fadeOutAndStop(oldRegen) }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func setMuted(_ on: Bool) {
        let work = { [weak self] in
            guard let self else { return }
            let wasMuted = self.muted
            self.muted = on
            if on {
                self.smoothBodyVol = 0
                self.smoothHumVol = 0
                self.smoothRegenVol = 0
                let body = self.bodyPlayer
                let hum = self.humPlayer
                let regen = self.regenPlayer
                let startB = body?.volume ?? 0
                let startH = hum?.volume ?? 0
                let startR = regen?.volume ?? 0
                for i in 1...6 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) {
                        let t = Float(i) / 6
                        body?.volume = max(0, startB * (1 - t))
                        hum?.volume = max(0, startH * (1 - t))
                        regen?.volume = max(0, startR * (1 - t))
                    }
                }
            } else if self.running {
                if self.bodyPlayer?.isPlaying != true { self.bodyPlayer?.play() }
                if self.humPlayer?.isPlaying != true { self.humPlayer?.play() }
                if self.regenPlayer?.isPlaying != true { self.regenPlayer?.play() }
                if wasMuted {
                    self.smoothBodyVol = 0.02
                    self.smoothHumVol = 0.03
                    self.smoothRegenVol = 0
                }
                self.applyParams(kmh: self.lastKmh, powerKw: self.lastPower, accelKmhS: self.lastAccel)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func setSpeed(kmh: Int, powerKw: Int?, accelKmhS: Double? = nil) {
        setSpeed(kmh: Double(max(0, kmh)), powerKw: powerKw.map { Double($0) }, accelKmhS: accelKmhS)
    }

    func setSpeed(kmh: Double, powerKw: Double?, accelKmhS: Double? = nil) {
        let work = { [weak self] in
            guard let self else { return }
            self.lastKmh = max(0, kmh)
            if let powerKw { self.lastPower = powerKw }
            if let accelKmhS, accelKmhS.isFinite { self.lastAccel = accelKmhS }
            else {
                let dt = 0.12
                let dv = self.lastKmh - self.prevKmh
                if abs(dv) >= 0.12 {
                    self.lastAccel = dv / dt
                }
            }
            guard self.running, !self.muted else { return }
            self.applyParams(kmh: self.lastKmh, powerKw: self.lastPower, accelKmhS: self.lastAccel)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func resumeIfNeeded() {
        let work = { [weak self] in
            guard let self else { return }
            guard self.running, !self.muted else { return }
            if self.bodyPlayer?.isPlaying != true { self.bodyPlayer?.play() }
            if self.humPlayer?.isPlaying != true { self.humPlayer?.play() }
            if self.regenPlayer?.isPlaying != true { self.regenPlayer?.play() }
            self.applyParams(kmh: self.lastKmh, powerKw: self.lastPower, accelKmhS: self.lastAccel)
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
            self.lastAccel = 0
            self.engineRpm = 0.12
            self.smoothThrottle = 0
            self.smoothRegen = 0
            self.prevKmh = 0
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Pack resolve (mirrors ClusterTheme.driveBasePack / Cap THEME_PACK_MAP)

    /// Theme rawValue / webKey / base pack → calm-ev | ion-whisper | sport-ev | boost-launch
    static func resolvePack(_ voice: String) -> String {
        if voice.isEmpty || voice == "silent-mode" { return "calm-ev" }
        if let theme = ClusterTheme(rawValue: voice) {
            return theme.driveBasePack
        }
        if let theme = ClusterTheme.allCases.first(where: { $0.webKey == voice }) {
            return theme.driveBasePack
        }
        switch voice {
        case "calm-ev", "ion-whisper", "sport-ev", "boost-launch":
            return voice
        case "volt-shift", "pulse-drive":
            return "calm-ev"
        case "jet-hum":
            return "sport-ev"
        case "deep-ocean":
            return "calm-ev"
        case "electric-ice", "cyber-lime":
            return "ion-whisper"
        case "violet-storm", "solar-flare":
            return voice == "solar-flare" ? "boost-launch" : "sport-ev"
        default:
            return "calm-ev"
        }
    }

    // MARK: - Internals

    private func fadeOutAndStop(_ player: AVAudioPlayer) {
        retiringPlayers.append(player)
        let steps = 8
        let startVol = player.volume
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.03) { [weak self] in
                let t = Float(i) / Float(steps)
                player.volume = max(0, startVol * (1 - t))
                if i == steps {
                    player.delegate = nil
                    player.stop()
                    self?.retiringPlayers.removeAll { $0 === player }
                }
            }
        }
    }

    private func stopPlayers() {
        bodyPlayer?.delegate = nil
        humPlayer?.delegate = nil
        regenPlayer?.delegate = nil
        bodyPlayer?.stop()
        humPlayer?.stop()
        regenPlayer?.stop()
        retiringPlayers.forEach {
            $0.delegate = nil
            $0.stop()
        }
        retiringPlayers.removeAll()
        bodyPlayer = nil
        humPlayer = nil
        regenPlayer = nil
    }

    /// Distinct loops per base pack — same catalog as JS AudioEngine PROFILES.
    private func loopFiles(for pack: String) -> (body: String, hum: String, bodyVol: Float, humVol: Float) {
        switch pack {
        case "calm-ev":
            return ("ev_id3_body_loop.wav", "ev_hum_soft_loop.wav", 0.72, 0.28)
        case "sport-ev":
            return ("ev_modely_body_loop.wav", "ev_hum_sport_loop.wav", 0.74, 0.30)
        case "ion-whisper":
            return ("ev_hum_sport_loop.wav", "ev_modely_body_loop.wav", 0.70, 0.22)
        case "boost-launch":
            return ("ev_modely_rev_body_loop.wav", "ev_hum_sport_loop.wav", 0.78, 0.24)
        default:
            return ("ev_id3_body_loop.wav", "ev_hum_soft_loop.wav", 0.70, 0.28)
        }
    }

    private func makeLoopPlayer(file: String, volume: Float) -> AVAudioPlayer? {
        guard let url = urlForLoop(file) else { return nil }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.enableRate = true
            p.delegate = nil
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

    /// GPS dv/dt birincil gaz; powerKw pedal varsa blend.
    private func applyParams(kmh: Double, powerKw: Double, accelKmhS: Double = 0) {
        let c = character
        let feel = max(0, kmh)
        prevKmh = feel
        let speedNorm = min(1.0, feel / c.speedRefKmh)
        lastAccel = accelKmhS

        func throttleFromAccel(_ a: Double) -> Double {
            let dead = 0.12
            if a <= dead { return 0 }
            return max(0, min(1, pow((a - dead) / 4.4, 0.82)))
        }
        func regenFromAccel(_ a: Double) -> Double {
            let dead = 0.16
            if a >= -dead { return 0 }
            return max(0, min(1, (-a - dead) / 5.1))
        }

        var targetThrottle = throttleFromAccel(accelKmhS)
        var targetRegen = regenFromAccel(accelKmhS)
        if powerKw > 8 {
            targetThrottle = max(powerKw / 220.0, targetThrottle * 0.72)
        } else if powerKw > 1 {
            targetThrottle = max(targetThrottle, min(1, powerKw / 220.0))
        } else if powerKw < -8 {
            targetRegen = max(-powerKw / 80.0, targetRegen * 0.65)
        } else if powerKw < -1 {
            targetRegen = max(targetRegen, min(1, -powerKw / 80.0))
        }

        // Soft flywheel: accel fast, lift/coast slow
        let thrRise = targetThrottle >= smoothThrottle - 0.01
        smoothThrottle += (targetThrottle - smoothThrottle) * (thrRise ? 0.62 : 0.16)
        let regRise = targetRegen >= smoothRegen - 0.01
        smoothRegen += (targetRegen - smoothRegen) * (regRise ? 0.5 : 0.2)

        let throttle = smoothThrottle
        let regen = smoothRegen

        // Target RPM: throttle primary, speed secondary, regen blend
        let targetRpm = max(
            0.08,
            min(1.0, throttle * 0.72 + speedNorm * 0.28 + regen * 0.38)
        )
        let rising = targetRpm >= engineRpm - 0.01 || throttle > regen + 0.05
        let rpmLerp = rising ? 0.22 : 0.065
        engineRpm += (targetRpm - engineRpm) * rpmLerp

        let targetRate = Float(min(c.rateMax, max(c.rateMin, c.rateBase + engineRpm * c.rateSpan + throttle * 0.06 + regen * 0.04)))
        let rateLerp: Float = rising ? 0.14 : 0.05
        smoothRate += (targetRate - smoothRate) * rateLerp
        smoothHumRate += (targetRate * c.humRateMul - smoothHumRate) * rateLerp
        if abs((bodyPlayer?.rate ?? smoothRate) - smoothRate) > 0.004 {
            bodyPlayer?.rate = smoothRate
        }
        if abs((humPlayer?.rate ?? smoothHumRate) - smoothHumRate) > 0.004 {
            humPlayer?.rate = smoothHumRate
        }
        let regenRate = Float(min(c.rateMax, max(c.rateMin, Double(smoothRate) * 0.96 + regen * 0.08)))
        if abs((regenPlayer?.rate ?? regenRate) - regenRate) > 0.004 {
            regenPlayer?.rate = regenRate
        }

        let moving = feel >= 3 || throttle > 0.04 || regen > 0.04
        if muted {
            bodyPlayer?.volume = 0
            humPlayer?.volume = 0
            regenPlayer?.volume = 0
            return
        }

        let duck = Float(1.0 - regen * 0.55)
        let targetBody: Float
        let targetHum: Float
        let targetRegenVol: Float
        if !moving {
            targetBody = c.idleBody
            targetHum = c.idleHum
            targetRegenVol = 0
        } else {
            let loadMul = Float(0.72 + throttle * Double(c.throttleBoost))
            targetBody = (c.bodyBase + Float(engineRpm) * c.bodySpeed + Float(throttle) * c.bodyLoad) * loadMul * duck
            targetHum = (c.humBase + Float(engineRpm) * c.humSpeed) * Float(0.85 + throttle * 0.2) * duck
            // Regen biases toward rev/body character
            targetRegenVol = Float(regen * (0.32 + regen * 0.48)) * (c.regenBoost)
        }
        let volLerp: Float = rising ? 0.24 : 0.1
        smoothBodyVol += (targetBody - smoothBodyVol) * volLerp
        smoothHumVol += (targetHum - smoothHumVol) * volLerp
        smoothRegenVol += (targetRegenVol - smoothRegenVol) * volLerp
        let mixGain = Self.cabinMixGain()
        bodyPlayer?.volume = max(0, smoothBodyVol * mixGain)
        humPlayer?.volume = max(0, smoothHumVol * mixGain)
        regenPlayer?.volume = max(0, smoothRegenVol * mixGain)
    }

    /// Blend/under sit under ducked Music; solo is full. Slider = cabin level.
    private static func cabinMixGain() -> Float {
        let cabin = Float(max(0.2, min(1.0, UserDefaults.standard.object(forKey: "etubu.cluster.alertVolume") as? Double ?? 0.85)))
        switch AppDelegate.storedMixMode {
        case "solo":
            return 1
        case "under":
            return max(0.28, cabin * 0.55)
        default:
            return max(0.5, cabin * 0.92)
        }
    }

    /// Per-pack feel: soft / sport / boost (theme → pack).
    private struct VoiceCharacter {
        var rateMin: Double
        var rateMax: Double
        var rateBase: Double
        var rateSpan: Double
        var humRateMul: Float
        var speedRefKmh: Double
        var idleBody: Float
        var idleHum: Float
        var bodyBase: Float
        var bodySpeed: Float
        var bodyLoad: Float
        var humBase: Float
        var humSpeed: Float
        var throttleBoost: Float
        var regenBoost: Float

        static let evSoft = VoiceCharacter(
            rateMin: 0.78, rateMax: 1.35, rateBase: 0.82, rateSpan: 0.48, humRateMul: 0.97,
            speedRefKmh: 140,
            idleBody: 0.06, idleHum: 0.10,
            bodyBase: 0.28, bodySpeed: 0.42, bodyLoad: 0.22,
            humBase: 0.14, humSpeed: 0.20, throttleBoost: 0.42, regenBoost: 0.95
        )
        static let evSport = VoiceCharacter(
            rateMin: 0.80, rateMax: 1.42, rateBase: 0.86, rateSpan: 0.52, humRateMul: 0.98,
            speedRefKmh: 160,
            idleBody: 0.07, idleHum: 0.11,
            bodyBase: 0.30, bodySpeed: 0.48, bodyLoad: 0.26,
            humBase: 0.15, humSpeed: 0.24, throttleBoost: 0.50, regenBoost: 1.05
        )
        static let evBoost = VoiceCharacter(
            rateMin: 0.84, rateMax: 1.48, rateBase: 0.90, rateSpan: 0.55, humRateMul: 0.99,
            speedRefKmh: 180,
            idleBody: 0.08, idleHum: 0.10,
            bodyBase: 0.34, bodySpeed: 0.52, bodyLoad: 0.30,
            humBase: 0.14, humSpeed: 0.22, throttleBoost: 0.58, regenBoost: 1.12
        )

        static func forVoice(_ pack: String) -> VoiceCharacter {
            switch pack {
            case "calm-ev", "ion-whisper":
                return .evSoft
            case "sport-ev":
                return .evSport
            case "boost-launch":
                return .evBoost
            default:
                return .evSoft
            }
        }
    }
}
