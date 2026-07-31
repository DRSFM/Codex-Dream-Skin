import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const testRoot = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(testRoot, "..", "..");
const css = fs.readFileSync(path.join(projectRoot, "runtime", "dream-skin.css"), "utf8");

assert.match(
  css,
  /Local chrome policy: keep Codex's native controls and copy/,
  "The local no-decoration policy is missing from the canonical runtime CSS.",
);
assert.match(
  css,
  /button\[aria-label\^="Toggle mode"\][\s\S]*?display:\s*none\s*!important/,
  "The decorative sidebar mode button must stay hidden.",
);
assert.match(
  css,
  /__DREAM_SELECTOR_HEADER_TINT__::before,[\s\S]*?__DREAM_SELECTOR_HEADER_TINT__::after,[\s\S]*?__DREAM_SELECTOR_SHELL_MAIN__:has\(__DREAM_SELECTOR_HOME_ROUTE_CSS__\)::after[\s\S]*?content:\s*none\s*!important/,
  "Injected header branding, status copy, and the home quote must stay hidden.",
);

console.log("PASS: local Codex chrome keeps native controls and hides injected decorations.");
