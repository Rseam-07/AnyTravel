import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { readFileSync } from "node:fs";

const defaults = JSON.parse(readFileSync(new URL("../Config/ServiceDefaults.json", import.meta.url), "utf8"));

export default defineConfig({
  base: "./",
  // Only explicitly public variables can enter browser bundles.
  envPrefix: "ANYTRAVEL_PUBLIC_",
  plugins: [react(), {
    name: "anytravel-offline-assets",
    generateBundle(_options, bundle) {
      this.emitFile({ type: "asset", fileName: "offline-assets.json", source: JSON.stringify(
        Object.keys(bundle).filter(file => /^assets\/.*\.(?:js|css)$/.test(file)).map(file => `./${file}`)
      ) });
    }
  }],
  define: {
    __ANYTRAVEL_SERVICE_URL__: JSON.stringify(process.env.ANYTRAVEL_SERVICE_URL || defaults.serviceBaseURL || "")
  },
  server: {
    port: 5182,
    host: "127.0.0.1",
    proxy: {
      "/health": "http://127.0.0.1:8787",
      "/v1": "http://127.0.0.1:8787"
    }
  },
  preview: {
    port: 5183,
    host: "127.0.0.1"
  }
});
