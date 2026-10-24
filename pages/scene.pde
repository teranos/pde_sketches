// The scene: looking up through trees at a sky that runs a day in three
// minutes. AssemblyScript (textures/gen.js) makes the images; this lays
// them out every frame and fades each new one in over the last.

static final float CYCLE = 180;        // seconds for one whole day
static final float SKY_EVERY = 2.5;    // seconds of the cycle between two skies
static final float SKY_FADE = 2.5;     // seconds a new sky takes to fade in
static final float TEX_FADE = 1.0;
static final float PITCH = radians(30);
static final float VFOV = radians(90);
static final float CAM_H = 1.7;
static final float CLOUD_TILE = 0.18;  // cloud texture repeats per this many plane units
static final float WIND_U = 1.6, WIND_V = 0.7;   // cloud texture tiles a day drifts
static final String[] THINGS = {"sky", "ground", "trunks", "lake", "mist"};
static final String[] SCENE_PARAMS = {"hue", "saturation", "scale"};
static final int SKY = 0, GROUND = 1, TRUNKS = 2, LAKE = 3, MIST = 4;

// Split a per-pixel pass across every core; each chunk owns its own range.
void par(int n, java.util.function.BiConsumer<Integer, Integer> body) {
  final int chunks = 48;
  java.util.stream.IntStream.range(0, chunks).parallel().forEach(c -> body.accept((int) ((long) n * c / chunks), (int) ((long) n * (c + 1) / chunks)));
}

class Scene {
  int w, h, horizonRow;
  float[] dx, dy, dz;           // the view direction of every pixel
  float[] hdr;                  // the frame before tone-mapping
  float[] cloudA;               // how much cloud covers each pixel this frame
  int[] cIndex; float[] cU, cV, cFade; int[] cLod;              // sky pixels
  int[] gIndex; float[] gU, gV, gFog, gMacro; int[] gLod;       // ground pixels
  int[] wIndex; float[] wU, wV, wT, wMx, wMy, wFres, wFog; int[] wLod;  // lake pixels
  int[] mIndex; float[] mDist, mHeight, mU, mV;                 // pixels mist can reach
  Trunk[] trunks;
  float[][] stars;              // x, y, z, brightness
  int[] gamma = new int[4096];

  // What the host says.
  float time = 0.22;
  boolean running = true;
  int thing;
  boolean thingLocked;
  float[][] v = new float[THINGS.length][3];
  boolean[][] l = new boolean[THINGS.length][3];

  float clock;                  // time, unwrapped across days
  float exposure = 1;           // follows what the frame measures
  long last;

  float[] skyFrom, skyTo;
  float skyAlpha = 1, skyToTime = -1;
  boolean skyPending;
  Tex ground = new Tex(256, false), bark = new Tex(256, false);
  Tex clouds = new Tex(512, true), ripples = new Tex(256, true), mist = new Tex(256, true);
  Gen gen;
  int seed = Integer.getInteger("sketches.seed", int(random(1 << 20)));  // settable, so a test can pick its day

  Scene() {
    for (int i = 0; i < gamma.length; i++)
      gamma[i] = round(255 * pow(i / 4095.0, 1 / 2.2));
    for (float[] row : v) java.util.Arrays.fill(row, 0.5);
    gen = new Gen();
  }

  void set(float t, boolean run, int th, boolean thLocked, float[] vals, boolean[] locks) {
    float d = t - time;
    if (d < -0.5) clock += 1 + d;
    else if (d > 0.5) clock += d - 1;
    else clock += d;
    time = t;
    running = run;
    thing = th;
    thingLocked = thLocked;
    for (int i = 0; i < vals.length; i++) {
      v[i / 3][i % 3] = vals[i];
      l[i / 3][i % 3] = locks[i];
    }
  }

  // The lake: from a wavering shore ahead out to the horizon, in the clearing.
  boolean inLake(float x, float z) {
    float shore = 9 + 4 * noise(x * 0.08 + 3);
    float half = z * (0.5 + 0.25 * noise(z * 0.04 + 11));
    return z > shore && abs(x) < half;
  }

  int lod(float foot, Tex t) {
    return constrain(round(log(max(foot, 1)) / log(2) + 0.5), 0, t.levels - 1);
  }

  void resize(int w, int h) {
    this.w = w;
    this.h = h;
    int n = w * h;
    dx = new float[n]; dy = new float[n]; dz = new float[n];
    hdr = new float[n * 3];
    cloudA = new float[n];
    float tanV = tan(VFOV / 2), tanH = tanV * w / h;
    float fy = sin(PITCH), fz = cos(PITCH), uy = cos(PITCH), uz = -sin(PITCH);
    horizonRow = constrain(int((1 + tan(PITCH) / tanV) * 0.5 * h), 1, h);
    for (int y = 0; y < h; y++) {
      float ny = (1 - 2 * (y + 0.5) / h) * tanV;
      for (int x = 0; x < w; x++) {
        float nx = (2 * (x + 0.5) / w - 1) * tanH;
        float ax = nx, ay = fy + ny * uy, az = fz + ny * uz;
        float len = sqrt(ax * ax + ay * ay + az * az);
        int i = y * w + x;
        dx[i] = ax / len; dy[i] = ay / len; dz[i] = az / len;
      }
    }
    float pix = VFOV / h;
    float[] dist = new float[n];
    java.util.Arrays.fill(dist, 1e6f);

    // The camera never moves, so where every pixel lands is worked out once.
    IntList ci = new IntList(), gi = new IntList(), wi = new IntList();
    for (int i = 0; i < n; i++) {
      // Clouds are soft: one sample per 2x2 block is enough.
      if (dy[i] > 0.02) { if ((i % w) % 2 == 0 && (i / w) % 2 == 0) ci.append(i); }
      else if (dy[i] < 0) {
        float t = CAM_H / -dy[i];
        dist[i] = t;
        if (inLake(dx[i] * t, dz[i] * t)) wi.append(i);
        else gi.append(i);
      }
    }
    int k = 0;
    cIndex = ci.array(); cU = new float[cIndex.length]; cV = new float[cIndex.length];
    cFade = new float[cIndex.length]; cLod = new int[cIndex.length];
    for (int i : cIndex) {
      // Clouds float on a plane overhead; nearer the horizon, more of it per pixel.
      float q = 1 / (dy[i] + 0.08);
      cU[k] = dx[i] * q * CLOUD_TILE;
      cV[k] = dz[i] * q * CLOUD_TILE;
      cFade[k] = smoothstep(0.02, 0.22, dy[i]);
      cLod[k] = lod(2 * pix * q * q * CLOUD_TILE * clouds.size, clouds);
      k++;
    }
    k = 0;
    gIndex = gi.array(); gU = new float[gIndex.length]; gV = new float[gIndex.length];
    gFog = new float[gIndex.length]; gLod = new int[gIndex.length]; gMacro = new float[gIndex.length];
    for (int i : gIndex) {
      float t = dist[i];
      gU[k] = dx[i] * t / 9;
      gV[k] = dz[i] * t / 9;
      // Patches far larger than one tile, so the repeat does not read as a grid.
      gMacro[k] = 0.55 + 0.9 * noise(dx[i] * t * 0.06 + 40, dz[i] * t * 0.06);
      gFog[k] = 1 - exp(-t / 180);
      gLod[k] = lod(pix * t / -dy[i] / 9 * ground.size, ground);
      k++;
    }

    randomSeed(seed);
    java.util.ArrayList<Trunk> list = new java.util.ArrayList<Trunk>();
    while (list.size() < 22) {
      float z = random(4, 55), x = random(-z * 1.1, z * 1.1), r = random(0.25, 0.7);
      // A clearing straight ahead, so there is sky to stare into; none in the lake.
      if (abs(x / z) < 0.22) continue;
      if (inLake(x, z) || inLake(x - r - 1, z) || inLake(x + r + 1, z)) continue;
      list.add(new Trunk(x, z, r, random(1)));
    }
    list.sort((a, b) -> Float.compare(b.z, a.z));
    trunks = list.toArray(new Trunk[0]);
    boolean[] covered = new boolean[n];
    for (Trunk t : trunks) {
      t.layout(this);
      for (int idx : t.index) {
        covered[idx] = true;
        dist[idx] = min(dist[idx], sqrt(t.x * t.x + t.z * t.z));
      }
    }

    // Water the trunks stand in front of is never seen; the rest mirrors
    // the sky straight across the horizon from it.
    IntList seen = new IntList();
    for (int i : wi.array()) if (!covered[i]) seen.append(i);
    wIndex = seen.array();
    int m = wIndex.length;
    wU = new float[m]; wV = new float[m]; wT = new float[m]; wMx = new float[m]; wMy = new float[m];
    wFres = new float[m]; wFog = new float[m]; wLod = new int[m];
    for (k = 0; k < m; k++) {
      int i = wIndex[k];
      float t = dist[i];
      wT[k] = t;
      wU[k] = dx[i] * t / 6;
      wV[k] = dz[i] * t / 6;
      float my = -dy[i], depth = my * fy + dz[i] * fz;
      wMx[k] = (dx[i] / depth / tanH + 1) * 0.5 * w;
      wMy[k] = (1 - (my * uy + dz[i] * uz) / depth / tanV) * 0.5 * h;
      wFres[k] = 0.02 + 0.98 * pow(1 - my, 5);
      wFog[k] = 1 - exp(-t / 260);
      wLod[k] = lod(pix * t / my / 6 * ripples.size, ripples);
    }

    // Mist lies low: only pixels looking near or below the horizon.
    IntList mi = new IntList();
    for (int i = 0; i < n; i++) if (dy[i] < 0.22) mi.append(i);
    mIndex = mi.array();
    mDist = new float[mIndex.length]; mHeight = new float[mIndex.length];
    mU = new float[mIndex.length]; mV = new float[mIndex.length];
    for (k = 0; k < mIndex.length; k++) {
      int i = mIndex[k];
      mDist[k] = 1 - exp(-dist[i] / 28);
      mHeight[k] = exp(-max(dy[i], 0) / 0.05);
      mU[k] = (i % w) / (float) w * 1.6;
      mV[k] = (i / w) / (float) h * 4;
    }

    stars = new float[900][4];
    for (float[] s : stars) {
      float a = random(TWO_PI), e = asin(random(0.02, 1));
      s[0] = cos(a) * cos(e); s[1] = sin(e); s[2] = sin(a) * cos(e); s[3] = pow(random(1), 3);
    }
    skyFrom = skyTo = null;
    skyToTime = -1;
  }

  // Everything that follows from the time of day.
  float sunEl() { return sin((time - 0.25) * TWO_PI) * radians(62); }
  float[] sunDir() {
    float az = (time - 0.5) * TWO_PI, el = sunEl();
    return new float[] {sin(az) * cos(el), sin(el), cos(az) * cos(el)};
  }
  float day() { return smoothstep(-0.12, 0.25, sin(sunEl())); }
  float golden() { float s = sin(sunEl()); return exp(-sq((s - 0.02) / 0.13)); }
  float[] sunColor() {
    float s = sin(sunEl());
    float vis = smoothstep(-0.04, 0.04, s), warm = smoothstep(0, 0.45, s);
    return new float[] {3 * vis, lerp(0.38, 0.96, warm) * 3 * vis, lerp(0.12, 0.9, warm) * 3 * vis};
  }
  float[] ambient() {
    float d = day(), g = golden();
    return new float[] {lerp(0.012, 0.30, d) + 0.12 * g, lerp(0.016, 0.38, d) + 0.06 * g, lerp(0.035, 0.52, d) + 0.05 * g};
  }
  float[] horizon() {
    float d = day(), g = golden();
    float[] hor = {lerp(0.012, 0.65, d), lerp(0.016, 0.8, d), lerp(0.03, 1.05, d)};
    hor[0] = lerp(hor[0], 1.25, g * 0.85); hor[1] = lerp(hor[1], 0.5, g * 0.85); hor[2] = lerp(hor[2], 0.22, g * 0.85);
    return hor;
  }
  float cover() { return 0.15 + 0.55 * noise(clock * 1.3 + 17); }

  // Some days are misty and some are not: each day rolls its own, changing
  // over at noon when there is none. It lies thickest at dawn, some at night.
  float mistToday() {
    double day = Math.floor(clock + 0.5);
    double r = Math.abs(Math.sin(day * 12.9898 + seed * 0.001) * 43758.5453) % 1;
    return r < 0.4 ? 0 : (float) ((r - 0.4) / 0.6);
  }
  float mistNow() {
    return mistToday() * max(exp(-sq((time - 0.26) / 0.06)), 0.45 * (1 - day()));
  }

  double[] skyParams() {
    float d = day(), g = golden();
    float[] s = sunDir(), c = sunColor(), a = ambient();
    float[] zen = {lerp(0.004, 0.16, d) + 0.05 * g, lerp(0.006, 0.34, d) + 0.04 * g, lerp(0.016, 0.95, d) + 0.12 * g};
    float[] hor = horizon();
    return new double[] {PITCH, VFOV, s[0], s[1], s[2], c[0], c[1], c[2], a[0], a[1], a[2],
      zen[0], zen[1], zen[2], hor[0], hor[1], hor[2], 1.2 * g, 0.45 * g, 0.15 * g, 0, 0, 0, 0, seed};
  }

  float cycDist(float a, float b) { float d = abs(a - b) % 1; return min(d, 1 - d); }

  // Ask for what is missing; take in what has arrived.
  void feed(float dt) {
    gen.poll(this);
    if (!skyPending && (skyTo == null || cycDist(skyToTime, time) > SKY_EVERY / CYCLE)) {
      // A running clock asks ahead, so the sky arrives about when it is due.
      float ahead = running ? (SKY_FADE / 2 + 0.3) / CYCLE : 0;
      float was = time;
      time = (time + ahead) % 1;
      gen.sky(w, h, skyParams(), time);
      time = was;
      skyPending = true;
    }
    Tex[] tex = {clouds, ground, bark, ripples, mist};
    String[] kind = {"clouds", "ground", "bark", "ripples", "mist"};
    for (int t = 0; t < tex.length; t++) {
      if (!tex[t].pending && tex[t].scale != v[t][2]) gen.texture(kind[t], tex[t], v[t][2], seed + t);
      tex[t].advance(dt / TEX_FADE, v[t][0], v[t][1]);
    }
    skyAlpha = min(1, skyAlpha + dt / SKY_FADE);
  }

  void skyArrived(float[] sky, float forTime) {
    skyPending = false;
    if (sky.length != w * h * 3) return;  // asked for before a resize
    if (skyTo == null) {
      skyFrom = skyTo = sky;
      skyAlpha = 1;
    } else {
      // A new sky mid-fade: what is on screen now becomes where it fades from.
      if (skyAlpha < 1) {
        float[] now = new float[skyTo.length];
        for (int i = 0; i < now.length; i++) now[i] = lerp(skyFrom[i], skyTo[i], skyAlpha);
        skyFrom = now;
      } else skyFrom = skyTo;
      skyTo = sky;
      skyAlpha = 0;
    }
    skyToTime = forTime;
  }

  void draw(int[] px) {
    long now = System.nanoTime();
    float dt = last == 0 ? 0 : (now - last) / 1e9;
    last = now;
    if (running) {
      time = (time + dt / CYCLE) % 1;
      clock += dt / CYCLE;
    }
    feed(dt);
    if (skyTo == null) {
      java.util.Arrays.fill(px, 0xff000000);
      return;
    }
    float[] s = sunDir(), sc = sunColor(), amb = ambient(), fog = horizon();
    float night = 1 - day();
    float a = skyAlpha;
    // The moon rides opposite the sun, a little off its line.
    float[] moon = {-s[0], -s[1] * 0.9 + 0.1, -s[2]};
    float ml = sqrt(sq(moon[0]) + sq(moon[1]) + sq(moon[2]));
    moon[0] /= ml; moon[1] /= ml; moon[2] /= ml;
    float sunDisk = 1 - cos(0.022), moonDisk = 1 - cos(0.028);

    // Sky: the faded keyframes, the sun and moon, then the clouds over them.
    int n = w * h;
    final float[] kA = skyFrom, kB = skyTo;
    par(n, (lo, hi) -> {
    for (int i = lo; i < hi; i++) {
      int j = i * 3;
      float r = kA[j] + (kB[j] - kA[j]) * a;
      float g = kA[j + 1] + (kB[j + 1] - kA[j + 1]) * a;
      float b = kA[j + 2] + (kB[j + 2] - kA[j + 2]) * a;
      if (dy[i] > -0.01) {
        float x = 1 - (dx[i] * s[0] + dy[i] * s[1] + dz[i] * s[2]);
        float glow = x < sunDisk ? 20 : 0.0006 / (x + 0.0004) + 0.15 / (1 + x * 8);
        r += sc[0] * glow; g += sc[1] * glow; b += sc[2] * glow;
        if (night > 0.01) {
          float xm = 1 - (dx[i] * moon[0] + dy[i] * moon[1] + dz[i] * moon[2]);
          float mg = xm < moonDisk ? 2.5 : 0.00004 / (xm + 0.0004) * 0.5;
          r += mg * night; g += mg * night; b += mg * 0.92 * night;
        }
      }
      hdr[j] = r; hdr[j + 1] = g; hdr[j + 2] = b;
      cloudA[i] = 0;
    }
    });
    float thresh = 0.66 - cover() * 0.5;
    float wu = clock * WIND_U, wv = clock * WIND_V;
    par(cIndex.length, (lo, hi) -> {
    float[] cl = new float[3];
    for (int k = lo; k < hi; k++) {
      int i = cIndex[k], j = i * 3;
      clouds.sample(cU[k] + wu, cV[k] + wv, cLod[k], cl);
      float c = smoothstep(thresh, thresh + 0.2, cl[0]) * cFade[k];
      if (c <= 0) continue;
      float lit = 0.45 + 0.55 * cl[1];
      float cs = max(0, dx[i] * s[0] + dy[i] * s[1] + dz[i] * s[2]);
      cs *= cs; cs *= cs; cs *= cs;
      float f = lit + cs * 0.7;
      float cr = sc[0] * f * 0.85 + amb[0] * 1.6, cg = sc[1] * f * 0.85 + amb[1] * 1.6, cb = sc[2] * f * 0.85 + amb[2] * 1.6;
      int x = i % w;
      for (int q = 0; q < 4; q++) {
        int p = i + (q & 1) + (q >> 1) * w;
        if ((q & 1) == 1 && x + 1 >= w) continue;
        if (p >= hdr.length / 3 || dy[p] <= 0.02) continue;
        int pj = p * 3;
        hdr[pj] += (cr - hdr[pj]) * c;
        hdr[pj + 1] += (cg - hdr[pj + 1]) * c;
        hdr[pj + 2] += (cb - hdr[pj + 2]) * c;
        cloudA[p] = c;
      }
    }
    });

    // Stars wheel round the pole as the night goes, hidden behind cloud.
    if (night > 0.01) {
      float rot = clock * TWO_PI, cr = cos(rot), sr = sin(rot);
      float tanV = tan(VFOV / 2), tanH = tanV * w / h;
      float fy = sin(PITCH), fz = cos(PITCH), uy = cos(PITCH), uz = -sin(PITCH);
      for (float[] st : stars) {
        float x = st[0] * cr - st[2] * sr, y = st[1], z = st[0] * sr + st[2] * cr;
        float depth = y * fy + z * fz;
        if (depth <= 0.05 || y < 0.03) continue;
        float sx = x / depth / tanH, sy = (y * uy + z * uz) / depth / tanV;
        int px_ = int((sx + 1) * 0.5 * w), py = int((1 - sy) * 0.5 * h);
        if (px_ < 0 || px_ >= w || py < 0 || py >= h) continue;
        int i = py * w + px_, j = i * 3;
        float bright = (0.15 + 1.2 * st[3]) * night * night * (1 - cloudA[i]);
        hdr[j] += bright; hdr[j + 1] += bright; hdr[j + 2] += bright * 1.1;
      }
    }
    // The sky's hue and saturation, on everything at or above the horizon.
    float[] skyM = hueSat(v[SKY][0], v[SKY][1]);
    par(n, (lo, hi) -> { for (int i = lo; i < hi; i++) if (dy[i] >= 0) mul(i * 3, skyM); });

    // The forest floor, lit by the same sun and sky.
    float sunUp = max(s[1], 0) * 0.8;
    float lr = amb[0] + sc[0] * sunUp, lg = amb[1] + sc[1] * sunUp, lb = amb[2] + sc[2] * sunUp;
    par(gIndex.length, (lo, hi) -> {
    float[] c = new float[3];
    for (int k = lo; k < hi; k++) {
      int j = gIndex[k] * 3;
      ground.sample(gU[k], gV[k], gLod[k], c);
      float f = gFog[k], mm = gMacro[k];
      hdr[j] = c[0] * mm * lr * (1 - f) + fog[0] * f;
      hdr[j + 1] = c[1] * mm * lg * (1 - f) + fog[1] * f;
      hdr[j + 2] = c[2] * mm * lb * (1 - f) + fog[2] * f;
    }
    });

    for (Trunk t : trunks) t.draw(this, s, sc, amb, fog);

    drawLake(s, sc, amb, fog, moon, night);
    drawMist(s, sc, amb);

    // Expose for what is actually on screen: the log-average brightness of
    // every 7th pixel, aimed lower at night so night still reads as night.
    double logSum = 0;
    int samples = 0;
    for (int i = 0; i < n; i += 7) {
      int j = i * 3;
      logSum += Math.log(1e-4 + 0.2126 * hdr[j] + 0.7152 * hdr[j + 1] + 0.0722 * hdr[j + 2]);
      samples++;
    }
    float avg = (float) Math.exp(logSum / samples);
    float target = constrain(lerp(0.07, 0.2, day()) / avg, 0.3, 14);
    exposure += (target - exposure) * min(1, dt * 2);
    float e = exposure;
    par(n, (lo, hi) -> {
    for (int i = lo; i < hi; i++) {
      int j = i * 3;
      px[i] = 0xff000000 | tone(hdr[j] * e) << 16 | tone(hdr[j + 1] * e) << 8 | tone(hdr[j + 2] * e);
    }
    });
  }

  void mul(int j, float[] m) {
    float r = hdr[j], g = hdr[j + 1], b = hdr[j + 2];
    hdr[j] = max(0, m[0] * r + m[1] * g + m[2] * b);
    hdr[j + 1] = max(0, m[3] * r + m[4] * g + m[5] * b);
    hdr[j + 2] = max(0, m[6] * r + m[7] * g + m[8] * b);
  }

  // Water: what it mirrors, bent by two layers of ripples drifting apart,
  // with the sun and moon glittering where the waves turn them toward us.
  void drawLake(float[] s, float[] sc, float[] amb, float[] fog, float[] moon, float night) {
    float[] m = hueSat(v[LAKE][0], v[LAKE][1]);
    float t1 = clock * 9, t2 = clock * 6;
    float br = 0.015 * (amb[0] + sc[0] * max(s[1], 0) * 0.3);
    float bg = 0.035 * (amb[1] + sc[1] * max(s[1], 0) * 0.3);
    float bb = 0.040 * (amb[2] + sc[2] * max(s[1], 0) * 0.3);
    int top = horizonRow - 1;
    par(wIndex.length, (lo, hi) -> {
    float[] r1 = new float[3], r2 = new float[3];
    for (int k = lo; k < hi; k++) {
      int i = wIndex[k], j = i * 3;
      ripples.sample(wU[k] + t1, wV[k] - t1 * 0.3, wLod[k], r1);
      float gx = r1[0] - 0.5, gz = r1[1] - 0.5;
      ripples.sample(wU[k] * 1.7 - t2, wV[k] * 1.7 + t2 * 0.5, wLod[k], r2);
      gx += r2[0] - 0.5; gz += r2[1] - 0.5;
      float near = 1 / (1 + wT[k] * 0.12);
      int mx = constrain(round(wMx[k] + gx * 40 * near), 0, w - 1);
      int my = constrain(round(wMy[k] + gz * 70 * near), 0, top);
      int src = (my * w + mx) * 3;
      // The mirror direction, tipped by the slope, against the sun and moon.
      float mxd = dx[i] + gx * 0.25, myd = -dy[i], mzd = dz[i] + gz * 0.25;
      float xs = 1 - (mxd * s[0] + myd * s[1] + mzd * s[2]);
      float glint = 0.00025 / (xs + 0.00025);
      float xm = 1 - (mxd * moon[0] + myd * moon[1] + mzd * moon[2]);
      float mglint = 0.00015 / (xm + 0.00015) * 0.6 * night;
      float F = wFres[k];
      float r = br * (1 - F) + (hdr[src] + sc[0] * glint + mglint) * F;
      float g = bg * (1 - F) + (hdr[src + 1] + sc[1] * glint + mglint) * F;
      float b = bb * (1 - F) + (hdr[src + 2] + sc[2] * glint + mglint * 0.95) * F;
      float f = wFog[k];
      hdr[j] = max(0, m[0] * r + m[1] * g + m[2] * b) * (1 - f) + fog[0] * f;
      hdr[j + 1] = max(0, m[3] * r + m[4] * g + m[5] * b) * (1 - f) + fog[1] * f;
      hdr[j + 2] = max(0, m[6] * r + m[7] * g + m[8] * b) * (1 - f) + fog[2] * f;
    }
    });
  }

  // Mist over whatever is low: thicker with distance, thinning upward,
  // in banks that drift. Lit by the sky, warm toward a low sun.
  void drawMist(float[] s, float[] sc, float[] amb) {
    float d = mistNow();
    if (d < 0.005) return;
    float[] m = hueSat(v[MIST][0], v[MIST][1]);
    float drift = clock * 1.2;
    par(mIndex.length, (lo, hi) -> {
    float[] mb3 = new float[3];
    for (int k = lo; k < hi; k++) {
      int i = mIndex[k], j = i * 3;
      float bank = mist.sample(mU[k] + drift, mV[k] + drift * 0.15, 1, mb3)[0];
      float alpha = min(0.97, d * (0.35 + 0.9 * bank) * mDist[k] * mHeight[k]);
      if (alpha <= 0.002) continue;
      float cs = max(0, dx[i] * s[0] + dy[i] * s[1] + dz[i] * s[2]);
      cs *= cs; cs *= cs;
      float lift = 0.3 + 0.7 * cs;
      float r = amb[0] * 1.25 + sc[0] * 0.3 * lift, g = amb[1] * 1.25 + sc[1] * 0.3 * lift, b = amb[2] * 1.25 + sc[2] * 0.3 * lift;
      float mr = m[0] * r + m[1] * g + m[2] * b, mg = m[3] * r + m[4] * g + m[5] * b, mb = m[6] * r + m[7] * g + m[8] * b;
      hdr[j] += (max(0, mr) - hdr[j]) * alpha;
      hdr[j + 1] += (max(0, mg) - hdr[j + 1]) * alpha;
      hdr[j + 2] += (max(0, mb) - hdr[j + 2]) * alpha;
    }
    });
  }

  int tone(float x) {
    float y = x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14);
    return gamma[(int) (constrain(y, 0, 1) * 4095)];
  }

  float smoothstep(float a, float b, float x) {
    float t = constrain((x - a) / (b - a), 0, 1);
    return t * t * (3 - 2 * t);
  }
}

// Hue turns colors round the grey axis; saturation scales away from grey.
// 0.5 on both leaves a color as it is.
static float[] hueSat(float hue, float sat) {
  float a = (hue - 0.5) * TWO_PI, c = cos(a), s = sin(a), k = 1 / 3.0, q = sqrt(k);
  float[] rot = {
    c + (1 - c) * k, k * (1 - c) - q * s, k * (1 - c) + q * s,
    k * (1 - c) + q * s, c + k * (1 - c), k * (1 - c) - q * s,
    k * (1 - c) - q * s, k * (1 - c) + q * s, c + k * (1 - c)};
  float m = sat * 2, lr = 0.2126, lg = 0.7152, lb = 0.0722;
  float[] satM = {
    lr + m * (1 - lr), lg - m * lg, lb - m * lb,
    lr - m * lr, lg + m * (1 - lg), lb - m * lb,
    lr - m * lr, lg - m * lg, lb + m * (1 - lb)};
  float[] out = new float[9];
  for (int r = 0; r < 3; r++)
    for (int col = 0; col < 3; col++)
      out[r * 3 + col] = rot[r * 3] * satM[col] + rot[r * 3 + 1] * satM[3 + col] + rot[r * 3 + 2] * satM[6 + col];
  return out;
}

// A tiling texture as float mip levels, the one before it kept while the
// new one fades in. A color texture is linear with hue and saturation
// applied; a data texture (clouds, ripples, mist) keeps its bytes as 0..1.
static class Tex {
  final int size, levels;
  final boolean data;
  int[] raw, rawOld;
  float[][] lin, linOld;
  float alpha = 1, scale = -1, hue = -1, sat = -1;
  boolean pending;
  static float[] toLinear = new float[256];
  static {
    for (int i = 0; i < 256; i++) toLinear[i] = (float) Math.pow(i / 255.0, 2.2);
  }

  Tex(int size, boolean data) {
    this.size = size;
    this.data = data;
    levels = Integer.numberOfTrailingZeros(size) - 2;
  }

  void arrived(int[] rgb, float forScale) {
    pending = false;
    rawOld = raw;
    linOld = lin;
    raw = rgb;
    scale = forScale;
    alpha = linOld == null ? 1 : 0;
    hue = -1;
  }

  void advance(float step, float h, float s) {
    if (raw == null) return;
    alpha = Math.min(1, alpha + step);
    if (data) { h = 0.5f; s = 0.5f; }
    if (h != hue || s != sat) {
      float[] m = hueSat(h, s);
      lin = bake(raw, m);
      if (rawOld != null && alpha < 1) linOld = bake(rawOld, m);
      hue = h;
      sat = s;
    }
  }

  float[][] bake(int[] rgb, float[] m) {
    float[][] lv = new float[levels][];
    float[] l0 = new float[size * size * 3];
    for (int i = 0; i < size * size; i++) {
      int R = (rgb[i] >> 16) & 255, G = (rgb[i] >> 8) & 255, B = rgb[i] & 255;
      if (data) {
        l0[i * 3] = R / 255f; l0[i * 3 + 1] = G / 255f; l0[i * 3 + 2] = B / 255f;
        continue;
      }
      float r = toLinear[R], g = toLinear[G], b = toLinear[B];
      l0[i * 3] = Math.max(0, m[0] * r + m[1] * g + m[2] * b);
      l0[i * 3 + 1] = Math.max(0, m[3] * r + m[4] * g + m[5] * b);
      l0[i * 3 + 2] = Math.max(0, m[6] * r + m[7] * g + m[8] * b);
    }
    lv[0] = l0;
    for (int k = 1; k < levels; k++) {
      int s = size >> k, ps = s * 2;
      float[] up = lv[k - 1], dn = new float[s * s * 3];
      for (int y = 0; y < s; y++)
        for (int x = 0; x < s; x++)
          for (int c = 0; c < 3; c++)
            dn[(y * s + x) * 3 + c] = 0.25f * (up[((2 * y) * ps + 2 * x) * 3 + c] + up[((2 * y) * ps + 2 * x + 1) * 3 + c]
              + up[((2 * y + 1) * ps + 2 * x) * 3 + c] + up[((2 * y + 1) * ps + 2 * x + 1) * 3 + c]);
      lv[k] = dn;
    }
    return lv;
  }

  // Bilinear within a level: one texel per sample is what drew blocks.
  // Into the caller's array, so threads can sample at once; sizes are
  // powers of two, so wrapping is a mask.
  float[] sample(float u, float v, int lod, float[] out) {
    if (lin == null) { out[0] = out[1] = out[2] = data ? 0.5f : 0; return out; }
    int s = size >> lod, mask = s - 1;
    float fu = u * s - 0.5f, fv = v * s - 0.5f;
    int x0 = (int) Math.floor(fu), y0 = (int) Math.floor(fv);
    float tx = fu - x0, ty = fv - y0;
    int x1 = (x0 + 1) & mask, y1 = (y0 + 1) & mask;
    x0 &= mask; y0 &= mask;
    int i00 = (y0 * s + x0) * 3, i10 = (y0 * s + x1) * 3, i01 = (y1 * s + x0) * 3, i11 = (y1 * s + x1) * 3;
    float w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
    float[] a = lin[lod];
    float[] o = alpha < 1 && linOld != null ? linOld[lod] : null;
    for (int c = 0; c < 3; c++) {
      float n = a[i00 + c] * w00 + a[i10 + c] * w10 + a[i01 + c] * w01 + a[i11 + c] * w11;
      if (o != null) {
        float m = o[i00 + c] * w00 + o[i10 + c] * w10 + o[i01 + c] * w01 + o[i11 + c] * w11;
        n = m + (n - m) * alpha;
      }
      out[c] = n;
    }
    return out;
  }
}

// A trunk on the ground, rising out of the top of the frame. Where it falls
// on screen is worked out once; each frame only lights it.
class Trunk {
  float x, z, r, phase, top;
  int[] index; float[] u, v, nx, nz, fog, facing; int[] lod;

  Trunk(float x, float z, float r, float phase) {
    this.x = x; this.z = z; this.r = r; this.phase = phase;
    top = 22 + phase * 20;
  }

  void layout(Scene sc) {
    int w = sc.w, h = sc.h;
    float tanV = tan(VFOV / 2), tanH = tanV * w / h;
    float fy = sin(PITCH), fz = cos(PITCH), uy = cos(PITCH), uz = -sin(PITCH);
    float d = sqrt(x * x + z * z);
    float tx = -x / d, tz = -z / d;       // toward the camera
    float rx = -tz, rz = tx;              // across the trunk
    java.util.ArrayList<float[]> cells = new java.util.ArrayList<float[]>();
    for (int py = 0; py < h; py++) {
      // The height on this trunk's axis that lands on row py.
      float ny = (1 - 2 * (py + 0.5) / h) * tanV;
      float py0 = -CAM_H;
      float hgt = (ny * (z * fz + py0 * fy) - (py0 * uy + z * uz)) / (uy - ny * fy);
      if (hgt < 0 || hgt > top) continue;
      float wy = py0 + hgt;
      float depth = wy * fy + z * fz;
      if (depth <= 0.1) continue;
      float rad = r * pow(1 - hgt / top, 0.7);
      if (rad < 0.01) continue;
      float cx = (x / depth / tanH + 1) * 0.5 * w;
      float hw = rad / depth / tanH * 0.5 * w;
      int x0 = max(0, ceil(cx - hw)), x1 = min(w - 1, floor(cx + hw));
      float foot = depth * (VFOV / h) / (TWO_PI * rad) * sc.bark.size;
      int l = constrain(int(log(max(foot, 1)) / log(2)), 0, sc.bark.levels - 1);
      for (int px = x0; px <= x1; px++) {
        float s = constrain((px + 0.5 - cx) / hw, -1, 1);
        float c = sqrt(1 - s * s);
        float ang = asin(s);
        cells.add(new float[] {py * w + px, ang / TWO_PI + phase, hgt / (TWO_PI * rad),
          rx * s + tx * c, rz * s + tz * c, 1 - exp(-d / 220), l, c});
      }
    }
    int n = cells.size();
    index = new int[n]; u = new float[n]; v = new float[n]; nx = new float[n]; nz = new float[n];
    fog = new float[n]; lod = new int[n]; facing = new float[n];
    for (int i = 0; i < n; i++) {
      float[] c = cells.get(i);
      index[i] = (int) c[0]; u[i] = c[1]; v[i] = c[2]; nx[i] = c[3]; nz[i] = c[4]; fog[i] = c[5]; lod[i] = (int) c[6]; facing[i] = c[7];
    }
  }

  void draw(Scene sc, float[] s, float[] sun, float[] amb, float[] haze) {
    float[] hdr = sc.hdr;
    float horiz = sqrt(s[0] * s[0] + s[2] * s[2]);
    par(index.length, (lo, hi) -> {
    float[] c = new float[3];
    for (int i = lo; i < hi; i++) {
      sc.bark.sample(u[i], v[i], lod[i], c);
      float face = horiz > 0 ? max(0, nx[i] * s[0] + nz[i] * s[2]) : 0;
      float shade = 0.35 + 0.65 * facing[i];
      float lr = amb[0] * shade + sun[0] * face, lg = amb[1] * shade + sun[1] * face, lb = amb[2] * shade + sun[2] * face;
      int j = index[i] * 3;
      float f = fog[i];
      hdr[j] = c[0] * lr * (1 - f) + haze[0] * f;
      hdr[j + 1] = c[1] * lg * (1 - f) + haze[1] * f;
      hdr[j + 2] = c[2] * lb * (1 - f) + haze[2] * f;
    }
    });
  }
}

// The AssemblyScript side: one node process, jobs in, `done <id>` out.
// Files are read on the reader thread; the frame thread takes them whole.
class Gen {
  Process proc;
  java.io.PrintWriter in;
  java.util.concurrent.ConcurrentLinkedQueue<Runnable> ready = new java.util.concurrent.ConcurrentLinkedQueue<Runnable>();
  java.util.concurrent.ConcurrentHashMap<Integer, Runnable> waiting = new java.util.concurrent.ConcurrentHashMap<Integer, Runnable>();
  int next;
  String dir = System.getenv("XDG_RUNTIME_DIR") == null ? "/tmp" : System.getenv("XDG_RUNTIME_DIR");

  Gen() {
    try {
      proc = new ProcessBuilder(System.getProperty("sketches.node", "node"), System.getProperty("sketches.gen"))
        .redirectError(ProcessBuilder.Redirect.INHERIT).start();
      in = new java.io.PrintWriter(proc.getOutputStream(), true);
      Thread t = new Thread(() -> {
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.InputStreamReader(proc.getInputStream()))) {
          for (String line; (line = r.readLine()) != null; ) {
            String[] f = line.split(" ");
            if (f.length == 2 && f[0].equals("done")) {
              Runnable job = waiting.remove(Integer.parseInt(f[1]));
              if (job != null) job.run();
            }
          }
        } catch (Exception e) {
          e.printStackTrace();
        }
        System.err.println("gen: node exited");
      });
      t.setDaemon(true);
      t.start();
    } catch (Exception e) {
      e.printStackTrace();
    }
  }

  void poll(Scene sc) {
    for (Runnable r; (r = ready.poll()) != null; ) r.run();
  }

  String path(String kind) {
    return dir + "/sketches." + kind;
  }

  void sky(int w, int h, double[] p, float forTime) {
    int id = ++next;
    String out = path("sky" + (id % 2));
    waiting.put(id, () -> {
      float[] sky = new float[w * h * 3];
      try {
        java.nio.ByteBuffer b = java.nio.ByteBuffer.wrap(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(out)));
        b.order(java.nio.ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(sky);
      } catch (Exception e) {
        e.printStackTrace();
      }
      ready.add(() -> scene.skyArrived(sky, forTime));
    });
    StringBuilder ps = new StringBuilder();
    for (int i = 0; i < p.length; i++) ps.append(i == 0 ? "" : ",").append(p[i]);
    in.println("{\"id\":" + id + ",\"kind\":\"sky\",\"w\":" + w + ",\"h\":" + h + ",\"p\":[" + ps + "],\"out\":\"" + out + "\"}");
  }

  void texture(String kind, Tex t, float scale, int seed) {
    int id = ++next;
    String out = path(kind);
    t.pending = true;
    waiting.put(id, () -> {
      int[] rgb = new int[t.size * t.size];
      try {
        byte[] b = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(out));
        for (int i = 0; i < rgb.length; i++)
          rgb[i] = (b[i * 4] & 255) << 16 | (b[i * 4 + 1] & 255) << 8 | (b[i * 4 + 2] & 255);
      } catch (Exception e) {
        e.printStackTrace();
      }
      ready.add(() -> t.arrived(rgb, scale));
    });
    in.println("{\"id\":" + id + ",\"kind\":\"" + kind + "\",\"size\":" + t.size + ",\"scale\":" + scale + ",\"seed\":" + seed + ",\"out\":\"" + out + "\"}");
  }
}
