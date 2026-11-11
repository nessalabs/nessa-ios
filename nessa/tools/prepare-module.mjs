import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { composedModule } from "../../Vendor/Exact/host/apple/compose.mjs";
import { writeDataKeys } from "../../Vendor/Exact/host/apple/data-keys.mjs";
import manifest from "../app.json";

const output = resolve(import.meta.dir, "../.exact/apple-module");
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, "Composition.swift"), composedModule([], true));
writeDataKeys({ manifest }, resolve(output, "DataKeys.swift"), "ios");
