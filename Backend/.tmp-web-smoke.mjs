import { chromium } from "playwright";
const BASE = "http://127.0.0.1:5182/";
const shots = "/tmp/anytravel-web-shots";
import { mkdirSync } from "node:fs";
mkdirSync(shots, { recursive: true });
const report = [];
const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
page.on("pageerror", (err) => report.push(`[pageerror] ${String(err).slice(0, 200)}`));
page.on("console", (m) => { if (m.type() === "error") report.push(`[console.error] ${m.text().slice(0, 160)}`); });

await page.goto(BASE, { waitUntil: "networkidle" });
await page.waitForSelector(".welcome h1", { timeout: 15000 });
await page.screenshot({ path: `${shots}/v2-01-welcome.png` });
await page.click(".primary-cta");
await page.waitForSelector(".composer input", { timeout: 8000 });
if (!(await page.locator(".suggestion").count())) {
  await page.fill(".composer input", "苏州");
  await page.waitForSelector(".suggestion", { timeout: 20000 });
}
await page.click(".suggestion");
await page.waitForTimeout(600);
report.push("destination ok");

// Origin via conditions tab.
await page.click(".side-tab:has-text('条件')");
await page.waitForSelector("input[placeholder='比如：上海']");
await page.fill("input[placeholder='比如：上海']", "上海");
await page.click(".side-panel button.generate-btn");

await page.waitForSelector(".rail-day", { timeout: 150000 });
await page.click(".side-tab:has-text('方案')");
await page.waitForTimeout(1500);
await page.screenshot({ path: `${shots}/v2-02-plan.png` });
report.push(`plan days=${await page.locator(".rail-day").count()}`);

// Wait for quotes + auto-pick.
await page.waitForTimeout(14000);
const bodyText = await page.textContent("body");
report.push(`has auto-pick notice: ${bodyText.includes("已帮你预选")}`);
await page.screenshot({ path: `${shots}/v2-03-plan-prices.png` });

// Stay tab with collapsed channels.
await page.click(".side-tab:has-text('住宿')");
await page.waitForTimeout(1200);
const stayText = await page.textContent(".side-content");
report.push(`stay items: ${await page.locator(".stay-card").count()} / has price: ${(stayText ?? "").includes("/晚")}`);
await page.screenshot({ path: `${shots}/v2-04-stay.png` });

// Transport tab + origin button.
await page.click(".side-tab:has-text('交通')");
await page.waitForTimeout(800);
await page.screenshot({ path: `${shots}/v2-05-transport.png` });

// Budget.
await page.click(".side-tab:has-text('费用')");
await page.waitForTimeout(600);
await page.screenshot({ path: `${shots}/v2-06-budget.png` });

// Dark glass mode.
await page.click("button[title='切换地图样式']");
await page.waitForTimeout(2500);
await page.screenshot({ path: `${shots}/v2-07-dark.png` });
await page.click("button[title='切换地图样式']");
await page.waitForTimeout(800);

// Chat.
await page.click(".chat-fab");
await page.waitForSelector(".chat-panel input");
await page.fill(".chat-panel input", "改成2天，人均预算2000");
await page.press(".chat-panel input", "Enter");
await page.waitForTimeout(22000);
await page.screenshot({ path: `${shots}/v2-08-chat.png` });
report.push(`chat bubbles=${await page.locator(".chat-msg").count()}`);

// Mobile.
const mobile = await browser.newPage({ viewport: { width: 390, height: 844 } });
await mobile.goto(BASE, { waitUntil: "networkidle" });
await mobile.waitForSelector(".welcome h1", { timeout: 15000 });
await mobile.click(".primary-cta");
await mobile.waitForSelector(".mobile-sheet");
await mobile.waitForTimeout(6000);
await mobile.screenshot({ path: `${shots}/v2-09-mobile.png` });

await browser.close();
console.log(report.join("\n"));
