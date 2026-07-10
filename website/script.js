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
      button.textContent = "Copied";
      button.dataset.state = "copied";
      if (status) status.textContent = "Homebrew command copied.";

      window.setTimeout(() => {
        button.textContent = "Copy";
        delete button.dataset.state;
      }, 1800);
    } catch {
      button.textContent = "Try again";
      if (status) status.textContent = "Copy failed. Select the command manually.";
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
    iframe.title = button.dataset.videoTitle || "YouTube tutorial";
    iframe.allow =
      "accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share";
    iframe.referrerPolicy = "strict-origin-when-cross-origin";
    iframe.setAttribute("allowfullscreen", "");
    iframe.tabIndex = 0;

    button.replaceWith(iframe);
    iframe.focus();
  });
});
