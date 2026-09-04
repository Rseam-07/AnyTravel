// Validates the guide knowledge base before it feeds the planner.
// Usage: node scripts/validate-knowledge.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const citiesJson = JSON.parse(readFileSync(join(root, "src/knowledge/cities.json"), "utf8"));
const rulesJson = JSON.parse(readFileSync(join(root, "src/knowledge/rules.json"), "utf8"));
const domesticJson = JSON.parse(readFileSync(join(root, "src/knowledge/raw/region-domestic-completion.json"), "utf8"));

const errors = [];
const cities = citiesJson.cities ?? [];
const rules = rulesJson.rules ?? [];

if (!Array.isArray(cities) || cities.length < 150) errors.push(`城市不足：${cities.length}（要求 ≥150）`);
if (!Array.isArray(rules) || rules.length < 12) errors.push(`规则不足：${rules.length}（要求 ≥12）`);
const chinaCities = cities.filter((city) => city.country === "中国");
if (chinaCities.length < 135) errors.push(`国内目的地不足：${chinaCities.length}（要求 ≥135）`);

const harvestedDomestic = domesticJson.cities ?? [];
if (harvestedDomestic.length < 84) errors.push(`本轮国内补库不足：${harvestedDomestic.length}（要求 ≥84）`);
const blockedDomesticName = /游客(服务)?中心|服务区|售票处|停车场|机场|火车站|汽车站|地铁站|高速公路|环线高速|公司|集团|苏宁|恒隆广场|万象城|太古里|印象城|银泰城|大悦城|来福士|购物中心|商场|事件|案件|打人|袭击|疫情|爆炸|事故|灾害|火灾|踩踏|太湖之光/;
for (const city of harvestedDomestic) {
  for (const place of city.places ?? []) {
    if (blockedDomesticName.test(place.name ?? "")) errors.push(`${city.city}/${place.name} 像设施、商业体或事件，不应进入景点库`);
  }
}

const requiredAnchors = new Map([
  ["上海", /外滩/], ["苏州", /拙政园/], ["杭州", /西湖/], ["成都", /杜甫草堂|武侯祠/],
  ["重庆", /洪崖洞/], ["西安", /兵马俑/], ["拉萨", /布达拉宫/],
  ["乌鲁木齐", /天池|新疆维吾尔自治区博物馆/], ["清远", /连州地下河|古龙峡/], ["中山", /孙中山/],
  ["唐山", /南湖|开滦/], ["本溪", /五女山/], ["白城", /嫩江湾/], ["连云港", /连岛/],
  ["丽水", /云和梯田/], ["黄冈", /麻城龟峰山/], ["河源", /万绿湖/], ["柳州", /程阳八寨/],
  ["腾冲", /和顺古镇/], ["甘南", /冶力关/], ["吴忠", /青铜峡黄河大峡谷/],
  ["齐齐哈尔", /扎龙/], ["阿克苏", /天山托木尔/]
]);
for (const [cityName, pattern] of requiredAnchors) {
  const city = cities.find((candidate) => candidate.city === cityName);
  if (!city || !city.places.some((place) => pattern.test(place.name))) errors.push(`${cityName} 缺少代表性地标`);
}

let places = 0;
let sources = new Set();
const categorySet = new Set([
  "园林", "古迹", "古镇", "宗教", "博物馆", "美术馆", "科技馆", "自然", "山水", "海滨",
  "公园", "亲子", "乐园", "动物园", "美食", "美食街", "夜游", "夜景", "城市", "购物", "剧院"
]);

for (const city of cities) {
  if (!city.city) errors.push("存在缺 city 的条目");
  if (!Array.isArray(city.places) || city.places.length < 3) {
    errors.push(`${city.city ?? "?"} 景点不足`);
    continue;
  }
  places += city.places.length;
  const tiers = new Set(city.places.map((p) => p.tier));
  if (!tiers.has("必去")) errors.push(`${city.city} 缺少“必去”档`);
  for (const p of city.places) {
    if (!p.name) errors.push(`${city.city} 有缺失名称的景点`);
    if (p.coord && (Math.abs(p.coord.lat) > 85 || Math.abs(p.coord.lng) > 200)) {
      errors.push(`${city.city}/${p.name} 坐标越界`);
    }
    if (p.category && !categorySet.has(p.category)) errors.push(`${city.city}/${p.name} 类别“${p.category}”不在清单`);
    if (!["必去", "推荐", "顺路"].includes(p.tier)) errors.push(`${city.city}/${p.name} tier 非法`);
  }
  for (const src of city.sources ?? []) sources.add(src);
}

for (const rule of rules) {
  if (!rule.rule || !rule.basis) errors.push("存在缺 rule/basis 的规则条目");
}

const summary = {
  cityCount: cities.length,
  placeCount: places,
  ruleCount: rules.length,
  sourceCount: sources.size,
  sources: sources.size >= 200 ? "达标（≥200）" : `不足（${sources.size}）`
};
console.log("知识库校验：", JSON.stringify(summary, null, 2));
if (errors.length > 0) {
  console.error("问题清单（前 20 条）：");
  for (const error of errors.slice(0, 20)) console.error(` - ${error}`);
  process.exit(1);
}
console.log("校验通过 ✓");
