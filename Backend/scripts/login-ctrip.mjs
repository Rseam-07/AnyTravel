import path from "node:path";
import process from "node:process";
import { chromium } from "playwright";

const profileDir = path.resolve(process.cwd(), process.env.CTRIP_PROFILE_DIR || ".data/ctrip-profile");
const context = await chromium.launchPersistentContext(profileDir, {
  headless: false,
  locale: "zh-CN",
  viewport: { width: 1440, height: 1000 }
});
const page = context.pages()[0] || await context.newPage();
await page.goto("https://passport.ctrip.com/user/login", { waitUntil: "domcontentloaded" });
process.stdout.write("请在打开的携程页面完成登录。完成后回到终端按回车保存本地会话。\n");
await new Promise((resolve) => process.stdin.once("data", resolve));
await context.close();
process.stdout.write(`本地会话已保存到 ${profileDir}\n`);
