import { chromium } from "playwright";
const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto("http://127.0.0.1:5182/", { waitUntil: "networkidle" });
await page.click(".primary-cta");
await page.waitForSelector(".composer input");
await page.fill(".composer input", "苏州");
await page.waitForSelector(".suggestion", { timeout: 30000 });
await page.click(".suggestion");
await page.waitForTimeout(600);
await page.click(".side-tab:has-text('条件')");
await page.waitForSelector("input[placeholder='比如：上海']");
await page.fill("input[placeholder='比如：上海']", "上海");
await page.click(".side-panel button.generate-btn");
for (let i = 0; i < 12; i++) {
  await page.waitForTimeout(6000);
  if (await page.locator(".rail-day").count() > 0) { console.log("PLAN OK at", (i+1)*6, "s"); break; }
  const note = await page.locator(".side-panel .issue-note").first().textContent().catch(() => "");
  if (note) { console.log("FAIL NOTE:", note?.slice(0, 240)); break; }
}
await browser.close();
