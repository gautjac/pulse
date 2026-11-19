import Foundation

/// One playing click. Plain value type with no heap storage, so it is safe to run on the audio thread.
struct Voice {
    var active = false
    var count = 0
    var phase = SIMD8<Double>(repeating: 0)
    var inc = SIMD8<Double>(repeating: 0)
    var env = SIMD8<Double>(repeating: 0)
    var decayMul = SIMD8<Double>(repeating: 1)
    var gain = SIMD8<Double>(repeating: 0)
    var noiseEnv = 0.0
    var noiseMul = 1.0
    var noiseGain = 0.0
    var hpA = 0.3
    var lpA = 0.8
    var n1 = 0.0
    var n2 = 0.0
    var rng: UInt32 = 2_463_534_242
    var age = 0
    var burstsLeft = 0
    var burstGap = 0
    var nextBurst = 0
    var pitchEnv = 0.0
    var pitchMul = 1.0
    var pitchDrop = 0.0
    var atk = 1.0
    var atkStep = 1.0
    var drive = 0.0
    var driveNorm = 1.0
    var level = 1.0

    private static let ln1000 = 6.907755278982137

    /// Loudness left in the voice; used to pick one to steal.
    var energy: Double {
        max((gain * env).max(), noiseGain * noiseEnv) * level
    }

    mutating func start(_ r: SoundRecipe, gain g: Double, pitchRatio: Double, sampleRate sr: Double, seed: UInt32) {
        active = true
        age = 0
        count = r.count
        phase = SIMD8<Double>(repeating: 0)
        inc = r.ratios * (r.freq * pitchRatio * 2.0 * Double.pi / sr)
        gain = r.gains * g
        env = SIMD8<Double>(repeating: 1)
        decayMul = SIMD8<Double>(repeating: 1)
        for k in 0..<r.count {
            decayMul[k] = exp(-Voice.ln1000 / (max(r.decays[k], 0.002) * sr))
        }
        noiseGain = r.noiseGain * g
        noiseEnv = 1
        noiseMul = exp(-Voice.ln1000 / (max(r.noiseDecay, 0.002) * sr))
        hpA = r.hpA
        lpA = r.lpA
        n1 = 0
        n2 = 0
        rng = seed == 0 ? 2_463_534_242 : seed
        burstsLeft = max(r.bursts - 1, 0)
        burstGap = Int(r.burstGap * sr)
        nextBurst = burstGap
        pitchDrop = r.pitchDrop
        pitchEnv = 1
        pitchMul = exp(-1.0 / (max(r.pitchTime, 0.001) * sr))
        if r.attack > 0 {
            atk = 0
            atkStep = 1.0 / (max(r.attack, 0.0001) * sr)
        } else {
            atk = 1
            atkStep = 1
        }
        drive = r.drive
        driveNorm = r.drive > 0 ? 1.0 / tanh(r.drive) : 1
        level = r.level
    }

    /// Adds `frames` samples of this voice into `out`.
    mutating func renderAdd(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        guard active else { return }
        let lvl = level
        for i in 0..<frames {
            var s = 0.0
            let pf = 1.0 + pitchDrop * pitchEnv
            var k = 0
            while k < count {
                s += gain[k] * env[k] * sin(phase[k])
                phase[k] += inc[k] * pf
                env[k] *= decayMul[k]
                k += 1
            }
            pitchEnv *= pitchMul

            if burstsLeft > 0 && age == nextBurst {
                noiseEnv = 1
                burstsLeft -= 1
                nextBurst += burstGap
            }
            if noiseGain > 0 {
                rng ^= rng << 13
                rng ^= rng >> 17
                rng ^= rng << 5
                let w = Double(Int32(bitPattern: rng)) * (1.0 / 2_147_483_648.0)
                n1 += hpA * (w - n1)
                let h = w - n1
                n2 += lpA * (h - n2)
                s += noiseGain * noiseEnv * n2
                noiseEnv *= noiseMul
            }
            if atk < 1 {
                atk = min(1, atk + atkStep)
                s *= atk
            }
            if drive > 0 { s = tanh(drive * s) * driveNorm }
            out[i] += Float(s * lvl)
            age += 1
        }
        // Keep the phases small so long-ringing voices stay accurate.
        var k = 0
        let twoPi = 2.0 * Double.pi
        while k < count {
            if phase[k] > twoPi { phase[k] = phase[k].truncatingRemainder(dividingBy: twoPi) }
            k += 1
        }
        if burstsLeft == 0 && energy < 1e-5 { active = false }
    }
}
