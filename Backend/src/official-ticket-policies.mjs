// Reviewed against the public booking rules on 2026-09-28. This is the adult
// admission tariff, never an availability or reservation confirmation.
const palace = {
  verifiedAt: "2026-09-28T06:19:52.000Z",
  source: "https://ticket.dpm.org.cn/",
  reviewAfter: "2026-12-28T00:00:00.000Z"
};

export function officialTicketQuote(attraction, destination, visitDate, now = new Date()) {
  if (!/北京/.test(`${destination} ${attraction.address || ""}`) || !/^(故宫|故宫博物院|北京故宫)$/.test(attraction.name) || /台北|沈阳/.test(attraction.name)) return null;
  if (now.getTime() > Date.parse(palace.reviewAfter)) return null;
  const month = Number(visitDate?.slice(5, 7));
  const amount = month >= 4 && month <= 10 ? 60 : month >= 1 && month <= 12 ? 40 : null;
  return { attractionID: attraction.id, attractionName: attraction.name, provider: "official-policy", kind: "indicative",
    amountCNY: amount, unit: "perPerson", priceType: "admission", capturedAt: palace.verifiedAt, bookingURL: palace.source,
    note: `故宫官方成人大门票${amount == null ? "：旺季60元、淡季40元" : `：${amount}元/人`}，珍宝馆、钟表馆各10元另计；这是票价政策，未查询余票。须在官方渠道实名预约。未满18周岁符合官方条件者免费但仍须预约；优惠资格请复核。资料核验于2026-09-28。` };
}
