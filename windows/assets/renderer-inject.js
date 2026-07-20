((cssText, artDataUrl, themeConfig) => {
  const STATE_KEY = "__CODEX_DREAM_SKIN_STATE__";
  const STYLE_ID = "codex-dream-skin-style";
  const CHROME_ID = "codex-dream-skin-chrome";
  const THEME = themeConfig && typeof themeConfig === "object" ? themeConfig : {};
  const THEME_VARIABLES = {
    background: "--ds-bg",
    backgroundAlt: "--ds-bg-alt",
    panel: "--ds-panel",
    panelAlt: "--ds-panel-alt",
    accent: "--ds-accent",
    accentAlt: "--ds-accent-alt",
    secondary: "--ds-secondary",
    highlight: "--ds-highlight",
    ink: "--ds-ink",
    muted: "--ds-muted",
    line: "--ds-line",
    onAccent: "--ds-on-accent",
  };
  const ROOT_CLASSES = [
    "codex-dream-skin",
    "dream-art-full-window",
    "dream-art-home-card",
    "dream-art-wide",
    "dream-art-standard",
    "dream-focus-left",
    "dream-focus-center",
    "dream-focus-right",
    "dream-safe-left",
    "dream-safe-center",
    "dream-safe-right",
    "dream-safe-none",
  ];
  const ROOT_PROPERTIES = [
    "--dream-art",
    "--dream-art-position",
    "--dream-focus-x",
    "--dream-focus-y",
    "--dream-image-luma",
  ];
  const clamp = (value, minimum = 0, maximum = 1) =>
    Math.min(maximum, Math.max(minimum, Number(value)));
  const hasNumber = (value) =>
    (typeof value === "number" || (typeof value === "string" && value.trim() !== "")) &&
    Number.isFinite(Number(value));
  const rawArt = THEME.art && typeof THEME.art === "object" ? THEME.art : {};
  const artConfig = {
    presentation: ["full-window", "home-card"].includes(rawArt.presentation)
      ? rawArt.presentation
      : "home-card",
    focusX: hasNumber(rawArt.focusX) ? clamp(rawArt.focusX) : null,
    focusY: hasNumber(rawArt.focusY) ? clamp(rawArt.focusY) : null,
    safeArea: ["auto", "left", "right", "center", "none"].includes(rawArt.safeArea)
      ? rawArt.safeArea
      : "auto",
  };
  const defaultProfile = {
    focusX: .5,
    focusY: .5,
    aspect: 16 / 10,
    luma: .5,
    safeArea: "center",
  };
  window.__CODEX_DREAM_SKIN_DISABLED__ = false;

  const previous = window[STATE_KEY];
  if (previous?.observer) previous.observer.disconnect();
  if (previous?.timer) clearInterval(previous.timer);
  if (previous?.scheduler?.timeout) clearTimeout(previous.scheduler.timeout);
  if (previous?.artUrl) URL.revokeObjectURL(previous.artUrl);
  const artUrl = (() => {
    const comma = artDataUrl.indexOf(",");
    const mime = /^data:([^;,]+)/.exec(artDataUrl)?.[1] || "image/png";
    const binary = atob(artDataUrl.slice(comma + 1));
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return URL.createObjectURL(new Blob([bytes], { type: mime }));
  })();
  const existingStyle = document.getElementById(STYLE_ID);
  if (existingStyle) {
    existingStyle.textContent = cssText;
    existingStyle.dataset.dreamVersion = "2";
  }
  let profile = { ...defaultProfile };

  const analyzeArt = () => new Promise((resolve) => {
    if (typeof Image !== "function") {
      resolve(defaultProfile);
      return;
    }
    const image = new Image();
    image.onload = () => {
      try {
        const width = 48;
        const height = Math.max(12, Math.round(width * image.naturalHeight / image.naturalWidth));
        const canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        const context = canvas.getContext?.("2d", { willReadFrequently: true });
        if (!context) throw new Error("Canvas is unavailable");
        context.drawImage(image, 0, 0, width, height);
        const pixels = context.getImageData(0, 0, width, height).data;
        const samples = [];
        let totalLuma = 0;
        for (let offset = 0; offset < pixels.length; offset += 4) {
          if (pixels[offset + 3] < 96) continue;
          const red = pixels[offset];
          const green = pixels[offset + 1];
          const blue = pixels[offset + 2];
          const luma = (.2126 * red + .7152 * green + .0722 * blue) / 255;
          const maximum = Math.max(red, green, blue);
          const minimum = Math.min(red, green, blue);
          const saturation = maximum ? (maximum - minimum) / maximum : 0;
          const sample = { index: offset / 4, luma, saturation };
          samples.push(sample);
          totalLuma += luma;
        }
        if (!samples.length) throw new Error("Image contains no opaque pixels");
        const averageLuma = totalLuma / samples.length;
        const zoneInformation = (start, end) => {
          const zone = samples.filter((sample) => {
            const x = sample.index % width;
            return x >= start && x < end;
          });
          if (!zone.length) return 1;
          const mean = zone.reduce((total, sample) => total + sample.luma, 0) / zone.length;
          const variance = zone.reduce((total, sample) =>
            total + (sample.luma - mean) ** 2, 0) / zone.length;
          const saturation = zone.reduce((total, sample) => total + sample.saturation, 0) / zone.length;
          return Math.sqrt(variance) * .68 + saturation * .32;
        };
        const zoneWidth = Math.max(1, Math.floor(width * .38));
        const leftInformation = zoneInformation(0, zoneWidth);
        const rightInformation = zoneInformation(width - zoneWidth, width);
        let safeArea = "center";
        if (leftInformation < rightInformation * .86) safeArea = "left";
        else if (rightInformation < leftInformation * .86) safeArea = "right";
        let focusWeight = 0;
        let focusX = 0;
        let focusY = 0;
        for (const sample of samples) {
          const x = sample.index % width;
          const y = Math.floor(sample.index / width);
          const weight = .04 + Math.abs(sample.luma - averageLuma) + sample.saturation * .7;
          focusX += (x / Math.max(1, width - 1)) * weight;
          focusY += (y / Math.max(1, height - 1)) * weight;
          focusWeight += weight;
        }
        let resolvedFocusX = clamp(focusX / focusWeight);
        if (safeArea === "left") resolvedFocusX = Math.max(.64, resolvedFocusX);
        if (safeArea === "right") resolvedFocusX = Math.min(.36, resolvedFocusX);
        resolve({
          focusX: resolvedFocusX,
          focusY: clamp(focusY / focusWeight),
          aspect: image.naturalWidth / Math.max(1, image.naturalHeight),
          luma: clamp(averageLuma),
          safeArea,
        });
      } catch {
        resolve(defaultProfile);
      }
    };
    image.onerror = () => resolve(defaultProfile);
    image.src = artUrl;
  });

  const applyArtProfile = (root) => {
    const focusX = artConfig.focusX ?? profile.focusX;
    const focusY = artConfig.focusY ?? profile.focusY;
    const focus = focusX < .4 ? "left" : focusX > .6 ? "right" : "center";
    const safeArea = artConfig.safeArea === "auto"
      ? (profile.safeArea || (focus === "left" ? "right" : focus === "right" ? "left" : "center"))
      : artConfig.safeArea;
    root.classList.toggle("dream-art-full-window", artConfig.presentation === "full-window");
    root.classList.toggle("dream-art-home-card", artConfig.presentation === "home-card");
    root.classList.toggle("dream-art-wide", profile.aspect >= 1.75);
    root.classList.toggle("dream-art-standard", profile.aspect < 1.75);
    for (const value of ["left", "center", "right"]) {
      root.classList.toggle(`dream-focus-${value}`, focus === value);
    }
    for (const value of ["left", "center", "right", "none"]) {
      root.classList.toggle(`dream-safe-${value}`, safeArea === value);
    }
    root.style.setProperty("--dream-art", `url("${artUrl}")`);
    root.style.setProperty("--dream-art-position", `${Math.round(focusX * 100)}% ${Math.round(focusY * 100)}%`);
    root.style.setProperty("--dream-focus-x", String(focusX));
    root.style.setProperty("--dream-focus-y", String(focusY));
    root.style.setProperty("--dream-image-luma", profile.luma.toFixed(3));
    root.dataset.dreamArtMode = artConfig.presentation;
  };

  const clearSkinDom = () => {
    const root = document.documentElement;
    for (const className of ROOT_CLASSES) root?.classList.remove(className);
    for (const property of ROOT_PROPERTIES) root?.style.removeProperty(property);
    for (const variable of Object.values(THEME_VARIABLES)) root?.style.removeProperty(variable);
    root?.style.removeProperty("--ds-tagline");
    root?.style.removeProperty("--ds-project-prefix");
    root?.removeAttribute("data-dream-theme");
    root?.removeAttribute("data-dream-scheme");
    root?.removeAttribute("data-dream-art-mode");
    document.querySelectorAll(".dream-home").forEach((node) => node.classList.remove("dream-home"));
    document.querySelectorAll(".dream-task").forEach((node) => node.classList.remove("dream-task"));
    document.querySelectorAll(".dream-home-shell").forEach((node) => node.classList.remove("dream-home-shell"));
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(CHROME_ID)?.remove();
  };

  const ensure = () => {
    if (window.__CODEX_DREAM_SKIN_DISABLED__) return;
    const root = document.documentElement;
    if (!root || !document.body) return;

    const shellMain = document.querySelector("main.main-surface");
    const shellSidebar = document.querySelector("aside.app-shell-left-panel");
    if (!shellMain || !shellSidebar) {
      clearSkinDom();
      return;
    }

    root.classList.add("codex-dream-skin");
    applyArtProfile(root);
    for (const [key, variable] of Object.entries(THEME_VARIABLES)) {
      const value = THEME.colors?.[key];
      if (typeof value === "string") root.style.setProperty(variable, value);
    }
    root.style.setProperty("--ds-tagline", JSON.stringify(THEME.description || THEME.brandSubtitle || "Dream Skin"));
    root.style.setProperty("--ds-project-prefix", JSON.stringify(`${THEME.name || "Dream Skin"} · `));
    root.dataset.dreamTheme = THEME.id || "pink-dream";
    root.dataset.dreamScheme = THEME.scheme === "dark" ? "dark" : "light";

    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      (document.head || root).appendChild(style);
    }
    if (style.dataset.dreamVersion !== "2") {
      style.textContent = cssText;
      style.dataset.dreamVersion = "2";
    }

    const home = document.querySelector('[role="main"]:has([data-testid="home-icon"])');
    for (const candidate of document.querySelectorAll('[role="main"]')) {
      candidate.classList.toggle("dream-home", candidate === home);
      candidate.classList.toggle("dream-task", candidate !== home);
    }

    shellMain.classList.toggle("dream-home-shell", Boolean(home));
    let chrome = document.getElementById(CHROME_ID);
    if (!chrome || chrome.parentElement !== document.body) {
      chrome?.remove();
      chrome = document.createElement("div");
      chrome.id = CHROME_ID;
      chrome.setAttribute("aria-hidden", "true");
      chrome.innerHTML = `
        <div class="dream-brand"><span class="dream-note" data-dream-note></span><span><b data-dream-title></b><small data-dream-subtitle></small></span></div>
        <div class="dream-signature" data-dream-signature></div>
        <div class="dream-sparkles"><i></i><i></i><i></i><i></i><i></i><i></i></div>
        <div class="dream-ribbon" data-dream-ribbon></div>
        <div class="dream-polaroid"></div>`;
      document.body.appendChild(chrome);
    }
    if (chrome.dataset.dreamTheme !== root.dataset.dreamTheme) {
      chrome.querySelector("[data-dream-note]").textContent = THEME.note || "✦";
      chrome.querySelector("[data-dream-title]").textContent = THEME.brandTitle || THEME.name || "Codex Dream Skin";
      chrome.querySelector("[data-dream-subtitle]").textContent = THEME.brandSubtitle || "CODEX DREAM SKIN";
      chrome.querySelector("[data-dream-signature]").textContent = THEME.signature || THEME.name || "Dream Skin";
      chrome.querySelector("[data-dream-ribbon]").textContent = THEME.ribbon || "✦";
      chrome.dataset.dreamTheme = root.dataset.dreamTheme;
    }
    const shellBox = shellMain.getBoundingClientRect();
    chrome.style.left = `${Math.round(shellBox.left)}px`;
    chrome.style.top = `${Math.round(shellBox.top)}px`;
    chrome.style.width = `${Math.round(shellBox.width)}px`;
    chrome.style.height = `${Math.round(shellBox.height)}px`;
    chrome.classList.toggle("dream-home-shell", Boolean(home));
  };

  const cleanup = () => {
    window.__CODEX_DREAM_SKIN_DISABLED__ = true;
    clearSkinDom();
    const state = window[STATE_KEY];
    state?.observer?.disconnect();
    if (state?.timer) clearInterval(state.timer);
    if (state?.scheduler?.timeout) clearTimeout(state.scheduler.timeout);
    if (state?.artUrl) URL.revokeObjectURL(state.artUrl);
    delete window[STATE_KEY];
    return true;
  };

  const scheduler = { timeout: null };
  const scheduleEnsure = () => {
    if (scheduler.timeout) clearTimeout(scheduler.timeout);
    scheduler.timeout = setTimeout(() => {
      scheduler.timeout = null;
      ensure();
    }, 180);
  };
  const observer = new MutationObserver(scheduleEnsure);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  const timer = setInterval(ensure, 5000);
  window[STATE_KEY] = {
    ensure,
    cleanup,
    observer,
    timer,
    scheduler,
    artUrl,
    profile,
    artConfig,
    version: "1.1.0",
    themeId: THEME.id || "pink-dream",
    themeName: THEME.name || "Dream Skin",
    scheme: THEME.scheme === "dark" ? "dark" : "light",
    presentation: artConfig.presentation,
  };
  ensure();
  analyzeArt().then((result) => {
    const state = window[STATE_KEY];
    if (!state || state.artUrl !== artUrl || window.__CODEX_DREAM_SKIN_DISABLED__) return;
    profile = result;
    state.profile = result;
    ensure();
  });
  return {
    installed: true,
    version: "1.1.0",
    themeId: window[STATE_KEY].themeId,
    presentation: artConfig.presentation,
    adaptive: true,
  };
})(__DREAM_CSS_JSON__, __DREAM_ART_JSON__, __DREAM_THEME_JSON__)
