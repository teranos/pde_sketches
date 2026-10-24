// Four sketches, one shown at a time. The host owns which page is up and
// what its parameters are; this only draws them. Runner.java drives it
// headless: no window, the pixels go to ramen's frame file.

import processing.awt.PGraphicsJava2D;

String[] PAGES = {"particles", "lines", "startfield", "scene"};
String[][] NAMES = {
  {"count", "speed", "size"},
  {"count", "speed", "twist"},
  {"stars", "speed", "trail"},
  {"hue", "saturation", "scale"},
};
String[] KEYS = {"ML", "MC", "MR"};

PGraphics pg;
PFont font;
int page;
float[] p = {0.4, 0.3, 0.3};
boolean[] locked = new boolean[3];

Particles particles = new Particles();
Lines lines = new Lines();
Startfield startfield = new Startfield();
Scene scene = new Scene();

void resizeTo(int w, int h) {
  // createGraphics wants a primary surface to copy; headless there is none.
  pg = new PGraphicsJava2D();
  pg.setParent(this);
  pg.setPrimary(false);
  pg.setSize(w, h);
  pg.smooth(4);
  font = new PFont(new java.awt.Font("Monospaced", java.awt.Font.PLAIN, 14), true);
  pg.beginDraw();
  pg.background(6, 8, 14);
  pg.endDraw();
  particles.reset(w, h);
  startfield.reset(w, h);
  scene.resize(w, h);
}

void show(int next) {
  if (next != page && pg != null) {
    pg.beginDraw();
    pg.background(6, 8, 14);
    pg.endDraw();
  }
  page = next;
}

void setState(String name, float a, float b, float c, boolean la, boolean lb, boolean lc) {
  int next = java.util.Arrays.asList(PAGES).indexOf(name);
  if (next < 0 || next == 3) return;
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

int[] frame() {
  pg.beginDraw();
  if (page == 0) particles.draw(pg, p[0], p[1], p[2]);
  else if (page == 1) lines.draw(pg, p[0], p[1], p[2]);
  else if (page == 2) startfield.draw(pg, p[0], p[1], p[2]);
  else {
    pg.loadPixels();
    scene.draw(pg.pixels);
    pg.updatePixels();
  }
  hud(pg);
  pg.endDraw();
  pg.loadPixels();
  return pg.pixels;
}

// What is up and what the knob will move, so a frame shows its own state.
void hud(PGraphics g) {
  float s = 14;
  boolean sc = page == 3;
  float y0 = g.height - (sc ? 8 : 6) * s;
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

  float bw = (g.width - 4 * s) / 3;
  for (int i = 0; i < 3; i++) {
    float bx = s + i * (bw + s);
    boolean lit = live && locked[i];
    int dim = live ? color(150) : color(80);
    g.fill(lit ? on : dim);
    g.text(KEYS[i] + " " + NAMES[page][i], bx, by);
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
