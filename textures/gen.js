import * as gen from "./build/release.js";
import { renameSync, writeFileSync } from "node:fs";
import { createInterface } from "node:readline";

// One JSON job per line in, `done <id>` out once its file is whole. The
// file is renamed into place, so a reader never sees half of one.
const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  const job = JSON.parse(line);
  let px;
  if (job.kind === "sky") px = gen.sky(job.w, job.h, Float64Array.from(job.p));
  else if (["ground", "bark", "clouds", "ripples", "mist"].includes(job.kind))
    px = gen[job.kind](job.size, job.scale, job.seed);
  else return;
  writeFileSync(job.out + ".tmp", Buffer.from(px.buffer, px.byteOffset, px.byteLength));
  renameSync(job.out + ".tmp", job.out);
  process.stdout.write(`done ${job.id}\n`);
});
rl.on("close", () => process.exit(0));
// The renderer going away mid-job closes this pipe; that is the end, not a crash.
process.stdout.on("error", () => process.exit(0));
