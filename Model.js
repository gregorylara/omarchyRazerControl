.pragma library

function parseOutput(rawText) {
  var result = {
    connected: false,
    name: "Razer Mouse",
    pid: "0x0000",
    supports_8k: false,
    hidraw_path: "",
    has_permission: false,
    activeProfile: "onboard-1",
    activeProfileName: "Profile 1",
    onboardSlot: 1,
    dpi: 1600,
    dpi_stages: [400, 800, 1600, 3200, 6400],
    active_stage: 3,
    poll_rate: 1000,
    brightness: 100,
    effect: "spectrum",
    effect_color: "#00FF66",
    profiles: []
  };

  if (!rawText || typeof rawText !== "string") return result;

  try {
    var clean = rawText.trim();
    var firstBrace = clean.indexOf("{");
    var lastBrace = clean.lastIndexOf("}");
    if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
      clean = clean.substring(firstBrace, lastBrace + 1);
    }
    var data = JSON.parse(clean);
    if (data) {
      result.connected = Boolean(data.connected);
      result.name = data.name || "Razer Device";
      result.pid = data.pid || "0x0000";
      result.supports_8k = Boolean(data.supports_8k);
      result.hidraw_path = data.hidraw_path || "";
      result.has_permission = Boolean(data.has_permission);
      result.activeProfile = data.activeProfile || "onboard-1";
      result.activeProfileName = data.activeProfileName || "Profile 1";
      result.onboardSlot = Number(data.onboardSlot) || 1;
      result.dpi = Number(data.dpi) || 1600;
      result.dpi_stages = Array.isArray(data.dpi_stages) ? data.dpi_stages : [400, 800, 1600, 3200, 6400];
      result.active_stage = Number(data.active_stage) || 3;
      result.poll_rate = Number(data.poll_rate) || 1000;
      result.brightness = Number(data.brightness) || 100;
      result.effect = data.effect || "spectrum";
      result.effect_color = data.effect_color || "#00FF00";
      result.profiles = Array.isArray(data.profiles) ? data.profiles : [];
    }
  } catch (e) {
    console.warn("Razer plugin: failed to parse JSON:", e);
  }

  return result;
}

function badgeColorForSlot(slot) {
  switch (Number(slot)) {
    case 1: return "#FFFFFF";
    case 2: return "#FF0000";
    case 3: return "#00FF00";
    case 4: return "#0066FF";
    case 5: return "#00FFFF";
    default: return "#00FF00";
  }
}

function pollRateLabel(rate) {
  if (rate >= 1000) {
    return (rate / 1000) + " kHz (" + rate + " Hz)";
  }
  return rate + " Hz";
}

var translations = {
  en: {
    disconnected: "(disconnected)",
    razerMouse: "Razer Mouse",
    razerMouseDetected: "Razer mouse detected",
    deviceNotDetected: "No device detected",
    onboardStatus: "On-Board",
    udevPermissionsStatus: "udev Permissions",
    disconnectedStatus: "Disconnected",
    udevRequiredTitle: "udev permissions required",
    udevRequiredDesc: "To apply hardware changes to the mouse, install the user access rule.",
    activateBtn: "Enable",
    onboardProfilesTitle: "ON-BOARD MEMORY PROFILES",
    saveToMouseBtn: "Save to mouse",
    sensitivityTitle: "SENSITIVITY (DPI)",
    stageLabel: "Stage",
    pollingRateTitle: "POLLING RATE",
    chromaLightingTitle: "CHROMA RGB LIGHTING",
    effectSpectrum: "Spectrum",
    effectStatic: "Static",
    effectBreathing: "Breathing",
    effectOff: "Off"
  },
  es: {
    disconnected: "(desconectado)",
    razerMouse: "Ratón Razer",
    razerMouseDetected: "Ratón Razer detectado",
    deviceNotDetected: "Dispositivo no detectado",
    onboardStatus: "On-Board",
    udevPermissionsStatus: "Permisos udev",
    disconnectedStatus: "Desconectado",
    udevRequiredTitle: "Permisos udev requeridos",
    udevRequiredDesc: "Para aplicar cambios de hardware al ratón, instala la regla de acceso de usuario.",
    activateBtn: "Activar",
    onboardProfilesTitle: "PERFILES EN MEMORIA (ON-BOARD)",
    saveToMouseBtn: "Guardar en ratón",
    sensitivityTitle: "SENSIBILIDAD (DPI)",
    stageLabel: "Etapa",
    pollingRateTitle: "TASA DE SONDEO (POLLING RATE)",
    chromaLightingTitle: "ILUMINACIÓN CHROMA RGB",
    effectSpectrum: "Espectro",
    effectStatic: "Estático",
    effectBreathing: "Respiración",
    effectOff: "Off"
  }
};

function t(key, lang) {
  var l = (lang === "es") ? "es" : "en";
  if (translations[l] && translations[l][key] !== undefined) {
    return translations[l][key];
  }
  if (translations["en"] && translations["en"][key] !== undefined) {
    return translations["en"][key];
  }
  return key;
}

function effectOptions(lang) {
  return [
    { value: "spectrum", label: t("effectSpectrum", lang) },
    { value: "static", label: t("effectStatic", lang) },
    { value: "breathing", label: t("effectBreathing", lang) },
    { value: "off", label: t("effectOff", lang) }
  ];
}

function effectLabel(eff, lang) {
  var l = (lang === "es") ? "es" : "en";
  switch (eff) {
    case "static": return t("effectStatic", l);
    case "spectrum": return l === "es" ? "Ciclo Espectro" : "Spectrum Cycling";
    case "breathing": return t("effectBreathing", l);
    case "off": return l === "es" ? "Apagado" : "Off";
    default: return eff;
  }
}

function pollOptions(supports8k) {
  if (supports8k) {
    return [
      { value: "125", label: "125" },
      { value: "500", label: "500" },
      { value: "1000", label: "1K" },
      { value: "2000", label: "2K" },
      { value: "4000", label: "4K" },
      { value: "8000", label: "8K" }
    ];
  }
  return [
    { value: "125", label: "125 Hz" },
    { value: "500", label: "500 Hz" },
    { value: "1000", label: "1000 Hz" }
  ];
}
