import assert from "node:assert/strict";
import test from "node:test";
import { ElongHotelAdapter, elongSignature } from "../src/adapters/elong.mjs";

test("implements the eLong documented nested MD5 formula on the unencoded JSON data", () => {
  const data = '{"Version":"1.28","Local":"zh_CN","Request":{"ArrivalDate":"2017-03-16","DepartureDate":"2017-03-17","CityId":"0101","PageIndex":1,"PageSize":10,"ResultType":"1,2,4","PaymentType":"All"}}';
  assert.equal(elongSignature({
    timestamp: "1489555911",
    data,
    appKey: "97f1f3804a9388663067f0eb04c21281",
    secretKey: "431d6af690d323f99bd816215b30b156"
  }), "08b5f546ea0722925a79e9680cb7dc49");
});

test("combines eLong city, hotel metadata and dated LowRate into live hotel cards", async () => {
  const calls = [];
  const fetchImpl = async (input, options) => {
    const url = new URL(input);
    const method = url.searchParams.get("method");
    const data = JSON.parse(url.searchParams.get("data"));
    calls.push({ method, data, options, url });
    const payload = payloadFor(method, data.Request);
    return { ok: true, status: 200, json: async () => payload };
  };
  const adapter = new ElongHotelAdapter({
    env: {
      ELONG_USER: "Agent-test",
      ELONG_APP_KEY: "app-key",
      ELONG_SECRET_KEY: "secret-key",
      ELONG_ENDPOINT: "https://api-test.elong.com/rest"
    },
    fetchImpl,
    now: () => new Date("2026-09-02T08:00:00.000Z")
  });

  const result = await adapter.discover({
    destination: "苏州市",
    checkIn: "2026-09-10",
    checkOut: "2026-09-12",
    adults: 2,
    rooms: 1,
    size: 2
  });

  assert.equal(result.diagnostics[0].status, "ok");
  assert.equal(result.diagnostics[0].pricedCount, 2);
  assert.equal(result.hotels.length, 2);
  assert.equal(result.hotels[0].provider, "tongcheng");
  assert.equal(result.hotels[0].source, "elong-open-api");
  assert.equal(result.hotels[0].name, "苏州松弛酒店");
  assert.equal(result.hotels[0].amountCNY, 328);
  assert.equal(result.hotels[0].kind, "live");
  assert.equal(result.hotels[0].unit, "perNight");
  assert.equal(result.hotels[0].brand, "折叠远方");
  assert.equal(result.hotels[0].address, "姑苏区诗意路1号");
  assert.equal(result.hotels[0].imageURL, "https://img.example.com/hotel-1.jpg");
  assert.ok(result.hotels[0].amenities.includes("免费停车场"));
  assert.match(result.hotels[0].bookingURL, /hotelid=hotel-1/);
  assert.match(result.hotels[0].bookingURL, /inDate=2026-09-10/);
  assert.ok(Math.abs(result.hotels[0].latitude - 31.30) < 0.02);
  assert.ok(Math.abs(result.hotels[0].longitude - 120.62) < 0.02);

  const dynamicCall = calls.find((call) => call.method === "hotel.detail");
  assert.equal(dynamicCall.data.Request.ArrivalDate, "2026-09-10");
  assert.equal(dynamicCall.data.Request.DepartureDate, "2026-09-12");
  assert.equal(dynamicCall.data.Request.HotelIds, "hotel-1,hotel-2");
  assert.equal(dynamicCall.data.Request.NumberOfAdults, 2);
  assert.equal(dynamicCall.data.Request.NumberOfRooms, 1);
  assert.equal(dynamicCall.options.headers["accept-encoding"], "br, gzip");
  assert.equal(dynamicCall.url.searchParams.get("user"), "Agent-test");
  assert.equal(dynamicCall.url.searchParams.get("signature").length, 32);
});

test("reports eLong as disabled until all issued credentials exist", async () => {
  const result = await new ElongHotelAdapter({ env: {} }).discover({
    destination: "苏州",
    checkIn: "2026-09-10",
    checkOut: "2026-09-12"
  });
  assert.deepEqual(result.hotels, []);
  assert.equal(result.diagnostics[0].status, "disabled");
});

function payloadFor(method, request) {
  switch (method) {
  case "hotel.static.city":
    return {
      Code: "0",
      Result: { Count: 1, Citys: [{ CityID: "0201", CityName: "苏州" }] }
    };
  case "hotel.static.list":
    assert.equal(request.CityId, "0201");
    return {
      Code: "0",
      Result: {
        Count: 3,
        HotelIds: [
          { HotelId: "hotel-1", HotelName: "苏州松弛酒店", HotelStatus: 0 },
          { HotelId: "hotel-2", HotelName: "苏州园林客栈", HotelStatus: 0 },
          { HotelId: "hotel-removed", HotelName: "已下线酒店", HotelStatus: 2 }
        ]
      }
    };
  case "hotel.detail":
    return {
      Code: "0",
      Result: {
        Count: 2,
        Hotels: [
          { HotelId: "hotel-1", LowRate: 328, CurrencyCode: "RMB" },
          { HotelId: "hotel-2", LowRate: 468.2, CurrencyCode: "CNY" }
        ]
      }
    };
  case "hotel.static.info": {
    const first = request.HotelId === "hotel-1";
    return {
      Code: "0",
      Result: {
        Detail: {
          HotelName: first ? "苏州松弛酒店" : "苏州园林客栈",
          BrandName: first ? "折叠远方" : null,
          Address: first ? "姑苏区诗意路1号" : "姑苏区园林路2号",
          GoogleLat: 31.30,
          GoogleLon: 120.62,
          StarRate: first ? 4 : 3,
          IntroEditor: "住进园林，慢慢醒来。<br>近地铁。",
          GeneralFacilities: [{ FacilityName: "免费停车场" }, { FacilityName: "免费 Wi-Fi" }],
          HotelTypes: [{ HotelTypeName: "精品酒店" }]
        },
        Images: first ? [{ ImageUrl: "https://img.example.com/hotel-1.jpg" }] : []
      }
    };
  }
  default:
    throw new Error(`unexpected method ${method}`);
  }
}
