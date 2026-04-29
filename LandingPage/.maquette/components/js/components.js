function setNavState(nav, open) {
  const toggle = nav.querySelector(".site-nav__toggle");
  nav.dataset.open = open ? "true" : "false";
  if (toggle) {
    toggle.setAttribute("aria-expanded", String(open));
  }
}

document.querySelectorAll(".site-nav").forEach((nav) => {
  const toggle = nav.querySelector(".site-nav__toggle");
  const panelLinks = nav.querySelectorAll(".site-nav__panel-link");

  setNavState(nav, nav.dataset.open === "true");

  toggle?.addEventListener("click", () => {
    setNavState(nav, nav.dataset.open !== "true");
  });

  panelLinks.forEach((link) => {
    link.addEventListener("click", () => setNavState(nav, false));
  });
});
