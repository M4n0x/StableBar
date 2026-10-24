const THEMES = [
  ["built-in", "Built-in", "ws-fill"],
  ["blueprint", "Blueprint", "ws-under"],
  ["broadsheet", "Broadsheet", "ws-under"],
  ["brutalist", "Brutalist", "ws-fill"],
  ["catppuccin", "Catppuccin", "ws-fill"],
  ["everforest", "Everforest", "ws-under"],
  ["graphite", "Graphite", "ws-fill"],
  ["gruvbox", "Gruvbox", "ws-text"],
  ["handheld", "Handheld", "ws-fill"],
  ["island", "Island", "ws-fill"],
  ["kanagawa", "Kanagawa", "ws-fill"],
  ["leman", "Léman", "ws-fill"],
  ["menu-bar", "Menu Bar", "ws-fill"],
  ["minimal", "Minimal", "ws-fill"],
  ["nord", "Nord", "ws-under"],
  ["notch", "Notch", "ws-text"],
  ["paper", "Paper", "ws-fill"],
  ["phosphor", "Phosphor", "ws-fill"],
  ["platinum", "Platinum", "ws-fill"],
  ["rose-pine", "Rosé Pine", "ws-fill"],
  ["slate", "Slate", "ws-fill"],
  ["synthwave", "Synthwave", "ws-under"],
  ["terminal", "Terminal", "ws-fill"],
];
const desk = document.getElementById("desk");
const dock = document.getElementById("dock");
const bar = document.getElementById("bar");
const gl = document.getElementById("gl");
const gr = document.getElementById("gr");
const more = bar.querySelector(".more");
const pop = document.getElementById("pop");
const panes = [...pop.querySelectorAll(".pane")];
const menu = pop.querySelector('[data-id="more"]');
const reduce = matchMedia("(prefers-reduced-motion: reduce)");
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
let openId = null;

/* Now playing: the track moves on while it plays */
const track = { at: 87, length: 243, playing: true };
const trackAt = document.getElementById("np-at");
const trackBar = document.getElementById("np-bar");
document.getElementById("np-play").addEventListener("click", e => {
  track.playing = !track.playing;
  dock.classList.toggle("paused", !track.playing);
  e.currentTarget.setAttribute("aria-label", track.playing ? "Pause" : "Play");
});

/* Clocks show the visitor's real time */
function tick() {
  const d = new Date();
  const hm = d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
  const day = `${d.toLocaleDateString("en-GB", { weekday: "short" })} ${d.getDate()} ${d.toLocaleDateString("en-GB", { month: "short" })}`;
  for (const c of document.querySelectorAll(".clock")) {
    if (c.dataset.format === "full") c.innerHTML = `<span class="day">${day}&nbsp;&nbsp;</span>${hm}`;
    else if (c.dataset.format === "seconds") c.textContent = d.toLocaleTimeString("en-GB");
    else c.textContent = hm;
  }
  if (track.playing) track.at = (track.at + 1) % track.length;
  trackAt.textContent = `${Math.floor(track.at / 60)}:${String(track.at % 60).padStart(2, "0")}`;
  trackBar.style.width = `${track.at / track.length * 100}%`;
}
tick();
setInterval(tick, 1000);

/* Sample bars: three workspaces, Finder, battery and clock, as in Settings' theme cards */
function mini() {
  return `<div class="mini"><div class="strip"></div>
    <div class="g"><span class="t ws" style="padding:0 2px;gap:0"><span class="wsi on">1</span><span class="wsi">2</span><span class="wsi">3</span></span><span class="t"><b style="font-weight:700">Finder</b></span></div>
    <div class="g"><span class="t"><svg style="width:17px;height:14px"><use href="#i-bat"/></svg>82%</span><span class="t num">9:41</span></div></div>`;
}
const cards = document.getElementById("cards");
const store = document.querySelector("#board .store");
for (const [id, name, ws] of THEMES) {
  const card = `<button class="card" data-theme-pick="${id}"><div class="shot ${ws}" data-theme="${id}" aria-hidden="true">${mini()}</div><div class="nm">${name}<svg viewBox="0 0 12 12"><use href="#p-check"/></svg></div></button>`;
  cards.insertAdjacentHTML("beforeend", card);
  store.insertAdjacentHTML("beforebegin", card);
}
const showAll = document.getElementById("show-all");
showAll.textContent = `Show all ${THEMES.length} themes`;
showAll.addEventListener("click", () => {
  const board = document.getElementById("board");
  board.classList.add("all");
  showAll.remove();
  board.children[8].focus();
});

function setTheme(id) {
  desk.dataset.theme = id;
  bar.className = `bar ${THEMES.find(t => t[0] === id)[2]}`;
  for (const b of document.querySelectorAll("[data-theme-pick]")) {
    b.classList.toggle("on", b.dataset.themePick === id);
    b.setAttribute("aria-pressed", b.dataset.themePick === id);
  }
  requestAnimationFrame(fit);
}
for (const b of document.querySelectorAll("[data-theme-pick]")) b.addEventListener("click", () => setTheme(b.dataset.themePick));

/* Overflow, as the real bar does it: lower priority first, equal priorities from the end */
const widgets = [...bar.querySelectorAll("[data-pri]")].filter(w => w.dataset.pri !== "never");
const order = widgets.map((w, i) => ({ w, p: Number(w.dataset.pri), i })).sort((a, b) => a.p - b.p || b.i - a.i).map(o => o.w);
const needed = () => gl.scrollWidth + gr.scrollWidth + 36;
function fit() {
  widgets.forEach(w => w.classList.remove("over"));
  more.hidden = true;
  const shown = order.filter(w => w.offsetWidth > 0);
  for (const w of shown) {
    if (needed() <= bar.clientWidth) break;
    w.classList.add("over");
    more.hidden = false;
  }
  for (const w of [...shown].reverse()) {
    if (!w.classList.contains("over")) continue;
    w.classList.remove("over");
    if (needed() > bar.clientWidth) w.classList.add("over");
  }
  more.hidden = !bar.querySelector(".over");
  for (const b of menu.querySelectorAll("[data-for]")) {
    b.classList.toggle("over-off", !bar.querySelector(`[data-key="${b.dataset.for}"]`).classList.contains("over"));
  }
  place();
  slide();
}

/* Popups open below their widget, or from More widgets when the widget is hidden */
function anchorFor(id) {
  if (id === "more") return more;
  const w = bar.querySelector(`[data-pop="${id}"]`);
  return w.classList.contains("over") ? more : w;
}
function place() {
  if (!openId) return;
  const pane = panes.find(p => p.dataset.id === openId);
  const dr = dock.getBoundingClientRect();
  const a = anchorFor(openId).getBoundingClientRect();
  let left = a.left - dr.left + a.width / 2 - pane.offsetWidth / 2;
  if (openId !== "more" && anchorFor(openId) === more) left = a.right - dr.left - pane.offsetWidth;
  pop.style.left = `${clamp(left, 8, dr.width - pane.offsetWidth - 8)}px`;
  pop.style.top = `${a.bottom - dr.top + 8}px`;
  pop.style.width = `${pane.offsetWidth}px`;
  pop.style.height = `${pane.offsetHeight}px`;
}
/* Opening another widget's popup morphs the open one into it, as the app does */
function open(id) {
  const from = openId;
  openId = openId === id ? null : id;
  pop.classList.toggle("morph", Boolean(from && openId));
  pop.classList.toggle("open", Boolean(openId));
  for (const p of panes) p.classList.toggle("on", p.dataset.id === openId);
  for (const w of bar.querySelectorAll("[data-pop]")) {
    w.classList.toggle("open", w.dataset.pop === openId || Boolean(openId && anchorFor(openId) === w));
    if (w.matches("button")) w.setAttribute("aria-expanded", w.classList.contains("open"));
  }
  place();
}
for (const w of bar.querySelectorAll("[data-pop]")) w.addEventListener("click", e => {
  if (e.target.closest("a")) return;
  e.stopPropagation();
  open(w.dataset.pop);
});
for (const b of menu.querySelectorAll("[data-open]")) b.addEventListener("click", e => { e.stopPropagation(); open(b.dataset.open); });
document.addEventListener("click", e => { if (openId && !e.target.closest(".pop, .win, .card, .w")) open(openId); });
/* Escape closes the popup and returns focus to its widget */
document.addEventListener("keydown", e => {
  if (e.key !== "Escape" || !openId) return;
  const from = pop.contains(document.activeElement) && anchorFor(openId);
  open(openId);
  if (from) from.focus();
});

/* Workspaces: the focus highlight slides to the one you click, as on the real bar */
const ind = bar.querySelector(".ind");
function slide() {
  const on = bar.querySelector(".wsi.on");
  ind.style.setProperty("--x", `${on.offsetLeft}px`);
  ind.style.setProperty("--w", `${on.offsetWidth}px`);
}
for (const el of bar.querySelectorAll(".wsi")) el.addEventListener("click", () => {
  bar.querySelectorAll(".wsi").forEach(e => {
    e.classList.toggle("on", e === el);
    e.setAttribute("aria-pressed", e === el);
  });
  slide();
});

/* The app's menus open on hover when the bar has room for them */
const finder = bar.querySelector(".finder");
finder.addEventListener("mouseenter", () => {
  if (needed() + finder.querySelector(".menus > span").scrollWidth <= bar.clientWidth) finder.classList.add("expand");
  setTimeout(place, 320);
});
finder.addEventListener("mouseleave", () => { finder.classList.remove("expand"); setTimeout(place, 320); });

/* Controls */
for (const seg of document.querySelectorAll(".seg")) for (const b of seg.querySelectorAll("button")) b.addEventListener("click", () => {
  seg.querySelectorAll("button").forEach(x => {
    x.classList.toggle("on", x === b);
    x.setAttribute("aria-pressed", x === b);
  });
});
for (const s of document.querySelectorAll(".search")) s.addEventListener("input", () => {
  const q = s.value.toLowerCase();
  s.nextElementSibling.querySelectorAll("div").forEach(d => d.hidden = !d.textContent.toLowerCase().includes(q));
  place();
});

/* The terminal runs its commands against the bar */
const out = document.getElementById("out");
for (const b of document.querySelectorAll("[data-run]")) b.addEventListener("click", e => {
  e.stopPropagation();
  if (b.dataset.run === "popup") {
    open("agenda");
    out.textContent = `{"popup":"agenda","open":${openId === "agenda"}}`;
  } else {
    bar.querySelector(".clock").dataset.format = "seconds";
    menu.querySelector(".clock").dataset.format = "seconds";
    tick();
    fit();
    out.textContent = '{"set":"clock"}';
  }
  b.classList.add("ran");
});

/* The bar stays at the top of the window once the desk reaches it,
   and becomes the page's header once the desk has scrolled away. */
function dockState() {
  const r = desk.getBoundingClientRect();
  const header = r.bottom <= 120;
  const docked = r.top <= 0;
  dock.classList.toggle("docked", docked);
  dock.style.left = docked ? `${r.left}px` : "";
  dock.style.width = docked ? `${r.width}px` : "";
  if (header === dock.classList.contains("header")) return;
  dock.classList.toggle("header", header);
  if (openId) open(openId);
  requestAnimationFrame(fit);
  setTimeout(fit, 450);
}

let queued = false;
addEventListener("scroll", () => {
  if (queued) return;
  queued = true;
  requestAnimationFrame(() => { queued = false; dockState(); });
}, { passive: true });

/* Drag a window by its title bar. It leans into the motion and glides when let go. */
const layers = [...desk.querySelectorAll(".layer")];
const px = (el, name) => parseFloat(el.style.getPropertyValue(name)) || 0;
function bounds(layer) {
  return {
    x: [8 - layer.offsetLeft, desk.clientWidth - layer.offsetWidth - 8 - layer.offsetLeft],
    y: [bar.offsetHeight + 8 - layer.offsetTop, desk.clientHeight - 48 - layer.offsetTop],
  };
}
function moveTo(layer, dx, dy) {
  const b = bounds(layer);
  const x = clamp(dx, ...b.x), y = clamp(dy, ...b.y);
  layer.style.setProperty("--dx", `${x}px`);
  layer.style.setProperty("--dy", `${y}px`);
  return [x !== dx, y !== dy];
}
for (const layer of layers) {
  const handle = layer.querySelector(".tb");
  let drag = null, frame = 0, vx = 0, vy = 0;

  function animate() {
    const tilt = px(layer, "--tilt");
    if (!drag) {
      const [hitX, hitY] = moveTo(layer, px(layer, "--dx") + vx * 16, px(layer, "--dy") + vy * 16);
      vx = hitX ? 0 : vx * .92;
      vy = hitY ? 0 : vy * .92;
    } else {
      vx *= .85;
    }
    const target = drag ? clamp(vx * 6, -8, 8) : 0;
    layer.style.setProperty("--tilt", `${tilt + (target - tilt) * .2}deg`);
    if (drag || Math.abs(vx) + Math.abs(vy) > .01 || Math.abs(tilt) > .05) frame = requestAnimationFrame(animate);
    else layer.style.setProperty("--tilt", "0deg");
  }

  handle.addEventListener("pointerdown", e => {
    if (e.button !== 0) return;
    e.preventDefault();
    handle.setPointerCapture(e.pointerId);
    layers.forEach(l => l.style.zIndex = l === layer ? 5 : 4);
    const r = layer.getBoundingClientRect();
    layer.style.transformOrigin = `${e.clientX - r.left}px ${e.clientY - r.top}px`;
    drag = { x: e.clientX, y: e.clientY, dx: px(layer, "--dx"), dy: px(layer, "--dy"), lx: e.clientX, ly: e.clientY, t: e.timeStamp };
    vx = vy = 0;
    layer.classList.add("dragging");
    cancelAnimationFrame(frame);
    if (!reduce.matches) frame = requestAnimationFrame(animate);
  });
  handle.addEventListener("pointermove", e => {
    if (!drag) return;
    moveTo(layer, drag.dx + e.clientX - drag.x, drag.dy + e.clientY - drag.y);
    const dt = Math.max(1, e.timeStamp - drag.t);
    vx = vx * .5 + (e.clientX - drag.lx) / dt * .5;
    vy = vy * .5 + (e.clientY - drag.ly) / dt * .5;
    Object.assign(drag, { lx: e.clientX, ly: e.clientY, t: e.timeStamp });
  });
  const release = () => {
    if (!drag) return;
    drag = null;
    layer.classList.remove("dragging");
  };
  handle.addEventListener("pointerup", release);
  handle.addEventListener("pointercancel", release);
}

/* The disk image: drag StableBar onto Applications */
const ico = document.getElementById("app-ico");
const folder = document.getElementById("folder");
let grab = null;
const overFolder = e => {
  const r = folder.getBoundingClientRect();
  return e.clientX > r.left - 20 && e.clientX < r.right + 20 && e.clientY > r.top - 20 && e.clientY < r.bottom + 20;
};
ico.addEventListener("pointerdown", e => {
  if (ico.classList.contains("in")) return;
  e.preventDefault();
  ico.setPointerCapture(e.pointerId);
  grab = { x: e.clientX, y: e.clientY };
  ico.classList.add("dragging");
});
ico.addEventListener("pointermove", e => {
  if (!grab) return;
  ico.style.transform = `translate(${e.clientX - grab.x}px, ${e.clientY - grab.y}px) scale(1.06)`;
  folder.classList.toggle("over", overFolder(e));
});
ico.addEventListener("pointerup", e => {
  if (!grab) return;
  grab = null;
  ico.classList.remove("dragging");
  folder.classList.remove("over");
  if (!overFolder(e)) { ico.style.transform = ""; return; }
  const f = folder.getBoundingClientRect();
  const home = ico.parentElement.getBoundingClientRect();
  ico.style.transform = `translate(${f.left + f.width / 2 - (home.left + home.width / 2)}px, ${f.top + f.height / 2 - (home.top + home.height / 2)}px) scale(.4)`;
  ico.classList.add("in");
  setTimeout(() => {
    ico.style.transition = "none";
    ico.style.transform = "";
    requestAnimationFrame(() => requestAnimationFrame(() => {
      ico.style.transition = "";
      ico.classList.remove("in");
    }));
  }, 1600);
});
ico.addEventListener("pointercancel", () => { grab = null; ico.classList.remove("dragging"); ico.style.transform = ""; });

/* The product pictures ease in as they scroll into view */
const io = new IntersectionObserver(entries => {
  for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
}, { rootMargin: "0px 0px -10% 0px" });
for (const el of document.querySelectorAll(".pops, .board, .scripts, .setup, .install .desktop")) {
  el.classList.add("reveal");
  io.observe(el);
}

/* Light and dark: starts from the system setting, remembers the visitor's choice */
const themeColor = document.querySelector('meta[name="theme-color"]');
const modeButton = document.getElementById("mode");
function setMode(mode) {
  root.dataset.mode = mode;
  themeColor.content = mode === "light" ? "#f5f0e8" : "#15110d";
  modeButton.setAttribute("aria-pressed", mode === "dark");
}
setMode(root.dataset.mode);
modeButton.addEventListener("click", () => {
  const mode = root.dataset.mode === "light" ? "dark" : "light";
  localStorage.setItem("mode", mode);
  if (document.startViewTransition && !reduce.matches) document.startViewTransition(() => setMode(mode));
  else setMode(mode);
});

addEventListener("resize", () => { fit(); dockState(); });
document.fonts.ready.then(fit);
setTheme("built-in");
fit();
dockState();

/* Arrival: the headline settles, the bar's widgets come in from the left, then the windows and the agenda */
bar.querySelectorAll(".g > .w").forEach((w, i) => w.style.setProperty("--i", i));
requestAnimationFrame(() => requestAnimationFrame(() => root.classList.add("arrived")));
if (innerWidth >= 720) setTimeout(() => { if (!openId) open("agenda"); }, reduce.matches ? 0 : 1100);
