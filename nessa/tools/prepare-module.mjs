import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { composedModule, moduleSeam } from "../../Vendor/Exact/host/apple/compose.mjs";
import { writeDataKeys } from "../../Vendor/Exact/host/apple/data-keys.mjs";
import manifest from "../app.json";

const output = resolve(import.meta.dir, "../.exact/apple-module");
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, "Composition.swift"), composedModule([], true));
writeDataKeys({ manifest }, resolve(output, "DataKeys.swift"), "ios");

for (const source of moduleSeam(resolve, resolve(import.meta.dir, "../../Vendor/Exact"))) {
  copyFileSync(source, resolve(output, basename(source)));
}
