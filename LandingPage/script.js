const nav = document.querySelector(".nav");
const navToggle = document.querySelector("[data-nav-toggle]");
const revealTargets = document.querySelectorAll("[data-reveal]");

function setNavOpen(open) {
  nav?.setAttribute("data-open", String(open));
  navToggle?.setAttribute("aria-expanded", String(open));
  document.body.classList.toggle("nav-open", open);
}

navToggle?.addEventListener("click", () => {
  setNavOpen(nav?.getAttribute("data-open") !== "true");
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    setNavOpen(false);
  }
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

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    {
      threshold: 0.16,
      rootMargin: "0px 0px -32px 0px",
    }
  );

  revealTargets.forEach((target) => observer.observe(target));
} else {
  revealTargets.forEach((target) => target.classList.add("is-visible"));
}

// Full-page captures do not always scroll through the document, so reveal any
// remaining sections as soon as the page has finished loading.
window.addEventListener("load", () => {
  revealTargets.forEach((target) => target.classList.add("is-visible"));
});
