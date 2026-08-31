import path from "node:path";
import { parseCtripCardTexts, selectCtripHotelSuggestion } from "../lib/ctrip-parser.mjs";
import { isoNow } from "../lib/normalize.mjs";
import { playwrightLaunchOptions } from "../lib/playwright-options.mjs";

const commonCityIDs = new Map([
  ["北京", 1], ["上海", 2], ["天津", 3], ["重庆", 4], ["南京", 12],
  ["苏州", 14], ["杭州", 17], ["厦门", 25], ["深圳", 30], ["广州", 32],
  ["成都", 28], ["西安", 10], ["武汉", 477], ["青岛", 7], ["长沙", 206]
]);
const hotelSuggestURL = "https://m.ctrip.com/restapi/soa2/21881/json/gaHotelSearchEngine";
const maximumTargetedHotels = 8;

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
    let context;
    try {
      context = await playwright.chromium.launchPersistentContext(profileDir, {
        headless: process.env.CTRIP_HEADLESS !== "false",
        locale: "zh-CN",
        viewport: { width: 1440, height: 1000 },
        ...playwrightLaunchOptions()
      });
    } catch (error) {
      return {
        quotes: [],
        diagnostics: [{ provider: this.name, status: "browser_unavailable", detail: error.message }]
      };
    }
    const page = context.pages()[0] || await context.newPage();

    try {
      const cityID = commonCityIDs.get(cleanCity(request.destination))
        ?? Number(process.env[`CTRIP_CITY_ID_${cleanCity(request.destination)}`]);
      if (!Number.isFinite(cityID)) {
        return { quotes: [], diagnostics: [{ provider: this.name, status: "city_id_missing" }] };
      }

      const requestedHotels = request.hotels.slice(0, maximumTargetedHotels);
      const suggestions = await Promise.all(
        requestedHotels.map((hotel) => resolveHotelSuggestion(hotel, cityID))
      );
      const targets = suggestions
        .map((suggestion, index) => suggestion ? { suggestion, hotel: requestedHotels[index] } : null)
        .filter(Boolean);

      const capturedAt = isoNow();
      const quotes = [];
      let resultCount = 0;
      let loginURL = null;
      let verificationURL = null;

      const searches = targets.length
        ? targets
        : [{ suggestion: null, hotel: null }];
      for (const target of searches) {
        const url = buildListURL(request, cityID, target.suggestion);
        const loaded = await loadListPage(page, url);
        if (loaded.status === "verification_required") {
          verificationURL = page.url();
          break;
        }
        const targetHotels = target.hotel ? [target.hotel] : request.hotels;
        const pageQuotes = parseCtripCardTexts(loaded.cardTexts, targetHotels, page.url(), capturedAt);
        quotes.push(...pageQuotes);
        resultCount += loaded.cardTexts.length;
        if (!pageQuotes.length && loaded.loginForPrice) {
          loginURL = page.url();
          break;
        }
      }

      const uniqueQuotes = lowestQuotePerHotel(quotes);
      const status = verificationURL
        ? "verification_required"
        : loginURL
          ? "login_required"
          : uniqueQuotes.length
            ? "ok"
            : (resultCount ? "no_matching_quotes" : "no_visible_cards");
      return {
        quotes: uniqueQuotes,
        diagnostics: [{
          provider: this.name,
          status,
          resultCount,
          capturedAt,
          ...(loginURL || verificationURL ? { loginURL: loginURL || verificationURL } : {})
        }]
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

function buildListURL(request, cityID, target = null) {
  const url = new URL("https://hotels.ctrip.com/hotels/list");
  const parameters = {
    flexType: "1",
    cityId: String(cityID),
    provinceId: "0",
    districtId: "0",
    countryId: "1",
    checkin: request.checkIn,
    checkout: request.checkOut,
    crn: String(request.rooms || 1),
    curr: "CNY"
  };
  if (target) {
    parameters.searchType = "H";
    parameters.optionId = target.id;
    parameters.optionName = target.name;
  }
  for (const [key, value] of Object.entries(parameters)) url.searchParams.set(key, value);
  return url.href;
}

async function resolveHotelSuggestion(hotel, cityID) {
  try {
    const response = await fetch(hotelSuggestURL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        keyword: hotel.name,
        searchType: "H",
        platform: "online",
        pageID: "102001",
        head: {
          Locale: "zh-CN",
          LocaleController: "zh_cn",
          Currency: "CNY",
          PageId: "102001",
          clientID: "anytravel-open-source",
          group: "ctrip",
          Frontend: { sessionID: 1, pvid: 1 },
          HotelExtension: { group: "CTRIP", WebpSupport: false }
        }
      }),
      signal: AbortSignal.timeout(10_000)
    });
    if (!response.ok) return null;
    return selectCtripHotelSuggestion(await response.json(), hotel.name, cityID);
  } catch {
    return null;
  }
}

async function loadListPage(page, url) {
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 });
  await page.waitForFunction(
    () => location.host === "passport.ctrip.com"
      || /账号异常|安全验证|访问过于频繁|请完成验证/.test(document.body?.innerText || "")
      || [...document.querySelectorAll(".list-item")].some((card) =>
        /酒店|宾馆|旅馆|客栈|民宿|公寓/.test(card.innerText || "")
      ),
    undefined,
    { timeout: 18_000 }
  ).catch(() => {});
  await page.waitForTimeout(1_500);

  const bodyText = await page.locator("body").innerText().catch(() => "");
  if (/账号异常|安全验证|访问过于频繁|请完成验证/.test(bodyText)) {
    return { status: "verification_required", cardTexts: [], loginForPrice: false };
  }
  if (page.url().includes("passport.ctrip.com") || /登录首页|登录携程/.test(bodyText)) {
    return { status: "content", cardTexts: [], loginForPrice: true };
  }
  const cardTexts = await page.locator(".list-item").evaluateAll((cards) =>
    cards.slice(0, 40).map((card) => card.innerText || "")
  );
  return {
    status: "content",
    cardTexts,
    loginForPrice: /登录(?:以)?查看(?:会员)?价|登录后查看|登录查看低价/.test(bodyText)
  };
}

function lowestQuotePerHotel(quotes) {
  const result = new Map();
  for (const quote of quotes) {
    const previous = result.get(quote.hotelID);
    if (!previous || quote.amountCNY < previous.amountCNY) result.set(quote.hotelID, quote);
  }
  return [...result.values()];
}
