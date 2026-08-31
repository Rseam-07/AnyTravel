import { chromium } from "../../Backend/node_modules/playwright/index.mjs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";

const root = new URL(".", import.meta.url).pathname;
const concepts = [
  ["迁徙轨迹", "migratory-path.svg"],
  ["折叠远方", "folded-horizon.svg"],
  ["河流罗盘", "river-compass.svg"]
];
const sizes = [40, 60, 120, 256];
const rows = [];

for (const [title, filename] of concepts) {
  const svg = await readFile(path.join(root, "Concepts", filename), "utf8");
  const marks = sizes.map(size => `<figure><div class="mark" style="width:${size}px;height:${size}px">${svg}</div><figcaption>${size}px</figcaption></figure>`).join("");
  rows.push(`<section><h2>${title}</h2><div class="row">${marks}</div></section>`);
}

const html = `<!doctype html><meta charset="utf-8"><style>
*{box-sizing:border-box}body{margin:0;padding:34px;background:#ecf1ef;color:#122421;font:14px -apple-system,BlinkMacSystemFont,sans-serif}
h1{font-size:24px;margin:0 0 26px}section{background:#fff;border-radius:24px;padding:22px 26px;margin:0 0 22px}h2{font-size:17px;margin:0 0 18px}.row{display:flex;align-items:flex-end;gap:30px}.mark{overflow:hidden;border-radius:22.5%;box-shadow:0 8px 24px #1234}.mark svg{display:block;width:100%;height:100%}figure{margin:0;text-align:center}figcaption{color:#66736f;margin-top:8px}
</style><h1>AnyTravel · 应用图标缩放检查</h1>${rows.join("")}`;
await writeFile(path.join(root, "icon-contact-sheet.html"), html);
await mkdir(path.join(root, "Exports"), { recursive: true });

const browser = await chromium.launch({
  headless: true,
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
});
const page = await browser.newPage({ viewport: { width: 1100, height: 1250 }, deviceScaleFactor: 1 });
await page.goto(`file://${path.join(root, "icon-contact-sheet.html")}`);
await page.screenshot({ path: path.join(root, "icon-contact-sheet.png"), fullPage: true });

for (const [, filename] of concepts) {
  const svg = await readFile(path.join(root, "Concepts", filename), "utf8");
  await page.setViewportSize({ width: 1024, height: 1024 });
  await page.setContent(`<style>*{margin:0}svg{display:block;width:1024px;height:1024px}</style>${svg}`);
  await page.screenshot({ path: path.join(root, "Exports", filename.replace(".svg", ".png")) });
}
await browser.close();
