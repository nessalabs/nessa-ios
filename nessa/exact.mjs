#!/usr/bin/env bun
import { resolve } from "node:path";

const sdk = resolve(import.meta.dir, "../Vendor/Exact");
const { run } = await import(resolve(sdk, "scripts/app-cli.mjs"));
process.exit(await run({ dir: import.meta.dir, name: "nessa", exact2: sdk, args: process.argv.slice(2) }));
