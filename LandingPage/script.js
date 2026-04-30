// ─── NAV ───
const nav = document.querySelector(".nav");
const navToggle = document.querySelector("[data-nav-toggle]");

function setNavOpen(open) {
  nav?.setAttribute("data-open", String(open));
  navToggle?.setAttribute("aria-expanded", String(open));
  document.body.classList.toggle("nav-open", open);
}

navToggle?.addEventListener("click", () => {
  setNavOpen(nav?.getAttribute("data-open") !== "true");
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") setNavOpen(false);
});

document.querySelectorAll(".mobile-menu a").forEach((link) => {
  link.addEventListener("click", () => setNavOpen(false));
});

// ─── COPY BUTTONS ───
document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    const value = button.getAttribute("data-copy") ?? "";
    const label = button.querySelector("span");
    const original = label?.textContent ?? "copy";
    try {
      await navigator.clipboard.writeText(value);
      if (label) label.textContent = "copied!";
      setTimeout(() => { if (label) label.textContent = original; }, 1400);
    } catch {
      if (label) label.textContent = "failed";
    }
  });
});

// ─── SCROLL REVEAL ───
const revealTargets = document.querySelectorAll("[data-reveal]");
if ("IntersectionObserver" in window) {
  const revealObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        revealObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.05, rootMargin: "0px 0px 0px 0px" });
  revealTargets.forEach((t) => revealObserver.observe(t));
} else {
  revealTargets.forEach((t) => t.classList.add("is-visible"));
}

window.addEventListener("load", () => {
  // Only reveal elements already above the fold
  revealTargets.forEach((t) => {
    const rect = t.getBoundingClientRect();
    if (rect.top < window.innerHeight * 0.3) {
      t.classList.add("is-visible");
    }
  });
});

// ─── SMOOTH SCROLL FOR NAV LINKS ───
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function (e) {
    const target = document.querySelector(this.getAttribute('href'));
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  });
});

// ─── HERO FLOAT ANIMATION ───
const heroVisual = document.querySelector('.hero-visual');
if (heroVisual) {
  let ticking = false;
  window.addEventListener('scroll', () => {
    if (!ticking) {
      requestAnimationFrame(() => {
        const scrollY = window.scrollY;
        const offset = scrollY * 0.15;
        const rotate = scrollY * 0.01;
        heroVisual.style.transform = `translateY(${-offset}px) rotate(${rotate}deg)`;
        ticking = false;
      });
      ticking = true;
    }
  });
}

// ─── TYPING CURSOR EFFECT ───
const typingEl = document.querySelector('.demo-typing');
if (typingEl) {
  const originalHTML = typingEl.innerHTML;
  // Add blinking cursor
  typingEl.innerHTML = originalHTML + '<span class="typing-cursor">|</span>';
}

// ─── COUNTER ANIMATION ───
function animateCounters() {
  document.querySelectorAll('[data-count]').forEach(el => {
    const target = parseInt(el.dataset.count);
    const suffix = el.dataset.suffix || '';
    const duration = 2000;
    const start = performance.now();

    function update(now) {
      const elapsed = now - start;
      const progress = Math.min(elapsed / duration, 1);
      // Ease out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.round(eased * target);
      el.textContent = current.toLocaleString() + suffix;
      if (progress < 1) requestAnimationFrame(update);
    }
    requestAnimationFrame(update);
  });
}

// ─── WAVEFORM ANIMATION IN HERO ───
const pillBars = document.querySelectorAll('.pill-bar');
if (pillBars.length) {
  let wavePhase = 0;
  setInterval(() => {
    wavePhase += 0.4;
    pillBars.forEach((bar, i) => {
      const h = 6 + 14 * Math.abs(Math.sin(wavePhase + i * 0.8));
      bar.style.height = h + 'px';
    });
  }, 120);
}

// ─── NAV BACKGROUND ON SCROLL ───
window.addEventListener('scroll', () => {
  if (window.scrollY > 20) {
    nav?.classList.add('nav-scrolled');
  } else {
    nav?.classList.remove('nav-scrolled');
  }
});
