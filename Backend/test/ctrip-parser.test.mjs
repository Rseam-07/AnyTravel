import test from "node:test";
import assert from "node:assert/strict";
import { parseCtripCardTexts, selectCtripHotelSuggestion } from "../src/lib/ctrip-parser.mjs";

test("selects an exact hotel suggestion in the expected city", () => {
  const payload = {
    Response: {
      searchResults: [
        { id: 60927309, type: "Hotel", word: "苏州柏悦酒店", cityId: 14 },
        { id: 123, type: "Hotel", word: "苏州柏悦酒店", cityId: 2 }
      ]
    }
  };

  assert.deepEqual(selectCtripHotelSuggestion(payload, "苏州柏悦酒店", 14), {
    id: "60927309",
    name: "苏州柏悦酒店",
    cityID: 14
  });
});

test("rejects a weakly related hotel suggestion", () => {
  const payload = {
    Response: {
      searchResults: [
        { id: 122475663, type: "Hotel", word: "福城柏悦商务宾馆(光福文体中心店)", cityId: 14 }
      ]
    }
  };

  assert.equal(selectCtripHotelSuggestion(payload, "苏州柏悦酒店", 14), null);
});

test("parses the current price without leaking review counts", () => {
  const hotels = [{ id: "dce71906-54d1-4d74-a5d6-cdbed9aa7dd2", name: "苏州吴宫泛太平洋酒店" }];
  const result = parseCtripCardTexts(
    ["苏州吴宫泛太平洋酒店 4.7 超棒 1,994条点评 近盘门 免费取消 ¥688 ¥566 起 查看详情"],
    hotels,
    "https://hotels.ctrip.com/hotels/list",
    "2026-08-31T05:00:00.000Z"
  );
  assert.equal(result.length, 1);
  assert.equal(result[0].amountCNY, 566);
  assert.equal(result[0].hotelID, hotels[0].id);
  assert.match(result[0].note, /划线价¥688/);
});

test("does not attach an unrelated hotel price to a map candidate", () => {
  const result = parseCtripCardTexts(
    ["完全不同的北京酒店 4.8 500条点评 ¥399 起"],
    [{ id: "7ee3520d-a041-47cb-a2b6-8723268362ec", name: "苏州柏悦酒店" }],
    "https://hotels.ctrip.com/hotels/list",
    "2026-08-31T05:00:00.000Z"
  );
  assert.deepEqual(result, []);
});
