import path from "node:path";
import { parseCtripFlightCards } from "../lib/flight-parser.mjs";
import { playwrightLaunchOptions } from "../lib/playwright-options.mjs";

const airportCodes = new Map([
  ["北京", "BJS"], ["上海", "SHA"], ["天津", "TSN"], ["重庆", "CKG"],
  ["广州", "CAN"], ["深圳", "SZX"], ["成都", "CTU"], ["杭州", "HGH"],
  ["南京", "NKG"], ["武汉", "WUH"], ["西安", "XIY"], ["长沙", "CSX"],
  ["青岛", "TAO"], ["厦门", "XMN"], ["宁波", "NGB"], ["郑州", "CGO"],
  ["昆明", "KMG"], ["海口", "HAK"], ["三亚", "SYX"], ["福州", "FOC"],
  ["济南", "TNA"], ["沈阳", "SHE"], ["大连", "DLC"], ["哈尔滨", "HRB"],
  ["长春", "CGQ"], ["太原", "TYN"], ["石家庄", "SJW"], ["南昌", "KHN"],
  ["合肥", "HFE"], ["贵阳", "KWE"], ["南宁", "NNG"], ["兰州", "LHW"],
  ["乌鲁木齐", "URC"], ["拉萨", "LXA"], ["珠海", "ZUH"], ["无锡", "WUX"],
  ["苏州", "WUX"]
]);

export class CtripFlightAdapter {
  name = "ctrip-flight";

  async search(request) {
    if (!request.modes?.includes("flight")) return { options: [], diagnostics: [] };
    const enabled = process.env.CTRIP_FLIGHT_SCRAPER_ENABLED ?? process.env.CTRIP_SCRAPER_ENABLED;
    if (enabled !== "true") {
      return { options: [], diagnostics: [{ provider: this.name, status: "disabled" }] };
    }
    const originCode = resolveCtripAirportCode(request.origin);
    const destinationCode = resolveCtripAirportCode(request.destination);
    if (!originCode || !destinationCode || originCode === destinationCode) {
      return {
        options: [],
        diagnostics: [{
          provider: this.name,
          status: "airport_code_missing",
          detail: `${request.origin} → ${request.destination}`
        }]
      };
    }

    let playwright;
    try { playwright = await import("playwright"); }
    catch (error) {
      return { options: [], diagnostics: [{ provider: this.name, status: "dependency_missing", detail: error.message }] };
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
        options: [],
        diagnostics: [{ provider: this.name, status: "browser_unavailable", detail: error.message }]
      };
    }

    const journeys = [{
      direction: "outbound",
      date: request.departureDate,
      originCode,
      destinationCode,
      originName: request.origin,
      destinationName: request.destination
    }];
    if (request.returnDate) {
      journeys.push({
        direction: "return",
        date: request.returnDate,
        originCode: destinationCode,
        destinationCode: originCode,
        originName: request.destination,
        destinationName: request.origin
      });
    }

    const options = [];
    const diagnostics = [];
    try {
      for (const journey of journeys) {
        const page = await context.newPage();
        const result = await searchJourney(page, journey, request.adults);
        await page.close();
        options.push(...result.options);
        diagnostics.push(result.diagnostic);
        if (["verification_required", "login_required"].includes(result.diagnostic.status)) break;
      }
      return { options, diagnostics };
    } catch (error) {
      return {
        options,
        diagnostics: [...diagnostics, { provider: this.name, status: "failed", detail: error.message }]
      };
    } finally {
      await context.close();
    }
  }
}

export function resolveCtripAirportCode(value) {
  const city = String(value || "").trim().replace(/市$/, "");
  const overrides = airportCodeOverrides();
  return overrides[city] || airportCodes.get(city) || (/^[A-Za-z]{3}$/.test(city) ? city.toUpperCase() : null);
}

async function searchJourney(page, journey, adults) {
  const url = new URL(`https://flights.ctrip.com/online/list/oneway-${journey.originCode.toLowerCase()}-${journey.destinationCode.toLowerCase()}`);
  url.searchParams.set("depdate", journey.date);
  url.searchParams.set("cabin", "Y_S_C_F");
  url.searchParams.set("adult", String(Math.min(Math.max(Number(adults || 1), 1), 8)));
  url.searchParams.set("child", "0");
  url.searchParams.set("infant", "0");
  url.searchParams.set("containstax", "1");
  await page.goto(url.href, { waitUntil: "domcontentloaded", timeout: 35_000 });
  await page.waitForFunction(
    () => /安全验证|访问过于频繁|请完成验证|登录携程/.test(document.body?.innerText || "")
      || document.querySelectorAll(".flight-item").length > 0,
    undefined,
    { timeout: 22_000 }
  ).catch(() => {});
  await page.waitForTimeout(1_800);
  const bodyText = await page.locator("body").innerText().catch(() => "");
  const label = journey.direction === "return" ? "返程" : "去程";
  if (/安全验证|访问过于频繁|请完成验证|账号异常/.test(bodyText)) {
    return {
      options: [],
      diagnostic: { provider: "ctrip-flight", status: "verification_required", detail: label, loginURL: page.url() }
    };
  }
  if (page.url().includes("passport.ctrip.com") || /登录携程|登录首页/.test(bodyText)) {
    return {
      options: [],
      diagnostic: { provider: "ctrip-flight", status: "login_required", detail: label, loginURL: page.url() }
    };
  }
  const cards = await page.locator(".flight-item").evaluateAll((nodes) =>
    nodes.slice(0, 50).map((node) => ({ text: node.innerText || "" }))
  );
  const capturedAt = new Date().toISOString();
  const options = parseCtripFlightCards(cards, {
    ...journey,
    bookingURL: page.url(),
    capturedAt
  }).slice(0, Math.min(Math.max(Number(process.env.FLIGHT_RESULT_LIMIT || 12), 1), 20));
  return {
    options,
    diagnostic: {
      provider: "ctrip-flight",
      status: options.length ? "ok" : "no_visible_cards",
      detail: `${label} ${options.length} 班`,
      resultCount: options.length,
      capturedAt
    }
  };
}

function airportCodeOverrides() {
  try {
    const value = JSON.parse(process.env.CTRIP_AIRPORT_CODES || "{}");
    return value && typeof value === "object" ? value : {};
  } catch { return {}; }
}
