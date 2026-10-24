import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.RandomAccessFile;
import java.nio.ByteOrder;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.util.concurrent.ConcurrentLinkedQueue;

/// The sketch, headless. Lines on stdin (`size w h`, `state ...`) set what
/// it draws; each frame goes into ramen's frame file, and `f` on stdout says
/// it is in. stdin closing is the end.
public class Runner {
  static final int MAGIC = 0x54484752; // "RGHT", little-endian
  static final int HEADER = 32;
  static final int SLOTS = 2;

  public static void main(String[] args) throws Exception {
    String path = args[0];
    pages s = new pages();
    ConcurrentLinkedQueue<String> in = new ConcurrentLinkedQueue<>();
    Thread reader = new Thread(() -> {
      try (BufferedReader r = new BufferedReader(new InputStreamReader(System.in))) {
        for (String line; (line = r.readLine()) != null; ) in.add(line);
      } catch (Exception e) {
      }
      System.exit(0);
    });
    reader.setDaemon(true);
    reader.start();

    RandomAccessFile file = new RandomAccessFile(path, "rw");
    MappedByteBuffer map = null;
    int w = 0, h = 0, seq = 0;
    final long frameNanos = 1_000_000_000L / 30;

    for (;;) {
      long start = System.nanoTime();
      for (String line; (line = in.poll()) != null; ) {
        String[] f = line.trim().split(" ");
        if (f[0].equals("size") && f.length == 3) {
          w = Integer.parseInt(f[1]);
          h = Integer.parseInt(f[2]);
          // Never shrink: ramen may still have the longer file mapped.
          long need = HEADER + (long) SLOTS * w * h * 4;
          if (file.length() < need) file.setLength(need);
          map = file.getChannel().map(FileChannel.MapMode.READ_WRITE, 0, file.length());
          map.order(ByteOrder.LITTLE_ENDIAN);
          s.resizeTo(w, h);
        } else if (f[0].equals("scene") && f.length > 5 && (f.length - 5) % 6 == 0) {
          // scene <time> <running> <thing> <locked>, then values and locks, three per thing
          int k = (f.length - 5) / 2;
          float[] vals = new float[k];
          boolean[] locks = new boolean[k];
          for (int i = 0; i < k; i++) {
            vals[i] = Float.parseFloat(f[5 + i]);
            locks[i] = f[5 + k + i].equals("1");
          }
          s.setScene(Float.parseFloat(f[1]), f[2].equals("1"), Integer.parseInt(f[3]), f[4].equals("1"), vals, locks);
        } else if (f[0].equals("state") && f.length == 8) {
          s.setState(f[1], Float.parseFloat(f[2]), Float.parseFloat(f[3]), Float.parseFloat(f[4]),
              f[5].equals("1"), f[6].equals("1"), f[7].equals("1"));
        } else if (f[0].equals("walker") && f.length == 11) {
          // walker <speed> <three values> <three locks> <image opacity> <image held> <paused>
          s.setWalker(Float.parseFloat(f[1]), Float.parseFloat(f[2]), Float.parseFloat(f[3]), Float.parseFloat(f[4]),
              f[5].equals("1"), f[6].equals("1"), f[7].equals("1"), Float.parseFloat(f[8]), f[9].equals("1"), f[10].equals("1"));
        } else if (f[0].equals("reset")) {
          s.resetWalk();
        } else if (f[0].equals("snapshot")) {
          s.snapshot();
        }
      }
      if (map != null) {
        int[] px = s.frame();
        int next = seq + 1;
        // Into the slot not on screen, then the header, sequence last.
        map.position(HEADER + (next % SLOTS) * w * h * 4);
        map.slice().order(ByteOrder.LITTLE_ENDIAN).asIntBuffer().put(px, 0, w * h);
        map.putInt(0, MAGIC);
        map.putInt(4, w);
        map.putInt(8, h);
        map.putInt(16, SLOTS);
        map.putInt(12, next);
        seq = next;
        System.out.println("f");
        System.out.flush();
      }
      long left = frameNanos - (System.nanoTime() - start);
      if (left > 0) Thread.sleep(left / 1_000_000, (int) (left % 1_000_000));
    }
  }
}
