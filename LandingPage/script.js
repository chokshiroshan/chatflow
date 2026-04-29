const nav = document.querySelector(".nav");
const navToggle = document.querySelector("[data-nav-toggle]");

function setNavOpen(open) {
  nav?.setAttribute("data-open", String(open));
  navToggle?.setAttribute("aria-expanded", String(open));
}

navToggle?.addEventListener("click", () => {
  setNavOpen(nav?.getAttribute("data-open") !== "true");
});

document.querySelectorAll(".mobile-menu a").forEach((link) => {
  link.addEventListener("click", () => setNavOpen(false));
});

document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    const value = button.getAttribute("data-copy") ?? "";
    const label = button.querySelector("span");
    const original = label?.textContent ?? "copy";

    try {
      await navigator.clipboard.writeText(value);
      if (label) label.textContent = "copied";
      window.setTimeout(() => {
        if (label) label.textContent = original;
      }, 1400);
    } catch {
      if (label) label.textContent = "copy failed";
    }
  });
});
