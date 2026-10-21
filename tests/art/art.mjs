// What the art tests share: a PNG reader (node's zlib, no packages) and the
// few image measures they make. Not a test itself (tests/*/*.test.mjs are).
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';

/** An 8-bit PNG as { width, height, data }: RGBA bytes, row by row. */
export function readPng(path) {
  const buf = readFileSync(path);
  const sig = [137, 80, 78, 71, 13, 10, 26, 10];
  if (!sig.every((b, i) => buf[i] === b)) throw new Error(`${path}: not a PNG`);
  let pos = 8, width = 0, height = 0, depth = 0, type = 0, interlace = 0, palette = null, trns = null;
  const idat = [];
  while (pos + 8 <= buf.length) {
    const len = buf.readUInt32BE(pos);
    const kind = buf.toString('latin1', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (kind === 'IHDR') {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4);
      depth = data[8]; type = data[9]; interlace = data[12];
    } else if (kind === 'PLTE') palette = data;
    else if (kind === 'tRNS') trns = data;
    else if (kind === 'IDAT') idat.push(data);
    else if (kind === 'IEND') break;
    pos += 12 + len;
  }
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[type];
  if (depth !== 8 || interlace !== 0 || !channels) {
    throw new Error(`${path}: only 8-bit, non-interlaced PNGs are read (depth ${depth}, type ${type}, interlace ${interlace})`);
  }
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = new Uint8Array(width * height * 4);
  let prev = new Uint8Array(stride), cur = new Uint8Array(stride);
  for (let y = 0; y < height; y++) {
    const start = y * (stride + 1);
    const filter = raw[start];
    for (let i = 0; i < stride; i++) {
      const a = i >= channels ? cur[i - channels] : 0;
      const b = prev[i];
      const c = i >= channels ? prev[i - channels] : 0;
      let v = raw[start + 1 + i];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      } else if (filter !== 0) throw new Error(`${path}: unknown filter ${filter}`);
      cur[i] = v & 255;
    }
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4, s = x * channels;
      if (type === 6) { out[o] = cur[s]; out[o + 1] = cur[s + 1]; out[o + 2] = cur[s + 2]; out[o + 3] = cur[s + 3]; }
      else if (type === 2) { out[o] = cur[s]; out[o + 1] = cur[s + 1]; out[o + 2] = cur[s + 2]; out[o + 3] = 255; }
      else if (type === 0) { out[o] = out[o + 1] = out[o + 2] = cur[s]; out[o + 3] = 255; }
      else if (type === 4) { out[o] = out[o + 1] = out[o + 2] = cur[s]; out[o + 3] = cur[s + 1]; }
      else {
        const k = cur[s];
        out[o] = palette[3 * k]; out[o + 1] = palette[3 * k + 1]; out[o + 2] = palette[3 * k + 2];
        out[o + 3] = trns && k < trns.length ? trns[k] : 255;
      }
    }
    [prev, cur] = [cur, prev];
  }
  return { width, height, data: out };
}

/** A Gaussian blur of a w x h float map, the edges repeated. */
export function gauss(map, w, h, sigma) {
  const r = Math.max(1, Math.ceil(3 * sigma));
  const k = [];
  for (let i = -r; i <= r; i++) k.push(Math.exp(-0.5 * (i / sigma) ** 2));
  const sum = k.reduce((s, v) => s + v, 0);
  for (let i = 0; i < k.length; i++) k[i] /= sum;
  const tmp = new Float64Array(w * h), out = new Float64Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let s = 0;
      for (let i = -r; i <= r; i++) s += k[i + r] * map[y * w + Math.min(w - 1, Math.max(0, x + i))];
      tmp[y * w + x] = s;
    }
  }
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let s = 0;
      for (let i = -r; i <= r; i++) s += k[i + r] * tmp[Math.min(h - 1, Math.max(0, y + i)) * w + x];
      out[y * w + x] = s;
    }
  }
  return out;
}

/** The 8-connected pieces of a w x h mask: a label per pixel (0 off the
 *  mask, 1.. on it) and each label's size (sizes[0] unused). */
export function components(mask, w, h) {
  const parent = [0];
  const find = x => { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; };
  const unite = (a, b) => { a = find(a); b = find(b); if (a !== b) parent[Math.max(a, b)] = Math.min(a, b); };
  const label = new Int32Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      if (!mask[i]) continue;
      const near = [];
      if (x > 0 && mask[i - 1]) near.push(label[i - 1]);
      if (y > 0) {
        for (let dx = -1; dx <= 1; dx++) {
          const xx = x + dx;
          if (xx >= 0 && xx < w && mask[i - w + dx]) near.push(label[i - w + dx]);
        }
      }
      if (near.length === 0) { parent.push(parent.length); label[i] = parent.length - 1; }
      else { label[i] = near[0]; for (const n of near) unite(near[0], n); }
    }
  }
  const root = new Int32Array(parent.length);
  const compact = new Map();
  for (let i = 1; i < parent.length; i++) {
    const r = find(i);
    if (!compact.has(r)) compact.set(r, compact.size + 1);
    root[i] = compact.get(r);
  }
  const sizes = new Int32Array(compact.size + 1);
  for (let i = 0; i < w * h; i++) if (label[i]) { label[i] = root[label[i]]; sizes[label[i]]++; }
  return { label, sizes, count: compact.size };
}

/** Hue (degrees), saturation and value (0 to 1) of an RGB byte triple. */
export function hsv(r, g, b) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), c = mx - mn;
  let h = 0;
  if (c > 0) {
    if (mx === r) h = (60 * ((g - b) / c) + 360) % 360;
    else if (mx === g) h = 60 * ((b - r) / c) + 120;
    else h = 60 * ((r - g) / c) + 240;
  }
  return { h, s: mx > 0 ? c / mx : 0, v: mx / 255 };
}

/** The chest piece's disc in a cut image (alpha), as tools/make_launch_logo.py
 *  measures it: the widest solid run in the image's upper right is its
 *  diameter. { x, y, r } in pixels. */
export function chestPiece(img) {
  const { width: n, data } = img;
  const x0 = Math.floor(0.55 * n);
  let best = 0;
  const rows = [];
  for (let y = 0; y < Math.floor(n / 2); y++) {
    let run = 0, longest = 0, mid = 0;
    for (let x = x0; x <= n; x++) {
      const solid = x < n && data[(y * n + x) * 4 + 3] > 0.9 * 255;
      if (solid) run++;
      else {
        if (run > longest) { longest = run; mid = x - 1 - (run - 1) / 2; }
        run = 0;
      }
    }
    rows.push({ y, width: longest, mid });
    best = Math.max(best, longest);
  }
  const widest = rows.filter(r => r.width >= 0.99 * best);
  return {
    x: widest.reduce((s, r) => s + r.mid, 0) / widest.length,
    y: widest.reduce((s, r) => s + r.y, 0) / widest.length,
    r: best / 2,
  };
}

// The brand art (the launch mark and the opaque icons) is private: it is kept
// outside this repository and added to the built app when it is downloaded.
// Here, where the build needs a file, a plain one-colour square stands in.
// ART_ROOT=<a checkout holding the art at the same paths> measures the art
// itself; without it, the tests check that what is here is only a stand-in.
export const ART_ROOT = process.env.ART_ROOT || null;

/** Whether an image is a stand-in: opaque, square and one colour throughout. */
export function isPlaceholder(img) {
  if (img.width !== img.height) return false;
  const d = img.data;
  for (let i = 0; i < d.length; i += 4) {
    if (d[i + 3] !== 255 || d[i] !== d[0] || d[i + 1] !== d[1] || d[i + 2] !== d[2]) return false;
  }
  return true;
}
