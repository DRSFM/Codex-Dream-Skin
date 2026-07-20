import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const windowsRoot = path.resolve(here, "..");
const template = await fs.readFile(path.join(windowsRoot, "assets", "renderer-inject.js"), "utf8");
const fixtureTheme = {
    id: "fixture-theme",
    name: "Fixture Theme",
    description: "Fixture description",
    scheme: "dark",
    brandTitle: "Fixture Brand",
    brandSubtitle: "Fixture Subtitle",
    signature: "Fixture Signature",
    note: "F",
    ribbon: "Fixture Ribbon",
    art: {
      presentation: "full-window",
      focusX: .72,
      focusY: .45,
      safeArea: "left",
    },
    colors: {
      background: "#111111",
      backgroundAlt: "#222222",
      panel: "#333333",
      panelAlt: "#444444",
      accent: "#555555",
      accentAlt: "#666666",
      secondary: "#777777",
      highlight: "#888888",
      ink: "#eeeeee",
      muted: "#aaaaaa",
      line: "#999999",
      onAccent: "#ffffff",
    },
  };
const buildPayload = (theme, art = "data:image/png;base64,AA==") => template
  .replace("__DREAM_CSS_JSON__", JSON.stringify(".fixture { color: blue; }"))
  .replace("__DREAM_ART_JSON__", JSON.stringify(art))
  .replace("__DREAM_THEME_JSON__", JSON.stringify(theme));
const payload = buildPayload(fixtureTheme);

function createFixture({ shellPresent, staleSkin = false }) {
  const nodes = new Map();
  const rootClasses = new Set(staleSkin ? ["codex-dream-skin"] : []);
  const rootStyles = new Map(staleSkin ? [["--dream-art", "url(\"blob:stale\")"]] : []);
  const revokedUrls = [];
  let objectUrlIndex = 0;
  let hasShell = shellPresent;

  const makeClassList = (classes = new Set()) => ({
    add(value) { classes.add(value); },
    remove(value) { classes.delete(value); },
    toggle(value, enabled) {
      if (enabled) classes.add(value);
      else classes.delete(value);
    },
  });

  const root = {
    dataset: {},
    classList: makeClassList(rootClasses),
    style: {
      setProperty(key, value) { rootStyles.set(key, value); },
      removeProperty(key) { rootStyles.delete(key); },
    },
    appendChild(node) {
      node.parentElement = root;
      nodes.set(node.id, node);
    },
    removeAttribute(name) {
      if (name === "data-dream-theme") delete this.dataset.dreamTheme;
      if (name === "data-dream-scheme") delete this.dataset.dreamScheme;
      if (name === "data-dream-art-mode") delete this.dataset.dreamArtMode;
    },
  };
  const body = {
    appendChild(node) {
      node.parentElement = body;
      nodes.set(node.id, node);
    },
  };
  const shellMain = {
    classList: makeClassList(),
    getBoundingClientRect() {
      return { left: 290, top: 36, width: 990, height: 784 };
    },
  };
  const staleHome = { classList: makeClassList(new Set(["dream-home"])) };
  const staleShell = { classList: makeClassList(new Set(["dream-home-shell"])) };

  const createElement = () => {
    const themeParts = new Map([
      ["[data-dream-note]", { textContent: "" }],
      ["[data-dream-title]", { textContent: "" }],
      ["[data-dream-subtitle]", { textContent: "" }],
      ["[data-dream-signature]", { textContent: "" }],
      ["[data-dream-ribbon]", { textContent: "" }],
    ]);
    return {
      id: "",
      dataset: {},
      style: {},
      classList: makeClassList(),
      parentElement: null,
      textContent: "",
      innerHTML: "",
      setAttribute() {},
      querySelector(selector) { return themeParts.get(selector) ?? null; },
      remove() { nodes.delete(this.id); },
    };
  };
  if (staleSkin) {
    const style = createElement();
    style.id = "codex-dream-skin-style";
    nodes.set(style.id, style);
    const chrome = createElement();
    chrome.id = "codex-dream-skin-chrome";
    nodes.set(chrome.id, chrome);
  }

  const document = {
    documentElement: root,
    head: root,
    body,
    createElement,
    getElementById(id) { return nodes.get(id) ?? null; },
    querySelector(selector) {
      if (selector === "main.main-surface") return hasShell ? shellMain : null;
      if (selector === "aside.app-shell-left-panel") return hasShell ? {} : null;
      return null;
    },
    querySelectorAll(selector) {
      if (!staleSkin) return [];
      if (selector === ".dream-home") return [staleHome];
      if (selector === ".dream-home-shell") return [staleShell];
      return [];
    },
  };
  const context = {
    window: {},
    document,
    MutationObserver: class {
      observe() {}
      disconnect() {}
    },
    URL: {
      createObjectURL() { objectUrlIndex += 1; return `blob:fixture-${objectUrlIndex}`; },
      revokeObjectURL(value) { revokedUrls.push(value); },
    },
    Blob,
    Uint8Array,
    atob,
    setInterval: () => 1,
    clearInterval: () => {},
    setTimeout: () => 2,
    clearTimeout: () => {},
  };

  return {
    context,
    nodes,
    rootClasses,
    rootStyles,
    revokedUrls,
    setShellPresent(value) { hasShell = value; },
  };
}

const main = createFixture({ shellPresent: true });
const mainResult = vm.runInNewContext(payload, main.context);
assert.equal(mainResult.installed, true);
assert.equal(main.rootClasses.has("codex-dream-skin"), true);
assert.equal(main.rootStyles.get("--dream-art"), 'url("blob:fixture-1")');
assert.equal(main.rootStyles.get("--ds-accent"), "#555555");
assert.equal(main.rootStyles.get("--dream-art-position"), "72% 45%");
assert.equal(main.rootClasses.has("dream-art-full-window"), true);
assert.equal(main.rootClasses.has("dream-art-home-card"), false);
assert.equal(main.rootClasses.has("dream-safe-left"), true);
assert.equal(main.context.window.__CODEX_DREAM_SKIN_STATE__.themeId, "fixture-theme");
assert.equal(main.context.window.__CODEX_DREAM_SKIN_STATE__.presentation, "full-window");
assert.equal(main.nodes.has("codex-dream-skin-style"), true);
assert.equal(main.nodes.has("codex-dream-skin-chrome"), true);
const alternateResult = vm.runInNewContext(buildPayload({
  ...fixtureTheme,
  id: "alternate-theme",
  name: "Alternate Theme",
  art: { presentation: "home-card", safeArea: "auto" },
  colors: { ...fixtureTheme.colors, accent: "#abcdef" },
}, "data:image/jpeg;base64,AA=="), main.context);
assert.equal(alternateResult.themeId, "alternate-theme");
assert.equal(main.rootStyles.get("--dream-art"), 'url("blob:fixture-2")');
assert.equal(main.rootStyles.get("--ds-accent"), "#abcdef");
assert.equal(main.rootClasses.has("dream-art-full-window"), false);
assert.equal(main.rootClasses.has("dream-art-home-card"), true);
assert.equal(main.context.window.__CODEX_DREAM_SKIN_STATE__.presentation, "home-card");
assert.deepEqual(main.revokedUrls, ["blob:fixture-1"]);
assert.equal(main.context.window.__CODEX_DREAM_SKIN_STATE__.cleanup(), true);
assert.equal(main.rootClasses.has("codex-dream-skin"), false);
assert.equal(main.rootClasses.has("dream-art-home-card"), false);
assert.equal(main.nodes.has("codex-dream-skin-style"), false);
assert.equal(main.nodes.has("codex-dream-skin-chrome"), false);
assert.deepEqual(main.revokedUrls, ["blob:fixture-1", "blob:fixture-2"]);

const auxiliary = createFixture({ shellPresent: false, staleSkin: true });
const auxiliaryResult = vm.runInNewContext(payload, auxiliary.context);
assert.equal(auxiliaryResult.installed, true);
assert.equal(auxiliary.rootClasses.has("codex-dream-skin"), false);
assert.equal(auxiliary.rootStyles.has("--dream-art"), false);
assert.equal(auxiliary.nodes.has("codex-dream-skin-style"), false);
assert.equal(auxiliary.nodes.has("codex-dream-skin-chrome"), false);

auxiliary.setShellPresent(true);
auxiliary.context.window.__CODEX_DREAM_SKIN_STATE__.ensure();
assert.equal(auxiliary.rootClasses.has("codex-dream-skin"), true);
assert.equal(auxiliary.nodes.has("codex-dream-skin-style"), true);
assert.equal(auxiliary.nodes.has("codex-dream-skin-chrome"), true);

console.log("PASS: renderer themes the Codex shell and preserves transparent auxiliary windows.");
