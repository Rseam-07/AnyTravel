import packageMetadata from "../package.json" with { type: "json" };

export const networkUserAgent =
  `AnyTravel-Companion/${packageMetadata.version} (+https://github.com/Rseam-07/AnyTravel)`;
