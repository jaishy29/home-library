(() => {
"use strict";
const $ = id => document.getElementById(id);
const today = () => new Date().toISOString().slice(0, 10);

/* ---------- storage: IndexedDB on this device ---------- */
const DB_NAME = "home-library", STORE = "books";
let dbp = null;
function idb() {
  if (!dbp) dbp = new Promise((res, rej) => {
    const r = indexedDB.open(DB_NAME, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(STORE, { keyPath: "id" });
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
  return dbp;
}
async function tx(mode, fn) {
  const db = await idb();
  return new Promise((res, rej) => {
    const t = db.transaction(STORE, mode), s = t.objectStore(STORE);
    const out = fn(s);
    t.oncomplete = () => res(out && "result" in out ? out.result : undefined);
    t.onerror = () => rej(t.error);
  });
}
const store = {
  all: () => tx("readonly", s => s.getAll()),
  put: b => tx("readwrite", s => s.put(b)),
  del: id => tx("readwrite", s => s.delete(id)),
  replaceAll: list => tx("readwrite", s => { s.clear(); list.forEach(b => s.put(b)); }),
};
try { navigator.storage && navigator.storage.persist && navigator.storage.persist(); } catch (e) {}

/* ---------- ISBN ---------- */
const cleanIsbn = s => String(s || "").toUpperCase().replace(/[^0-9X]/g, "");
function valid13(d) { if (!/^\d{13}$/.test(d)) return false; let s = 0; for (let i = 0; i < 12; i++) s += +d[i] * (i % 2 ? 3 : 1); return (10 - s % 10) % 10 === +d[12]; }
function valid10(d) { if (!/^\d{9}[\dX]$/.test(d)) return false; let s = 0; for (let i = 0; i < 10; i++) s += (d[i] === "X" ? 10 : +d[i]) * (10 - i); return s % 11 === 0; }
function to13(d) { const b = "978" + d.slice(0, 9); let s = 0; for (let i = 0; i < 12; i++) s += +b[i] * (i % 2 ? 3 : 1); return b + ((10 - s % 10) % 10); }
function normIsbn(s) { const d = cleanIsbn(s); if (valid13(d)) return d; if (valid10(d)) return to13(d); return null; }
const fmtIsbn = d => d && d.length === 13 ? `${d.slice(0, 3)}-${d.slice(3, 12)}-${d[12]}` : (d || "");
const isBookCode = s => { const d = cleanIsbn(s); return /^97[89]/.test(d) && valid13(d); };

/* ---------- utils ---------- */
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
function hue(s) { let h = 0; for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) % 360; return h; }
const daysSince = d => d ? Math.max(0, Math.round((Date.now() - new Date(d + "T12:00:00").getTime()) / 864e5)) : 0;
const fmtDate = d => { if (!d) return ""; try { return new Date(d + "T12:00:00").toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" }); } catch { return d; } };
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));
let toastT; function toast(m) { const t = $("toast"); t.textContent = m; t.hidden = false; clearTimeout(toastT); toastT = setTimeout(() => t.hidden = true, 2600); }
const SPINES = ["#e0528b", "#c2709b", "#9b6fd0", "#ef8aa8", "#d4789b", "#b85c8e", "#e9a07a", "#7f8fd6"];
const coverSrc = b => b.coverData || b.coverUrl || null;

/* ---------- book lookup: Open Library, then Google Books ---------- */
async function getJSON(url) {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 12000);
  try { const r = await fetch(url, { signal: ctl.signal }); if (!r.ok) return null; return await r.json(); }
  catch { return null; } finally { clearTimeout(t); }
}
function imageExists(url) {
  return new Promise(res => {
    if (!url) return res(false);
    const i = new Image(); const t = setTimeout(() => res(false), 8000);
    i.onload = () => { clearTimeout(t); res(i.naturalWidth > 20); };
    i.onerror = () => { clearTimeout(t); res(false); };
    i.src = url;
  });
}
async function lookupIsbn(isbn) {
  let info = null;
  const ol = await getJSON(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`);
  const b = ol && ol["ISBN:" + isbn];
  if (b && b.title) {
    info = {
      title: b.title + (b.subtitle && b.title.length < 40 ? ": " + b.subtitle : ""),
      author: (b.authors || []).map(a => a.name).join(", "),
      year: ((b.publish_date || "").match(/\d{4}/) || [""])[0],
      cover: null,
    };
    const c = b.cover && (b.cover.large || b.cover.medium);
    const candidates = [c && c.replace(/^http:/, "https:"), `https://covers.openlibrary.org/b/isbn/${isbn}-L.jpg?default=false`];
    for (const u of candidates) if (u && await imageExists(u)) { info.cover = u; break; }
  }
  if (!info || !info.cover) {
    const g = await getJSON(`https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`);
    const v = g && g.items && g.items[0] && g.items[0].volumeInfo;
    if (v) {
      if (!info) info = { title: v.title || "", author: (v.authors || []).join(", "), year: (v.publishedDate || "").slice(0, 4), cover: null };
      const th = v.imageLinks && (v.imageLinks.thumbnail || v.imageLinks.smallThumbnail);
      if (th) { const u = th.replace(/^http:/, "https:").replace("&edge=curl", "").replace("zoom=1", "zoom=2"); if (await imageExists(u)) info.cover = u; }
    }
  }
  return info;
}

/* ---------- state + render ---------- */
let books = [], filter = "all", editing = null, draft = {};

async function reload() { books = await store.all(); render(); }

function match(b) {
  if (filter === "read" && b.status !== "read") return false;
  if (filter === "toread" && b.status === "read") return false;
  if (filter === "loan" && !b.loanTo) return false;
  const q = $("q").value.trim().toLowerCase(); if (!q) return true;
  const qd = cleanIsbn(q);
  return [b.title, b.author, b.loanTo, b.from].some(v => String(v || "").toLowerCase().includes(q)) || (qd.length > 2 && String(b.isbn || "").includes(qd));
}
function sorted(list) {
  const k = $("sort").value, s = (a, b) => String(a || "").localeCompare(String(b || ""));
  return [...list].sort((a, b) => k === "title" ? s(a.title, b.title) : k === "author" ? (s(a.author, b.author) || s(a.title, b.title)) : k === "bought" ? s(b.boughtOn, a.boughtOn) : (b.addedAt || 0) - (a.addedAt || 0));
}
function render() {
  const read = books.filter(b => b.status === "read").length, loan = books.filter(b => b.loanTo).length;
  $("n-all").textContent = books.length; $("n-read").textContent = read; $("n-toread").textContent = books.length - read; $("n-loan").textContent = loan;
  document.querySelectorAll(".stat").forEach(b => b.setAttribute("aria-pressed", b.dataset.filter === filter));
  const yr = new Date().getFullYear(), boughtYr = books.filter(b => (b.boughtOn || "").startsWith(String(yr))).length;
  $("subline").textContent = books.length ? `${books.length} books · ${boughtYr} bought in ${yr} · ${loan} lent out` : "Every book on your shelves, read or waiting, home or lent out.";

  const wrap = $("listWrap");
  if (!books.length) {
    wrap.innerHTML = `<div class="list"><div class="empty"><svg width="96" height="70" viewBox="0 0 96 70" aria-hidden="true"><path d="M48 18C38 10 22 8 8 10v50c14-2 30 0 40 8 10-8 26-10 40-8V10c-14-2-30 0-40 8z" fill="var(--surface-2)" stroke="var(--accent)" stroke-width="2.5" stroke-linejoin="round"/><path d="M48 18v50" stroke="var(--accent)" stroke-width="2.5"/><path d="M18 24h20M18 32h20M18 40h14M58 24h20M58 32h20M58 40h14" stroke="var(--accent-2)" stroke-width="2.5" stroke-linecap="round"/><path d="M48 6c-2-3-7-2-6 2 .8 3 6 6 6 6s5-3 6-6c1-4-4-5-6-2z" fill="var(--accent)"/></svg><h2>Your shelves are waiting</h2><div>Tap <b>Scan a book</b> and point your camera at the barcode on the back cover. The title, author and cover fill in on their own.</div></div></div>`;
    return;
  }
  const shown = sorted(books.filter(match));
  if (!shown.length) { wrap.innerHTML = `<div class="list"><div class="empty">No books on this shelf yet.</div></div>`; return; }
  wrap.innerHTML = `<div class="shelf-list"><div class="list">${shown.map(b => {
    const src = coverSrc(b);
    const spine = `<div class="cover" style="background:${SPINES[hue(b.title) % SPINES.length]}">${esc((b.title || "?").split(/\s+/).slice(0, 3).join(" "))}</div>`;
    const cov0 = src ? `<img class="cover" src="${esc(src)}" alt="" loading="lazy" data-spine="${esc(spine)}">` : spine;
    const cov = `<div class="cover-wrap">${cov0}${b.status === "reading" ? '<span class="ribbon" title="Currently reading"></span>' : ""}</div>`;
    const st = b.status === "read" ? `<span class="pill read">Read</span>` : b.status === "reading" ? `<span class="pill reading">Reading</span>` : `<span class="pill unread">To be read</span>`;
    const ln = b.loanTo ? `<span class="pill loan">Lent to ${esc(b.loanTo)} · ${daysSince(b.loanOn)}d</span>` : "";
    return `<button class="row" data-id="${esc(b.id)}">${cov}<div class="meta"><div class="t">${esc(b.title || "Untitled")}</div><div class="a">${esc(b.author || "Unknown author")}${b.year ? " · " + esc(b.year) : ""}</div><div class="chips">${st}${ln}</div></div><span class="chev" aria-hidden="true">›</span></button>`;
  }).join("")}</div></div><div class="foot">♡ ${shown.length} ${shown.length === 1 ? "book" : "books"} on this shelf ♡</div>`;
  // fall back to a coloured spine if a cover image fails (e.g. offline)
  wrap.querySelectorAll("img.cover").forEach(img => img.addEventListener("error", () => { img.outerHTML = img.dataset.spine; }, { once: true }));
}

/* ---------- editor sheet ---------- */
function setStatus(v) {
  draft.status = v;
  document.querySelectorAll("#seg button").forEach(b => b.setAttribute("aria-pressed", b.dataset.v === v));
  $("finishedWrap").hidden = v !== "read";
  if (v === "read" && !$("f-finished").value) $("f-finished").value = today();
}
function isbnHint() {
  const d = cleanIsbn($("f-isbn").value), h = $("isbnHint"); h.classList.remove("bad");
  if (!d) { h.textContent = ""; return; }
  const n = normIsbn(d);
  if (n) {
    const dup = books.find(b => b.isbn === n && (!editing || b.id !== editing.id));
    h.textContent = dup ? `You already own this: “${dup.title}”` : "Check digit OK";
    if (dup) h.classList.add("bad");
  } else { h.textContent = d.length < 10 ? "" : "Check digit doesn't match. Re-check the number."; if (d.length >= 10) h.classList.add("bad"); }
}
function showCover() {
  const src = draft.coverData || draft.coverUrl;
  $("coverPrev").hidden = !src; $("coverPh").hidden = !!src; $("removeCover").hidden = !src;
  if (src) $("coverPrev").src = src;
}
function loanUi() {
  $("returnBtn").hidden = !(editing && editing.loanTo && $("f-loanTo").value.trim());
  const hist = draft.loanHistory || [];
  $("loanHist").innerHTML = hist.length ? "Past loans:<br>" + hist.slice().reverse().map(h => `${esc(h.to)} · ${fmtDate(h.on)} → ${fmtDate(h.back)}`).join("<br>") : "";
}
function openSheet(book) {
  editing = book || null;
  draft = { status: book?.status || "unread", coverUrl: book?.coverUrl || null, coverData: book?.coverData || null, loanHistory: book?.loanHistory || [] };
  $("sheetTitle").textContent = book ? "Edit book" : "Add a book";
  $("f-title").value = book?.title || ""; $("f-author").value = book?.author || "";
  $("f-isbn").value = book?.isbn ? fmtIsbn(book.isbn) : ""; $("f-year").value = book?.year || "";
  $("f-bought").value = book ? (book.boughtOn || "") : today(); $("f-price").value = book?.price ?? ""; $("f-from").value = book?.from || "";
  $("f-finished").value = book?.finishedOn || ""; $("f-loanTo").value = book?.loanTo || ""; $("f-loanOn").value = book?.loanOn || "";
  $("f-notes").value = book?.notes || ""; $("lookupMsg").textContent = "";
  setStatus(draft.status); isbnHint(); loanUi(); showCover();
  $("delBtn").hidden = !book; $("delConfirm").hidden = true;
  $("scrim").hidden = false;
}
function closeSheet() { $("scrim").hidden = true; editing = null; }

async function fillFromIsbn(isbn, overwrite) {
  $("lookupMsg").innerHTML = `<span class="spin"></span>Looking up ${fmtIsbn(isbn)}…`;
  const btn = $("lookupBtn"); btn.disabled = true;
  try {
    const info = await lookupIsbn(isbn);
    if (!info) { $("lookupMsg").textContent = navigator.onLine === false ? "You're offline. Type the details in, or look it up later." : "Couldn't find this ISBN online. Type the title and author in."; return; }
    if (overwrite || !$("f-title").value) $("f-title").value = info.title;
    if (overwrite || !$("f-author").value) $("f-author").value = info.author;
    if (!$("f-year").value) $("f-year").value = info.year;
    if (info.cover && !draft.coverData) { draft.coverUrl = info.cover; showCover(); }
    $("lookupMsg").textContent = info.cover ? "Details and cover filled in. Check them, then save." : "Details filled in. No cover found, so tap the cover to add a photo.";
  } finally { btn.disabled = false; }
}

async function save(ev) {
  ev.preventDefault();
  const title = $("f-title").value.trim(); if (!title) { $("f-title").focus(); return; }
  const raw = cleanIsbn($("f-isbn").value), loanTo = $("f-loanTo").value.trim();
  const b = {
    ...(editing || { id: uid(), addedAt: Date.now() }),
    title, author: $("f-author").value.trim(), isbn: normIsbn(raw) || raw, year: $("f-year").value.trim(),
    boughtOn: $("f-bought").value || "", price: $("f-price").value.trim(), from: $("f-from").value.trim(),
    status: draft.status, finishedOn: draft.status === "read" ? ($("f-finished").value || "") : "",
    loanTo, loanOn: loanTo ? ($("f-loanOn").value || today()) : "", loanHistory: draft.loanHistory || [],
    notes: $("f-notes").value.trim(), coverUrl: draft.coverUrl || null, coverData: draft.coverData || null,
  };
  try { await store.put(b); toast(editing ? "Saved" : `Added “${title}” to your shelf ♡`); closeSheet(); await reload(); }
  catch (e) { toast("Couldn't save. Your phone may be out of storage."); }
}

/* ---------- barcode decoding ---------- */
// Decodes book barcodes from a canvas region. Tries the native BarcodeDetector
// when the browser has one, then ZXing on the region and on it rotated 90°.
let zxReader = null;
function zx() {
  if (!zxReader && window.ZXing) {
    const h = new Map();
    h.set(ZXing.DecodeHintType.POSSIBLE_FORMATS, [ZXing.BarcodeFormat.EAN_13, ZXing.BarcodeFormat.UPC_A, ZXing.BarcodeFormat.EAN_8]);
    h.set(ZXing.DecodeHintType.TRY_HARDER, true);
    zxReader = new ZXing.MultiFormatReader(); zxReader.setHints(h);
  }
  return zxReader;
}
function lumaOf(ctx, w, h) {
  const px = ctx.getImageData(0, 0, w, h).data, out = new Uint8ClampedArray(w * h);
  for (let i = 0, j = 0; j < out.length; i += 4, j++) out[j] = (px[i] * 77 + px[i + 1] * 150 + px[i + 2] * 29) >> 8;
  return out;
}
function zxDecodeLuma(luma, w, h) {
  const r = zx(); if (!r) return null;
  try {
    const bmp = new ZXing.BinaryBitmap(new ZXing.HybridBinarizer(new ZXing.RGBLuminanceSource(luma, w, h)));
    return r.decodeWithState(bmp).getText();
  } catch (e) { return null; } finally { try { r.reset(); } catch (e) {} }
}
function rotateLuma(l, w, h) { // 90° clockwise
  const out = new Uint8ClampedArray(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) out[x * h + (h - 1 - y)] = l[y * w + x];
  return out;
}
let detector = null;
try { if ("BarcodeDetector" in window) detector = new BarcodeDetector({ formats: ["ean_13", "upc_a", "ean_8"] }); } catch (e) { detector = null; }

const work = document.createElement("canvas");
const wctx = work.getContext("2d", { willReadFrequently: true });
/** Draw (sx,sy,sw,sh) of `src` scaled to at most maxW wide, then decode. */
async function decodeRegion(src, sx, sy, sw, sh, maxW, tryRotate) {
  const scale = Math.min(1, maxW / sw);
  const w = Math.max(1, Math.round(sw * scale)), h = Math.max(1, Math.round(sh * scale));
  work.width = w; work.height = h;
  wctx.drawImage(src, sx, sy, sw, sh, 0, 0, w, h);
  if (detector) {
    try { for (const r of await detector.detect(work)) { const n = bookIsbn(r.rawValue); if (n) return n; } } catch (e) {}
  }
  const l = lumaOf(wctx, w, h);
  let t = decodeWithCleanup(l, w, h);
  if (!t && tryRotate) t = decodeWithCleanup(rotateLuma(l, w, h), h, w);
  return t ? (bookIsbn(t) || { notBook: t }) : null;
}
// Camera frames are noisy and a little soft. Bars are vertical, so averaging
// down each column removes noise without smearing them; a light horizontal
// sharpen helps slightly out-of-focus frames.
function decodeWithCleanup(l, w, h) {
  let t = zxDecodeLuma(l, w, h); if (t) return t;
  const smooth = stretch(smoothV(l, w, h, Math.max(2, Math.round(h / 60))));
  t = zxDecodeLuma(smooth, w, h); if (t) return t;
  return zxDecodeLuma(sharpenH(smooth, w, h, 1.2), w, h);
}
function smoothV(l, w, h, k) {
  const o = new Uint8ClampedArray(w * h);
  for (let x = 0; x < w; x++) {
    let s = 0, n = 0;
    for (let y = 0; y < h + k; y++) {
      if (y < h) { s += l[y * w + x]; n++; }
      if (y - 2 * k - 1 >= 0) { s -= l[(y - 2 * k - 1) * w + x]; n--; }
      const c = y - k; if (c >= 0 && c < h) o[c * w + x] = s / n;
    }
  }
  return o;
}
function sharpenH(l, w, h, a) {
  const o = new Uint8ClampedArray(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x, c = l[i], lf = x ? l[i - 1] : c, rt = x < w - 1 ? l[i + 1] : c;
    o[i] = c + a * (2 * c - lf - rt);
  }
  return o;
}
function stretch(l) {
  let lo = 255, hi = 0;
  for (let i = 0; i < l.length; i += 7) { if (l[i] < lo) lo = l[i]; if (l[i] > hi) hi = l[i]; }
  const r = Math.max(1, hi - lo), o = new Uint8ClampedArray(l.length);
  for (let i = 0; i < l.length; i++) o[i] = (l[i] - lo) * 255 / r;
  return o;
}
function bookIsbn(text) {
  let d = cleanIsbn(text);
  if (d.length === 12) d = "0" + d; // UPC-A seen as 12 digits
  return isBookCode(d) ? d : null;
}

/* ---------- live camera scanner ---------- */
let stream = null, scanning = false, frameNo = 0, lastNote = 0, lastOther = null;
async function startScan() {
  $("scanner").hidden = false; $("typedIsbn").value = "";
  setScanMsg("Starting the camera…");
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    setScanMsg("This browser can't use the live camera. Tap “Take a photo” or type the ISBN."); return;
  }
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { facingMode: { ideal: "environment" }, width: { ideal: 1920 }, height: { ideal: 1080 } },
    });
  } catch (e) {
    setScanMsg(e && e.name === "NotAllowedError"
      ? "Camera access is blocked. On iPhone: Settings → Safari → Camera → Allow, then reopen the app. Or tap “Take a photo”."
      : "Couldn't start the camera. Tap “Take a photo” or type the ISBN.");
    return;
  }
  const track = stream.getVideoTracks()[0];
  // Continuous focus and a little zoom let you hold the book far enough away to stay sharp.
  try {
    const caps = track.getCapabilities ? track.getCapabilities() : {};
    const adv = {};
    if (caps.focusMode && caps.focusMode.includes("continuous")) adv.focusMode = "continuous";
    if (caps.zoom && caps.zoom.max >= 1.6) adv.zoom = Math.min(2, caps.zoom.max);
    if (Object.keys(adv).length) await track.applyConstraints({ advanced: [adv] });
  } catch (e) {}
  const v = $("video");
  v.setAttribute("playsinline", ""); v.muted = true; v.srcObject = stream;
  try { await v.play(); } catch (e) {}
  scanning = true; frameNo = 0; lastNote = Date.now();
  setScanMsg("Hold the barcode inside the pink box, about a hand's length away");
  loop();
}
function setScanMsg(m) { $("scanMsg").textContent = m; }
async function loop() {
  if (!scanning) return;
  const v = $("video");
  if (v.readyState >= 2 && v.videoWidth) {
    frameNo++;
    const W = v.videoWidth, H = v.videoHeight;
    // the middle of the picture, where the pink box is
    const sw = Math.round(W * 0.9), sh = Math.round(H * (W > H ? 0.6 : 0.4));
    const sx = Math.round((W - sw) / 2), sy = Math.round((H - sh) / 2);
    const r = await decodeRegion(v, sx, sy, sw, sh, frameNo % 2 ? 1000 : 1400, frameNo % 3 === 0);
    if (!scanning) return;
    if (typeof r === "string") { scanning = false; if (navigator.vibrate) navigator.vibrate(60); gotIsbn(r); return; }
    if (r && r.notBook) { if (r.notBook === lastOther) setScanMsg("That barcode isn't an ISBN. Look for the one starting 978 or 979."); lastOther = r.notBook; }
    else if (Date.now() - lastNote > 9000) { lastNote = Date.now(); setScanMsg("Still looking… Try more light, hold steadier, or tap “Take a photo”."); }
  }
  setTimeout(() => requestAnimationFrame(loop), 60);
}
function stopScan() {
  scanning = false;
  try { stream && stream.getTracks().forEach(t => t.stop()); } catch (e) {}
  stream = null; $("video").srcObject = null; $("scanner").hidden = true;
}
function gotIsbn(isbn) {
  stopScan();
  const dup = books.find(b => b.isbn === isbn);
  if (dup) { toast(`Already on your shelf: “${dup.title}”`); openSheet(dup); return; }
  openSheet(null); $("f-isbn").value = fmtIsbn(isbn); isbnHint(); fillFromIsbn(isbn, true);
}

/* ---------- scan from a still photo ---------- */
async function scanPhoto(file) {
  setScanMsg("Reading the photo…");
  let img;
  try {
    const url = URL.createObjectURL(file);
    img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = url; });
  } catch (e) { setScanMsg("Couldn't open that photo. Try again or type the ISBN."); return; }
  const W = img.naturalWidth, H = img.naturalHeight;
  const tries = [
    [0, 0, W, H, 1600], [0, 0, W, H, 1000],
    [W * .1, H * .25, W * .8, H * .5, 1400], [W * .1, H * .1, W * .8, H * .8, 1200],
    [0, 0, W, H, 2400],
  ];
  for (const [x, y, w, h, m] of tries) {
    const r = await decodeRegion(img, Math.round(x), Math.round(y), Math.round(w), Math.round(h), m, true);
    if (typeof r === "string") { gotIsbn(r); return; }
    if (r && r.notBook) { setScanMsg("That barcode isn't an ISBN. Look for the one starting 978 or 979."); return; }
  }
  setScanMsg("Couldn't find a barcode in that photo. Fill the frame with the barcode and make sure it's sharp, or type the ISBN.");
  if (stream) { scanning = true; loop(); }
}

/* ---------- cover photo ---------- */
async function shrinkToDataUrl(file, max = 600) {
  const url = URL.createObjectURL(file);
  const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = url; });
  URL.revokeObjectURL(url);
  const s = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
  const c = document.createElement("canvas"); c.width = Math.round(img.naturalWidth * s); c.height = Math.round(img.naturalHeight * s);
  c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
  return c.toDataURL("image/jpeg", 0.82);
}

/* ---------- backup ---------- */
async function exportBackup() {
  const data = JSON.stringify({ app: "home-library", version: 1, exportedAt: new Date().toISOString(), books }, null, 1);
  const name = `home-library-backup-${today()}.json`;
  const file = new File([data], name, { type: "application/json" });
  try {
    if (navigator.canShare && navigator.canShare({ files: [file] })) { await navigator.share({ files: [file], title: "Home Library backup" }); return; }
  } catch (e) { if (e && e.name === "AbortError") return; }
  const a = document.createElement("a"); a.href = URL.createObjectURL(file); a.download = name; document.body.appendChild(a); a.click(); a.remove();
  toast("Backup saved");
}
let pendingRestore = null;
async function readBackup(file) {
  try {
    const obj = JSON.parse(await file.text());
    const list = Array.isArray(obj) ? obj : obj.books;
    if (!Array.isArray(list)) throw 0;
    pendingRestore = list.filter(b => b && b.title).map(b => ({ ...b, id: b.id || uid() }));
    $("restoreText").textContent = `This backup has ${pendingRestore.length} books. Restoring replaces the ${books.length} books on this phone.`;
    $("restoreScrim").hidden = false;
  } catch { toast("That file isn't a Home Library backup"); }
}

/* ---------- wire up ---------- */
document.querySelectorAll(".stat").forEach(b => b.addEventListener("click", () => { filter = (filter === b.dataset.filter && filter !== "all") ? "all" : b.dataset.filter; render(); }));
$("q").addEventListener("input", render); $("sort").addEventListener("change", render);
$("listWrap").addEventListener("click", e => { const r = e.target.closest(".row"); if (!r) return; const b = books.find(x => x.id === r.dataset.id); if (b) openSheet(b); });
$("scanBtn").addEventListener("click", startScan);
$("cancelScan").addEventListener("click", stopScan);
$("photoScan").addEventListener("click", () => { $("scanPhotoFile").value = ""; $("scanPhotoFile").click(); });
$("scanPhotoFile").addEventListener("change", e => { const f = e.target.files[0]; if (f) { scanning = false; scanPhoto(f); } });
$("typedGo").addEventListener("click", () => { const n = normIsbn($("typedIsbn").value); if (n) gotIsbn(n); else $("scanMsg").textContent = "That ISBN doesn't look right. Check the number."; });
$("typedIsbn").addEventListener("keydown", e => { if (e.key === "Enter") $("typedGo").click(); });
$("addBtn").addEventListener("click", () => openSheet(null));
$("closeSheet").addEventListener("click", closeSheet); $("cancelBtn").addEventListener("click", closeSheet);
$("scrim").addEventListener("click", e => { if (e.target === $("scrim")) closeSheet(); });
document.addEventListener("keydown", e => { if (e.key === "Escape") { if (!$("scanner").hidden) stopScan(); else if (!$("scrim").hidden) closeSheet(); } });
$("seg").addEventListener("click", e => { const b = e.target.closest("button"); if (b) setStatus(b.dataset.v); });
$("f-isbn").addEventListener("input", isbnHint);
$("f-loanTo").addEventListener("input", () => { if ($("f-loanTo").value && !$("f-loanOn").value) $("f-loanOn").value = today(); loanUi(); });
$("returnBtn").addEventListener("click", () => {
  const to = $("f-loanTo").value.trim(); if (!to) return;
  draft.loanHistory = [...(draft.loanHistory || []), { to, on: $("f-loanOn").value || "", back: today() }];
  $("f-loanTo").value = ""; $("f-loanOn").value = ""; loanUi(); toast("Marked returned. Save to keep it.");
});
$("lookupBtn").addEventListener("click", () => { const n = normIsbn($("f-isbn").value); if (n) fillFromIsbn(n, false); else toast("Enter a valid ISBN first"); });
$("coverBtn").addEventListener("click", () => { $("coverCam").value = ""; $("coverCam").click(); });
$("coverCam").addEventListener("change", async e => { const f = e.target.files[0]; if (!f) return; try { draft.coverData = await shrinkToDataUrl(f); showCover(); } catch { toast("Couldn't use that photo"); } });
$("removeCover").addEventListener("click", () => { draft.coverData = null; draft.coverUrl = null; showCover(); });
$("form").addEventListener("submit", save);
$("delBtn").addEventListener("click", () => { $("delConfirm").hidden = false; });
$("delNo").addEventListener("click", () => { $("delConfirm").hidden = true; });
$("delYes").addEventListener("click", async () => { if (!editing) return; const t = editing.title; await store.del(editing.id); closeSheet(); await reload(); toast(`Deleted “${t}”`); });
$("exportBtn").addEventListener("click", exportBackup);
$("importBtn").addEventListener("click", () => { $("importFile").value = ""; $("importFile").click(); });
$("importFile").addEventListener("change", e => { const f = e.target.files[0]; if (f) readBackup(f); });
$("restoreNo").addEventListener("click", () => { pendingRestore = null; $("restoreScrim").hidden = true; });
$("restoreYes").addEventListener("click", async () => { if (!pendingRestore) return; await store.replaceAll(pendingRestore); $("restoreScrim").hidden = true; toast(`Restored ${pendingRestore.length} books`); pendingRestore = null; await reload(); });

// "Add to Home Screen" tip on iPhone Safari when not already installed
try {
  const standalone = window.navigator.standalone || matchMedia("(display-mode: standalone)").matches;
  const ios = /iPhone|iPad|iPod/.test(navigator.userAgent);
  if (ios && !standalone && localStorage.getItem("hideInstallTip") !== "1") $("installTip").hidden = false;
} catch (e) {}
$("hideTip").addEventListener("click", () => { $("installTip").hidden = true; try { localStorage.setItem("hideInstallTip", "1"); } catch (e) {} });

if ("serviceWorker" in navigator && location.protocol === "https:") navigator.serviceWorker.register("sw.js").catch(() => {});

reload().catch(() => { $("listWrap").innerHTML = `<div class="notice">This browser is blocking storage, so books can't be saved. If you're in a private window, open the app in a normal one.</div>`; });
})();
