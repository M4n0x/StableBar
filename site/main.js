const THEMES = [
  ["built-in", "Built-in", "ws-fill"],
  ["blueprint", "Blueprint", "ws-under"],
  ["broadsheet", "Broadsheet", "ws-under"],
  ["brutalist", "Brutalist", "ws-fill"],
  ["catppuccin", "Catppuccin", "ws-fill"],
  ["everforest", "Everforest", "ws-under"],
  ["gruvbox", "Gruvbox", "ws-text"],
  ["handheld", "Handheld", "ws-fill"],
  ["kanagawa", "Kanagawa", "ws-fill"],
  ["leman", "Léman", "ws-fill"],
  ["nord", "Nord", "ws-under"],
  ["notch", "Notch", "ws-text"],
  ["phosphor", "Phosphor", "ws-fill"],
  ["platinum", "Platinum", "ws-fill"],
  ["rose-pine", "Rosé Pine", "ws-fill"],
  ["synthwave", "Synthwave", "ws-under"],
];
const desk = document.getElementById("desk");
const dock = document.getElementById("dock");
const bar = document.getElementById("bar");
const gl = document.getElementById("gl");
const gc = document.getElementById("gc");
const gr = document.getElementById("gr");
const more = bar.querySelector(".more");
const pop = document.getElementById("pop");
const panes = [...pop.querySelectorAll(".pane")];
const menu = pop.querySelector('[data-id="more"]');
const reduce = matchMedia("(prefers-reduced-motion: reduce)");
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
let openId = null;
let editing = false;

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
const needed = () => gl.scrollWidth + gc.scrollWidth + gr.scrollWidth + 36 + (gc.offsetWidth ? 12 : 0);
function fit() {
  const widgets = [...bar.querySelectorAll("[data-pri]")].filter(w => w.dataset.pri !== "never");
  widgets.forEach(w => w.classList.remove("over"));
  more.hidden = true;
  if (editing) { fades(); return; }
  const order = widgets.map((w, i) => ({ w, p: Number(w.dataset.pri), i })).sort((a, b) => a.p - b.p || b.i - a.i).map(o => o.w);
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
    b.classList.toggle("over-off", !bar.querySelector(`[data-key="${b.dataset.for}"]`)?.classList.contains("over"));
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
  if (id !== openId && anchorFor(id).hidden) return;
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

/* Sound opens its volume slider on hover, when the bar has room for it */
const sound = bar.querySelector(".snd");
const volume = sound.querySelector("input");
function expandSound(open) {
  sound.classList.toggle("expand", open && needed() + sound.querySelector(".slide > span").scrollWidth + 7 <= bar.clientWidth);
  setTimeout(place, 320);
}
sound.addEventListener("mouseenter", () => expandSound(true));
sound.addEventListener("mouseleave", () => { if (!sound.querySelector(":focus-visible")) expandSound(false); });
sound.addEventListener("focusin", () => expandSound(true));
sound.addEventListener("focusout", () => { if (!sound.matches(":hover")) expandSound(false); });
volume.addEventListener("input", () => {
  sound.querySelector(".pct").textContent = `${volume.value}%`;
  volume.style.setProperty("--v", `${volume.value}%`);
});

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
  endEditing();
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
  if (header) endEditing();
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
for (const el of document.querySelectorAll(".pops, .board, .scripts, .store-win, .setup, .install .desktop")) {
  el.classList.add("reveal");
  io.observe(el);
}

/* Edit Bar in Place: the bar becomes its own editor, as in the app. Each position gets a tray,
   widgets keep their look, − takes one off, + adds one where it sits, and Undo and Done wait below. */
const trays = [gl, gc, gr];
const TRAYS = ["Left", "Center", "Right"];
const NAMES = { apple: "Apple menu", ws: "Workspaces", app: "App menus", np: "Now playing", meeting: "Calendar", system: "System monitor", sound: "Sound", battery: "Battery", clock: "Clock & date" };
const ease = "cubic-bezier(.22, 1, .36, 1)";
const editCtl = document.getElementById("edit-ctl");
const undoButton = document.getElementById("edit-undo");
const addPop = document.getElementById("addpop");
const ctx = document.getElementById("ctx");
const live = document.getElementById("edit-live");
let past = [], future = [], drag = null, adding = null, made = 0;

const lane = i => trays[i].querySelector(".lane");
const tilesIn = (i, except) => [...lane(i).querySelectorAll(":scope > .tile:not([hidden])")].filter(t => t !== except);
const trayOf = t => trays.indexOf(t.closest(".g"));
const nameOf = t => t.dataset.name;
const snap = () => trays.map((g, i) => tilesIn(i));
const same = (a, b) => a.every((tiles, i) => tiles.length === b[i].length && tiles.every((t, k) => t === b[i][k]));
const say = text => { live.textContent = text; };

function tile(w) {
  const t = document.createElement("div");
  t.className = "tile";
  t.tabIndex = 0;
  t.hidden = w.hidden;
  t.dataset.name = w.dataset.name || NAMES[w.dataset.key];
  t.setAttribute("role", "button");
  t.setAttribute("aria-label", t.dataset.name);
  t.setAttribute("aria-describedby", "edit-help");
  w.hidden = false;
  w.inert = true;
  const minus = document.createElement("button");
  minus.className = "minus";
  minus.tabIndex = -1;
  minus.title = minus.ariaLabel = `Remove ${t.dataset.name}`;
  t.append(w, minus);
  return t;
}

function beginEditing() {
  if (editing || dock.classList.contains("header")) return;
  if (openId) open(openId);
  closeMenu();
  editing = true;
  past = [];
  future = [];
  sound.classList.remove("expand");
  finder.classList.remove("expand");
  for (const [i, g] of trays.entries()) {
    const l = document.createElement("div");
    l.className = "lane";
    for (const w of [...g.children].filter(w => w.dataset.key && !w.matches(".more, .dl, .site"))) l.append(tile(w));
    const add = document.createElement("button");
    add.className = "add";
    add.title = add.ariaLabel = `Add a widget to ${TRAYS[i]}`;
    add.innerHTML = '<svg aria-hidden="true"><use href="#i-plus"/></svg>';
    add.addEventListener("click", e => { e.stopPropagation(); adding?.i === i ? closeAdd() : openAdd(i, add); });
    i === 2 ? l.prepend(add) : l.append(add);
    l.addEventListener("scroll", fades, { passive: true });
    l.addEventListener("wheel", e => {
      if (l.scrollWidth <= l.clientWidth || Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;
      l.scrollLeft += e.deltaY;
      e.preventDefault();
    }, { passive: false });
    const chip = document.createElement("span");
    chip.className = "chip";
    chip.textContent = TRAYS[i];
    chip.ariaHidden = "true";
    g.append(chip, l);
    g.setAttribute("role", "group");
    g.ariaLabel = TRAYS[i];
  }
  dock.classList.add("editing");
  updateControls();
  fit();
  say("Editing the bar. Done or Escape finishes.");
}

function endEditing() {
  if (!editing) return;
  if (drag?.started) {
    settle(false);
    drag.ghost.remove();
  }
  drag = null;
  closeAdd();
  closeMenu();
  for (const g of trays) {
    const end = g.querySelector(":scope > .dl, :scope > .site");
    for (const t of g.querySelectorAll(".lane > .tile")) {
      const w = t.firstElementChild;
      w.inert = false;
      w.hidden = t.hidden;
      g.insertBefore(w, end);
    }
    g.querySelector(".lane").remove();
    g.querySelector(".chip").remove();
    g.removeAttribute("role");
    g.removeAttribute("aria-label");
  }
  editing = false;
  dock.classList.remove("editing", "dragging");
  updateControls();
  requestAnimationFrame(() => { fit(); slide(); });
  say("Finished editing the bar.");
}

function updateControls() {
  undoButton.disabled = !past.length;
}

/* Lanes too crowded for their tray scroll sideways, with faded edges */
function fades() {
  for (const l of bar.querySelectorAll(".lane")) {
    l.classList.toggle("fl", l.scrollLeft > 1);
    l.classList.toggle("fr", l.scrollLeft + l.clientWidth < l.scrollWidth - 1);
  }
}

/* Widgets slide aside to make room: each one glides from where it was to where it lands */
function rearrange(change) {
  const items = [...bar.querySelectorAll(".lane > *")];
  const first = new Map(items.map(e => [e, e.getBoundingClientRect()]));
  change();
  fades();
  if (reduce.matches) return;
  for (const e of items) {
    e.getAnimations().forEach(a => a.cancel());
    const a = first.get(e), b = e.getBoundingClientRect();
    if (e.hidden || !a.width || !b.width) continue;
    const dx = a.left - b.left, dy = a.top - b.top;
    if (Math.abs(dx) + Math.abs(dy) > .5) e.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "none" }], { duration: 300, easing: ease });
  }
}

/* Put a widget at a place among the shown widgets of a position; the + keeps its end */
function putAt(i, t, index) {
  const tiles = tilesIn(i, t);
  if (tiles[index]) tiles[index].before(t);
  else if (tiles.length) tiles.at(-1).after(t);
  else i === 2 ? lane(i).append(t) : lane(i).prepend(t);
}

function record(before, message) {
  if (same(before, snap())) return;
  past.push(before);
  future = [];
  updateControls();
  say(message);
}

function restore(state) {
  rearrange(() => {
    const kept = new Set(state.flat());
    for (const t of bar.querySelectorAll(".lane > .tile")) t.hidden = !kept.has(t);
    state.forEach((tiles, i) => tiles.forEach((t, k) => putAt(i, t, k)));
  });
}
function undo() {
  if (!past.length) return;
  future.push(snap());
  restore(past.pop());
  updateControls();
  say("Undone.");
}
function redo() {
  if (!future.length) return;
  past.push(snap());
  restore(future.pop());
  updateControls();
  say("Redone.");
}

function step(t, by) {
  const before = snap(), i = trayOf(t), tiles = tilesIn(i), k = tiles.indexOf(t);
  if (!tiles[k + by] && !trays[i + by]) return;
  rearrange(() => {
    if (tiles[k + by]) putAt(i, t, k + by);
    else putAt(i + by, t, by < 0 ? Infinity : 0);
  });
  t.focus();
  t.scrollIntoView({ block: "nearest", inline: "nearest" });
  record(before, `Moved ${nameOf(t)} to ${TRAYS[trayOf(t)]}, position ${tilesIn(trayOf(t)).indexOf(t) + 1}.`);
}

function remove(t) {
  const before = snap();
  const next = t.nextElementSibling?.matches(".tile:not([hidden])") ? t.nextElementSibling : t.previousElementSibling;
  rearrange(() => { t.hidden = true; });
  (next?.matches(".tile, .add") ? next : editCtl.querySelector(".done")).focus();
  record(before, `Removed ${nameOf(t)}.`);
}

/* Dragging: the widget lifts off the bar, the others make room, and it settles into the gap */
function trayAt(x, y) {
  const b = bar.getBoundingClientRect();
  if (y < b.top - 40 || y > b.bottom + 70) return -1;
  let best = -1, gap = Infinity;
  trays.forEach((g, i) => {
    const r = g.getBoundingClientRect();
    const d = x < r.left ? r.left - x : x > r.right ? x - r.right : 0;
    if (r.width && d < gap) { best = i; gap = d; }
  });
  return best;
}
function indexAt(i, x, t) {
  const tiles = tilesIn(i, t);
  const k = tiles.findIndex(o => { const r = o.getBoundingClientRect(); return x < r.left + r.width / 2; });
  return k < 0 ? tiles.length : k;
}
function lift(e) {
  const t = drag.t, r = t.getBoundingClientRect();
  drag.started = true;
  drag.before = snap();
  drag.home = [trayOf(t), tilesIn(trayOf(t)).indexOf(t)];
  drag.dx = e.clientX - r.left;
  drag.dy = e.clientY - r.top;
  const ghost = document.createElement("div");
  ghost.className = `ghost ${[...bar.classList].filter(c => c.startsWith("ws-")).join(" ")}`;
  const copy = t.firstElementChild.cloneNode(true);
  copy.querySelector(".ind")?.remove();
  ghost.append(copy);
  desk.append(ghost);
  drag.ghost = ghost;
  t.classList.add("lifted");
  dock.classList.add("dragging");
  closeAdd();
  closeMenu();
}
function follow(e) {
  const { t, ghost } = drag;
  ghost.style.left = `${e.clientX - drag.dx}px`;
  ghost.style.top = `${e.clientY - drag.dy}px`;
  const i = trayAt(e.clientX, e.clientY);
  drag.target = i;
  trays.forEach((g, k) => g.classList.toggle("target", k === i));
  if (i < 0) return;
  const l = lane(i), r = l.getBoundingClientRect();
  if (e.clientX < r.left + 24) l.scrollLeft -= 8;
  else if (e.clientX > r.right - 24) l.scrollLeft += 8;
  const index = indexAt(i, e.clientX, t);
  if (trayOf(t) !== i || tilesIn(i).indexOf(t) !== index) rearrange(() => putAt(i, t, index));
}
function settle(dropped) {
  const { t, ghost, before, home } = drag;
  if (!dropped) rearrange(() => putAt(home[0], t, home[1]));
  trays.forEach(g => g.classList.remove("target"));
  dock.classList.remove("dragging");
  const r = t.getBoundingClientRect(), from = ghost.getBoundingClientRect();
  const done = () => { ghost.remove(); t.classList.remove("lifted"); };
  if (reduce.matches) done();
  else ghost.animate([{ left: `${from.left}px`, top: `${from.top}px`, scale: 1.04 }, { left: `${r.left}px`, top: `${r.top}px`, scale: 1 }], { duration: 260, easing: ease, fill: "forwards" }).finished.then(done);
  if (dropped) record(before, `Moved ${nameOf(t)} to ${TRAYS[trayOf(t)]}.`);
}
bar.addEventListener("pointerdown", e => {
  const t = editing && e.button === 0 && e.target.closest(".tile");
  if (!t || e.target.closest(".minus")) return;
  e.preventDefault();
  t.focus({ preventScroll: true });
  t.setPointerCapture(e.pointerId);
  drag = { t, x: e.clientX, y: e.clientY, started: false };
});
bar.addEventListener("pointermove", e => {
  if (!drag) return;
  if (!drag.started) {
    if (Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 4) return;
    lift(e);
  }
  follow(e);
});
bar.addEventListener("pointerup", () => {
  if (drag?.started) settle(drag.target >= 0);
  drag = null;
});
bar.addEventListener("pointercancel", () => {
  if (drag?.started) settle(false);
  drag = null;
});
bar.addEventListener("click", e => {
  const minus = editing && e.target.closest(".minus");
  if (minus) { e.stopPropagation(); remove(minus.closest(".tile")); }
});
bar.addEventListener("keydown", e => {
  const t = editing && e.target.closest?.(".tile");
  if (!t) return;
  if (e.key === "ArrowLeft" || e.key === "ArrowRight") { e.preventDefault(); step(t, e.key === "ArrowLeft" ? -1 : 1); }
  else if (e.key === "Delete" || e.key === "Backspace") { e.preventDefault(); remove(t); }
});

/* Add here: the app's list of widgets, then a review for a Store package before it's added */
const CHOICES = [
  { id: "clock", name: "Clock & date", icon: "i-clock", key: "clock", html: '<div class="w num clock" data-format="time"></div>' },
  { id: "activeApp", name: "Active app", icon: "i-window", html: '<div class="w app"><img class="ai" src="images/apps/finder.svg" alt="" width="16" height="16" style="width:16px;height:16px"><span class="name">Finder</span></div>' },
  { id: "appleMenu", name: "Apple menu", icon: "i-apple", key: "apple", html: '<div class="w apple"><svg style="width:13px;height:15px;fill:currentColor"><use href="#i-apple"/></svg></div>' },
  { id: "appMenu", name: "App menus", icon: "i-menubar", key: "app", html: '<div class="w app"><span class="name">Finder</span></div>' },
  { id: "controlCenter", name: "Control Center", icon: "i-switch", html: '<div class="w"><svg><use href="#i-switch"/></svg></div>' },
  { id: "menuBarItems", name: "Menu bar items", icon: "i-grid", html: '<div class="w"><svg><use href="#i-grid"/></svg></div>' },
  { id: "battery", name: "Battery", icon: "i-bat", key: "battery", html: '<div class="w"><svg style="width:19px"><use href="#i-bat"/></svg>82%</div>' },
  { id: "audio", name: "Sound", icon: "i-snd", key: "sound", html: '<div class="w"><svg><use href="#i-snd"/></svg></div>' },
  { id: "system", name: "System monitor", icon: "i-cpu", key: "system", html: '<div class="w"><svg><use href="#i-cpu"/></svg>18%&nbsp;&nbsp;<svg><use href="#i-mem"/></svg>54%</div>' },
  { id: "network", name: "Network", icon: "i-globe", html: '<div class="w num">↓ 2.4 MB/s&nbsp;&nbsp;↑ 180 KB/s</div>' },
  { id: "calendar", name: "Calendar", icon: "i-cal", key: "meeting", html: '<div class="w"><svg><use href="#i-cal"/></svg>Design review&nbsp;&nbsp;10:30</div>' },
  { id: "workspaces", name: "Workspaces", icon: "i-group", key: "ws", html: '<div class="w ws copy"><span class="wsi on">1</span><span class="wsi">2</span><span class="wsi">3</span></div>' },
  { id: "text", name: "Text", icon: "i-text", html: '<div class="w">New widget</div>' },
  { id: "spacer", name: "Spacer", icon: "i-spacer", html: '<div class="w spacer"></div>' },
  { id: "ai-usage", name: "AI usage", version: "1.2.5", commands: 1, hosts: ["api.anthropic.com", "chatgpt.com"], description: "Shows your Claude Code and Codex limits in one widget, with reset countdowns and weekly pace, using the sign-ins those tools already keep.", html: '<div class="w"><svg><use href="#i-asterisk"/></svg><span class="gauge"><i style="--p:42%"></i><i style="--p:64%"></i></span>42%&nbsp;&nbsp;<svg><use href="#i-term"/></svg><span class="gauge"><i style="--p:18%"></i><i style="--p:30%"></i></span>18%</div>' },
  { id: "agent-status", name: "Agent status", version: "1.0.4", commands: 1, requires: ["jq"], description: "Shows Claude Code waiting or finishing and Codex finishing.", html: '<div class="w"><svg><use href="#i-term"/></svg>1</div>' },
  { id: "amphetamine", name: "Amphetamine", version: "1.1.1", commands: 5, permissions: ["Automation"], description: "Toggle Amphetamine from the bar, adjust its timer with an inline hover slider, and see the time remaining.", html: '<div class="w"><svg><use href="#i-pill"/></svg>Off</div>' },
  { id: "dev-servers", name: "Development servers", version: "1.0.2", commands: 2, requires: ["jq"], description: "Lists your listening TCP ports and their processes, with actions to open localhost or stop a process.", html: '<div class="w"><svg><use href="#i-server"/></svg>3</div>' },
  { id: "dock-badges", name: "Dock badges", version: "1.0.2", commands: 1, requires: ["jq"], description: "Shows the total unread count from running apps' Dock badges, with a popup that opens each app.", html: '<div class="w"><svg><use href="#i-badge"/></svg>2</div>' },
  { id: "github-notifications", name: "GitHub notifications", version: "1.0.2", commands: 1, hosts: ["api.github.com"], description: "Shows your unread GitHub notification count and lists the latest ones, each opening on GitHub.", html: '<div class="w"><svg><use href="#i-bell"/></svg>3</div>' },
  { id: "homebrew-outdated", name: "Homebrew outdated", version: "1.0.3", commands: 1, requires: ["brew"], description: "Shows how many Homebrew formulae and casks are outdated, and lists them.", html: '<div class="w"><svg><use href="#i-box"/></svg>4</div>' },
  { id: "now-playing", name: "Now playing", version: "1.2.2", commands: 11, hosts: ["i.scdn.co"], permissions: ["Automation"], key: "np", description: "Shows the playing or paused track from Music or Spotify with its artwork and bouncing bars while it plays, and a popup with seeking, volume, shuffle, repeat and favorites.", html: '<div class="w"><i class="art"></i>Midnight City · M83</div>' },
  { id: "quick-ask", name: "Quick ask", version: "1.0.0", commands: 12, hosts: ["api.anthropic.com", "chatgpt.com", "api.openai.com"], requires: ["jq"], description: "Ask Claude Code or Codex from the bar. Choose the model and effort, follow up, retry, and drag the chat anywhere to keep it on screen.", html: '<div class="w"><svg><use href="#i-sparkles"/></svg></div>' },
  { id: "weather", name: "Weather", version: "1.0.3", commands: 1, hosts: ["wttr.in"], description: "Shows the current temperature and conditions from wttr.in, with feels-like, humidity, wind and today's high and low.", html: '<div class="w"><svg><use href="#i-weather"/></svg>14°</div>' },
  { id: "script", name: "Script", icon: "i-term", html: '<div class="w num clock" data-format="time"></div>' },
];
const list = (items, last) => items.length > 1 ? `${items.slice(0, -1).join(", ")} ${last} ${items.at(-1)}` : items[0];

addPop.addEventListener("click", e => e.stopPropagation());
function openAdd(i, button) {
  closeMenu();
  adding = { i, button };
  bar.querySelectorAll(".add").forEach(b => b.classList.toggle("on", b === button));
  dock.classList.add("adding");
  showChoices("");
}
function closeAdd() {
  if (!adding) return;
  const { button } = adding;
  adding = null;
  addPop.hidden = true;
  addPop.classList.remove("review");
  dock.classList.remove("adding");
  bar.querySelectorAll(".add").forEach(b => b.classList.remove("on"));
  if (addPop.contains(document.activeElement)) button.focus();
}
function placeAdd() {
  const dr = dock.getBoundingClientRect(), a = adding.button.getBoundingClientRect();
  const left = clamp(a.left - dr.left + a.width / 2 - 30, 8, dr.width - addPop.offsetWidth - 8);
  addPop.style.left = `${left}px`;
  addPop.style.top = `${a.bottom - dr.top + 13}px`;
  addPop.style.setProperty("--ax", `${a.left - dr.left + a.width / 2 - left - 6}px`);
}
function showChoices(query) {
  addPop.classList.remove("review");
  addPop.innerHTML = '<p class="t">ADD HERE</p><input class="find" type="search" placeholder="Search widgets" aria-label="Search widgets"><div class="list"></div>';
  const find = addPop.querySelector(".find"), grid = addPop.querySelector(".list");
  find.value = query;
  const fill = () => {
    const q = find.value.trim().toLowerCase();
    const shown = CHOICES.filter(c => c.name.toLowerCase().includes(q));
    grid.innerHTML = shown.map(c => `<button class="ch" data-id="${c.id}" title="${c.description || ""}"><svg class="ic" aria-hidden="true"><use href="#${c.version ? "i-box" : c.icon}"/></svg><span><b>${c.name}</b><small>${c.version ? "Store" : "Built-in"}</small></span>${c.version ? '<svg class="from-store" role="img" aria-label="Downloads from Store"><use href="#i-get"/></svg>' : ""}</button>`).join("") || '<p class="none">No widgets found.</p>';
    placeAdd();
  };
  find.addEventListener("input", fill);
  find.addEventListener("keydown", e => { if (e.key === "Enter") grid.querySelector(".ch")?.click(); });
  grid.addEventListener("click", e => {
    const c = CHOICES.find(c => c.id === e.target.closest(".ch")?.dataset.id);
    if (c) c.version ? review(c, find.value) : add(c);
  });
  addPop.hidden = false;
  fill();
  find.focus({ preventScroll: true });
}
/* A Store package's review: what it can do, before it's added */
function reviewHTML(c, back, go) {
  const can = [
    ["i-term", `Runs ${c.commands} command${c.commands === 1 ? "" : "s"} while it’s on your bar`],
    ["i-lock", c.permissions ? `Uses ${list(c.permissions, "and")} access` : "Needs no macOS permissions"],
    ["i-globe", c.hosts ? `Connects to ${list(c.hosts, "and")}` : "Doesn’t go online"],
    ...(c.requires || []).map(tool => ["i-tool", `Needs ${tool}`]),
  ];
  return `<button class="back">${back}</button><h4>${c.name}</h4><p class="d">${c.description}</p><p class="m">${c.id} · Version ${c.version} · StableBar Store</p>
    <ul class="can">${can.map(([icon, text]) => `<li><svg aria-hidden="true"><use href="#${icon}"/></svg>${text}</li>`).join("")}</ul>
    <div class="foot"><span>A maintainer read this package before the Store published it.</span><button class="go">${go}</button></div>`;
}
function review(c, query) {
  addPop.classList.add("review");
  addPop.innerHTML = reviewHTML(c, "Back", "Add widget");
  addPop.querySelector(".back").addEventListener("click", () => showChoices(query));
  addPop.querySelector(".go").addEventListener("click", () => add(c));
  placeAdd();
  addPop.querySelector(".go").focus({ preventScroll: true });
}
/* A new widget from a choice, listed in More widgets in case the bar runs out of room */
function make(c) {
  const holder = document.createElement("div");
  holder.innerHTML = c.html;
  const w = holder.firstElementChild;
  w.dataset.key = `added-${++made}`;
  w.dataset.pri = "2";
  w.dataset.name = c.name;
  menu.insertAdjacentHTML("beforeend", `<button data-for="${w.dataset.key}">${c.name}</button>`);
  if (c.version) installed(c.id);
  return w;
}
function add(c) {
  const { i } = adding, before = snap();
  let t = c.key && [...bar.querySelectorAll(".lane > .tile[hidden]")].find(o => o.firstElementChild.dataset.key === c.key);
  if (!t) {
    t = tile(make(c));
    t.hidden = true;
    lane(i).append(t);
    tick();
  }
  rearrange(() => {
    t.hidden = false;
    putAt(i, t, i === 2 ? 0 : Infinity);
  });
  if (!reduce.matches) t.animate([{ opacity: 0, scale: .85 }, { opacity: 1, scale: 1 }], { duration: 220, easing: ease });
  closeAdd();
  t.focus({ preventScroll: true });
  t.scrollIntoView({ block: "nearest", inline: "nearest" });
  record(before, `Added ${c.name} to ${TRAYS[i]}.`);
}

/* The Store section: Get reviews a package, and Add to bar puts it on the bar at the top of the page */
const pkgReview = document.getElementById("pkg-review");
const storeWin = document.querySelector(".store-win");
let reviewing = null;
function installed(id) {
  const state = document.querySelector(`.pkg[data-id="${id}"] .pkg-get`);
  state?.replaceWith(Object.assign(document.createElement("span"), { className: "state", innerHTML: '<svg viewBox="0 0 12 12" aria-hidden="true"><use href="#p-check"/></svg>Installed' }));
}
function closeReview() {
  if (!reviewing) return;
  const get = reviewing;
  reviewing = null;
  pkgReview.hidden = true;
  storeWin.classList.remove("sheet");
  if (pkgReview.contains(document.activeElement) && get.isConnected) get.focus({ preventScroll: true });
}
document.querySelector(".pkgs").addEventListener("click", e => {
  const get = e.target.closest(".pkg-get");
  if (!get) return;
  e.stopPropagation();
  if (reviewing === get) return closeReview();
  const c = CHOICES.find(c => c.id === get.closest(".pkg").dataset.id);
  reviewing = get;
  pkgReview.innerHTML = reviewHTML(c, "Cancel", "Add to bar");
  pkgReview.hidden = false;
  storeWin.classList.add("sheet");
  pkgReview.querySelector(".back").addEventListener("click", closeReview);
  pkgReview.querySelector(".go").addEventListener("click", () => {
    closeReview();
    const w = make(c);
    if (editing) {
      const t = tile(w);
      t.hidden = true;
      lane(2).append(t);
      const before = snap();
      rearrange(() => { t.hidden = false; putAt(2, t, 0); });
      record(before, `Added ${c.name} to Right.`);
    } else {
      gr.insertBefore(w, more.nextElementSibling);
      fit();
      if (!reduce.matches) w.animate([{ opacity: 0, scale: .85 }, { opacity: 1, scale: 1 }], { duration: 260, easing: ease });
    }
    say(`Added ${c.name} to the bar.`);
  });
  pkgReview.querySelector(".go").focus({ preventScroll: true });
});
pkgReview.addEventListener("click", e => e.stopPropagation());

/* Right-click the bar, as in the app: Edit Bar in Place, or a widget's moves while editing */
function showMenu(x, y, items) {
  closeAdd();
  ctx.innerHTML = items.map(item => item ? `<button role="menuitem">${item[0]}</button>` : "<hr>").join("");
  const actions = items.filter(Boolean).map(item => item[1]);
  ctx.querySelectorAll("button").forEach((b, k) => b.addEventListener("click", e => { e.stopPropagation(); closeMenu(); actions[k](); }));
  ctx.hidden = false;
  const dr = dock.getBoundingClientRect();
  ctx.style.left = `${clamp(x - dr.left, 4, dr.width - ctx.offsetWidth - 4)}px`;
  ctx.style.top = `${y - dr.top + 2}px`;
  ctx.querySelector("button").focus({ preventScroll: true });
}
function closeMenu() { ctx.hidden = true; }
bar.addEventListener("contextmenu", e => {
  if (dock.classList.contains("header") || innerWidth < 720 || e.target.closest(".menus a")) return;
  e.preventDefault();
  const t = editing && e.target.closest(".tile");
  if (!editing) showMenu(e.clientX, e.clientY, [["Edit Bar in Place", beginEditing]]);
  else if (t) showMenu(e.clientX, e.clientY, [["Move Left", () => step(t, -1)], ["Move Right", () => step(t, 1)], ["Remove Widget", () => remove(t)], null, ["Finish Editing Bar", endEditing]]);
  else showMenu(e.clientX, e.clientY, [["Finish Editing Bar", endEditing]]);
});
ctx.addEventListener("keydown", e => {
  const items = [...ctx.querySelectorAll("button")], k = items.indexOf(document.activeElement);
  if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); items[(k + (e.key === "ArrowDown" ? 1 : -1) + items.length) % items.length].focus(); }
});

document.getElementById("edit-start").addEventListener("click", e => {
  e.stopPropagation();
  beginEditing();
  bar.querySelector(".tile")?.focus({ preventScroll: true });
});
/* From the Configure section: back to the bar, then edit it */
document.getElementById("try-edit").addEventListener("click", e => {
  e.stopPropagation();
  scrollTo({ top: 0, behavior: reduce.matches ? "auto" : "smooth" });
  const until = performance.now() + 2500;
  const go = () => {
    if (scrollY > 1) { if (performance.now() < until) requestAnimationFrame(go); return; }
    dockState();
    beginEditing();
    bar.querySelector(".tile")?.focus({ preventScroll: true });
  };
  requestAnimationFrame(go);
});
undoButton.addEventListener("click", e => { e.stopPropagation(); undo(); });
document.getElementById("edit-done").addEventListener("click", e => {
  e.stopPropagation();
  endEditing();
  document.getElementById("edit-start").focus({ preventScroll: true });
});
document.addEventListener("click", e => {
  if (!ctx.hidden && !e.target.closest(".ctx")) closeMenu();
  if (adding && !e.target.closest(".addpop, .add")) closeAdd();
  if (reviewing) closeReview();
});
document.addEventListener("keydown", e => {
  if (e.key === "Escape") {
    if (reviewing) { closeReview(); return; }
    if (!ctx.hidden) { closeMenu(); return; }
    if (adding) { closeAdd(); return; }
    if (drag?.started) { settle(false); drag = null; return; }
    if (editing) { endEditing(); document.getElementById("edit-start").focus({ preventScroll: true }); }
  } else if (editing && (e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z" && !e.target.closest("input")) {
    e.preventDefault();
    e.shiftKey ? redo() : undo();
  }
});
addEventListener("scroll", closeMenu, { passive: true });

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
if (innerWidth >= 720) setTimeout(() => { if (!openId && !editing) open("agenda"); }, reduce.matches ? 0 : 1100);
