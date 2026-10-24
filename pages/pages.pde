// Five sketches, one shown at a time. The host owns which page is up and
// what its parameters are; this only draws them. Runner.java drives it
// headless: no window, the pixels go to ramen's frame file.

import processing.awt.PGraphicsJava2D;

String[] PAGES = {"particles", "lines", "startfield", "scene", "walker"};
String[][] NAMES = {
  {"count", "speed", "size"},
  {"count", "speed", "twist"},
  {"stars", "speed", "trail"},
  {"hue", "saturation", "scale"},
  {"walkers", "diagonals", "triangles"},
};
static final int WALKER = 4;
// ML, MC, MR as the pad glyph: which key, not its name.
String[] KEYS = {"[...#.....]", "[....#....]", "[.....#...]"};

// When this build was made, read off its own class file.
String builtAt() {
  try {
    java.io.File where = new java.io.File(pages.class.getProtectionDomain().getCodeSource().getLocation().toURI());
    java.io.File c = where.isDirectory() ? new java.io.File(where, "pages.class") : where;
    return new java.text.SimpleDateFormat("HH:mm:ss").format(new java.util.Date(c.lastModified()));
  } catch (Exception e) {
    return "unknown";
  }
}

String built = builtAt();

PGraphics pg; // the page, with no HUD on it
PGraphics hudLayer; // the HUD, clear around it
PGraphics composite; // the two, which is what goes out
PFont font;
int page;
float[] p = {0.4, 0.3, 0.3};
boolean[] locked = new boolean[3];

Particles particles = new Particles();
Lines lines = new Lines();
Startfield startfield = new Startfield();
Scene scene = new Scene();
Walker walker = new Walker();

void resizeTo(int w, int h) {
  // createGraphics wants a primary surface to copy; headless there is none.
  pg = new PGraphicsJava2D();
  pg.setParent(this);
  pg.setPrimary(false);
  pg.setSize(w, h);
  pg.smooth(4);
  font = new PFont(new java.awt.Font("Monospaced", java.awt.Font.PLAIN, 14), true);
  pg.beginDraw();
  pg.background(page == WALKER ? color(0) : color(6, 8, 14));
  pg.endDraw();
  hudLayer = newLayer(w, h);
  composite = newLayer(w, h);
  walker.reset(w, h);
  particles.reset(w, h);
  startfield.reset(w, h);
  scene.resize(w, h);
}

void show(int next) {
  if (next != page && pg != null) {
    pg.beginDraw();
    pg.background(next == WALKER ? color(0) : color(6, 8, 14));
    pg.endDraw();
    if (next == WALKER) walker.reset(pg.width, pg.height);
  }
  page = next;
}

void setState(String name, float a, float b, float c, boolean la, boolean lb, boolean lc) {
  int next = java.util.Arrays.asList(PAGES).indexOf(name);
  if (next < 0 || next == 3 || next == WALKER) return;
  show(next);
  p[0] = a; p[1] = b; p[2] = c;
  locked[0] = la; locked[1] = lb; locked[2] = lc;
}

void setScene(float t, boolean running, int thing, boolean thingLocked, float[] vals, boolean[] locks) {
  show(3);
  scene.set(t, running, thing, thingLocked, vals, locks);
  for (int i = 0; i < 3; i++) {
    p[i] = vals[thing * 3 + i];
    locked[i] = locks[thing * 3 + i];
  }
}

float walkSpeed = 0.4;
float imageOpacity = 0;
boolean imageHeld;
boolean walkPaused;
boolean snapshotNext;
String savedAs = ""; // the last snapshot, by file name
long savedAt; // and when, so the HUD names it for a few seconds
String unsaid; // its whole path, until the host has been told

// The walker's own line: its speed, which the wheel moves, then its three,
// then how much of the picture it follows shows, whether the wheel has it,
// and whether the walkers stand still.
void setWalker(float speed, float a, float b, float c, boolean la, boolean lb, boolean lc, float opacity, boolean held, boolean paused) {
  show(WALKER);
  walkSpeed = speed;
  p[0] = a; p[1] = b; p[2] = c;
  locked[0] = la; locked[1] = lb; locked[2] = lc;
  imageOpacity = opacity;
  imageHeld = held;
  walkPaused = paused;
}

void snapshot() {
  if (pg != null) snapshotNext = true;
}

// The page as it is, without the HUD, as a PNG in captures/ beside the picture.
// The walker's own canvas stops where its HUD rows start.
void saveSnapshot() {
  snapshotNext = false;
  String path = System.getProperty("sketches.image", "image/walker.jpg");
  java.io.File dir = new java.io.File(new java.io.File(path).getAbsoluteFile().getParentFile(), "captures");
  dir.mkdirs();
  String name = new java.text.SimpleDateFormat("yyyyMMdd-HHmmss").format(new java.util.Date()) + "-" + PAGES[page] + ".png";
  String file = new java.io.File(dir, name).getAbsolutePath();
  pg.get(0, 0, pg.width, page == WALKER ? pg.height - walker.hudRows : pg.height).save(file);
  savedAs = name;
  savedAt = System.currentTimeMillis();
  unsaid = file;
}

// The path of a snapshot not yet reported, once.
String takeSaved() {
  String file = unsaid;
  unsaid = null;
  return file;
}

// A drawing surface that is clear where nothing is drawn.
PGraphics newLayer(int w, int h) {
  PGraphics l = new PGraphicsJava2D();
  l.setParent(this);
  l.setPrimary(false);
  l.setSize(w, h);
  l.smooth(4);
  return l;
}

void resetWalk() {
  if (pg == null || page != WALKER) return;
  pg.beginDraw();
  pg.background(0);
  pg.endDraw();
  walker.reset(pg.width, pg.height);
}

int[] frame() {
  pg.beginDraw();
  if (page == 0) particles.draw(pg, p[0], p[1], p[2]);
  else if (page == 1) lines.draw(pg, p[0], p[1], p[2]);
  else if (page == 2) startfield.draw(pg, p[0], p[1], p[2]);
  else if (page == WALKER) walker.draw(pg, walkSpeed, p[0], p[1], p[2], imageOpacity);
  else {
    pg.loadPixels();
    scene.draw(pg.pixels);
    pg.updatePixels();
  }
  if (snapshotNext) saveSnapshot();
  pg.endDraw();

  hudLayer.beginDraw();
  hudLayer.clear();
  hud(hudLayer);
  hudLayer.endDraw();
  composite.beginDraw();
  composite.image(pg, 0, 0);
  composite.image(hudLayer, 0, 0);
  composite.endDraw();
  composite.loadPixels();
  return composite.pixels;
}

// What is up and what the knob will move, so a frame shows its own state.
void hud(PGraphics g) {
  float s = 14;
  boolean sc = page == 3;
  boolean wk = page == WALKER;
  float y0 = g.height - (sc || wk ? 8 : 6) * s;
  g.noStroke();
  g.fill(0, 200);
  g.rect(0, y0 - s * 0.6, g.width, g.height - y0 + s * 0.6);
  g.textFont(font);
  g.textSize(s);
  g.textAlign(LEFT, TOP);
  int on = color(255, 190, 60);

  float x = s;
  for (int i = 0; i < PAGES.length; i++) {
    g.fill(i == page ? color(255) : color(110));
    String t = i == page ? "[" + PAGES[i] + "]" : " " + PAGES[i] + " ";
    g.text(t, x, y0);
    x += g.textWidth(t) + s;
  }
  g.textAlign(RIGHT, TOP);
  boolean fresh = System.currentTimeMillis() - savedAt < 6000 && savedAs.length() > 0;
  g.fill(fresh || (wk && walkPaused) ? color(255, 190, 60) : color(110));
  g.text(fresh ? "saved " + savedAs.substring(9) : (wk && walkPaused ? "paused   " : "") + "built " + built, g.width - s, y0);
  g.textAlign(LEFT, TOP);

  float by = y0 + 2 * s;
  // The scene's own row: the hour, which thing the bottom row is on, and
  // whether time runs.
  boolean live = true;
  if (sc) {
    int minutes = (int) (scene.time * 24 * 60) % (24 * 60);
    g.fill(255);
    String clock = nf(minutes / 60, 2) + ":" + nf(minutes % 60, 2);
    g.text(clock, s, by);
    x = s + g.textWidth(clock) + 2 * s;
    for (int i = 0; i < THINGS.length; i++) {
      boolean here = i == scene.thing;
      g.fill(here ? (scene.thingLocked ? on : color(255)) : color(110));
      String t = here ? "[" + THINGS[i] + "]" : " " + THINGS[i] + " ";
      g.text(t, x, by);
      x += g.textWidth(t) + s;
    }
    g.textAlign(RIGHT, TOP);
    g.fill(scene.thingLocked ? on : color(150));
    float mt = scene.mistToday();
    String weather = mt > 0 ? "mist today " + round(mt * 100) + "%" : "no mist today";
    g.text(weather + "   " + (scene.thingLocked ? "LOCKED  time stopped" : "time running"), g.width - s, by);
    g.textAlign(LEFT, TOP);
    by += 2 * s;
    live = scene.thingLocked;
  }
  // The walker's own row: its speed, which the wheel moves while nothing is locked.
  if (wk) {
    boolean wheel = !imageHeld && !(locked[0] || locked[1] || locked[2]);
    g.fill(wheel ? on : color(150));
    g.text("speed " + nf(walkSpeed, 1, 2) + (wheel ? "  turn" : ""), s, by);
    g.fill(imageHeld ? on : color(150));
    g.text("image " + nf(imageOpacity, 1, 2) + (imageHeld ? "  turn" : ""), s + 14 * s, by);
    g.textAlign(RIGHT, TOP);
    g.fill(150);
    g.textAlign(LEFT, TOP);
    glyphLine(g, "[......#..] image  [.......#.] pause  [...#.#...] snap  [........#] reset", g.width - s, by, true, color(150));
    by += 2 * s;
  }

  float bw = (g.width - 4 * s) / 3;
  for (int i = 0; i < 3; i++) {
    float bx = s + i * (bw + s);
    boolean lit = live && locked[i];
    int dim = live ? color(150) : color(80);
    glyphLine(g, KEYS[i] + " " + NAMES[page][i], bx, by, false, lit ? on : dim);
    g.fill(lit ? on : dim);
    g.text(lit ? "locked" : "", bx, by + 2.8 * s);
    g.fill(40);
    g.rect(bx, by + 1.6 * s, bw, s * 0.8);
    g.fill(lit ? on : live ? color(200) : color(90));
    g.rect(bx, by + 1.6 * s, bw * p[i], s * 0.8);
    g.textAlign(RIGHT, TOP);
    g.fill(lit ? on : dim);
    g.text(nf(p[i], 1, 2), bx + bw, by);
    g.textAlign(LEFT, TOP);
  }
}

// The pad drawn as itself, as ramen draws it: square, circle, square over
// two rows of three. "[...#.#...]" is ML and MR; "+" is half strength, and
// a trailing "<" or ">" is the knob turning.
java.util.regex.Pattern GLYPH = java.util.regex.Pattern.compile("\\[[.+#]{9}[<>]?\\]");

void drawGlyph(PGraphics g, float x, float y, float side, String code, int col) {
  if (side < 24) {
    pixelGlyph(g, x, y, side, code, col);
    return;
  }
  float cell = side / 3.4, gap = cell * 0.2, line = max(1, cell * 0.09);
  // Bits, not red(): those go through the primary surface, and headless there is none.
  float r = (col >> 16) & 255, gr = (col >> 8) & 255, b = col & 255, a = (col >>> 24) & 255;
  g.strokeWeight(line);
  g.stroke(r, gr, b, a);
  for (int i = 0; i < 9; i++) {
    float cx = x + (i % 3) * (cell + gap), cy = y + (i / 3) * (cell + gap);
    char f = code.charAt(1 + i);
    if (f == '.') g.noFill();
    else g.fill(r, gr, b, f == '#' ? a : a * 0.5);
    if (i == 1) g.ellipse(cx + cell / 2, cy + cell / 2, cell - line, cell - line);
    else g.rect(cx + line / 2, cy + line / 2, cell - line, cell - line);
  }
  char spin = code.charAt(code.length() - 2);
  if (spin == '<' || spin == '>') {
    // Over the top of the circle, the head at the end the knob turns toward.
    float ox = x + cell + gap + cell / 2, oy = y + cell / 2, rr = cell * 0.66;
    float arcA = radians(210), arcB = radians(330), tip;
    g.noFill();
    g.arc(ox, oy, 2 * rr, 2 * rr, arcA, arcB);
    float dx, dy;
    if (spin == '>') { tip = arcB; dx = -sin(tip); dy = cos(tip); }
    else { tip = arcA; dx = sin(tip); dy = -cos(tip); }
    float tx = ox + rr * cos(tip), ty = oy + rr * sin(tip), len = rr * 0.3, wide = rr * 0.18;
    g.line(tx - dx * len + dy * wide, ty - dy * len - dx * wide, tx, ty);
    g.line(tx, ty, tx - dx * len - dy * wide, ty - dy * len + dx * wide);
  }
  g.noStroke();
}

// The small form, as ramen draws it: solid blocks on whole pixels, no
// outlines, strength as brightness (empty 22%, half 55%, full), the knob's
// corners cut, and a turn as the knob become an arrowhead.
void pixelGlyph(PGraphics g, float x, float y, float side, String code, int col) {
  int gap = side >= 20 ? 2 : 1;
  int cell = max(4, floor((side - 2 * gap) / 3));
  int x0 = round(x), y0 = round(y);
  float r = (col >> 16) & 255, gr = (col >> 8) & 255, b = col & 255, a = (col >>> 24) & 255;
  char spin = code.charAt(code.length() - 2);
  boolean turning = spin == '<' || spin == '>';
  g.noStroke();
  for (int i = 0; i < 9; i++) {
    int cx = x0 + (i % 3) * (cell + gap), cy = y0 + (i / 3) * (cell + gap);
    char f = code.charAt(1 + i);
    float strength = f == '#' ? 1 : f == '+' ? 0.55 : 0.22;
    if (i == 1 && turning) {
      g.fill(r, gr, b, a);
      int tip = spin == '>' ? cx + cell : cx, back = spin == '>' ? cx : cx + cell;
      g.triangle(back, cy, tip, cy + cell / 2f, back, cy + cell);
    } else if (i == 1) {
      g.fill(r, gr, b, a * strength);
      int k = max(1, cell / 4);
      g.rect(cx + k, cy, cell - 2 * k, cell);
      g.rect(cx, cy + k, k, cell - 2 * k);
      g.rect(cx + cell - k, cy + k, k, cell - 2 * k);
    } else {
      g.fill(r, gr, b, a * strength);
      g.rect(cx, cy, cell, cell);
    }
  }
}

// A line of text in which any glyph is drawn as the pad, a character tall.
// `right` puts the line's end at x. Returns how wide it was.
float glyphLine(PGraphics g, String line, float x, float y, boolean right, int col) {
  float side = max(14, g.textAscent()), wide = 0;
  java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
  java.util.regex.Matcher m = GLYPH.matcher(line);
  int at = 0;
  while (m.find()) {
    if (m.start() > at) parts.add(line.substring(at, m.start()));
    parts.add(m.group());
    at = m.end();
  }
  if (at < line.length()) parts.add(line.substring(at));
  for (String part : parts) wide += GLYPH.matcher(part).matches() ? side : g.textWidth(part);
  float cx = right ? x - wide : x;
  g.textAlign(LEFT, TOP);
  for (String part : parts) {
    if (GLYPH.matcher(part).matches()) {
      drawGlyph(g, cx, y + (g.textAscent() - side) / 2 + 1, side, part, col);
      cx += side;
    } else {
      g.fill(col);
      g.text(part, cx, y);
      cx += g.textWidth(part);
    }
  }
  return wide;
}

// Points carried along a slowly changing noise field.
class Particles {
  int max = 6000;
  float[] x = new float[max], y = new float[max];
  float t;

  void reset(int w, int h) {
    for (int i = 0; i < max; i++) {
      x[i] = random(w);
      y[i] = random(h);
    }
  }

  void draw(PGraphics g, float count, float speed, float size) {
    int n = int(lerp(100, max, count));
    float sp = lerp(0.3, 6, speed);
    float sz = lerp(1, 7, size);
    t += 0.003;
    g.noStroke();
    g.fill(6, 8, 14, 30);
    g.rect(0, 0, g.width, g.height);
    g.colorMode(HSB, 360, 100, 100, 100);
    for (int i = 0; i < n; i++) {
      float a = noise(x[i] * 0.003, y[i] * 0.003, t) * TWO_PI * 2;
      x[i] += cos(a) * sp;
      y[i] += sin(a) * sp;
      if (x[i] < 0 || x[i] >= g.width || y[i] < 0 || y[i] >= g.height) {
        x[i] = random(g.width);
        y[i] = random(g.height);
      }
      g.fill((degrees(a) + t * 400) % 360, 70, 100, 70);
      g.rect(x[i], y[i], sz, sz);
    }
    g.colorMode(RGB, 255);
  }
}

// A bundle of lines strung between two points that wander on Lissajous paths.
class Lines {
  float t;

  void draw(PGraphics g, float count, float speed, float twist) {
    g.background(6, 8, 14);
    int n = int(lerp(3, 180, count));
    t += lerp(0.002, 0.06, speed);
    float tw = lerp(0, 0.12, twist);
    float cx = g.width / 2, cy = g.height / 2;
    float r = min(g.width, g.height) * 0.42;
    g.strokeWeight(1.2);
    g.colorMode(HSB, 360, 100, 100, 100);
    for (int i = 0; i < n; i++) {
      float a = t + i * tw;
      float x1 = cx + cos(a * 1.3) * r, y1 = cy + sin(a * 1.7) * r;
      float x2 = cx + cos(a * 0.7 + PI) * r, y2 = cy + sin(a * 1.1 + HALF_PI) * r;
      g.stroke((200 + i * 260.0 / n + t * 20) % 360, 60, 100, 60);
      g.line(x1, y1, x2, y2);
    }
    g.noStroke();
    g.colorMode(RGB, 255);
  }
}

// Stars coming at you; trail keeps the previous frames around longer.
class Startfield {
  int max = 3000;
  float[] x = new float[max], y = new float[max], z = new float[max];
  float depth;

  void reset(int w, int h) {
    depth = max(w, h);
    for (int i = 0; i < max; i++) spawn(i, random(1, depth));
  }

  void spawn(int i, float zz) {
    x[i] = random(-depth, depth);
    y[i] = random(-depth, depth);
    z[i] = zz;
  }

  void draw(PGraphics g, float stars, float speed, float trail) {
    int n = int(lerp(50, max, stars));
    float sp = lerp(0.5, 40, speed);
    g.noStroke();
    g.fill(0, 0, 0, lerp(255, 12, trail));
    g.rect(0, 0, g.width, g.height);
    float cx = g.width / 2, cy = g.height / 2;
    float f = g.width / 2;
    for (int i = 0; i < n; i++) {
      float pz = z[i];
      z[i] -= sp;
      if (z[i] < 1) {
        spawn(i, depth);
        continue;
      }
      float sx = cx + x[i] / z[i] * f, sy = cy + y[i] / z[i] * f;
      float px = cx + x[i] / pz * f, py = cy + y[i] / pz * f;
      if (sx < 0 || sx >= g.width || sy < 0 || sy >= g.height) {
        spawn(i, depth);
        continue;
      }
      float b = map(z[i], depth, 0, 60, 255);
      g.stroke(b);
      g.strokeWeight(map(z[i], depth, 0, 0.5, 3));
      g.line(px, py, sx, sy);
    }
    g.noStroke();
  }
}

// White lines on black, like traces on a board. Walkers set out from the
// middle on straight runs and turn by 90 or 45 degrees, and where one turns
// it leaves a ring, now and then a triangle. Nothing fades. Walkers head for
// room and end runs by forms; a form is part clear, over the line under it.
class Walker {
  int max = 24;
  float[] x = new float[max], y = new float[max];
  int[] heading = new int[max]; // in 45 degree steps, 0 is east, turning clockwise
  float[] left = new float[max]; // what is left of the run, in pixels
  float cell = 12; // a run is a few of these
  float mark = 3; // the radius of what a turn leaves
  float sharp = 0.5; // how hard a crowded way is avoided
  int hudRows = 9 * 14; // the bottom rows belong to the HUD
  int cols, rows;
  float[] ink; // per cell, the length of line drawn in it, in cells
  ArrayList<ArrayList<float[]>> formsIn = new ArrayList<ArrayList<float[]>>(); // per cell: x, y, heading, 1 for a triangle, red, green, blue, size
  float follow = 3; // how hard the white of the picture pulls
  float thin = 0.3; // the weight of a line where the picture is black, or not there
  float grip = 0.2; // the chance a step through the darkest ends the run
  java.awt.image.BufferedImage source; // the picture, as read
  boolean tried;
  PImage shown; // the picture fitted into the canvas
  float shownX, shownY;
  int fitW, fitH;
  float[] light; // per cell, how white the picture is there, 0..1
  PGraphics layer; // the lines, clear where nothing is drawn
  PGraphics formLayer; // the forms, over the lines
  ArrayList<float[]> fresh = new ArrayList<float[]>(); // forms made since they were last drawn
  float take = 0.6; // how much of the picture's colour a line takes on, against white
  float[] wob = new float[max]; // per walker, how heavy its run is against the picture
  float[] shade = new float[max]; // and how much lighter or darker

  void reset(int w, int h) {
    cols = ceil(w / cell);
    rows = ceil((h - hudRows) / cell);
    ink = new float[cols * rows];
    formsIn.clear();
    fresh.clear();
    for (int c = 0; c < cols * rows; c++) formsIn.add(new ArrayList<float[]>());
    layer = newLayer(w, h);
    layer.beginDraw();
    layer.clear();
    layer.endDraw();
    formLayer = newLayer(w, h);
    formLayer.beginDraw();
    formLayer.clear();
    formLayer.endDraw();
    fit(w, h - hudRows);
    for (int i = 0; i < max; i++) {
      x[i] = w / 2;
      y[i] = (h - hudRows) / 2;
      heading[i] = int(random(8));
      left[i] = run();
      vary(i);
      place(i, w, h - hudRows);
    }
  }

  // The picture, whole, as large as the canvas holds it, and how white each
  // cell of the canvas is. No picture where the file is not.
  void fit(int w, int h) {
    if (shown != null && w == fitW && h == fitH) return;
    shown = null;
    light = null;
    fitW = w;
    fitH = h;
    if (!tried) {
      tried = true;
      String path = System.getProperty("sketches.image");
      try {
        if (path != null) source = javax.imageio.ImageIO.read(new java.io.File(path));
      } catch (Exception e) {
        System.err.println("walker picture " + path + ": " + e);
      }
    }
    if (source == null) return;
    int sw = source.getWidth(), sh = source.getHeight();
    float sc = min(w / (float) sw, h / (float) sh);
    int iw = max(1, round(sw * sc)), ih = max(1, round(sh * sc));
    float[] sum = new float[iw * ih * 3];
    int[] n = new int[iw * ih];
    int[] row = new int[sw];
    for (int yy = 0; yy < sh; yy++) {
      source.getRGB(0, yy, sw, 1, row, 0, sw);
      int dy = min(ih - 1, int(yy * sc));
      for (int xx = 0; xx < sw; xx++) {
        int k = dy * iw + min(iw - 1, int(xx * sc));
        int c = row[xx];
        sum[k * 3] += (c >> 16) & 255;
        sum[k * 3 + 1] += (c >> 8) & 255;
        sum[k * 3 + 2] += c & 255;
        n[k]++;
      }
    }
    shown = new PImage(iw, ih, RGB);
    shownX = (w - iw) / 2;
    shownY = (h - ih) / 2;
    light = new float[cols * rows];
    for (int k = 0; k < iw * ih; k++) {
      if (n[k] == 0) continue;
      float r = sum[k * 3] / n[k], gr = sum[k * 3 + 1] / n[k], b = sum[k * 3 + 2] / n[k];
      shown.pixels[k] = color(r, gr, b);
      int cx = int((shownX + k % iw) / cell), cy = int((shownY + k / iw) / cell);
      if (cx < cols && cy < rows) light[cy * cols + cx] += (0.299 * r + 0.587 * gr + 0.114 * b) / 255 / (cell * cell);
    }
    shown.updatePixels();
    // Brightness as it is, full from 0.7 up, so the shadows keep a little.
    for (int c = 0; c < light.length; c++) light[c] = constrain(light[c] / 0.7, 0, 1);
  }

  float lightAt(float px, float py) {
    if (light == null) return 1;
    int cx = int(px / cell), cy = int(py / cell);
    if (px < 0 || py < 0 || cx >= cols || cy >= rows) return 0;
    return light[cy * cols + cx];
  }

  // Set walker i down somewhere white, going nowhere in particular.
  void place(int i, int w, int h) {
    if (light == null) return;
    for (int tries = 0; tries < 400; tries++) {
      float px = random(mark * 2, w - mark * 2), py = random(mark * 2, h - mark * 2);
      if (random(1) < lightAt(px, py)) {
        x[i] = px;
        y[i] = py;
        return;
      }
    }
  }

  // How white the way is ahead, going heading h from where walker i is.
  float glow(int i, int h) {
    float a = h * QUARTER_PI, sum = 0;
    for (int k = 1; k <= 9; k++) sum += lightAt(x[i] + cos(a) * cell * k, y[i] + sin(a) * cell * k);
    return sum / 9;
  }

  float run() {
    return cell * int(random(2, 12));
  }

  int at(float px, float py) {
    return constrain(int(py / cell), 0, rows - 1) * cols + constrain(int(px / cell), 0, cols - 1);
  }

  // What is down around a point: the line in its cell and in the ones next
  // to it, and each form there.
  float crowd(float px, float py) {
    int cx = int(px / cell), cy = int(py / cell);
    if (px < 0 || py < 0 || cx >= cols || cy >= rows) return 2;
    float sum = 0;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        int ax = cx + dx, ay = cy + dy;
        if (ax < 0 || ay < 0 || ax >= cols || ay >= rows) continue;
        int c = ay * cols + ax;
        sum += min(ink[c], 2) * (dx == 0 && dy == 0 ? 1 : 0.4) + 2 * formsIn.get(c).size();
      }
    }
    return sum;
  }

  // How crowded the way is ahead, going heading h from where walker i is.
  float ahead(int i, int h) {
    float a = h * QUARTER_PI, sum = 0;
    for (int k = 2; k <= 9; k++) {
      float px = x[i] + cos(a) * cell * k, py = y[i] + sin(a) * cell * k;
      // The darker the place, the sooner it counts as full.
      sum += crowd(px, py) * 1.1 / (0.1 + lightAt(px, py));
    }
    return sum;
  }

  // How many forms have their centre between lo and hi from a point.
  int formsBetween(float px, float py, float lo, float hi) {
    int cx = max(int(px / cell), 0), cy = max(int(py / cell), 0), r = ceil(hi / cell);
    int found = 0;
    for (int ay = max(cy - r, 0); ay <= min(cy + r, rows - 1); ay++) {
      for (int ax = max(cx - r, 0); ax <= min(cx + r, cols - 1); ax++) {
        for (float[] f : formsIn.get(ay * cols + ax)) {
          float away = dist(px, py, f[0], f[1]);
          if (away >= lo && away < hi) found++;
        }
      }
    }
    return found;
  }

  // An index chosen by weight, -1 when nothing has any.
  int pick(float[] w) {
    float total = 0;
    for (float v : w) total += v;
    if (total <= 0) return -1;
    float r = random(total);
    for (int k = 0; k < w.length; k++) {
      r -= w[k];
      if (r < 0) return k;
    }
    return w.length - 1;
  }

  // Two to eleven cells, the ones that end by a form likelier, none that end
  // on one.
  float runFrom(PGraphics g, float px, float py, float a) {
    float[] w = new float[10];
    for (int n = 2; n <= 11; n++) {
      float ex = px + cos(a) * cell * n, ey = py + sin(a) * cell * n;
      if (!inside(g, ex, ey)) continue;
      w[n - 2] = formsBetween(ex, ey, 0, mark * 4) > 0 ? 0.1 : formsBetween(ex, ey, mark * 4, mark * 4 + cell * 3) > 0 ? 5 : 1;
      float lit = 0;
      for (int k = 1; k <= n; k++) lit += lightAt(px + cos(a) * cell * k, py + sin(a) * cell * k);
      w[n - 2] *= exp(follow * (lit / n - 1));
    }
    int which = pick(w);
    return which < 0 ? cell * 2 : cell * (which + 2);
  }

  // The picture's average colour under a form centred here, black where there is none.
  float[] behind(float px, float py, int r) {
    float[] sum = new float[3];
    if (shown == null) return sum;
    int count = 0;
    for (int dy = -r; dy <= r; dy++) {
      for (int dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy > r * r) continue;
        count++;
        int sx = int(px + dx - shownX), sy = int(py + dy - shownY);
        if (sx < 0 || sy < 0 || sx >= shown.width || sy >= shown.height) continue;
        int c = shown.pixels[sy * shown.width + sx];
        sum[0] += (c >> 16) & 255;
        sum[1] += (c >> 8) & 255;
        sum[2] += c & 255;
      }
    }
    for (int k = 0; k < 3; k++) sum[k] /= count;
    return sum;
  }

  // A new run is heavier or lighter, brighter or dimmer, than the one before.
  void vary(int i) {
    wob[i] = random(0.6, 1.5);
    shade[i] = random(-40, 15);
  }

  // The picture's colour at a point, black off it. White where there is no picture.
  int pictureAt(float px, float py) {
    if (shown == null) return 0xFFFFFF;
    int sx = int(px - shownX), sy = int(py - shownY);
    if (px < shownX || py < shownY || sx >= shown.width || sy >= shown.height) return 0;
    return shown.pixels[sy * shown.width + sx] & 0xFFFFFF;
  }

  // One channel of a line: white pulled towards the picture, then shaded, for walker i.
  float takeOn(int channel, int i) {
    return constrain(lerp(255, channel, take) + shade[i], 0, 255);
  }

  // A form is part clear, with a thin dim border.
  void drawForm(PGraphics g, float[] f) {
    float r = f[3] > 0.5 ? f[7] * 1.4 : f[7];
    g.stroke(170, 200);
    g.strokeWeight(lerp(thin, 0.6, lightAt(f[0], f[1])));
    g.fill(f[4], f[5], f[6], 150);
    if (f[3] > 0.5) {
      g.triangle(f[0] + cos(f[2]) * r, f[1] + sin(f[2]) * r,
          f[0] + cos(f[2] + TWO_PI / 3) * r, f[1] + sin(f[2] + TWO_PI / 3) * r,
          f[0] + cos(f[2] - TWO_PI / 3) * r, f[1] + sin(f[2] - TWO_PI / 3) * r);
    } else {
      g.ellipse(f[0], f[1], r * 2, r * 2);
    }
    g.noFill();
  }

  boolean inside(PGraphics g, float px, float py) {
    float m = mark * 2.2;
    return px > m && px < g.width - m && py > m && py < g.height - hudRows - m;
  }

  void draw(PGraphics out, float speed, float walkers, float diagonals, float triangles, float opacity) {
    PGraphics g = layer;
    g.beginDraw();
    int n = walkPaused ? 0 : round(lerp(1, max, walkers));
    float pace = lerp(1, 24, speed);
    g.stroke(255);
    g.strokeWeight(1);
    g.noFill();
    for (int i = 0; i < n; i++) {
      float todo = pace;
      for (int guard = 0; todo > 0 && guard < 64; guard++) {
        float d = min(min(todo, left[i]), cell / 2);
        float a = heading[i] * QUARTER_PI;
        float nx = x[i] + cos(a) * d, ny = y[i] + sin(a) * d;
        if (!inside(g, nx, ny)) {
          turn(g, i, diagonals, triangles, true);
          continue;
        }
        if (random(1) < grip * (1 - lightAt(nx, ny))) {
          turn(g, i, diagonals, triangles, false);
          continue;
        }
        float mx = (x[i] + nx) / 2, my = (y[i] + ny) / 2;
        int under = pictureAt(mx, my);
        g.stroke(takeOn((under >> 16) & 255, i), takeOn((under >> 8) & 255, i), takeOn(under & 255, i));
        g.strokeWeight(lerp(thin, 1, lightAt(mx, my)) * wob[i]);
        g.line(x[i], y[i], nx, ny);
        ink[at(mx, my)] += d / cell;
        x[i] = nx;
        y[i] = ny;
        left[i] -= d;
        todo -= d;
        if (left[i] < 0.001) turn(g, i, diagonals, triangles, false);
      }
    }
    g.noStroke();
    g.endDraw();

    // The forms go on their own layer, over the lines, so a line passes behind one.
    formLayer.beginDraw();
    for (float[] f : fresh) drawForm(formLayer, f);
    fresh.clear();
    formLayer.endDraw();

    out.background(0);
    if (shown != null && opacity > 0) {
      out.tint(255, opacity * 255);
      out.image(shown, shownX, shownY);
      out.noTint();
    }
    out.image(layer, 0, 0);
    out.image(formLayer, 0, 0);
  }

  // By 90 degrees or by 45, to the left or the right, the way with the most
  // room likelier. At a wall, towards somewhere that is not one.
  void turn(PGraphics g, int i, float diagonals, float triangles, boolean wall) {
    if (lightAt(x[i], y[i]) < 0.03) {
      // Out in the dark: set down again somewhere white.
      place(i, g.width, g.height - hudRows);
      heading[i] = int(random(8));
      left[i] = run();
      vary(i);
      return;
    }
    int[] turns = {1, -1, 2, -2, 3, -3, 4};
    float[] w = new float[turns.length];
    float[] room = new float[turns.length];
    float[] white = new float[turns.length];
    float least = 1e9, whitest = 0;
    for (int t = 0; t < turns.length; t++) {
      int by = abs(turns[t]);
      if (by > 2 && !wall) continue;
      float a = ((heading[i] + turns[t] + 8) % 8) * QUARTER_PI;
      if (!inside(g, x[i] + cos(a) * cell * 2, y[i] + sin(a) * cell * 2)) continue;
      room[t] = ahead(i, (heading[i] + turns[t] + 8) % 8);
      w[t] = by == 1 ? diagonals : by == 2 ? 1 - diagonals : by == 3 ? 0.15 : 0.05;
      if (w[t] > 0) {
        least = min(least, room[t]);
        white[t] = glow(i, (heading[i] + turns[t] + 8) % 8);
        whitest = max(whitest, white[t]);
      }
    }
    for (int t = 0; t < turns.length; t++) {
      if (w[t] > 0) w[t] *= exp(-sharp * (room[t] - least)) * exp(follow * (white[t] - whitest));
    }
    int which = pick(w);
    if (which < 0 && !wall) {
      turn(g, i, diagonals, triangles, true);
      return;
    }
    if (which < 0 && light != null) {
      // Nowhere white to go from here: set down again somewhere else.
      place(i, g.width, g.height - hudRows);
      heading[i] = int(random(8));
      left[i] = run();
      vary(i);
      return;
    }
    int next;
    if (which >= 0) {
      next = (heading[i] + turns[which] + 8) % 8;
    } else {
      // Cornered: back towards the middle.
      float toMiddle = atan2((g.height - hudRows) / 2.0 - y[i], g.width / 2.0 - x[i]);
      next = (round(toMiddle / QUARTER_PI) + 8) % 8;
    }
    heading[i] = next;
    float a = next * QUARTER_PI;
    left[i] = runFrom(g, x[i], y[i], a);
    vary(i);

    if (formsBetween(x[i], y[i], 0, mark * 3) > 0) return; // a form is here already
    // Half the size in black, one and a half in white, so the white is built up in larger pieces.
    float size = mark * (shown == null ? 1 : lerp(0.5, 1.5, lightAt(x[i], y[i])));
    float[] under = behind(x[i], y[i], ceil(size * 1.4));
    float[] f = {x[i], y[i], a, random(1) < triangles ? 1 : 0, under[0], under[1], under[2], size};
    formsIn.get(at(f[0], f[1])).add(f);
    fresh.add(f);
  }
}
