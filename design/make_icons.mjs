// Draws the four StreamBoss icons and writes every size every platform needs.
//
//   NODE_PATH=<dir with playwright> node design/make_icons.mjs
//
// Needs Node and Playwright (Chromium renders the SVGs). The output is committed, so building the app
// never needs this: it only runs when a mark changes. Marks are drawn on Android's adaptive grid
// (108 units square, everything that matters inside the central 66 units), the same drawing is used
// for the launcher icons, the TV banners, the picker previews and the other platforms' icons.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright'); // honors NODE_PATH, unlike an ES import
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const w = (rel, data) => {
  const p = path.join(ROOT, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, data);
};

const grad = (id, a, b) => `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`;
const DEFS = `<defs>${grad('gPG', '#ff4d7d', '#ffb02e')}${grad('gPP', '#ff3d71', '#6a1b9a')}${grad('gInk', '#171726', '#0b0b12')}${grad('gIndigo', '#2a1b5e', '#0b0b12')}</defs>`;

const TRI = { crown: 'M47 52 L47 71 L64 61.5 Z' };
// name -> { label, bg, fg (colored foreground), mono (one color, cut-outs transparent), flat (background color for the one-color preview) }
const MARKS = {
  crown: {
    label: 'Crown',
    bg: '<rect width="108" height="108" fill="url(#gInk)"/>',
    fg: `<mask id="cut"><rect width="108" height="108" fill="#fff"/><path d="${TRI.crown}" fill="#000" stroke="#000" stroke-width="3" stroke-linejoin="round"/></mask>
         <path mask="url(#cut)" d="M27 79 L27 38 L43 53 L54 31 L65 53 L81 38 L81 79 Z" fill="url(#gPG)" stroke="url(#gPG)" stroke-width="6" stroke-linejoin="round"/>`,
    mono: `<mask id="cut"><rect width="108" height="108" fill="#fff"/><path d="${TRI.crown}" fill="#000" stroke="#000" stroke-width="3" stroke-linejoin="round"/></mask>
         <path mask="url(#cut)" d="M27 79 L27 38 L43 53 L54 31 L65 53 L81 38 L81 79 Z" fill="#000" stroke="#000" stroke-width="6" stroke-linejoin="round"/>`,
  },
  bold: {
    label: 'Bold B',
    bg: '<rect width="108" height="108" fill="url(#gPP)"/>',
    fg: `<path d="M38 28 V82 M38 28 H55 Q69 28 69 41 Q69 54 55 54 H38 M38 54 H59 Q76 54 76 68 Q76 82 59 82 H38" fill="none" stroke="#fff" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/>
         <path d="M49 62 L49 74 L60 68 Z" fill="#ffd166" stroke="#ffd166" stroke-width="3" stroke-linejoin="round"/>`,
    mono: `<path d="M38 28 V82 M38 28 H55 Q69 28 69 41 Q69 54 55 54 H38 M38 54 H59 Q76 54 76 68 Q76 82 59 82 H38" fill="none" stroke="#000" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/>
         <path d="M49 62 L49 74 L60 68 Z" fill="#000" stroke="#000" stroke-width="3" stroke-linejoin="round"/>`,
  },
  signal: {
    label: 'Signal',
    bg: '<rect width="108" height="108" fill="url(#gIndigo)"/>',
    fg: `<path d="M31 36 L31 72 L58 54 Z" fill="url(#gPG)" stroke="url(#gPG)" stroke-width="6" stroke-linejoin="round"/>
         <path d="M66 43 A15 15 0 0 1 66 65" fill="none" stroke="#ff4d7d" stroke-width="6" stroke-linecap="round"/>
         <path d="M74 33 A28 28 0 0 1 74 75" fill="none" stroke="#ff8f5a" stroke-width="6" stroke-linecap="round"/>`,
    mono: `<path d="M31 36 L31 72 L58 54 Z" fill="#000" stroke="#000" stroke-width="6" stroke-linejoin="round"/>
         <path d="M66 43 A15 15 0 0 1 66 65 M74 33 A28 28 0 0 1 74 75" fill="none" stroke="#000" stroke-width="6" stroke-linecap="round"/>`,
  },
  screen: {
    label: 'Screen',
    bg: '<rect width="108" height="108" fill="#ff3d71"/>',
    fg: `<rect x="25" y="31" width="58" height="40" rx="9" fill="none" stroke="#fff" stroke-width="7"/>
         <path d="M49 42 L49 60 L65 51 Z" fill="#ffd166" stroke="#ffd166" stroke-width="3" stroke-linejoin="round"/>
         <path d="M44 81 H64" stroke="#fff" stroke-width="7" stroke-linecap="round"/>`,
    mono: `<rect x="25" y="31" width="58" height="40" rx="9" fill="none" stroke="#000" stroke-width="7"/>
         <path d="M49 42 L49 60 L65 51 Z" fill="#000" stroke="#000" stroke-width="3" stroke-linejoin="round"/>
         <path d="M44 81 H64" stroke="#000" stroke-width="7" stroke-linecap="round"/>`,
  },
};
const NAMES = Object.keys(MARKS);

// --- the wordmark: stroked letters on a 100-unit-high grid (the same hand as the B mark) ------------------
const GLYPH = {
  S: [72, 'M66 16 Q58 0 36 0 Q6 0 6 25 Q6 46 36 50 Q68 55 68 76 Q68 100 36 100 Q10 100 2 82'],
  T: [70, 'M0 0 H70 M35 0 V100'],
  R: [72, 'M0 100 V0 H40 Q70 0 70 28 Q70 56 40 56 H0 M38 56 L70 100'],
  E: [64, 'M64 0 H0 V100 H64 M0 50 H54'],
  A: [72, 'M0 100 L36 0 L72 100 M12 68 H60'],
  M: [76, 'M0 100 V0 L38 62 L76 0 V100'],
  B: [74, 'M0 100 V0 H42 Q68 0 68 25 Q68 50 42 50 H0 M0 50 H46 Q74 50 74 75 Q74 100 46 100 H0'],
  O: [72, 'M36 0 Q72 0 72 50 Q72 100 36 100 Q0 100 0 50 Q0 0 36 0 Z'],
};
function word(text, x, y, h, stroke) {
  const s = h / 100, sw = h * 0.17, gap = h * 0.3;
  let cx = x, out = '';
  for (const ch of text) {
    const [gw, d] = GLYPH[ch];
    out += `<path transform="translate(${cx} ${y}) scale(${s})" d="${d}" fill="none" stroke="${stroke}" stroke-width="${sw / s}" stroke-linecap="round" stroke-linejoin="round"/>`;
    cx += gw * s + gap;
  }
  return { svg: out, width: cx - x - gap };
}
const wordmarkBlock = (x, y, h, dark = true) =>
  word('STREAM', x, y, h, dark ? '#f2f2f7' : '#17151d').svg + word('BOSS', x, y + h * 1.42, h, 'url(#gPG)').svg;

// --- compositions ------------------------------------------------------------------------------------------
const svg = (w_, h_, vb, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w_}" height="${h_}" viewBox="${vb}">${DEFS}${body}</svg>`;
const clipSq = (r = 24) => `<clipPath id="sq"><rect width="108" height="108" rx="${r}"/></clipPath>`;
const clipCircle = '<clipPath id="ci"><circle cx="54" cy="54" r="54"/></clipPath>';
const full = (n, { round = false, rx = 24, scale = 1 } = {}) => {
  const m = MARKS[n];
  const t = scale === 1 ? '' : `transform="translate(${54 - 54 * scale} ${54 - 54 * scale}) scale(${scale})"`;
  return svg(108, 108, '0 0 108 108', `${round ? clipCircle : clipSq(rx)}<g ${t}><g clip-path="url(#${round ? 'ci' : 'sq'})">${m.bg}${m.fg}</g></g>`);
};
const squareOpaque = (n) => svg(108, 108, '0 0 108 108', `${MARKS[n].bg}${MARKS[n].fg}`); // iOS and maskable: the system rounds it
const fgOnly = (n) => svg(108, 108, '0 0 108 108', MARKS[n].fg);
const bgOnly = (n) => svg(108, 108, '0 0 108 108', MARKS[n].bg);
const monoOnly = (n) => svg(108, 108, '0 0 108 108', MARKS[n].mono);
const banner = (n, wpx = 320, hpx = 180) =>
  svg(wpx, hpx, '0 0 320 180', `<rect width="320" height="180" fill="#0b0b12"/>
    <g transform="translate(22 42) scale(${96 / 108})">${clipSq(24)}<g clip-path="url(#sq)">${MARKS[n].bg}${MARKS[n].fg}</g></g>
    <rect x="22.5" y="42.5" width="95" height="95" rx="21" fill="none" stroke="#ffffff22"/>
    ${wordmarkBlock(132, 62, 21)}`);
const lockup = (n, wpx, hpx) => // the logo and name centered, for splash screens and Roku
  svg(wpx, hpx, `0 0 ${wpx} ${hpx}`, `<rect width="${wpx}" height="${hpx}" fill="#0b0b12"/>` +
    (() => {
      const s = Math.min(wpx, hpx) * 0.34, ix = (wpx - s) / 2, iy = hpx * 0.2;
      const hh = Math.min(wpx, hpx) * 0.07;
      const sm = word('STREAMBOSS', 0, 0, hh, '#000').width;
      return `<g transform="translate(${ix} ${iy}) scale(${s / 108})">${clipSq(24)}<g clip-path="url(#sq)">${MARKS[n].bg}${MARKS[n].fg}</g></g>` +
        word('STREAMBOSS', (wpx - sm) / 2, iy + s + hh * 1.6, hh, '#f2f2f7').svg;
    })());

// --- render ------------------------------------------------------------------------------------------------
const browser = await chromium.launch();
const page = await browser.newPage();
async function png(svgText, wpx, hpx, rel, { transparent = true } = {}) {
  await page.setViewportSize({ width: Math.max(1, Math.round(wpx)), height: Math.max(1, Math.round(hpx)) });
  await page.setContent(`<html><body style="margin:0;background:transparent">${svgText.replace(/width="[\d.]+" height="[\d.]+"/, `width="${wpx}" height="${hpx}"`)}</body></html>`);
  const buf = await page.screenshot({ omitBackground: transparent, clip: { x: 0, y: 0, width: Math.round(wpx), height: Math.round(hpx) } });
  w(rel, buf);
  return buf;
}

const DENS = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
const RES = 'tool/android_res';
const adaptiveXml = (n) => `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_logo_${n}_bg"/>
    <foreground android:drawable="@drawable/ic_logo_${n}_fg"/>
    <monochrome android:drawable="@drawable/ic_logo_${n}_mono"/>
</adaptive-icon>
`;

for (const n of NAMES) {
  // Source drawings, for people.
  w(`design/icons/${n}.svg`, full(n, { rx: 24 }));
  w(`design/icons/${n}_mono.svg`, monoOnly(n));
  w(`design/icons/banner_${n}.svg`, banner(n));

  // Android: legacy square and round icons, adaptive layers, the TV banner.
  for (const [d, k] of Object.entries(DENS)) {
    await png(full(n), 48 * k, 48 * k, `${RES}/mipmap-${d}/ic_logo_${n}.png`);
    await png(full(n, { round: true }), 48 * k, 48 * k, `${RES}/mipmap-${d}/ic_logo_${n}_round.png`);
    await png(fgOnly(n), 108 * k, 108 * k, `${RES}/drawable-${d}/ic_logo_${n}_fg.png`);
  }
  await png(bgOnly(n), 432, 432, `${RES}/drawable-nodpi/ic_logo_${n}_bg.png`, { transparent: false });
  await png(monoOnly(n), 432, 432, `${RES}/drawable-nodpi/ic_logo_${n}_mono.png`);
  w(`${RES}/mipmap-anydpi-v26/ic_logo_${n}.xml`, adaptiveXml(n));
  w(`${RES}/mipmap-anydpi-v26/ic_logo_${n}_round.xml`, adaptiveXml(n)); // round icons are adaptive too
  await png(banner(n), 320, 180, `${RES}/drawable-xhdpi/banner_${n}.png`, { transparent: false });

  // The in-app picker (and the macOS Dock icon): 512 px, rounded.
  await png(full(n), 512, 512, `assets/app_icons/${n}.png`);
}

// The default icon (Flutter's `ic_launcher` and `banner`) is the first mark.
const DEF = 'crown';
for (const [d, k] of Object.entries(DENS)) {
  await png(full(DEF), 48 * k, 48 * k, `${RES}/mipmap-${d}/ic_launcher.png`);
  await png(fgOnly(DEF), 108 * k, 108 * k, `${RES}/drawable-${d}/ic_launcher_fg.png`);
}
await png(bgOnly(DEF), 432, 432, `${RES}/drawable-nodpi/ic_launcher_bg.png`, { transparent: false });
await png(monoOnly(DEF), 432, 432, `${RES}/drawable-nodpi/ic_launcher_mono.png`);
w(`${RES}/mipmap-anydpi-v26/ic_launcher.xml`, adaptiveXml(DEF).replaceAll(`ic_logo_${DEF}_`, 'ic_launcher_'));
await png(banner(DEF), 320, 180, `${RES}/drawable-xhdpi/banner.png`, { transparent: false });

// Other platforms get the default mark.
const T = 'tool/icons';
for (const px of [16, 20, 29, 32, 40, 48, 57, 58, 60, 64, 72, 76, 80, 87, 96, 100, 114, 120, 128, 144, 152, 167, 180, 192, 256, 512, 1024]) {
  await png(squareOpaque(DEF), px, px, `${T}/ios/${px}.png`, { transparent: false }); // iOS: square, no alpha
}
for (const px of [16, 32, 64, 128, 256, 512, 1024]) {
  await png(full(DEF, { rx: 24, scale: 0.8 }), px, px, `${T}/mac/${px}.png`); // macOS: rounded, with the usual margin
}
for (const [px, name] of [[192, 'Icon-192'], [512, 'Icon-512'], [32, 'favicon']]) await png(full(DEF), px, px, `${T}/web/${name}.png`);
for (const px of [192, 512]) await png(squareOpaque(DEF), px, px, `${T}/web/Icon-maskable-${px}.png`, { transparent: false });

// Windows .ico with PNG frames.
const icoSizes = [16, 24, 32, 48, 64, 128, 256];
const frames = [];
for (const px of icoSizes) frames.push(await png(full(DEF), px, px, `${T}/windows/_${px}.png`));
const head = Buffer.alloc(6); head.writeUInt16LE(0, 0); head.writeUInt16LE(1, 2); head.writeUInt16LE(frames.length, 4);
let off = 6 + 16 * frames.length;
const dir = Buffer.concat(frames.map((b, i) => {
  const e = Buffer.alloc(16), s = icoSizes[i];
  e.writeUInt8(s === 256 ? 0 : s, 0); e.writeUInt8(s === 256 ? 0 : s, 1); e.writeUInt8(0, 2); e.writeUInt8(0, 3);
  e.writeUInt16LE(1, 4); e.writeUInt16LE(32, 6); e.writeUInt32LE(b.length, 8); e.writeUInt32LE(off, 12);
  off += b.length; return e;
}));
w(`${T}/windows/app_icon.ico`, Buffer.concat([head, dir, ...frames]));
for (const px of icoSizes) fs.rmSync(path.join(ROOT, `${T}/windows/_${px}.png`));

// Roku channel icons and splash.
await png(lockup(DEF, 290, 218), 290, 218, 'roku/images/icon_hd.png', { transparent: false });
await png(lockup(DEF, 246, 140), 246, 140, 'roku/images/icon_sd.png', { transparent: false });
await png(lockup(DEF, 1280, 720), 1280, 720, 'roku/images/splash_hd.png', { transparent: false });

await browser.close();
console.log('Icons written.');
