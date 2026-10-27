/** Exercise the Swift phone in the gateway stress driver's loaded conversation. */
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";

const gateway = resolve(process.argv[2] ?? ".");
const evidence = resolve(process.argv[3] ?? "verification/phone-file-stress");
const { KNOBS } = await import(
  pathToFileURL(
    join(gateway, "verification/desktop/scripts/lib/stress-plan.mjs"),
  )
);
const driver = join(
  gateway,
  "verification/desktop/scripts/conversation-stress.mjs",
);
mkdirSync(evidence, { recursive: true });
// The driver owns async teardown. CI owns the process-tree budget; killing
// only the driver leader on a local timeout can strand its owned children.
function run(args) {
  const result = spawnSync(
    process.execPath,
    [driver, "--channel", "bundled", ...args],
    {
      cwd: gateway,
      env: process.env,
      stdio: "inherit",
    },
  );
  if (result.error || result.status !== 0) {
    throw new Error(
      `Phone stress failed: ${result.error?.message ?? result.status}`,
    );
  }
}
// Default plan retains every surrounding feature and background conversation.
run([
  "--evidence",
  join(evidence, "default"),
  "--out",
  join(evidence, "default.json"),
]);
const zero = Object.keys(KNOBS)
  .filter((key) => key !== "seed")
  .flatMap((key) => [`--${key}`, "0"]);
// Repeat the new path while real background turns and followers continue.
run([
  ...zero,
  "--engine",
  "chromium,webkit",
  "--seed",
  "1149",
  "--inputFiles",
  "3",
  "--parallel",
  "2",
  "--turns",
  "3",
  "--followers",
  "1",
  "--evidence",
  join(evidence, "raised"),
  "--out",
  join(evidence, "raised.json"),
]);
