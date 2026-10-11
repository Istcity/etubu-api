/**
 * ETUBU MOTION EXPERIENCE & TELEMETRY ENGINE
 * Inspired by motion.so — Micro-Interactions, 3D Physics Tilts,
 * Split Left-Card Navigation, Live Interactive Telemetry HUD, Hover Scrubbers & Ambient Lighting.
 */

(function () {
  'use strict';

  class MotionExperience {
    constructor() {
      this.telemetryCanvas = document.getElementById('telemetryGraphCanvas');
      this.tooltip = document.getElementById('telemetryTooltip');
      this.currentMode = 'power';
      this.telemetryHistory = [];
      this.maxHistoryPoints = 70;
      this.isPaused = false;
      this.syncWithThrottle = true;
      this.mouseX = -1;
      this.mouseY = -1;

      // Mode configurations for rich graphics
      this.MODES = {
        power: {
          title: 'Anlık Güç & Tork Analizi',
          subtitle: 'Çift motor inverter yükü ve anlık tork çıkış eğrisi',
          unit: 'kW',
          maxVal: 750,
          color: '#00f0ff',
          glowColor: 'rgba(0, 240, 255, 0.4)',
          gradientStart: 'rgba(0, 240, 255, 0.28)',
          gradientEnd: 'rgba(0, 240, 255, 0.01)',
          peakVal: '650 kW'
        },
        rpm: {
          title: 'Dinamik Motor Devri (RPM) & Rotor Hızı',
          subtitle: 'Harmonik vites geçişleri ve yüksek devir inverter senkronu',
          unit: 'RPM',
          maxVal: 18500,
          color: '#8b5cf6',
          glowColor: 'rgba(139, 92, 246, 0.4)',
          gradientStart: 'rgba(139, 92, 246, 0.28)',
          gradientEnd: 'rgba(139, 92, 246, 0.01)',
          peakVal: '17.800 RPM'
        },
        regen: {
          title: 'Kinetik Rejenerasyon & Enerji Geri Kazanımı',
          subtitle: 'Frenleme anında bataryaya aktarılan dinamik şarj akımı',
          unit: 'kW',
          maxVal: 85,
          color: '#10b981',
          glowColor: 'rgba(16, 185, 129, 0.4)',
          gradientStart: 'rgba(16, 185, 129, 0.28)',
          gradientEnd: 'rgba(16, 185, 129, 0.01)',
          peakVal: '78 kW Regen'
        },
        spectrum: {
          title: 'Akustik Dalga Boyu & Harmonik Spektrum',
          subtitle: 'evsoundfx motorunun ürettiği 20 Hz - 20 kHz ses dalgası',
          unit: 'Hz',
          maxVal: 12000,
          color: '#ec4899',
          glowColor: 'rgba(236, 72, 153, 0.4)',
          gradientStart: 'rgba(236, 72, 153, 0.28)',
          gradientEnd: 'rgba(236, 72, 153, 0.01)',
          peakVal: '9.800 Hz Whine'
        }
      };

      this.init3DTilt();
      this.initSplitTelemetry();
      this.initAmbientLighting();
      this.initMeteors();
      this.initSecurityShield();
    }

    /* ----------------------------------------------------
       0. MAGIC UI METEORS GENERATOR
       ---------------------------------------------------- */
    initMeteors() {
      const container = document.getElementById('meteorsContainer');
      if (!container) return;

      const count = 24;
      for (let i = 0; i < count; i++) {
        const meteor = document.createElement('span');
        meteor.className = 'magic-meteor';
        meteor.style.top = `${Math.random() * 80}%`;
        meteor.style.left = `${Math.random() * 100}%`;
        meteor.style.animationDelay = `${(Math.random() * 7).toFixed(2)}s`;
        meteor.style.animationDuration = `${(Math.random() * 5 + 3).toFixed(2)}s`;
        container.appendChild(meteor);
      }
    }

    /* ----------------------------------------------------
       1. 3D CARD TILT & MOUSE PHYSICS (motion.so style)
       ---------------------------------------------------- */
    init3DTilt() {
      const cards = document.querySelectorAll('.card-3d, .price-card-motion');
      cards.forEach(card => {
        card.addEventListener('mousemove', (e) => {
          const rect = card.getBoundingClientRect();
          const x = e.clientX - rect.left;
          const y = e.clientY - rect.top;

          const centerX = rect.width / 2;
          const centerY = rect.height / 2;

          const rotateX = ((y - centerY) / centerY) * -6;
          const rotateY = ((x - centerX) / centerX) * 6;

          card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-6px)`;
        });

        card.addEventListener('mouseleave', () => {
          card.style.transform = 'perspective(1000px) rotateX(0deg) rotateY(0deg) translateY(0px)';
        });
      });
    }

    /* ----------------------------------------------------
       2. MOTION.SO SPLIT TELEMETRY — LEFT CARDS & RIGHT STAGE
       ---------------------------------------------------- */
    initSplitTelemetry() {
      if (!this.telemetryCanvas) return;
      this.ctx = this.telemetryCanvas.getContext('2d');

      // Sol Kart Tıklama Olayları
      const sideCards = document.querySelectorAll('.telemetry-side-card');
      sideCards.forEach(card => {
        card.addEventListener('click', () => {
          const mode = card.dataset.mode;
          if (!mode || !this.MODES[mode]) return;

          sideCards.forEach(c => {
            c.classList.remove('is-active');
            c.setAttribute('aria-selected', 'false');
          });
          card.classList.add('is-active');
          card.setAttribute('aria-selected', 'true');

          this.switchMode(mode);
        });
      });

      // Kontrol Butonları
      const pauseBtn = document.getElementById('btnPauseTelemetry');
      if (pauseBtn) {
        pauseBtn.addEventListener('click', () => {
          this.isPaused = !this.isPaused;
          pauseBtn.innerHTML = this.isPaused ? '▶️ Devam Et' : '⏸️ Duraklat';
          pauseBtn.classList.toggle('is-active', this.isPaused);
          const statusText = document.getElementById('stageTelemetryStatusText');
          if (statusText) {
            statusText.textContent = this.isPaused ? 'TELEMETRİ DONDURULDU (PAUSED)' : 'CANLI TELEMETRİ AKIŞI AKTİF (60 FPS)';
          }
        });
      }

      const syncBtn = document.getElementById('btnSyncThrottle');
      if (syncBtn) {
        syncBtn.addEventListener('click', () => {
          this.syncWithThrottle = !this.syncWithThrottle;
          syncBtn.classList.toggle('is-active', this.syncWithThrottle);
        });
      }

      // Mouse Hover Scrubber on Canvas
      this.telemetryCanvas.addEventListener('mousemove', (e) => {
        const rect = this.telemetryCanvas.getBoundingClientRect();
        this.mouseX = e.clientX - rect.left;
        this.mouseY = e.clientY - rect.top;
      });

      this.telemetryCanvas.addEventListener('mouseleave', () => {
        this.mouseX = -1;
        this.mouseY = -1;
        if (this.tooltip) {
          this.tooltip.style.opacity = '0';
        }
      });

      // Initial history population
      for (let i = 0; i < this.maxHistoryPoints; i++) {
        this.telemetryHistory.push(this.generatePoint(i));
      }

      this.startTelemetryLoop();
    }

    switchMode(mode) {
      this.currentMode = mode;
      const config = this.MODES[mode];

      // Update right stage headers
      const titleEl = document.getElementById('stageTitle');
      const subEl = document.getElementById('stageSubtitle');
      const peakEl = document.getElementById('stageMetricPeak');

      if (titleEl) titleEl.textContent = config.title;
      if (subEl) subEl.textContent = config.subtitle;
      if (peakEl) peakEl.textContent = config.peakVal;

      // Animate stage with subtle pulse
      const stage = document.querySelector('.telemetry-right-stage');
      if (stage) {
        stage.style.transition = 'box-shadow 0.3s ease';
        stage.style.boxShadow = `0 25px 60px -15px rgba(0, 0, 0, 0.8), 0 0 35px -5px ${config.glowColor}`;
      }
    }

    generatePoint(tick) {
      let speedKmH = 65;
      if (this.syncWithThrottle && window.etubuSoundStudio) {
        speedKmH = window.etubuSoundStudio.speedKmH;
      }
      const speedNorm = Math.min(Math.max(speedKmH / 260, 0), 1);

      return {
        power: Math.round(speedNorm * 650 + Math.sin(tick * 0.1) * 25 + Math.random() * 8),
        rpm: Math.round(800 + speedNorm * 16500 + Math.sin(tick * 0.15) * 200),
        regen: Math.round(speedNorm < 0.08 ? 35 : Math.max(0, 20 - speedNorm * 20) + Math.sin(tick * 0.1) * 4),
        spectrum: Math.round(400 + speedNorm * 8800 + Math.sin(tick * 0.25) * 600)
      };
    }

    startTelemetryLoop() {
      const canvas = this.telemetryCanvas;
      const ctx = this.ctx;
      let tick = 0;

      const render = () => {
        tick++;

        // Canvas Boyutlandırma
        if (canvas.width !== canvas.clientWidth) {
          canvas.width = canvas.clientWidth;
          canvas.height = canvas.clientHeight;
        }

        const w = canvas.width;
        const h = canvas.height;

        ctx.clearRect(0, 0, w, h);

        // Tarihçe Güncelleme (her 2 framede bir)
        if (!this.isPaused && tick % 2 === 0) {
          this.telemetryHistory.shift();
          this.telemetryHistory.push(this.generatePoint(tick));
        }

        const config = this.MODES[this.currentMode];
        const lastVal = this.telemetryHistory[this.telemetryHistory.length - 1][this.currentMode];

        // Sol Kart Rozetlerini ve Sağ Canlı Değeri Güncelle
        this.updateBadges(lastVal);

        // 1. Fütüristik Izgara Çizgileri (Grid)
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
        ctx.lineWidth = 1;
        const gridStepY = 35;
        for (let y = 0; y < h; y += gridStepY) {
          ctx.beginPath();
          ctx.moveTo(0, y);
          ctx.lineTo(w, y);
          ctx.stroke();
        }

        const gridStepX = 60;
        for (let x = 0; x < w; x += gridStepX) {
          ctx.beginPath();
          ctx.moveTo(x, 0);
          ctx.lineTo(x, h);
          ctx.stroke();
        }

        // 2. Noktaları Hesapla
        const stepX = w / (this.telemetryHistory.length - 1);
        const points = this.telemetryHistory.map((item, idx) => {
          const val = item[this.currentMode];
          const normY = Math.min(Math.max(val / config.maxVal, 0.02), 0.98);
          return {
            x: idx * stepX,
            y: h - normY * (h - 30) - 15,
            val: val
          };
        });

        if (points.length > 1) {
          // 3. Akıcı Bezier Eğrisi (Spline Path)
          ctx.beginPath();
          ctx.moveTo(points[0].x, points[0].y);

          for (let i = 0; i < points.length - 1; i++) {
            const xc = (points[i].x + points[i + 1].x) / 2;
            const yc = (points[i].y + points[i + 1].y) / 2;
            ctx.quadraticCurveTo(points[i].x, points[i].y, xc, yc);
          }
          ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);

          // 4. Çizgi Konturu ve Neon Parıltısı
          ctx.strokeStyle = config.color;
          ctx.lineWidth = 3;
          ctx.shadowColor = config.color;
          ctx.shadowBlur = 14;
          ctx.stroke();

          // 5. Degrade Alan Doldurma
          ctx.lineTo(w, h);
          ctx.lineTo(0, h);
          ctx.closePath();

          const grad = ctx.createLinearGradient(0, 0, 0, h);
          grad.addColorStop(0, config.gradientStart);
          grad.addColorStop(1, config.gradientEnd);
          ctx.fillStyle = grad;
          ctx.shadowBlur = 0;
          ctx.fill();

          // 6. Uç Noktada Nabız Gibi Atan Dalga Halkaları (Pulse Radar Effect)
          const lastPt = points[points.length - 1];
          const pulseRadius = 6 + (Math.sin(tick * 0.1) + 1) * 6;

          // Dış genişleyen halka
          ctx.beginPath();
          ctx.arc(lastPt.x - 4, lastPt.y, pulseRadius, 0, Math.PI * 2);
          ctx.strokeStyle = config.color;
          ctx.lineWidth = 1.5;
          ctx.globalAlpha = Math.max(0, 1 - pulseRadius / 18);
          ctx.stroke();
          ctx.globalAlpha = 1.0;

          // İç katı nokta
          ctx.beginPath();
          ctx.arc(lastPt.x - 4, lastPt.y, 5, 0, Math.PI * 2);
          ctx.fillStyle = '#ffffff';
          ctx.shadowColor = config.color;
          ctx.shadowBlur = 18;
          ctx.fill();
          ctx.shadowBlur = 0;

          // 7. İnteraktif Fare Gezintisi (Scrubber Line & Tooltip)
          if (this.mouseX >= 0 && this.mouseX <= w) {
            // En yakın veri noktasını bul
            const closestIdx = Math.round(this.mouseX / stepX);
            const clampedIdx = Math.max(0, Math.min(points.length - 1, closestIdx));
            const targetPt = points[clampedIdx];

            // Dikey Scrubber Çizgisi
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
            ctx.lineWidth = 1;
            ctx.setLineDash([4, 4]);
            ctx.beginPath();
            ctx.moveTo(targetPt.x, 0);
            ctx.lineTo(targetPt.x, h);
            ctx.stroke();
            ctx.setLineDash([]);

            // Scrubber Kesişim Noktası
            ctx.beginPath();
            ctx.arc(targetPt.x, targetPt.y, 7, 0, Math.PI * 2);
            ctx.fillStyle = config.color;
            ctx.strokeStyle = '#ffffff';
            ctx.lineWidth = 2;
            ctx.fill();
            ctx.stroke();

            // Tooltip Göster
            if (this.tooltip) {
              this.tooltip.style.opacity = '1';
              this.tooltip.style.left = `${targetPt.x}px`;
              this.tooltip.style.top = `${targetPt.y - 12}px`;
              this.tooltip.innerHTML = `<span>${config.title.split(' ')[0]}: <strong>${targetPt.val.toLocaleString()} ${config.unit}</strong></span>`;
            }
          }
        }

        requestAnimationFrame(render);
      };

      requestAnimationFrame(render);
    }

    updateBadges(currentVal) {
      const config = this.MODES[this.currentMode];
      
      // Sağ sahne canlı değer kutusu
      const liveMetricEl = document.getElementById('stageMetricLive');
      if (liveMetricEl) {
        liveMetricEl.textContent = `${currentVal.toLocaleString()} ${config.unit}`;
      }

      // Sol kart minik sayaç rozetleri
      const pBadge = document.getElementById('sideBadgePower');
      const rBadge = document.getElementById('sideBadgeRpm');
      const gBadge = document.getElementById('sideBadgeRegen');
      const sBadge = document.getElementById('sideBadgeSpectrum');

      const latest = this.telemetryHistory[this.telemetryHistory.length - 1];
      if (!latest) return;

      if (pBadge) pBadge.textContent = `+${latest.power} kW`;
      if (rBadge) rBadge.textContent = `${latest.rpm.toLocaleString()} RPM`;
      if (gBadge) gBadge.textContent = `%${Math.min(99, Math.round(latest.regen * 1.8))}`;
      if (sBadge) sBadge.textContent = `${latest.spectrum} Hz`;
    }

    /* ----------------------------------------------------
       3. AMBIENT MOUSE LIGHTING TRACKER (motion.so style)
       ---------------------------------------------------- */
    initAmbientLighting() {
      const orb1 = document.querySelector('.ambient-glow--1');
      if (!orb1) return;

      window.addEventListener('mousemove', (e) => {
        const mouseX = e.clientX / window.innerWidth - 0.5;
        const mouseY = e.clientY / window.innerHeight - 0.5;

        orb1.style.transform = `translateX(calc(-50% + ${mouseX * 60}px)) translateY(${mouseY * 40}px)`;
      });
    }

    /* ----------------------------------------------------
       4. SECURITY SHIELD & DATA INTEGRITY ENGINE
       ---------------------------------------------------- */
    initSecurityShield() {
      // Ensure click handlers use secure attributes
      document.querySelectorAll('a[target="_blank"]').forEach(a => {
        a.setAttribute('rel', 'noopener noreferrer');
      });

      // Secure storage with integrity check
      try {
        const testKey = '__etubu_sec_test__';
        localStorage.setItem(testKey, '1');
        localStorage.removeItem(testKey);
      } catch (err) {
        console.info('Secure storage fallback active');
      }

      // App entry handler
      const startLinks = document.querySelectorAll('.js-start-app');
      startLinks.forEach(link => {
        link.addEventListener('click', () => {
          try {
            localStorage.setItem('etubu_dash', '1');
            document.cookie = 'etubu_dash=1;max-age=31536000;path=/;SameSite=Lax;Secure';
          } catch (err) {}
        });
      });
    }
  }

  // Initialize
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      window.etubuMotion = new MotionExperience();
    });
  } else {
    window.etubuMotion = new MotionExperience();
  }
})();
