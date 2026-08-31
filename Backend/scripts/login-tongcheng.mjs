import path from "node:path";
import process from "node:process";
import { chromium } from "playwright";
import { playwrightLaunchOptions } from "../src/lib/playwright-options.mjs";

const profileDir = path.resolve(process.cwd(), process.env.TONGCHENG_PROFILE_DIR || ".data/tongcheng-profile");
const context = await chromium.launchPersistentContext(profileDir, {
  headless: false,
  locale: "zh-CN",
  viewport: { width: 430, height: 900 },
  ...playwrightLaunchOptions()
});
const page = context.pages()[0] || await context.newPage();
await page.goto("https://m.elong.com/hotel/", { waitUntil: "domcontentloaded" });
process.stdout.write("请在打开的同程/艺龙页面完成本人账号登录。完成后回到终端按回车保存本地会话。\n");
await new Promise((resolve) => process.stdin.once("data", resolve));
await context.close();
process.stdout.write(`本地会话已保存到 ${profileDir}\n`);
