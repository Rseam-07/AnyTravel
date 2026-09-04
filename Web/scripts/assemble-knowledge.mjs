// Assembles raw harvested region files into the knowledge base.
// Usage: node scripts/assemble-knowledge.mjs

import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const rawDir = join(root, "src/knowledge/raw");
const outCities = join(root, "src/knowledge/cities.json");
const outRules = join(root, "src/knowledge/rules.json");

if (!existsSync(rawDir)) {
  console.error("raw 目录不存在:", rawDir);
  process.exit(1);
}

const files = readdirSync(rawDir).filter((f) => f.endsWith(".json"));
const cities = [];
const rules = [];
const sources = new Set();
let places = 0;

for (const file of files) {
  const payload = JSON.parse(readFileSync(join(rawDir, file), "utf8"));
  for (const city of payload.cities ?? []) {
    if (!city || !city.city || !Array.isArray(city.places) || city.places.length === 0) continue;
    cities.push(city);
    places += city.places.length;
    for (const src of city.sources ?? []) sources.add(src);
  }
  for (const rule of payload.rules ?? []) {
    if (rule && rule.rule && rule.basis) rules.push(rule);
  }
}

// Dedupe cities by name (keep the entry with more places).
const byName = new Map();
for (const city of cities) {
  const existing = byName.get(city.city);
  if (!existing || city.places.length > existing.places.length) byName.set(city.city, city);
}
const finalCities = [...byName.values()].sort((a, b) => a.city.localeCompare(b.city, "zh-CN"));

const citiesDoc = {
  version: "2026-09-04.0",
  harvestedAt: new Date().toISOString(),
  sourceCount: sources.size,
  cityCount: finalCities.length,
  cities: finalCities
};
const rulesDoc = {
  version: "2026-09-04.0",
  harvestedAt: new Date().toISOString(),
  ruleCount: rules.length,
  rules
};

writeFileSync(outCities, JSON.stringify(citiesDoc, null, 1));
writeFileSync(outRules, JSON.stringify(rulesDoc, null, 1));
const repositoryRoot = join(root, "..");
const platformCopies = [
  join(repositoryRoot, "AnyTravel/Resources/DomesticGuideKnowledge.json"),
  join(repositoryRoot, "Android/app/src/main/assets/domestic_guide_knowledge.json")
];
for (const target of platformCopies) {
  mkdirSync(dirname(target), { recursive: true });
  copyFileSync(outCities, target);
}
console.log(
  `汇编完成：城市 ${finalCities.length}，景点 ${places}，城市级规则 ${rules.length}，去重后来源 ${sources.size}`
);
console.log(`raw 文件：${files.join(", ")}`);
console.log(`已同步 iOS / Android 内置目的地资料。`);
