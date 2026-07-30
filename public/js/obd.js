/**
 * OBD-II / ELM327 BLE — araç hızı (PID 0D) + RPM (PID 0C).
 * Bağlıyken GPS yerine birincil hız kaynağı olur.
 */
const ObdLink = (() => {
  const SPEED_PID = "010D";
  const RPM_PID = "010C";
  const POLL_MS = 70;

  let device = null;
  let rxChar = null;
  let txChar = null;
  let pollTimer = null;
  let buffer = "";
  let connected = false;
  let lastKmh = 0;
  let lastRpm = null;

  function t(key, vars) {
    return typeof I18n !== "undefined" ? I18n.t(key, vars) : key;
  }

  function setNote(msg) {
    const el = document.getElementById("obdStatusNote");
    if (el) el.textContent = msg;
    const btn = document.getElementById("obdConnectBtn");
    if (btn) {
      btn.textContent = connected ? t("obdDisconnect") : t("obdConnect");
      btn.classList.toggle("obd-active", connected);
    }
  }

  function supported() {
    return !!(navigator.bluetooth && navigator.bluetooth.requestDevice);
  }

  function pushSpeed(kmh, rpm) {
    lastKmh = Math.max(0, kmh);
    if (rpm != null) lastRpm = rpm;
    GpsTracker.setExternalSpeed(lastKmh, {
      source: "obd",
      rpm: lastRpm,
    });
    AudioEngine.setSpeedSource?.("obd");
  }

  function parseLine(line) {
    const clean = line.replace(/\s+/g, "").toUpperCase();
    let m = clean.match(/410D([0-9A-F]{2})/);
    if (m) {
      const kmh = parseInt(m[1], 16);
      if (Number.isFinite(kmh)) pushSpeed(kmh, lastRpm);
      return;
    }
    m = clean.match(/410C([0-9A-F]{4})/);
    if (m) {
      const rpm = parseInt(m[1], 16) / 4;
      if (Number.isFinite(rpm)) {
        lastRpm = rpm;
        pushSpeed(lastKmh, rpm);
      }
    }
  }

  function onNotify(ev) {
    const value = ev.target.value;
    if (!value) return;
    buffer += new TextDecoder("utf-8").decode(value);
    let idx;
    while ((idx = buffer.search(/[\r\n>]/)) >= 0) {
      const line = buffer.slice(0, idx).trim();
      buffer = buffer.slice(idx + 1);
      if (line && line !== ">") parseLine(line);
    }
  }

  async function writeCmd(cmd) {
    if (!txChar) return;
    const data = new TextEncoder().encode(cmd + "\r");
    if (txChar.properties.writeWithoutResponse) {
      await txChar.writeValueWithoutResponse(data);
    } else {
      await txChar.writeValue(data);
    }
  }

  async function findUart(gattServer) {
    const uuids = [
      "0000fff0-0000-1000-8000-00805f9b34fb",
      "6e400001-b5a3-f393-e0a9-e50e24dcca9e",
      "0000ffe0-0000-1000-8000-00805f9b34fb",
    ];
    for (const u of uuids) {
      try {
        const s = await gattServer.getPrimaryService(u);
        const chars = await s.getCharacteristics();
        let rx = null;
        let tx = null;
        for (const c of chars) {
          if (c.properties.notify || c.properties.indicate) rx = c;
          if (c.properties.write || c.properties.writeWithoutResponse) tx = c;
        }
        if (rx && tx) return { rx, tx };
      } catch (_) {}
    }
    const services = await gattServer.getPrimaryServices();
    for (const s of services) {
      try {
        const chars = await s.getCharacteristics();
        let rx = null;
        let tx = null;
        for (const c of chars) {
          if (c.properties.notify || c.properties.indicate) rx = c;
          if (c.properties.write || c.properties.writeWithoutResponse) tx = c;
        }
        if (rx && tx) return { rx, tx };
      } catch (_) {}
    }
    return null;
  }

  let pollToggle = false;
  let nativeObdListener = null;

  function nativeSupported() {
    return !!window.EtubuNative?.obdBleConnect;
  }

  function handleNativeEvt(payload) {
    if (!payload || typeof payload !== "object") return;
    if (payload.type === "speed") {
      const kmh = Number(payload.kmh) || 0;
      const rpm = payload.rpm != null ? Number(payload.rpm) : null;
      pushSpeed(kmh, Number.isFinite(rpm) ? rpm : null);
      return;
    }
    if (payload.type === "status") {
      const st = String(payload.state || "");
      if (st === "connected") {
        connected = true;
        setNote(t("obdConnected", { name: payload.name || "OBD" }));
      } else if (st === "disconnected" || st === "scan_timeout" || st === "connect_failed") {
        connected = false;
        if (st === "scan_timeout") setNote(t("obdFail"));
        else setNote(t("obdDisconnected"));
      }
    }
  }
  async function pollTick() {
    if (!connected || !txChar) return;
    try {
      pollToggle = !pollToggle;
      await writeCmd(pollToggle ? SPEED_PID : RPM_PID);
    } catch (_) {}
  }

  async function connect() {
    if (nativeSupported()) {
      try {
        setNote(t("obdConnecting"));
        if (!nativeObdListener && window.EtubuNative?.addObdBleListener) {
          nativeObdListener = await window.EtubuNative.addObdBleListener(handleNativeEvt);
        }
        const res = await window.EtubuNative.obdBleConnect();
        connected = !!res?.ok;
        if (connected) {
          setNote(t("obdConnected", { name: "OBD" }));
          return true;
        }
        setNote(t("obdFail"));
        return false;
      } catch (e) {
        console.warn(e);
        setNote(t("obdFail"));
        connected = false;
        return false;
      }
    }
    if (!supported()) {
      setNote(t("obdUnsupported"));
      return false;
    }
    try {
      setNote(t("obdConnecting"));
      device = await navigator.bluetooth.requestDevice({
        acceptAllDevices: true,
        optionalServices: [
          "0000fff0-0000-1000-8000-00805f9b34fb",
          "6e400001-b5a3-f393-e0a9-e50e24dcca9e",
          "0000ffe0-0000-1000-8000-00805f9b34fb",
          "000018f0-0000-1000-8000-00805f9b34fb",
        ],
      });
      device.addEventListener("gattserverdisconnected", () => {
        connected = false;
        clearInterval(pollTimer);
        pollTimer = null;
        GpsTracker.clearExternalSpeed?.();
        AudioEngine.setSpeedSource?.("gps");
        setNote(t("obdDisconnected"));
      });
      const server = await device.gatt.connect();
      const uart = await findUart(server);
      if (!uart) {
        setNote(t("obdNoUart"));
        await disconnect();
        return false;
      }
      rxChar = uart.rx;
      txChar = uart.tx;
      await rxChar.startNotifications();
      rxChar.addEventListener("characteristicvaluechanged", onNotify);

      await writeCmd("ATZ");
      await new Promise((r) => setTimeout(r, 450));
      await writeCmd("ATE0");
      await writeCmd("ATL0");
      await writeCmd("ATS0");
      await writeCmd("ATH0");
      await writeCmd("ATSP0");

      connected = true;
      setNote(t("obdConnected", { name: device.name || "OBD" }));
      clearInterval(pollTimer);
      pollTimer = setInterval(pollTick, POLL_MS);
      return true;
    } catch (e) {
      console.warn(e);
      setNote(t("obdFail"));
      connected = false;
      return false;
    }
  }

  async function disconnect() {
    if (nativeSupported()) {
      try {
        await window.EtubuNative.obdBleDisconnect();
      } catch (_) {}
      if (nativeObdListener?.remove) {
        try {
          await nativeObdListener.remove();
        } catch (_) {}
      }
      nativeObdListener = null;
      connected = false;
      GpsTracker.clearExternalSpeed?.();
      AudioEngine.setSpeedSource?.("gps");
      setNote(t("obdDisconnected"));
      return;
    }
    clearInterval(pollTimer);
    pollTimer = null;
    try {
      if (rxChar) {
        rxChar.removeEventListener("characteristicvaluechanged", onNotify);
        await rxChar.stopNotifications().catch(() => {});
      }
    } catch (_) {}
    try {
      device?.gatt?.disconnect();
    } catch (_) {}
    device = null;
    rxChar = null;
    txChar = null;
    connected = false;
    GpsTracker.clearExternalSpeed?.();
    AudioEngine.setSpeedSource?.("gps");
    setNote(t("obdDisconnected"));
  }

  async function toggle() {
    if (connected) await disconnect();
    else await connect();
  }

  function bindUi() {
    document.getElementById("obdConnectBtn")?.addEventListener("click", () => toggle());
    refreshLocale();
  }

  function refreshLocale() {
    const btn = document.getElementById("obdConnectBtn");
    if (btn) btn.textContent = connected ? t("obdDisconnect") : t("obdConnect");
    if (!supported() && !nativeSupported()) {
      setNote(t("obdUnsupported"));
      if (btn) btn.disabled = true;
    } else if (!connected) {
      if (btn) btn.disabled = false;
      setNote(t("obdHint"));
    } else {
      setNote(t("obdConnected", { name: device?.name || "OBD" }));
    }
  }

  function init() {
    bindUi();
  }

  return {
    init,
    refreshLocale,
    connect,
    disconnect,
    toggle,
    isConnected: () => connected,
    supported,
  };
})();
