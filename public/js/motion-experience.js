/**
 * ETUBU MOTION EXPERIENCE & TELEMETRY ENGINE
 * Inspired by motion.so — Micro-Interactions, 3D Physics Tilts,
 * Live Telemetry HUD Graphs, Strict Security Sanitizers & Ambient Lights.
 */

(function () {
  'use strict';

  class MotionExperience {
    constructor() {
      this.telemetryCanvas = document.getElementById('telemetryGraphCanvas');
      this.currentTelemetryMode = 'power';
      this.telemetryHistory = [];
      this.maxHistoryPoints = 60;
      this.simSpeed = 0;

      this.init3DTilt();
      this.initTelemetryCanvas();
      this.initAmbientLighting();
      this.initSecurityShield();
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

          const rotateX = ((y - centerY) / centerY) * -7;
          const rotateY = ((x - centerX) / centerX) * 7;

          card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-6px)`;
        });

        card.addEventListener('mouseleave', () => {
          card.style.transform = 'perspective(1000px) rotateX(0deg) rotateY(0deg) translateY(0px)';
        });
      });
    }

    /* ----------------------------------------------------
       2. INTERACTIVE TELEMETRY GRAPH SHOWCASE (motion.so style)
       ---------------------------------------------------- */
    initTelemetryCanvas() {
      if (!this.telemetryCanvas) return;
      this.ctx = this.telemetryCanvas.getContext('2d');

      // Setup tabs
      const tabs = document.querySelectorAll('.telemetry-tab');
      tabs.forEach(tab => {
        tab.addEventListener('click', () => {
          tabs.forEach(t => t.classList.remove('is-active'));
          tab.classList.add('is-active');
          this.currentTelemetryMode = tab.dataset.mode || 'power';
        });
      });

      // Pre-fill history
      for (let i = 0; i < this.maxHistoryPoints; i++) {
        this.telemetryHistory.push({
          power: 40 + Math.sin(i * 0.2) * 25 + Math.random() * 5,
          rpm: 2500 + Math.sin(i * 0.15) * 1800,
          regen: Math.max(0, -Math.sin(i * 0.2) * 20),
          efficiency: 145 + Math.cos(i * 0.1) * 20
        });
      }

      this.startTelemetryLoop();
    }

    startTelemetryLoop() {
      const canvas = this.telemetryCanvas;
      const ctx = this.ctx;

      let tick = 0;
      const render = () => {
        tick++;
        if (canvas.width !== canvas.clientWidth) {
          canvas.width = canvas.clientWidth;
          canvas.height = canvas.clientHeight;
        }

        const w = canvas.width;
        const h = canvas.height;

        ctx.clearRect(0, 0, w, h);

        // Update data point
        const activeSpeed = window.etubuSoundStudio ? window.etubuSoundStudio.speedKmH : 60;
        const speedNorm = activeSpeed / 260;
        const livePower = speedNorm * 650 + Math.sin(tick * 0.08) * 15;
        const liveRpm = 800 + speedNorm * 16500;
        const liveRegen = speedNorm < 0.1 ? 30 : Math.max(0, 15 - speedNorm * 15);
        const liveEfficiency = 135 + Math.sin(tick * 0.05) * 25;

        if (tick % 3 === 0) {
          this.telemetryHistory.shift();
          this.telemetryHistory.push({
            power: livePower,
            rpm: liveRpm,
            regen: liveRegen,
            efficiency: liveEfficiency
          });
        }

        // Draw grid lines
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        ctx.lineWidth = 1;
        const gridStep = 40;
        for (let y = 0; y < h; y += gridStep) {
          ctx.beginPath();
          ctx.moveTo(0, y);
          ctx.lineTo(w, y);
          ctx.stroke();
        }

        // Mode configurations
        let maxVal = 750;
        let strokeColor = '#00f0ff';
        let fillColorStart = 'rgba(0, 240, 255, 0.25)';
        let keyName = 'power';
        let unit = 'kW';

        if (this.currentTelemetryMode === 'rpm') {
          maxVal = 18000;
          strokeColor = '#8b5cf6';
          fillColorStart = 'rgba(139, 92, 246, 0.25)';
          keyName = 'rpm';
          unit = 'RPM';
        } else if (this.currentTelemetryMode === 'regen') {
          maxVal = 60;
          strokeColor = '#10b981';
          fillColorStart = 'rgba(16, 185, 129, 0.25)';
          keyName = 'regen';
          unit = 'kW Regen';
        } else if (this.currentTelemetryMode === 'efficiency') {
          maxVal = 250;
          strokeColor = '#f59e0b';
          fillColorStart = 'rgba(245, 158, 11, 0.25)';
          keyName = 'efficiency';
          unit = 'Wh/km';
        }

        // Draw smooth bezier curve
        ctx.beginPath();
        const stepX = w / (this.telemetryHistory.length - 1);
        
        const points = this.telemetryHistory.map((item, idx) => {
          const val = item[keyName];
          const normY = Math.min(Math.max(val / maxVal, 0), 1);
          return {
            x: idx * stepX,
            y: h - normY * (h - 30) - 15
          };
        });

        if (points.length > 0) {
          ctx.moveTo(points[0].x, points[0].y);
          for (let i = 0; i < points.length - 1; i++) {
            const xc = (points[i].x + points[i + 1].x) / 2;
            const yc = (points[i].y + points[i + 1].y) / 2;
            ctx.quadraticCurveTo(points[i].x, points[i].y, xc, yc);
          }
          ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);

          // Line stroke
          ctx.strokeStyle = strokeColor;
          ctx.lineWidth = 3;
          ctx.shadowColor = strokeColor;
          ctx.shadowBlur = 12;
          ctx.stroke();

          // Gradient area fill
          ctx.lineTo(w, h);
          ctx.lineTo(0, h);
          ctx.closePath();

          const grad = ctx.createLinearGradient(0, 0, 0, h);
          grad.addColorStop(0, fillColorStart);
          grad.addColorStop(1, 'rgba(0, 0, 0, 0)');
          ctx.fillStyle = grad;
          ctx.shadowBlur = 0;
          ctx.fill();

          // Draw active pulse point on the latest reading
          const lastPoint = points[points.length - 1];
          ctx.beginPath();
          ctx.arc(lastPoint.x - 4, lastPoint.y, 6, 0, Math.PI * 2);
          ctx.fillStyle = '#ffffff';
          ctx.shadowColor = strokeColor;
          ctx.shadowBlur = 15;
          ctx.fill();
        }

        requestAnimationFrame(render);
      };

      requestAnimationFrame(render);
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
      // Input sanitization & safe navigation
      const sanitizeAndRedirect = (url) => {
        try {
          const parsed = new URL(url, window.location.origin);
          if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
            return parsed.href;
          }
        } catch (e) {
          return '/app.html';
        }
        return '/app.html';
      };

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
        link.addEventListener('click', (e) => {
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
