import path from "node:path";
import { parseCtripCardTexts } from "../lib/ctrip-parser.mjs";
import { isoNow } from "../lib/normalize.mjs";

const commonCityIDs = new Map([
  ["北京", 1], ["上海", 2], ["天津", 3], ["重庆", 4], ["南京", 12],
  ["苏州", 14], ["杭州", 17], ["厦门", 25], ["深圳", 30], ["广州", 32],
  ["成都", 28], ["西安", 10], ["武汉", 477], ["青岛", 7], ["长沙", 206]
]);

export class CtripAdapter {
  name = "ctrip";

  async search(request) {
    if (process.env.CTRIP_SCRAPER_ENABLED !== "true") {
      return { quotes: [], diagnostics: [{ provider: this.name, status: "disabled" }] };
    }

    let playwright;
    try {
      playwright = await import("playwright");
    } catch (error) {
      return { quotes: [], diagnostics: [{ provider: this.name, status: "dependency_missing", detail: error.message }] };
    }

    const profileDir = path.resolve(process.cwd(), process.env.CTRIP_PROFILE_DIR || ".data/ctrip-profile");
    const context = await playwright.chromium.launchPersistentContext(profileDir, {
      headless: process.env.CTRIP_HEADLESS !== "false",
      locale: "zh-CN",
      viewport: { width: 1440, height: 1000 }
    });
    const page = context.pages()[0] || await context.newPage();

    try {
      const cityID = commonCityIDs.get(cleanCity(request.destination))
        ?? Number(process.env[`CTRIP_CITY_ID_${cleanCity(request.destination)}`]);
      if (!Number.isFinite(cityID)) {
        return { quotes: [], diagnostics: [{ provider: this.name, status: "city_id_missing" }] };
      }

      const url = buildListURL(request, cityID);
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 });
      if (page.url().includes("passport.ctrip.com")) {
        return {
          quotes: [],
          diagnostics: [{ provider: this.name, status: "login_required", loginURL: page.url() }]
        };
      }

      await page.waitForSelector(".list-item", { timeout: 18_000 });
      await page.waitForTimeout(2_000);
      const cardTexts = await page.locator(".list-item").evaluateAll((cards) =>
        cards.slice(0, 40).map((card) => card.innerText || "")
      );
      const capturedAt = isoNow();
      return {
        quotes: parseCtripCardTexts(cardTexts, request.hotels, page.url(), capturedAt),
        diagnostics: [{ provider: this.name, status: "ok", resultCount: cardTexts.length, capturedAt }]
      };
    } catch (error) {
      return { quotes: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    } finally {
      await context.close();
    }
  }
}

function cleanCity(value) {
  return String(value ?? "").replace(/市$/, "").trim();
}

function buildListURL(request, cityID) {
  const city = cleanCity(request.destination);
  const url = new URL("https://hotels.ctrip.com/hotels/list");
  const parameters = {
    flexType: "1",
    cityId: String(cityID),
    provinceId: "0",
    districtId: "0",
    countryId: "1",
    cityName: city,
    destName: city,
    searchType: "CT",
    optionId: String(cityID),
    checkin: request.checkIn,
    checkout: request.checkOut,
    crn: String(request.rooms || 1),
    curr: "CNY",
    locale: "zh-CN",
    old: "1"
  };
  for (const [key, value] of Object.entries(parameters)) url.searchParams.set(key, value);
  return url.href;
}
