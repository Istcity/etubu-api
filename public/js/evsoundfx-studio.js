/**
 * ETUBU EVSOUNDFX STUDIO — Real-Time Web Audio Synthesizer & Acoustic Generator
 * Inspired by evsoundfx.com & Advanced Automotive Sound Design
 * Pure Web Audio API — Zero latency, zero external binary dependency
 */

(function () {
  'use strict';

  class EvSoundFxStudio {
    constructor() {
      this.ctx = null;
      this.isPlaying = false;
      this.speedKmH = 0;
      this.targetSpeed = 0;
      this.throttle = 0;
      this.activePreset = 'plaid';
      
      // Fine-tuning knobs
      this.tuning = {
        pitchMult: 1.0,
        subBass: 1.0,
        whineGain: 1.0,
        saturation: 0.5
      };

      // Sound presets definition
      this.PRESETS = {
        plaid: {
          name: 'Hyper EV Plaid',
          subtitle: 'Dual-Inverter Superconductive Whine',
          baseFreq: 54,
          maxFreq: 480,
          whineFreqMult: 14.5,
          waveType: 'sawtooth',
          filterBase: 380,
          filterMax: 4800,
          subBassGain: 0.42,
          whineBaseGain: 0.28,
          driveColor: '#00f0ff'
        },
        taycan: {
          name: 'Taycan E-Sound',
          subtitle: 'Sport Acoustic Dual Motor Pulse',
          baseFreq: 44,
          maxFreq: 380,
          whineFreqMult: 9.8,
          waveType: 'triangle',
          filterBase: 260,
          filterMax: 3200,
          subBassGain: 0.55,
          whineBaseGain: 0.22,
          driveColor: '#8b5cf6'
        },
        warp: {
          name: 'Cyber Hyperspace',
          subtitle: 'Tron Pulsar & Sci-Fi Warp Core',
          baseFreq: 36,
          maxFreq: 620,
          whineFreqMult: 18.2,
          waveType: 'sine',
          filterBase: 500,
          filterMax: 7500,
          subBassGain: 0.48,
          whineBaseGain: 0.38,
          driveColor: '#10b981'
        },
        v8hybrid: {
          name: 'Quantum V8 Pulse',
          subtitle: 'Electro-Mechanical Crossplane Rumble',
          baseFreq: 32,
          maxFreq: 310,
          whineFreqMult: 6.4,
          waveType: 'sawtooth',
          filterBase: 220,
          filterMax: 2600,
          subBassGain: 0.65,
          whineBaseGain: 0.15,
          driveColor: '#ef4444'
        },
        turbo: {
          name: 'Twin-Turbo Boxer',
          subtitle: 'Spooling Compressor & Wastegate Air',
          baseFreq: 48,
          maxFreq: 420,
          whineFreqMult: 12.0,
          waveType: 'sawtooth',
          filterBase: 320,
          filterMax: 4200,
          subBassGain: 0.45,
          whineBaseGain: 0.3,
          driveColor: '#f59e0b'
        },
        formulae: {
          name: 'Formula E Apex',
          subtitle: 'Straight-Cut Gear Screamer & Inverter',
          baseFreq: 68,
          maxFreq: 750,
          whineFreqMult: 21.0,
          waveType: 'sawtooth',
          filterBase: 600,
          filterMax: 8200,
          subBassGain: 0.28,
          whineBaseGain: 0.48,
          driveColor: '#06b6d4'
        },
        spinner: {
          name: 'Blade Runner 2049',
          subtitle: 'Deep Cinematic Synth Atmospheric Drone',
          baseFreq: 28,
          maxFreq: 280,
          whineFreqMult: 7.2,
          waveType: 'sine',
          filterBase: 180,
          filterMax: 2100,
          subBassGain: 0.72,
          whineBaseGain: 0.18,
          driveColor: '#ec4899'
        }
      };

      this.initDom();
    }

    initAudioContext() {
      if (this.ctx) return;
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) {
        console.warn('Web Audio API not supported in this browser.');
        return;
      }
      this.ctx = new AudioCtx();

      // Master output node
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.setValueAtTime(0.0001, this.ctx.currentTime);

      // Analyzer for realtime visualizer
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = 256;
      this.analyser.smoothingTimeConstant = 0.85;

      this.masterGain.connect(this.analyser);
      this.analyser.connect(this.ctx.destination);

      // Sub-bass oscillator
      this.subOsc = this.ctx.createOscillator();
      this.subGain = this.ctx.createGain();
      this.subOsc.type = 'sine';
      this.subOsc.connect(this.subGain);
      this.subGain.connect(this.masterGain);

      // Motor core oscillator
      this.coreOsc = this.ctx.createOscillator();
      this.coreGain = this.ctx.createGain();
      this.coreFilter = this.ctx.createBiquadFilter();
      this.coreFilter.type = 'lowpass';
      this.coreFilter.Q.value = 3.5;
      this.coreOsc.connect(this.coreFilter);
      this.coreFilter.connect(this.coreGain);
      this.coreGain.connect(this.masterGain);

      // Inverter high-frequency whine oscillator
      this.whineOsc = this.ctx.createOscillator();
      this.whineGain = this.ctx.createGain();
      this.whineFilter = this.ctx.createBiquadFilter();
      this.whineFilter.type = 'bandpass';
      this.whineFilter.Q.value = 6.0;
      this.whineOsc.type = 'sine';
      this.whineOsc.connect(this.whineFilter);
      this.whineFilter.connect(this.whineGain);
      this.whineGain.connect(this.masterGain);

      // Distortion/Saturation shaper
      this.waveShaper = this.ctx.createWaveShaper();
      this.waveShaper.curve = this.makeDistortionCurve(20);
      this.waveShaper.oversample = '4x';

      // Start oscillators
      const now = this.ctx.currentTime;
      this.subOsc.start(now);
      this.coreOsc.start(now);
      this.whineOsc.start(now);

      this.updateSynthParameters();
    }

    makeDistortionCurve(amount) {
      const k = typeof amount === 'number' ? amount : 50;
      const n_samples = 44100;
      const curve = new Float32Array(n_samples);
      const deg = Math.PI / 180;
      for (let i = 0; i < n_samples; ++i) {
        const x = (i * 2) / n_samples - 1;
        curve[i] = ((3 + k) * x * 20 * deg) / (Math.PI + k * Math.abs(x));
      }
      return curve;
    }

    start() {
      this.initAudioContext();
      if (!this.ctx) return;
      if (this.ctx.state === 'suspended') {
        this.ctx.resume();
      }
      this.isPlaying = true;
      const now = this.ctx.currentTime;
      this.masterGain.gain.cancelScheduledValues(now);
      this.masterGain.gain.setTargetAtTime(0.75, now, 0.15);

      if (this.startStopBtn) {
        this.startStopBtn.innerHTML = `
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
            <rect x="6" y="4" width="4" height="16"></rect>
            <rect x="14" y="4" width="4" height="16"></rect>
          </svg>
          Sesi Durdur
        `;
        this.startStopBtn.classList.add('btn-motion--primary');
        this.startStopBtn.classList.remove('btn-motion--ghost');
      }

      this.requestVisualizerLoop();
    }

    stop() {
      if (!this.ctx) return;
      this.isPlaying = false;
      const now = this.ctx.currentTime;
      this.masterGain.gain.cancelScheduledValues(now);
      this.masterGain.gain.setTargetAtTime(0.0001, now, 0.2);

      if (this.startStopBtn) {
        this.startStopBtn.innerHTML = `
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
            <polygon points="5 3 19 12 5 21 5 3"></polygon>
          </svg>
          Sesi Başlat
        `;
        this.startStopBtn.classList.remove('btn-motion--primary');
        this.startStopBtn.classList.add('btn-motion--ghost');
      }
    }

    toggle() {
      if (this.isPlaying) {
        this.stop();
      } else {
        this.start();
      }
    }

    selectPreset(presetKey) {
      if (!this.PRESETS[presetKey]) return;
      this.activePreset = presetKey;
      
      // Update UI active state
      document.querySelectorAll('.preset-chip').forEach(el => {
        el.classList.toggle('is-active', el.dataset.preset === presetKey);
      });

      const p = this.PRESETS[presetKey];
      if (this.coreOsc) {
        this.coreOsc.type = p.waveType;
      }
      this.updateSynthParameters();
    }

    updateSynthParameters() {
      if (!this.ctx) return;
      const p = this.PRESETS[this.activePreset];
      const now = this.ctx.currentTime;

      const normSpeed = Math.min(Math.max(this.speedKmH / 260, 0), 1);
      const pitchMult = this.tuning.pitchMult;

      // Base engine frequency
      const targetCoreFreq = (p.baseFreq + (p.maxFreq - p.baseFreq) * Math.pow(normSpeed, 1.25)) * pitchMult;
      this.coreOsc.frequency.setTargetAtTime(Math.max(targetCoreFreq, 20), now, 0.08);

      // Sub-bass frequency
      const targetSubFreq = Math.max(targetCoreFreq * 0.5, 20);
      this.subOsc.frequency.setTargetAtTime(targetSubFreq, now, 0.08);

      // Inverter whine frequency
      const targetWhineFreq = Math.min(targetCoreFreq * p.whineFreqMult, 14000);
      this.whineOsc.frequency.setTargetAtTime(targetWhineFreq, now, 0.06);

      // Filter modulation
      const targetFilter = p.filterBase + (p.filterMax - p.filterBase) * Math.pow(normSpeed, 1.1);
      this.coreFilter.frequency.setTargetAtTime(Math.min(targetFilter, 16000), now, 0.08);
      this.whineFilter.frequency.setTargetAtTime(targetWhineFreq, now, 0.06);

      // Gains based on load and speed
      const baseGain = 0.25 + normSpeed * 0.45;
      this.subGain.gain.setTargetAtTime(p.subBassGain * this.tuning.subBass * baseGain, now, 0.08);
      this.coreGain.gain.setTargetAtTime(baseGain * 0.7, now, 0.08);
      this.whineGain.gain.setTargetAtTime(p.whineBaseGain * this.tuning.whineGain * (0.15 + normSpeed * 0.85), now, 0.08);
    }

    updateSpeed(kmh) {
      this.speedKmH = Math.max(0, Math.min(260, kmh));
      const normSpeed = this.speedKmH / 260;
      
      // Update speedometer text
      if (this.speedGaugeVal) {
        this.speedGaugeVal.textContent = Math.round(this.speedKmH);
      }
      
      // Secondary metrics
      const rpm = Math.round(800 + normSpeed * 16500);
      const kw = Math.round(Math.pow(normSpeed, 1.35) * 750);

      if (this.rpmMetricVal) {
        this.rpmMetricVal.textContent = rpm.toLocaleString() + ' RPM';
      }
      if (this.powerMetricVal) {
        this.powerMetricVal.textContent = (this.speedKmH > 0 ? '+' : '') + kw + ' kW';
      }

      // 1. SOL KADRAN (Hız İbresi ve Arkı)
      const speedAngle = -135 + normSpeed * 270;
      if (this.speedNeedleWrap) {
        this.speedNeedleWrap.style.transform = `rotate(${speedAngle}deg)`;
      }
      if (this.speedProgressArc) {
        // Çevre = 2 * PI * 70 ≈ 440; 270 derecelik yay boyutu ≈ 330
        const dashOffset = 440 - normSpeed * 330;
        this.speedProgressArc.style.strokeDashoffset = dashOffset;
      }

      // 2. SAĞ KADRAN (Güç & Devir İbresi ve Arkı)
      const powerAngle = -135 + (kw / 750) * 270;
      if (this.powerNeedleWrap) {
        this.powerNeedleWrap.style.transform = `rotate(${powerAngle}deg)`;
      }
      if (this.powerProgressArc) {
        const powerDashOffset = 440 - (kw / 750) * 330;
        this.powerProgressArc.style.strokeDashoffset = powerDashOffset;
      }

      this.updateSynthParameters();
    }

    initDom() {
      // Elements lookup
      this.startStopBtn = document.getElementById('studioStartBtn');
      this.speedSlider = document.getElementById('studioSpeedSlider');
      this.virtualPedal = document.getElementById('studioPedalBtn');
      this.speedGaugeVal = document.getElementById('gaugeSpeedVal');
      this.rpmMetricVal = document.getElementById('rpmMetricVal');
      this.powerMetricVal = document.getElementById('powerMetricVal');
      this.spectrumCanvas = document.getElementById('audioSpectrumCanvas');
      this.exportWavBtn = document.getElementById('studioExportBtn');

      // Çift Kadran Elementleri
      this.speedNeedleWrap = document.getElementById('dialSpeedNeedleWrap');
      this.speedProgressArc = document.getElementById('dialSpeedProgress');
      this.powerNeedleWrap = document.getElementById('dialPowerNeedleWrap');
      this.powerProgressArc = document.getElementById('dialPowerProgress');
      this.cockpitCard = document.getElementById('cockpitGaugeCard');

      // Kadran Tema Seçici
      const themeButtons = document.querySelectorAll('.gauge-theme-btn');
      themeButtons.forEach(btn => {
        btn.addEventListener('click', () => {
          themeButtons.forEach(b => b.classList.remove('is-active'));
          btn.classList.add('is-active');
          const targetTheme = btn.dataset.gaugeTheme;
          if (this.cockpitCard && targetTheme) {
            this.cockpitCard.className = `cockpit-gauge-card ${targetTheme}`;
          }
        });
      });

      // Bind Start/Stop Button
      if (this.startStopBtn) {
        this.startStopBtn.addEventListener('click', () => this.toggle());
      }

      // Bind Presets
      document.querySelectorAll('.preset-chip').forEach(chip => {
        chip.addEventListener('click', (e) => {
          const presetKey = chip.dataset.preset;
          this.selectPreset(presetKey);
          if (!this.isPlaying) this.start();
        });
      });

      // Bind Speed Slider
      if (this.speedSlider) {
        this.speedSlider.addEventListener('input', (e) => {
          const val = parseFloat(e.target.value);
          this.updateSpeed(val);
          if (!this.isPlaying && val > 0) this.start();
        });
      }

      // Bind Virtual Pedal (Press & Hold)
      if (this.virtualPedal) {
        const pressPedal = () => {
          this.pedalPressed = true;
          this.virtualPedal.classList.add('is-pressed');
          if (!this.isPlaying) this.start();
          this.runPedalPhysics();
        };

        const releasePedal = () => {
          this.pedalPressed = false;
          this.virtualPedal.classList.remove('is-pressed');
        };

        this.virtualPedal.addEventListener('mousedown', pressPedal);
        window.addEventListener('mouseup', releasePedal);
        this.virtualPedal.addEventListener('touchstart', (e) => {
          e.preventDefault();
          pressPedal();
        }, { passive: false });
        window.addEventListener('touchend', releasePedal);
      }

      // Bind Tuning Knobs
      const pitchSlider = document.getElementById('tunePitch');
      const subSlider = document.getElementById('tuneSub');
      const whineSlider = document.getElementById('tuneWhine');

      if (pitchSlider) {
        pitchSlider.addEventListener('input', (e) => {
          this.tuning.pitchMult = parseFloat(e.target.value);
          const valEl = document.getElementById('tunePitchVal');
          if (valEl) valEl.textContent = this.tuning.pitchMult.toFixed(2) + 'x';
          this.updateSynthParameters();
        });
      }
      if (subSlider) {
        subSlider.addEventListener('input', (e) => {
          this.tuning.subBass = parseFloat(e.target.value);
          const valEl = document.getElementById('tuneSubVal');
          if (valEl) valEl.textContent = Math.round(this.tuning.subBass * 100) + '%';
          this.updateSynthParameters();
        });
      }
      if (whineSlider) {
        whineSlider.addEventListener('input', (e) => {
          this.tuning.whineGain = parseFloat(e.target.value);
          const valEl = document.getElementById('tuneWhineVal');
          if (valEl) valEl.textContent = Math.round(this.tuning.whineGain * 100) + '%';
          this.updateSynthParameters();
        });
      }

      // Bind WAV Export (evsoundfx style audio export)
      if (this.exportWavBtn) {
        this.exportWavBtn.addEventListener('click', () => this.exportSoundWav());
      }
    }

    runPedalPhysics() {
      if (this.physicsActive) return;
      this.physicsActive = true;

      const loop = () => {
        if (this.pedalPressed) {
          // Accelerate smoothly
          this.speedKmH = Math.min(260, this.speedKmH + 2.8);
        } else {
          // Regenerative braking / deceleration
          this.speedKmH = Math.max(0, this.speedKmH - 1.9);
        }

        if (this.speedSlider) {
          this.speedSlider.value = this.speedKmH;
        }
        this.updateSpeed(this.speedKmH);

        if (this.pedalPressed || this.speedKmH > 0) {
          requestAnimationFrame(loop);
        } else {
          this.physicsActive = false;
        }
      };

      requestAnimationFrame(loop);
    }

    requestVisualizerLoop() {
      if (this.visLoopActive) return;
      this.visLoopActive = true;

      const canvas = this.spectrumCanvas;
      if (!canvas) return;
      const ctx2d = canvas.getContext('2d');

      const render = () => {
        if (!this.analyser) {
          requestAnimationFrame(render);
          return;
        }

        const bufferLength = this.analyser.frequencyBinCount;
        const dataArray = new Uint8Array(bufferLength);
        this.analyser.getByteFrequencyData(dataArray);

        // Adjust canvas resolution
        if (canvas.width !== canvas.clientWidth) {
          canvas.width = canvas.clientWidth;
          canvas.height = canvas.clientHeight;
        }

        const width = canvas.width;
        const height = canvas.height;

        ctx2d.clearRect(0, 0, width, height);

        // Grid lines
        ctx2d.strokeStyle = 'rgba(255, 255, 255, 0.04)';
        ctx2d.lineWidth = 1;
        for (let y = 0; y < height; y += 30) {
          ctx2d.beginPath();
          ctx2d.moveTo(0, y);
          ctx2d.lineTo(width, y);
          ctx2d.stroke();
        }

        // Draw frequency bars
        const barWidth = (width / bufferLength) * 2.2;
        let barHeight;
        let x = 0;

        const preset = this.PRESETS[this.activePreset];
        const barColor = preset ? preset.driveColor : '#00f0ff';

        for (let i = 0; i < bufferLength; i++) {
          barHeight = (dataArray[i] / 255) * height;

          // Gradient bar
          const grad = ctx2d.createLinearGradient(0, height, 0, height - barHeight);
          grad.addColorStop(0, 'rgba(0, 240, 255, 0.1)');
          grad.addColorStop(1, barColor);

          ctx2d.fillStyle = grad;
          ctx2d.fillRect(x, height - barHeight, barWidth - 1, barHeight);

          // Glow cap
          ctx2d.fillStyle = '#ffffff';
          ctx2d.fillRect(x, height - barHeight - 2, barWidth - 1, 2);

          x += barWidth;
        }

        requestAnimationFrame(render);
      };

      requestAnimationFrame(render);
    }

    // High quality offline render and WAV downloader
    async exportSoundWav() {
      const btn = this.exportWavBtn;
      const originalText = btn.innerHTML;
      btn.innerHTML = '<span>Hazırlanıyor...</span>';
      btn.disabled = true;

      try {
        const sampleRate = 44100;
        const durationSec = 4;
        const OfflineCtx = window.OfflineAudioContext || window.webkitOfflineAudioContext;
        const offlineCtx = new OfflineCtx(2, sampleRate * durationSec, sampleRate);

        const p = this.PRESETS[this.activePreset];
        const osc = offlineCtx.createOscillator();
        const sub = offlineCtx.createOscillator();
        const gain = offlineCtx.createGain();

        osc.type = p.waveType;
        sub.type = 'sine';

        // Simulated acceleration ramp
        osc.frequency.setValueAtTime(p.baseFreq, 0);
        osc.frequency.exponentialRampToValueAtTime(p.maxFreq, durationSec);

        sub.frequency.setValueAtTime(p.baseFreq * 0.5, 0);
        sub.frequency.exponentialRampToValueAtTime(p.maxFreq * 0.5, durationSec);

        osc.connect(gain);
        sub.connect(gain);
        gain.connect(offlineCtx.destination);

        osc.start(0);
        sub.start(0);

        const renderedBuffer = await offlineCtx.startRendering();
        const wavBlob = this.bufferToWave(renderedBuffer, renderedBuffer.length);

        const url = URL.createObjectURL(wavBlob);
        const a = document.createElement('a');
        a.style.display = 'none';
        a.href = url;
        a.download = `etubu-${this.activePreset}-ev-soundfx.wav`;
        document.body.appendChild(a);
        a.click();
        setTimeout(() => {
          document.body.removeChild(a);
          window.URL.revokeObjectURL(url);
        }, 1000);
      } catch (err) {
        console.error('WAV export error:', err);
      } finally {
        btn.innerHTML = originalText;
        btn.disabled = false;
      }
    }

    bufferToWave(abuffer, len) {
      let numOfChan = abuffer.numberOfChannels,
        length = len * numOfChan * 2 + 44,
        out = new DataView(new ArrayBuffer(length)),
        channels = [],
        i,
        sample,
        offset = 0,
        pos = 0;

      function setUint16(data) {
        out.setUint16(pos, data, true);
        pos += 2;
      }
      function setUint32(data) {
        out.setUint32(pos, data, true);
        pos += 4;
      }

      setUint32(0x46464952); // "RIFF"
      setUint32(length - 8); // file length - 8
      setUint32(0x45564157); // "WAVE"

      setUint32(0x20746d66); // "fmt " chunk
      setUint32(16); // length = 16
      setUint16(1); // PCM (uncompressed)
      setUint16(numOfChan);
      setUint32(abuffer.sampleRate);
      setUint32(abuffer.sampleRate * 2 * numOfChan); // avg. bytes/sec
      setUint16(numOfChan * 2); // block-align
      setUint16(16); // 16-bit precision

      setUint32(0x61746164); // "data" - chunk
      setUint32(length - pos - 4); // chunk length

      for (i = 0; i < abuffer.numberOfChannels; i++) {
        channels.push(abuffer.getChannelData(i));
      }

      while (pos < length) {
        for (i = 0; i < numOfChan; i++) {
          sample = Math.max(-1, Math.min(1, channels[i][offset]));
          sample = (0.5 + sample < 0 ? sample * 32768 : sample * 32767) | 0;
          out.setInt16(pos, sample, true);
          pos += 2;
        }
        offset++;
      }

      return new Blob([out], { type: 'audio/wav' });
    }
  }

  // Auto initialize on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      window.etubuSoundStudio = new EvSoundFxStudio();
    });
  } else {
    window.etubuSoundStudio = new EvSoundFxStudio();
  }
})();
