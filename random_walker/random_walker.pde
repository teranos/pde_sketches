// Random walker: white lines on black, forms black inside and over the lines.
// R starts over.

Walker walker = new Walker();

void setup() {
  size(900, 600);
  walker.reset();
}

void draw() {
  // speed, walkers, diagonals, triangles
  walker.draw(0.4, 0.5, 0.5, 0.3);
}

void keyPressed() {
  if (key == 'r') walker.reset();
}

class Walker {
  int count = 24;
  float[] x;
  float[] y;
  int[] heading; // in 45 degree steps, 0 is east, turning clockwise
  float[] togo; // what is left of the run, in pixels
  float cell = 12; // a run is a few of these
  float mark = 5; // the radius of what a turn leaves
  float sharp = 0.5; // how hard a crowded way is avoided
  int cols;
  int rows;
  float[] ink; // per cell, the length of line drawn in it, in cells
  int maxForms = 6000;
  int forms;
  float[] formX;
  float[] formY;
  float[] formA;
  int[] formTriangle; // 1 for a triangle, 0 for a ring
  int[] formNext; // the next form in the same cell, -1 for none
  int[] firstForm; // per cell, its first form, -1 for none
  int[] formsHere; // per cell, how many

  void reset() {
    background(0);
    cols = ceil(width / cell);
    rows = ceil(height / cell);
    ink = new float[cols * rows];
    firstForm = new int[cols * rows];
    formsHere = new int[cols * rows];
    for (int c = 0; c < cols * rows; c++) {
      firstForm[c] = -1;
    }
    forms = 0;
    formX = new float[maxForms];
    formY = new float[maxForms];
    formA = new float[maxForms];
    formTriangle = new int[maxForms];
    formNext = new int[maxForms];
    x = new float[count];
    y = new float[count];
    heading = new int[count];
    togo = new float[count];
    for (int i = 0; i < count; i++) {
      x[i] = width / 2;
      y[i] = height / 2;
      heading[i] = int(random(8));
      togo[i] = run();
    }
  }

  float run() {
    return cell * int(random(2, 12));
  }

  int at(float px, float py) {
    return constrain(int(py / cell), 0, rows - 1) * cols + constrain(int(px / cell), 0, cols - 1);
  }

  boolean inside(float px, float py) {
    float m = mark * 1.5;
    return px > m && px < width - m && py > m && py < height - m;
  }

  // What is down around a point: the line in its cell and in the ones next
  // to it, and each form there.
  float crowd(float px, float py) {
    int cx = int(px / cell);
    int cy = int(py / cell);
    if (px < 0 || py < 0 || cx >= cols || cy >= rows) return 2;
    float sum = 0;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        int ax = cx + dx;
        int ay = cy + dy;
        if (ax < 0 || ay < 0 || ax >= cols || ay >= rows) continue;
        int c = ay * cols + ax;
        sum += min(ink[c], 2) * (dx == 0 && dy == 0 ? 1 : 0.4) + 2 * formsHere[c];
      }
    }
    return sum;
  }

  // How crowded the way is ahead, going heading h from where walker i is.
  float ahead(int i, int h) {
    float a = h * QUARTER_PI;
    float sum = 0;
    for (int k = 2; k <= 9; k++) {
      sum += crowd(x[i] + cos(a) * cell * k, y[i] + sin(a) * cell * k);
    }
    return sum;
  }

  // How many forms have their centre between lo and hi from a point.
  int formsBetween(float px, float py, float lo, float hi) {
    int cx = max(int(px / cell), 0);
    int cy = max(int(py / cell), 0);
    int r = ceil(hi / cell);
    int found = 0;
    for (int ay = max(cy - r, 0); ay <= min(cy + r, rows - 1); ay++) {
      for (int ax = max(cx - r, 0); ax <= min(cx + r, cols - 1); ax++) {
        for (int f = firstForm[ay * cols + ax]; f >= 0; f = formNext[f]) {
          float away = dist(px, py, formX[f], formY[f]);
          if (away >= lo && away < hi) found++;
        }
      }
    }
    return found;
  }

  // An index chosen by weight, -1 when nothing has any.
  int pick(float[] w) {
    float total = 0;
    for (int k = 0; k < w.length; k++) {
      total += w[k];
    }
    if (total <= 0) return -1;
    float r = random(total);
    for (int k = 0; k < w.length; k++) {
      r -= w[k];
      if (r < 0) return k;
    }
    return w.length - 1;
  }

  // Two to eleven cells, the ones that end by a form likelier, none that end on one.
  float runFrom(float px, float py, float a) {
    float[] w = new float[10];
    for (int n = 2; n <= 11; n++) {
      float ex = px + cos(a) * cell * n;
      float ey = py + sin(a) * cell * n;
      if (!inside(ex, ey)) continue;
      w[n - 2] = formsBetween(ex, ey, 0, mark * 3) > 0 ? 0.1 : formsBetween(ex, ey, mark * 3, cell * 4) > 0 ? 5 : 1;
    }
    int which = pick(w);
    return which < 0 ? cell * 2 : cell * (which + 2);
  }

  void drawForm(int f) {
    fill(0);
    if (formTriangle[f] == 1) {
      float r = mark * 1.4;
      float a = formA[f];
      triangle(formX[f] + cos(a) * r, formY[f] + sin(a) * r,
          formX[f] + cos(a + TWO_PI / 3) * r, formY[f] + sin(a + TWO_PI / 3) * r,
          formX[f] + cos(a - TWO_PI / 3) * r, formY[f] + sin(a - TWO_PI / 3) * r);
    } else {
      ellipse(formX[f], formY[f], mark * 2, mark * 2);
    }
    noFill();
  }

  // The forms near a point are drawn again, over the line that just ran there.
  void cover(float px, float py) {
    int cx = int(px / cell);
    int cy = int(py / cell);
    for (int ay = max(cy - 1, 0); ay <= min(cy + 1, rows - 1); ay++) {
      for (int ax = max(cx - 1, 0); ax <= min(cx + 1, cols - 1); ax++) {
        for (int f = firstForm[ay * cols + ax]; f >= 0; f = formNext[f]) {
          if (dist(px, py, formX[f], formY[f]) < mark * 2.4) drawForm(f);
        }
      }
    }
  }

  void draw(float speed, float walkers, float diagonals, float triangles) {
    int n = round(lerp(1, count, walkers));
    float pace = lerp(1, 24, speed);
    stroke(255);
    strokeWeight(1);
    noFill();
    for (int i = 0; i < n; i++) {
      float todo = pace;
      for (int guard = 0; todo > 0 && guard < 64; guard++) {
        float d = min(min(todo, togo[i]), cell / 2);
        float a = heading[i] * QUARTER_PI;
        float nx = x[i] + cos(a) * d;
        float ny = y[i] + sin(a) * d;
        if (!inside(nx, ny)) {
          turn(i, diagonals, triangles, true);
          continue;
        }
        line(x[i], y[i], nx, ny);
        ink[at((x[i] + nx) / 2, (y[i] + ny) / 2)] += d / cell;
        cover((x[i] + nx) / 2, (y[i] + ny) / 2);
        x[i] = nx;
        y[i] = ny;
        togo[i] -= d;
        todo -= d;
        if (togo[i] < 0.001) turn(i, diagonals, triangles, false);
      }
    }
  }

  // By 90 degrees or by 45, to the left or the right, the way with the most
  // room likelier. At a wall, towards somewhere that is not one.
  void turn(int i, float diagonals, float triangles, boolean wall) {
    int[] turns = {1, -1, 2, -2, 3, -3, 4};
    float[] w = new float[7];
    float[] room = new float[7];
    float least = 1e9;
    for (int t = 0; t < 7; t++) {
      int by = abs(turns[t]);
      if (by > 2 && !wall) continue;
      int h = (heading[i] + turns[t] + 8) % 8;
      float a = h * QUARTER_PI;
      if (!inside(x[i] + cos(a) * cell * 2, y[i] + sin(a) * cell * 2)) continue;
      room[t] = ahead(i, h);
      w[t] = by == 1 ? diagonals : by == 2 ? 1 - diagonals : by == 3 ? 0.15 : 0.05;
      if (w[t] > 0) least = min(least, room[t]);
    }
    for (int t = 0; t < 7; t++) {
      if (w[t] > 0) w[t] *= exp(-sharp * (room[t] - least));
    }
    int which = pick(w);
    if (which < 0 && !wall) {
      turn(i, diagonals, triangles, true);
      return;
    }
    int next;
    if (which >= 0) {
      next = (heading[i] + turns[which] + 8) % 8;
    } else {
      // Cornered: back towards the middle.
      float toMiddle = atan2(height / 2.0 - y[i], width / 2.0 - x[i]);
      next = (round(toMiddle / QUARTER_PI) + 8) % 8;
    }
    heading[i] = next;
    float a = next * QUARTER_PI;
    togo[i] = runFrom(x[i], y[i], a);

    // A form is here already, or there is no room for another.
    if (formsBetween(x[i], y[i], 0, mark * 2) > 0 || forms >= maxForms) return;
    int f = forms;
    forms++;
    int c = at(x[i], y[i]);
    formX[f] = x[i];
    formY[f] = y[i];
    formA[f] = a;
    formTriangle[f] = random(1) < triangles ? 1 : 0;
    formNext[f] = firstForm[c];
    firstForm[c] = f;
    formsHere[c]++;
    drawForm(f);
  }
}
