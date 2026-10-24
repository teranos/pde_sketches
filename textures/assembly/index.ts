// The scene's images. The sky is HDR: linear float RGB, past 1.0 allowed.
// The rest are bytes that tile. Whatever moves every frame -- sun, moon,
// stars, the clouds drifting -- Processing draws from these.

function hash(x: i32, y: i32, seed: i32): f64 {
  let h: u32 = (x as u32) * 374761393 + (y as u32) * 668265263 + (seed as u32) * 2246822519;
  h = (h ^ (h >> 13)) * 1274126177;
  h ^= h >> 16;
  return (h & 0xffffff) as f64 / 16777216.0;
}

function smooth(t: f64): f64 {
  return t * t * (3.0 - 2.0 * t);
}

function mix(a: f64, b: f64, t: f64): f64 {
  return a + (b - a) * t;
}

function smoothstep(a: f64, b: f64, x: f64): f64 {
  const t = Math.min(1.0, Math.max(0.0, (x - a) / (b - a)));
  return smooth(t);
}

function wrap(i: i32, p: i32): i32 {
  if (p <= 0) return i;
  const m = i % p;
  return m < 0 ? m + p : m;
}

// Value noise repeating every px by py lattice cells; 0 never repeats.
function vnoise(x: f64, y: f64, px: i32, py: i32, seed: i32): f64 {
  const xf = Math.floor(x);
  const yf = Math.floor(y);
  const xi = xf as i32;
  const yi = yf as i32;
  const tx = smooth(x - xf);
  const ty = smooth(y - yf);
  const x0 = wrap(xi, px), x1 = wrap(xi + 1, px);
  const y0 = wrap(yi, py), y1 = wrap(yi + 1, py);
  const a = hash(x0, y0, seed), b = hash(x1, y0, seed);
  const c = hash(x0, y1, seed), d = hash(x1, y1, seed);
  return mix(mix(a, b, tx), mix(c, d, tx), ty);
}

// Octaves double the frequency and the period together, so a tiling base
// stays tiling all the way down.
function fbm(x: f64, y: f64, px: i32, py: i32, seed: i32, octaves: i32): f64 {
  let sum = 0.0, amp = 0.5, norm = 0.0;
  let fx = x, fy = y, qx = px, qy = py;
  for (let o = 0; o < octaves; o++) {
    sum += amp * vnoise(fx, fy, qx, qy, seed + o * 101);
    norm += amp;
    amp *= 0.5;
    fx *= 2.0; fy *= 2.0; qx *= 2; qy *= 2;
  }
  return sum / norm;
}

/// One sky as the camera sees it, without clouds; `p` is laid out by
/// Scene.skyParams: pitch, fov, sun dir (3), sun, ambient, zenith, horizon,
/// glow (3 each), then four unused, then seed.
export function sky(w: i32, h: i32, p: Float64Array): Float32Array {
  const out = new Float32Array(w * h * 3);
  const pitch = p[0], tanV = Math.tan(p[1] * 0.5);
  const tanH = tanV * (w as f64) / (h as f64);
  const sx = p[2], sy = p[3], sz = p[4];
  const fy = Math.sin(pitch), fz = Math.cos(pitch);
  const uy = Math.cos(pitch), uz = -Math.sin(pitch);

  for (let y = 0; y < h; y++) {
    const ny = (1.0 - 2.0 * ((y as f64) + 0.5) / (h as f64)) * tanV;
    for (let x = 0; x < w; x++) {
      const nx = (2.0 * ((x as f64) + 0.5) / (w as f64) - 1.0) * tanH;
      let dx = nx, dy = fy + ny * uy, dz = fz + ny * uz;
      const len = Math.sqrt(dx * dx + dy * dy + dz * dz);
      dx /= len; dy /= len; dz /= len;
      const i = (y * w + x) * 3;
      const el = Math.max(dy, 0.0);

      // Horizon to zenith, then the warm side of a low sun.
      const t = Math.pow(el, 0.45);
      let r = mix(p[14], p[11], t), g = mix(p[15], p[12], t), b = mix(p[16], p[13], t);
      const toward = 0.5 + 0.5 * (dx * sx + dz * sz) / Math.max(1e-6, Math.sqrt(sx * sx + sz * sz));
      const glow = toward * toward * toward * (1.0 - t) * (1.0 - t);
      r += p[17] * glow; g += p[18] * glow; b += p[19] * glow;

      out[i] = r as f32; out[i + 1] = g as f32; out[i + 2] = b as f32;
    }
  }
  return out;
}

function put(out: Uint8Array, i: i32, r: f64, g: f64, b: f64): void {
  out[i] = Math.min(255.0, Math.max(0.0, r * 255.0)) as u8;
  out[i + 1] = Math.min(255.0, Math.max(0.0, g * 255.0)) as u8;
  out[i + 2] = Math.min(255.0, Math.max(0.0, b * 255.0)) as u8;
  out[i + 3] = 255;
}

/// Forest floor: soil with grit, soft grass and moss patches, round
/// fallen leaves scattered on the bare parts. Tiles.
export function ground(size: i32, scale: f64, seed: i32): Uint8Array {
  const out = new Uint8Array(size * size * 4);
  const P = Math.round(mix(14.0, 3.0, scale)) as i32;
  const cell = P * 10;
  for (let y = 0; y < size; y++) {
    const v = (y as f64) / (size as f64);
    for (let x = 0; x < size; x++) {
      const u = (x as f64) / (size as f64);
      const patch = fbm(u * P, v * P, P, P, seed, 6);
      const detail = fbm(u * P * 4, v * P * 4, P * 4, P * 4, seed + 31, 4);
      const grit = fbm(u * P * 16, v * P * 16, P * 16, P * 16, seed + 43, 2);
      const mossy = fbm(u * P * 2, v * P * 2, P * 2, P * 2, seed + 57, 4);
      // soil: never flat, the grit keeps it from reading as blocks
      const dirt = mix(0.55, 1.15, detail) * mix(0.8, 1.2, grit);
      let r = 0.27 * dirt, g = 0.20 * dirt, b = 0.14 * dirt;
      const grass = smoothstep(0.38, 0.68, patch + (grit - 0.5) * 0.12);
      const blade = mix(0.65, 1.2, detail) * mix(0.85, 1.15, grit);
      const gr = mix(0.22, 0.17, mossy) * blade, gg = mix(0.30, 0.26, mossy) * blade, gb = mix(0.13, 0.11, mossy) * blade;
      r = mix(r, gr, grass); g = mix(g, gg, grass); b = mix(b, gb, grass);
      // Leaves: one jittered point per cell, round, soft-edged, on bare soil.
      const fu = u * cell, fv = v * cell;
      const cx = Math.floor(fu) as i32, cy = Math.floor(fv) as i32;
      const wx = wrap(cx, cell), wy = wrap(cy, cell);
      if (hash(wx, wy, seed + 77) > 0.8) {
        const px = (cx as f64) + 0.25 + 0.5 * hash(wx, wy, seed + 79);
        const py = (cy as f64) + 0.25 + 0.5 * hash(wx, wy, seed + 80);
        const d = Math.sqrt((fu - px) * (fu - px) * 1.6 + (fv - py) * (fv - py));
        const leaf = (1.0 - smoothstep(0.18, 0.3, d)) * (1.0 - grass * 0.8);
        const tone = hash(wx, wy, seed + 78);
        r = mix(r, mix(0.48, 0.34, tone), leaf); g = mix(g, mix(0.30, 0.19, tone), leaf); b = mix(b, mix(0.11, 0.08, tone), leaf);
      }
      put(out, (y * size + x) * 4, r, g, b);
    }
  }
  return out;
}

/// Bark: vertical ridges with dark furrows, lichen in patches. u goes round
/// the trunk, v up it. Tiles both ways.
export function bark(size: i32, scale: f64, seed: i32): Uint8Array {
  const out = new Uint8Array(size * size * 4);
  const R = Math.round(mix(22.0, 5.0, scale)) as i32;
  const V: i32 = max<i32>(1, R / 4);
  for (let y = 0; y < size; y++) {
    const v = (y as f64) / (size as f64);
    for (let x = 0; x < size; x++) {
      const u = (x as f64) / (size as f64);
      const warp = fbm(u * 4.0, v * 4.0, 4, 4, seed + 5, 3) - 0.5;
      // Furrows run up the trunk, R of them around it, wandering with the warp.
      const wob = vnoise(u * R, v * V * 3.0, R, V * 3, seed + 1) - 0.5;
      const sx = (u + warp * 0.1) * R + wob * 0.35;
      const d = Math.abs(sx - Math.floor(sx) - 0.5) * 2.0;
      const grain = fbm(u * R * 2, v * V * 8, R * 2, V * 8, seed + 11, 3);
      const furrow = 1.0 - smoothstep(0.62, 0.92, d + (grain - 0.5) * 0.3);
      let r = mix(0.10, mix(0.30, 0.42, grain), furrow);
      let g = mix(0.08, mix(0.25, 0.35, grain), furrow);
      let b = mix(0.06, mix(0.20, 0.27, grain), furrow);
      const lichen = smoothstep(0.68, 0.78, fbm(u * 3.0, v * 3.0, 3, 3, seed + 23, 4)) * furrow * 0.6;
      r = mix(r, 0.45, lichen * 0.8); g = mix(g, 0.50, lichen * 0.8); b = mix(b, 0.36, lichen * 0.8);
      put(out, (y * size + x) * 4, r, g, b);
    }
  }
  return out;
}

/// Cloud density in R and thickness in G, as seen from below: the plane
/// they float on. Tiles, so the wind can move it forever.
export function clouds(size: i32, scale: f64, seed: i32): Uint8Array {
  const out = new Uint8Array(size * size * 4);
  const P = Math.round(mix(9.0, 2.0, scale)) as i32;
  for (let y = 0; y < size; y++) {
    const v = (y as f64) / (size as f64);
    for (let x = 0; x < size; x++) {
      const u = (x as f64) / (size as f64);
      const n = fbm(u * P, v * P, P, P, seed, 7);
      const thick = fbm(u * P * 2 + 0.37, v * P * 2, P * 2, P * 2, seed + 9, 4);
      put(out, (y * size + x) * 4, n, thick, 0.0);
    }
  }
  return out;
}

/// The lake's surface: the slope of small waves, x in R and z in G, with
/// 0.5 flat. Waves run longer across than along.
export function ripples(size: i32, scale: f64, seed: i32): Uint8Array {
  const out = new Uint8Array(size * size * 4);
  const P = Math.round(mix(18.0, 4.0, scale)) as i32;
  const Q = max<i32>(2, P / 2);
  const e = 1.0 / (size as f64);
  const k = 0.12 / (P as f64);
  for (let y = 0; y < size; y++) {
    const v = (y as f64) / (size as f64);
    for (let x = 0; x < size; x++) {
      const u = (x as f64) / (size as f64);
      const hx = fbm((u + e) * P, v * Q, P, Q, seed, 4) - fbm((u - e) * P, v * Q, P, Q, seed, 4);
      const hz = fbm(u * P, (v + e) * Q, P, Q, seed, 4) - fbm(u * P, (v - e) * Q, P, Q, seed, 4);
      put(out, (y * size + x) * 4, 0.5 + hx / (2.0 * e) * k, 0.5 + hz / (2.0 * e) * k, 0.0);
    }
  }
  return out;
}

/// Mist: soft banks and gaps. Tiles.
export function mist(size: i32, scale: f64, seed: i32): Uint8Array {
  const out = new Uint8Array(size * size * 4);
  const P = Math.round(mix(7.0, 2.0, scale)) as i32;
  for (let y = 0; y < size; y++) {
    const v = (y as f64) / (size as f64);
    for (let x = 0; x < size; x++) {
      const u = (x as f64) / (size as f64);
      const n = smoothstep(0.3, 0.75, fbm(u * P, v * P, P, P, seed, 5));
      put(out, (y * size + x) * 4, n, n, n);
    }
  }
  return out;
}
