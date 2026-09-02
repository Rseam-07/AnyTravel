import path from "node:path";
import { parseTongchengCardTexts, parseTongchengCatalogCards } from "../lib/tongcheng-parser.mjs";
import { isoNow } from "../lib/normalize.mjs";
import { playwrightLaunchOptions } from "../lib/playwright-options.mjs";

const homeURL = "https://m.elong.com/hotel/";

export class TongchengAdapter {
  name = "tongcheng";

  async discover(request) {
    if (process.env.TONGCHENG_SCRAPER_ENABLED !== "true") {
      return { hotels: [], diagnostics: [{ provider: this.name, status: "disabled" }] };
    }
    const launched = await launchTongchengContext();
    if (launched.error) return { hotels: [], diagnostics: [launched.error] };
    const { context, page } = launched;
    try {
      const city = cleanCity(request.destination);
      const cityCode = await resolveCityCode(page, city);
      if (!cityCode) {
        return { hotels: [], diagnostics: [{ provider: this.name, status: "city_id_missing" }] };
      }
      const listURL = buildListURL(request, city, cityCode);
      await page.goto(listURL, { waitUntil: "domcontentloaded", timeout: 30_000 });
      await page.waitForTimeout(4_000);
      const bodyText = await page.locator("body").innerText().catch(() => "");
      if (/账号异常|安全验证|访问过于频繁|请完成验证/.test(bodyText)) {
        return {
          hotels: [],
          diagnostics: [{ provider: this.name, status: "verification_required", loginURL: page.url() }]
        };
      }
      const cards = await extractVisibleHotelCards(page, { includeUnpriced: true });
      const capturedAt = isoNow();
      const hotels = parseTongchengCatalogCards(cards, page.url(), capturedAt);
      const needsLogin = /登录查看(?:低价|价格)|登录后查看/.test(bodyText)
        && !hotels.some((hotel) => hotel.amountCNY != null);
      return {
        hotels,
        diagnostics: [{
          provider: this.name,
          status: needsLogin ? "login_required" : hotels.length ? "ok" : "no_visible_cards",
          resultCount: hotels.length,
          capturedAt,
          ...(needsLogin ? { loginURL: page.url() } : {})
        }]
      };
    } catch (error) {
      return { hotels: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    } finally {
      await context.close();
    }
  }

  async search(request) {
    if (process.env.TONGCHENG_SCRAPER_ENABLED !== "true") {
      return { quotes: [], diagnostics: [{ provider: this.name, status: "disabled" }] };
    }

    const launched = await launchTongchengContext();
    if (launched.error) return { quotes: [], diagnostics: [launched.error] };
    const { context, page } = launched;

    try {
      const city = cleanCity(request.destination);
      const cityCode = await resolveCityCode(page, city);
      if (!cityCode) {
        return { quotes: [], diagnostics: [{ provider: this.name, status: "city_id_missing" }] };
      }

      const listURL = buildListURL(request, city, cityCode);
      await page.goto(listURL, { waitUntil: "domcontentloaded", timeout: 30_000 });
      await page.waitForTimeout(4_000);
      const bodyText = await page.locator("body").innerText().catch(() => "");
      if (/账号异常|安全验证|访问过于频繁|请完成验证/.test(bodyText)) {
        return {
          quotes: [],
          diagnostics: [{ provider: this.name, status: "verification_required", loginURL: page.url() }]
        };
      }

      const cards = await extractVisibleHotelCards(page);
      const capturedAt = isoNow();
      const quotes = parseTongchengCardTexts(cards, request.hotels, page.url(), capturedAt);
      if (!quotes.length && /登录查看(?:低价|价格)|登录后查看/.test(bodyText)) {
        return {
          quotes: [],
          diagnostics: [{ provider: this.name, status: "login_required", loginURL: homeURL }]
        };
      }
      return {
        quotes,
        diagnostics: [{
          provider: this.name,
          status: quotes.length ? "ok" : "no_matching_quotes",
          resultCount: cards.length,
          capturedAt
        }]
      };
    } catch (error) {
      return { quotes: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    } finally {
      await context.close();
    }
  }
}

export function cleanTongchengCity(value) {
  return String(value ?? "").trim().replace(/市$/, "");
}

async function launchTongchengContext() {
  let playwright;
  try { playwright = await import("playwright"); }
  catch (error) {
    return { error: { provider: "tongcheng", status: "dependency_missing", detail: error.message } };
  }
  const profileDir = path.resolve(process.cwd(), process.env.TONGCHENG_PROFILE_DIR || ".data/tongcheng-profile");
  try {
    const context = await playwright.chromium.launchPersistentContext(profileDir, {
      headless: process.env.TONGCHENG_HEADLESS !== "false",
      locale: "zh-CN",
      viewport: { width: 390, height: 844 },
      ...playwrightLaunchOptions()
    });
    return { context, page: context.pages()[0] || await context.newPage() };
  } catch (error) {
    return { error: { provider: "tongcheng", status: "browser_unavailable", detail: error.message } };
  }
}

async function resolveCityCode(page, city) {
  await page.goto(homeURL, { waitUntil: "domcontentloaded", timeout: 30_000 });
  await page.waitForSelector(".city", { timeout: 15_000 });
  await page.locator(".city").click();
  const search = page.locator('input[placeholder*="城市"]').first();
  await search.waitFor({ state: "visible", timeout: 10_000 });
  await search.fill(city);
  await page.waitForTimeout(800);
  const exact = page.getByText(city, { exact: true }).first();
  if (!await exact.isVisible().catch(() => false)) return null;
  await exact.click();
  await page.waitForSelector(".hs-search-btn", { timeout: 10_000 });
  await page.waitForFunction(
    (expectedCity) => document.querySelector(".city")?.textContent?.trim() === expectedCity,
    city,
    { timeout: 10_000 }
  );
  // The public H5 page updates its visible label before its search-state store.
  // Give the observed UI transition time to settle before submitting.
  await page.waitForTimeout(1_000);
  await Promise.all([
    page.waitForURL(/\/hotel\/hotellist/, { timeout: 20_000 }).catch(() => {}),
    page.locator(".hs-search-btn").click()
  ]);
  try {
    const resultURL = new URL(page.url());
    if (resultURL.searchParams.get("cityName") !== city) return null;
    return resultURL.searchParams.get("city");
  } catch { return null; }
}

function buildListURL(request, city, cityCode) {
  const url = new URL("https://m.elong.com/hotel/hotellist");
  const parameters = {
    city: cityCode,
    cityName: city,
    inDate: request.checkIn,
    outDate: request.checkOut,
    pageSize: "30",
    resourceType: "1",
    ch: "h5_hotel_02"
  };
  for (const [key, value] of Object.entries(parameters)) url.searchParams.set(key, String(value));
  return url.href;
}

function cleanCity(value) {
  return cleanTongchengCity(value);
}

async function extractVisibleHotelCards(page, options = {}) {
  const includeUnpriced = options.includeUnpriced === true;
  return page.locator("body").evaluate((body, includeUnpriced) => {
    const selectors = [
      "[class*=hotel-item]", "[class*=hotelItem]", "[class*=hotel-card]",
      "[class*=list-item]", "[class*=listItem]", "article", "li"
    ];
    const nodes = [...new Set(selectors.flatMap((selector) => [...body.querySelectorAll(selector)]))];
    const qualifies = (node) => {
      const text = (node.innerText || "").trim();
      return text.length >= 8 && text.length <= 1_200
        && /酒店|宾馆|旅馆|客栈|民宿|公寓/.test(text)
        && (includeUnpriced || /[¥￥]\s*\d{2,}/.test(text) || /登录查看(?:低价|价格)/.test(text));
    };
    let cards = nodes.filter(qualifies);
    if (!cards.length) {
      cards = [...body.querySelectorAll("div,a,section")]
        .filter(qualifies)
        .filter((node) => ![...node.children].some(qualifies));
    }
    const seen = new Set();
    return cards.map((node) => {
      const text = (node.innerText || "").trim();
      const anchor = node.matches("a") ? node : node.querySelector("a[href]");
      const href = anchor?.href || null;
      return { text, href };
    }).filter((card) => {
      const key = card.text.replace(/\s+/g, " ");
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    }).slice(0, 60);
  }, includeUnpriced);
}
