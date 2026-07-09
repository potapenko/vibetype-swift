const navToggle = document.querySelector("[data-nav-toggle]");
const siteNav = document.querySelector("[data-site-nav]");
const navLabel = document.querySelector("[data-nav-label]");

function closeNavigation({ returnFocus = false } = {}) {
  if (!navToggle || !siteNav || !navLabel) return;

  siteNav.classList.remove("is-open");
  navToggle.setAttribute("aria-expanded", "false");
  navLabel.textContent = "Menu";

  if (returnFocus) navToggle.focus();
}

if (navToggle && siteNav && navLabel) {
  navToggle.addEventListener("click", () => {
    const nextOpenState = navToggle.getAttribute("aria-expanded") !== "true";

    siteNav.classList.toggle("is-open", nextOpenState);
    navToggle.setAttribute("aria-expanded", String(nextOpenState));
    navLabel.textContent = nextOpenState ? "Close" : "Menu";
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

  window.matchMedia("(min-width: 861px)").addEventListener("change", (event) => {
    if (event.matches) closeNavigation();
  });
}

const demo = document.querySelector("[data-demo]");
const demoIndicator = document.querySelector("[data-demo-indicator]");
const demoStatus = document.querySelector("[data-demo-status]");
const demoPanels = [...document.querySelectorAll("[data-demo-panel]")];
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

const demoStates = [
  {
    name: "listening",
    label: "Listening",
    image: "assets/indicator-listening.png",
  },
  {
    name: "transcribing",
    label: "Transcribing",
    image: "assets/indicator-transcribing.png",
  },
  {
    name: "inserted",
    label: "Inserted",
    image: "assets/app-icon.png",
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
