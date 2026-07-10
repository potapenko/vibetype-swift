const localeConfigElement = document.querySelector("#locale-config");

const defaultLocaleConfig = {
  currentLocale: "en",
  defaultLocale: "en",
  isDefaultRoute: true,
  assetPrefix: "assets/",
  preferenceStorageKey: "holdtype.preferredLocale.v1",
  dismissedSessionKey: "holdtype.localeSuggestionDismissed.v1",
  strings: {
    "header.menuClosed": "Menu",
    "header.menuOpen": "Close",
    "hero.demo.status.listening": "Listening",
    "hero.demo.status.transcribing": "Transcribing",
    "hero.demo.status.inserted": "Inserted",
    "install.homebrew.copyIdle": "Copy",
    "install.homebrew.copyCopied": "Copied",
    "install.homebrew.copyRetry": "Try again",
    "install.homebrew.copySuccessStatus": "Homebrew command copied.",
    "install.homebrew.copyFailureStatus": "Copy failed. Select the command manually.",
    "apiKeyGuide.video.fallbackIframeTitle": "YouTube tutorial",
    "lightbox.fallbackImageAlt": "Full-size HoldType screenshot",
  },
  locales: [],
};

let localeConfig = defaultLocaleConfig;

try {
  const parsedLocaleConfig = localeConfigElement
    ? JSON.parse(localeConfigElement.textContent)
    : null;
  if (parsedLocaleConfig && typeof parsedLocaleConfig === "object") {
    localeConfig = { ...defaultLocaleConfig, ...parsedLocaleConfig };
    localeConfig.strings = {
      ...defaultLocaleConfig.strings,
      ...(parsedLocaleConfig.strings || {}),
    };
  }
} catch {
  localeConfig = defaultLocaleConfig;
}

const localizedString = (key) => localeConfig.strings[key] || defaultLocaleConfig.strings[key] || key;

const navToggle = document.querySelector("[data-nav-toggle]");
const siteNav = document.querySelector("[data-site-nav]");
const navLabel = document.querySelector("[data-nav-label]");
const languageSelector = document.querySelector("[data-language-selector]");

function closeNavigation({ returnFocus = false } = {}) {
  if (!navToggle || !siteNav || !navLabel) return;

  siteNav.classList.remove("is-open");
  navToggle.setAttribute("aria-expanded", "false");
  navLabel.textContent = localizedString("header.menuClosed");

  if (returnFocus) navToggle.focus();
}

if (navToggle && siteNav && navLabel) {
  navToggle.addEventListener("click", () => {
    const nextOpenState = navToggle.getAttribute("aria-expanded") !== "true";

    siteNav.classList.toggle("is-open", nextOpenState);
    navToggle.setAttribute("aria-expanded", String(nextOpenState));
    navLabel.textContent = localizedString(
      nextOpenState ? "header.menuOpen" : "header.menuClosed",
    );
    if (nextOpenState && languageSelector) languageSelector.open = false;
  });

  siteNav.addEventListener("click", (event) => {
    const link = event.target.closest("a");
    if (!link || !siteNav.classList.contains("is-open")) return;

    const href = link.getAttribute("href");
    if (!href?.startsWith("#")) {
      closeNavigation();
      return;
    }

    const target = document.getElementById(href.slice(1));
    if (!target) return;

    event.preventDefault();
    closeNavigation();

    const hadTabIndex = target.hasAttribute("tabindex");
    if (!hadTabIndex) target.setAttribute("tabindex", "-1");

    target.focus({ preventScroll: true });
    target.scrollIntoView({ block: "start" });
    window.history.pushState(null, "", href);

    if (!hadTabIndex) {
      target.addEventListener(
        "blur",
        () => target.removeAttribute("tabindex"),
        { once: true },
      );
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && siteNav.classList.contains("is-open")) {
      closeNavigation({ returnFocus: true });
    }
  });

  window.matchMedia("(min-width: 1121px)").addEventListener("change", (event) => {
    if (event.matches) closeNavigation();
  });
}

function readStorage(storage, key) {
  try {
    return storage?.getItem(key) || null;
  } catch {
    return null;
  }
}

function writeStorage(storage, key, value) {
  try {
    storage?.setItem(key, value);
  } catch {
    // Storage is an optional enhancement. Links continue to navigate without it.
  }
}

function browserStorage(name) {
  try {
    return window[name];
  } catch {
    return null;
  }
}

const persistentLocaleStorage = browserStorage("localStorage");
const localeSessionStorage = browserStorage("sessionStorage");

const localeLinks = document.querySelectorAll("[data-locale-link]");

localeLinks.forEach((link) => {
  link.addEventListener("click", () => {
    const locale = link.dataset.locale || link.dataset.localeLink;
    if (locale) {
      writeStorage(persistentLocaleStorage, localeConfig.preferenceStorageKey, locale);
    }

    if (window.location.hash) {
      const destination = new URL(link.href, window.location.href);
      destination.hash = window.location.hash;
      link.href = destination.href;
    }
  });
});

if (languageSelector) {
  const languageSummary = languageSelector.querySelector("summary");

  languageSelector.addEventListener("toggle", () => {
    if (languageSelector.open) closeNavigation();
  });

  document.addEventListener("click", (event) => {
    if (languageSelector.open && !languageSelector.contains(event.target)) {
      languageSelector.open = false;
    }
  });

  languageSelector.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && languageSelector.open) {
      event.preventDefault();
      languageSelector.open = false;
      languageSummary?.focus();
    }
  });
}

const languageSuggestion = document.querySelector("[data-language-suggestion]");
const languageSuggestionText = languageSuggestion?.querySelector(
  "[data-language-suggestion-text]",
);
const languageSuggestionAction = languageSuggestion?.querySelector(
  "[data-language-suggestion-action]",
);
const languageSuggestionDismiss = languageSuggestion?.querySelector(
  "[data-language-suggestion-dismiss]",
);

function localeForPreference(preference) {
  if (!preference || !Array.isArray(localeConfig.locales)) return null;
  const normalized = preference.replaceAll("_", "-").toLowerCase();

  return (
    localeConfig.locales.find((locale) => locale.code.toLowerCase() === normalized) ||
    localeConfig.locales.find((locale) =>
      locale.browserMatches?.some((candidate) => {
        const match = candidate.toLowerCase();
        return normalized === match || normalized.startsWith(`${match}-`);
      }),
    ) ||
    null
  );
}

function suggestedLocale() {
  const savedLocale = readStorage(persistentLocaleStorage, localeConfig.preferenceStorageKey);
  if (savedLocale) {
    const savedMatch = localeForPreference(savedLocale);
    if (savedMatch) return savedMatch;
  }

  const browserLanguages = Array.isArray(navigator.languages)
    ? navigator.languages
    : [navigator.language].filter(Boolean);
  for (const language of browserLanguages) {
    const match = localeForPreference(language);
    if (match) return match;
  }
  return null;
}

function showLanguageSuggestion() {
  if (
    !languageSuggestion ||
    !languageSuggestionText ||
    !languageSuggestionAction ||
    !languageSuggestionDismiss ||
    !localeConfig.isDefaultRoute ||
    readStorage(localeSessionStorage, localeConfig.dismissedSessionKey)
  ) {
    return;
  }

  const suggestion = suggestedLocale();
  if (!suggestion || suggestion.code === localeConfig.defaultLocale) return;

  languageSuggestionText.textContent = suggestion.suggestionMessage;
  languageSuggestionAction.textContent = suggestion.suggestionAction;
  languageSuggestionAction.href = suggestion.href;
  languageSuggestionAction.dataset.locale = suggestion.code;
  languageSuggestionDismiss.textContent = suggestion.suggestionDismiss;
  languageSuggestionDismiss.setAttribute("aria-label", suggestion.suggestionDismissAria);
  languageSuggestion.setAttribute("aria-label", suggestion.suggestionAria);
  languageSuggestion.lang = suggestion.code;
  languageSuggestion.dir = suggestion.dir;
  languageSuggestion.hidden = false;
}

languageSuggestionAction?.addEventListener("click", () => {
  const locale = languageSuggestionAction.dataset.locale;
  if (locale) {
    writeStorage(persistentLocaleStorage, localeConfig.preferenceStorageKey, locale);
  }
});

languageSuggestionDismiss?.addEventListener("click", () => {
  writeStorage(localeSessionStorage, localeConfig.dismissedSessionKey, "true");
  languageSuggestion.hidden = true;
});

showLanguageSuggestion();

const demo = document.querySelector("[data-demo]");
const demoIndicator = document.querySelector("[data-demo-indicator]");
const demoStatus = document.querySelector("[data-demo-status]");
const demoPanels = [...document.querySelectorAll("[data-demo-panel]")];
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

const demoStates = [
  {
    name: "listening",
    label: localizedString("hero.demo.status.listening"),
    image: `${localeConfig.assetPrefix}indicator-listening.png`,
  },
  {
    name: "transcribing",
    label: localizedString("hero.demo.status.transcribing"),
    image: `${localeConfig.assetPrefix}indicator-transcribing.png`,
  },
  {
    name: "inserted",
    label: localizedString("hero.demo.status.inserted"),
    image: `${localeConfig.assetPrefix}app-icon.png`,
  },
];

let currentDemoState = 2;
let demoTimers = [];
let demoHasPlayed = false;

function renderDemoState(index) {
  if (!demo || !demoIndicator || !demoStatus) return;

  const state = demoStates[index];
  demo.dataset.state = state.name;
  demoStatus.textContent = state.label;
  demoIndicator.src = state.image;

  demoPanels.forEach((panel) => {
    panel.hidden = panel.dataset.demoPanel !== state.name;
  });
}

function stopDemo() {
  demoTimers.forEach((timer) => window.clearTimeout(timer));
  demoTimers = [];
}

function startDemo() {
  stopDemo();

  if (reduceMotion.matches || document.hidden || demoHasPlayed) {
    currentDemoState = 2;
    renderDemoState(currentDemoState);
    return;
  }

  demoHasPlayed = true;
  currentDemoState = 0;
  renderDemoState(currentDemoState);

  demoTimers.push(
    window.setTimeout(() => {
      currentDemoState = 1;
      renderDemoState(currentDemoState);
    }, 1700),
    window.setTimeout(() => {
      currentDemoState = 2;
      renderDemoState(currentDemoState);
      demoTimers = [];
    }, 3400),
  );
}

if (demo) {
  renderDemoState(currentDemoState);
  startDemo();
  reduceMotion.addEventListener("change", startDemo);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      stopDemo();
      currentDemoState = 2;
      renderDemoState(currentDemoState);
    } else {
      startDemo();
    }
  });
}

const copyButtons = document.querySelectorAll("[data-copy-target]");

async function copyToClipboard(text) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const temporaryInput = document.createElement("textarea");
  temporaryInput.value = text;
  temporaryInput.setAttribute("readonly", "");
  temporaryInput.style.position = "fixed";
  temporaryInput.style.opacity = "0";
  document.body.append(temporaryInput);
  temporaryInput.select();

  const copied = document.execCommand("copy");
  temporaryInput.remove();

  if (!copied) throw new Error("Copy command was not available");
}

copyButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    const targetId = button.dataset.copyTarget;
    const target = targetId ? document.getElementById(targetId) : null;
    const status = button.parentElement?.querySelector("[data-copy-status]");

    if (!target) return;

    try {
      await copyToClipboard(target.textContent.trim());
      button.textContent = localizedString("install.homebrew.copyCopied");
      button.dataset.state = "copied";
      if (status) {
        status.textContent = localizedString("install.homebrew.copySuccessStatus");
      }

      window.setTimeout(() => {
        button.textContent = localizedString("install.homebrew.copyIdle");
        delete button.dataset.state;
      }, 1800);
    } catch {
      button.textContent = localizedString("install.homebrew.copyRetry");
      if (status) {
        status.textContent = localizedString("install.homebrew.copyFailureStatus");
      }
    }
  });
});

const videoFacades = document.querySelectorAll("[data-video-facade]");

videoFacades.forEach((button) => {
  button.addEventListener("click", () => {
    const videoId = button.dataset.videoId;
    if (!videoId || !/^[A-Za-z0-9_-]{11}$/.test(videoId)) return;

    const iframe = document.createElement("iframe");
    iframe.className = "video-iframe";
    iframe.src = `https://www.youtube-nocookie.com/embed/${videoId}?autoplay=1&rel=0`;
    iframe.title =
      button.dataset.videoTitle ||
      localizedString("apiKeyGuide.video.fallbackIframeTitle");
    iframe.allow =
      "accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share";
    iframe.referrerPolicy = "strict-origin-when-cross-origin";
    iframe.setAttribute("allowfullscreen", "");
    iframe.tabIndex = 0;

    button.replaceWith(iframe);
    iframe.focus();
  });
});

const imageLightbox = document.querySelector("[data-image-lightbox]");
const lightboxImage = imageLightbox?.querySelector("[data-lightbox-image]");
const lightboxCaption = imageLightbox?.querySelector("[data-lightbox-caption]");
const lightboxClose = imageLightbox?.querySelector("[data-lightbox-close]");
const lightboxLinks = document.querySelectorAll("[data-lightbox-link]");

let activeLightboxTrigger = null;

const lightboxBackgroundElements = imageLightbox
  ? [...document.body.children].filter(
      (element) => element !== imageLightbox && element instanceof HTMLElement,
    )
  : [];

function closeImageLightbox() {
  if (!imageLightbox || !lightboxImage || !lightboxCaption || imageLightbox.hidden) {
    return;
  }

  imageLightbox.hidden = true;
  document.body.classList.remove("has-image-lightbox");
  lightboxBackgroundElements.forEach((element) => {
    element.inert = false;
  });

  lightboxImage.removeAttribute("src");
  lightboxImage.alt = "";
  lightboxCaption.textContent = "";

  const trigger = activeLightboxTrigger;
  activeLightboxTrigger = null;
  if (trigger?.isConnected) trigger.focus();
}

if (imageLightbox && lightboxImage && lightboxCaption && lightboxClose) {
  document.documentElement.classList.add("lightbox-ready");

  lightboxLinks.forEach((link) => {
    link.setAttribute("aria-haspopup", "dialog");

    link.addEventListener("click", (event) => {
      const sourceImage = link.closest("figure")?.querySelector("img");
      const imageAlt =
        sourceImage?.alt || localizedString("lightbox.fallbackImageAlt");

      event.preventDefault();
      activeLightboxTrigger = link;
      lightboxImage.src = link.href;
      lightboxImage.alt = imageAlt;
      lightboxCaption.textContent = link.dataset.lightboxCaption || imageAlt;

      lightboxBackgroundElements.forEach((element) => {
        element.inert = true;
      });
      imageLightbox.hidden = false;
      document.body.classList.add("has-image-lightbox");
      lightboxClose.focus();
    });
  });

  lightboxClose.addEventListener("click", closeImageLightbox);

  imageLightbox.addEventListener("click", (event) => {
    const protectedTarget = event.target.closest?.(
      "[data-lightbox-image], [data-lightbox-close]",
    );
    if (!protectedTarget) closeImageLightbox();
  });

  imageLightbox.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      closeImageLightbox();
      return;
    }

    if (event.key === "Tab") {
      event.preventDefault();
      lightboxClose.focus();
    }
  });
}
