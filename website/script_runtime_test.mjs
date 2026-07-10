import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("./script.js", import.meta.url), "utf8");

const locales = [
  { code: "en", browserMatches: ["en"] },
  { code: "de", browserMatches: ["de"] },
  { code: "ru", browserMatches: ["ru"] },
  { code: "zh-Hans", browserMatches: ["zh-hans", "zh-cn", "zh-sg"] },
].map((locale) => ({
  ...locale,
  href: "/",
  nativeName: locale.code,
  dir: "ltr",
  suggestionMessage: locale.code,
  suggestionAction: locale.code,
}));

function resolveSuggestion({ savedLocale = null, browserLanguages = [], storageThrows = false }) {
  const storage = {
    getItem() {
      if (storageThrows) throw new Error("blocked storage");
      return savedLocale;
    },
    setItem() {},
  };
  const localeConfig = {
    currentLocale: "en",
    defaultLocale: "en",
    isDefaultRoute: true,
    strings: {},
    locales,
  };
  const localeConfigElement = { textContent: JSON.stringify(localeConfig) };
  const document = {
    body: { children: [], classList: { add() {}, remove() {} } },
    documentElement: { classList: { add() {} } },
    hidden: false,
    querySelector(selector) {
      return selector === "#locale-config" ? localeConfigElement : null;
    },
    querySelectorAll() {
      return [];
    },
    addEventListener() {},
  };
  const window = {
    localStorage: storage,
    sessionStorage: storage,
    location: { hash: "" },
    matchMedia() {
      return { matches: false, addEventListener() {} };
    },
  };
  const context = vm.createContext({
    document,
    window,
    navigator: {
      languages: browserLanguages,
      language: browserLanguages[0],
    },
    URL,
  });
  new vm.Script(source, { filename: "script.js" }).runInContext(context);
  return context.suggestedLocale();
}

assert.equal(
  resolveSuggestion({ savedLocale: "unsupported-value", browserLanguages: ["de-DE"] })?.code,
  "de",
  "an invalid stored locale must fall through to browser-language matching",
);
assert.equal(
  resolveSuggestion({ savedLocale: "ru", browserLanguages: ["de-DE"] })?.code,
  "ru",
  "a supported explicit choice must take precedence",
);
assert.equal(
  resolveSuggestion({ browserLanguages: ["zh-TW"] }),
  null,
  "Traditional Chinese must not silently map to Simplified Chinese",
);
assert.equal(
  resolveSuggestion({ browserLanguages: ["zh-CN"] })?.code,
  "zh-Hans",
  "Simplified Chinese regional variants must match zh-Hans",
);
assert.equal(
  resolveSuggestion({ browserLanguages: ["de-DE"], storageThrows: true })?.code,
  "de",
  "blocked storage must not disable browser-language matching",
);

console.log("Locale runtime tests passed.");
