.pragma library

function parseOutput(rawText) {
  var result = {
    connected: false,
    name: "Razer Mouse",
    pid: "0x0000",
    max_dpi: 20000,
    supports_8k: false,
    profile_mode: "dpi_led",
    hidraw_path: "",
    has_permission: false,
    activeProfile: "onboard-3",
    activeProfileName: "Profile 3",
    onboardSlot: 3,
    dpi: 4800,
    dpi_stages: [2400, 3400, 4800, 5000, 5200],
    active_stage: 3,
    poll_rate: 8000,
    battery: -1,
    charging: false,
    brightness: 100,
    effect: "static",
    effect_color: "#00FF00",
    lighting_zones: ["logo"],
    zones: {},
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
      result.max_dpi = Number(data.max_dpi) || 20000;
      result.supports_8k = Boolean(data.supports_8k);
      result.profile_mode = data.profile_mode || "dpi_led";
      result.hidraw_path = data.hidraw_path || "";
      result.has_permission = Boolean(data.has_permission);
      result.activeProfile = data.activeProfile || "onboard-3";
      result.activeProfileName = data.activeProfileName || "Profile 3";
      result.onboardSlot = Number(data.onboardSlot) || 3;
      result.dpi = Number(data.dpi) || 4800;
      result.dpi_stages = Array.isArray(data.dpi_stages) ? data.dpi_stages : [2400, 3400, 4800, 5000, 5200];
      result.active_stage = Number(data.active_stage) || 3;
      result.poll_rate = Number(data.poll_rate) || 8000;
      result.brightness = (data.brightness !== undefined) ? Number(data.brightness) : 100;
      result.battery = (data.battery === null || data.battery === undefined) ? -1 : Number(data.battery);
      result.charging = Boolean(data.charging);
      result.brightness = Number(data.brightness) || 100;
      result.effect = data.effect || "static";
      result.effect_color = data.effect_color || "#00FF00";
      result.lighting_zones = (Array.isArray(data.lighting_zones) && data.lighting_zones.length) ? data.lighting_zones : ["logo"];
      result.zones = (data.zones && typeof data.zones === "object") ? data.zones : {};
      result.profiles = Array.isArray(data.profiles) ? data.profiles : [];
    }
  } catch (e) {
    console.warn("Razer plugin: failed to parse JSON:", e);
  }

  return result;
}

function badgeColorForSlot(slot, profiles) {
  var s = Number(slot);
  if (Array.isArray(profiles)) {
    for (var i = 0; i < profiles.length; i++) {
      if (Number(profiles[i].onboardSlot) === s && profiles[i].badgeColor) {
        return profiles[i].badgeColor;
      }
    }
  }
  switch (s) {
    case 1: return "#FFFF00";
    case 2: return "#FF0000";
    case 3: return "#00FF00";
    case 4: return "#0066FF";
    case 5: return "#00FFFF";
    default: return "#00FF00";
  }
}

function defaultProfileForSlot(slot) {
  var s = Number(slot) || 1;
  var defaults = {
    1: { id: "onboard-1", name: "Profile 1 (Default / Yellow)", onboardSlot: 1, badgeColor: "#FFFF00", dpi: 2400, dpi_stages: [2400, 3400, 4800, 5000, 5200], active_stage: 1, poll_rate: 8000, brightness: 100, effect: "static", effect_color: "#FFFF00" },
    2: { id: "onboard-2", name: "Profile 2 (FPS Ultra / Red)", onboardSlot: 2, badgeColor: "#FF0000", dpi: 3400, dpi_stages: [2400, 3400, 4800, 5000, 5200], active_stage: 2, poll_rate: 8000, brightness: 100, effect: "static", effect_color: "#FF0000" },
    3: { id: "onboard-3", name: "Profile 3 (MOBA / Green)", onboardSlot: 3, badgeColor: "#00FF00", dpi: 4800, dpi_stages: [2400, 3400, 4800, 5000, 5200], active_stage: 3, poll_rate: 8000, brightness: 100, effect: "static", effect_color: "#00FF00" },
    4: { id: "onboard-4", name: "Profile 4 (Productivity / Blue)", onboardSlot: 4, badgeColor: "#0066FF", dpi: 5000, dpi_stages: [2400, 3400, 4800, 5000, 5200], active_stage: 4, poll_rate: 8000, brightness: 100, effect: "static", effect_color: "#0066FF" },
    5: { id: "onboard-5", name: "Profile 5 (Stealth / Cyan)", onboardSlot: 5, badgeColor: "#00FFFF", dpi: 5200, dpi_stages: [2400, 3400, 4800, 5000, 5200], active_stage: 5, poll_rate: 8000, brightness: 100, effect: "static", effect_color: "#00FFFF" }
  };
  return defaults[s] || defaults[3];
}

function profileForSlot(slot, profiles) {
  var s = Number(slot) || 1;
  if (Array.isArray(profiles)) {
    for (var i = 0; i < profiles.length; i++) {
      if (Number(profiles[i].onboardSlot) === s) {
        return profiles[i];
      }
    }
  }
  return defaultProfileForSlot(s);
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
    switchingProfile: "Applying profile...",
    profileSettingsBtn: "Settings",
    closeSettingsBtn: "Back",
    saveChangesBtn: "Save Changes",
    profileSettingsTitle: "PROFILE SETTINGS",
    editingProfileLabel: "Profile Slot",
    profileBadgeColorLabel: "Profile Indicator Color",
    dpiStagesEditorLabel: "DPI per Stage (1–5)",
    profilePollingLabel: "Profile Polling Rate",
    profileLightingLabel: "Profile Chroma Lighting",
    sensitivityTitle: "SENSITIVITY (DPI)",
    stageLabel: "Stage",
    pollingRateTitle: "POLLING RATE",
    chromaLightingTitle: "CHROMA RGB LIGHTING",
    effectSpectrum: "Spectrum",
    effectStatic: "Static",
    effectBreathing: "Breathing",
    effectOff: "Off",
    zoneAll: "All",
    zoneLogo: "Logo",
    zoneScroll: "Scroll",
    zoneUnderglow: "Underglow",
    zoneLeft: "Left",
    zoneRight: "Right",
    zoneBacklight: "Backlight",
    lightingMixed: "Mixed"
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
    switchingProfile: "Cambiando perfil...",
    profileSettingsBtn: "Ajustes",
    closeSettingsBtn: "Volver",
    saveChangesBtn: "Guardar cambios",
    profileSettingsTitle: "AJUSTES DE PERFILES",
    editingProfileLabel: "Seleccionar Perfil",
    profileBadgeColorLabel: "Color del Perfil",
    dpiStagesEditorLabel: "DPI de cada Stage (1–5)",
    profilePollingLabel: "Polling Rate del Perfil",
    profileLightingLabel: "Color y Efecto del Perfil",
    sensitivityTitle: "SENSIBILIDAD (DPI)",
    stageLabel: "Etapa",
    pollingRateTitle: "TASA DE SONDEO (POLLING RATE)",
    chromaLightingTitle: "ILUMINACIÓN CHROMA RGB",
    effectSpectrum: "Espectro",
    effectStatic: "Estático",
    effectBreathing: "Respiración",
    effectOff: "Off",
    zoneAll: "Todo",
    zoneLogo: "Logo",
    zoneScroll: "Rueda",
    zoneUnderglow: "Inferior",
    zoneLeft: "Izquierda",
    zoneRight: "Derecha",
    zoneBacklight: "Retroiluminación",
    lightingMixed: "Mixto"
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

function zoneOptions(zones, lang) {
  var keys = { logo: "zoneLogo", scroll: "zoneScroll", underglow: "zoneUnderglow", left: "zoneLeft", right: "zoneRight", backlight: "zoneBacklight" };
  var options = [{ value: "all", label: t("zoneAll", lang) }];
  for (var i = 0; i < zones.length; i++) {
    options.push({ value: zones[i], label: t(keys[zones[i]] || zones[i], lang) });
  }
  return options;
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
