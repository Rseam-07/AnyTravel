import { readFileSync } from "node:fs";

const packageMetadata = JSON.parse(
  readFileSync(new URL("../package.json", import.meta.url), "utf8")
);

export const networkUserAgent =
  `AnyTravel-Companion/${packageMetadata.version} (+https://github.com/Rseam-07/AnyTravel)`;
