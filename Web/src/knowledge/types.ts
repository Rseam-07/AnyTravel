// AnyTravel 行程规划知识库类型。
// 这是从未完成的旧会话中回收的研究快照，只用于目的地印象、候选地点、
// 建议停留时长与日程排序。门票和开放信息不是实时数据。

export interface FamousPlace {
  name: string;
  coord?: { lat: number; lng: number };
  category: string; // 园林/博物馆/自然/美食/古镇/亲子/夜游/宗教/城市…
  stayMinutes?: number;
  tier: "必去" | "推荐" | "顺路";
  ticket?: string; // 常见门票区间/免费/需预约
  best?: "清晨" | "上午" | "下午" | "傍晚" | "晚上" | "白天" | "全天";
  openingHoursWeek?: string; // 开放数据规则快照；规划时仍需按日期复核
  tags?: string[];
}

export interface GuideCity {
  city: string;
  province?: string;
  region?: string;
  country: string;
  coord?: { lat: number; lng: number };
  tripDays?: string;
  sense?: string; // 一句印象
  places: FamousPlace[];
  patterns?: string[]; // 攻略中的典型日程句（学习样本）
  sources: string[];
}

export interface GuideRule {
  rule: string; // 普遍规则
  basis: string; // 攻略共识/依据
  counter?: string; // 例外
}

export interface GuideKnowledge {
  version: string;
  harvestedAt: string;
  cities: GuideCity[];
  rules: GuideRule[];
  sourceCount: number;
}

export const CATEGORY_TO_INTEREST: Record<string, string> = {
  园林: "gardens",
  古迹: "gardens",
  古镇: "gardens",
  宗教: "gardens",
  博物馆: "culture",
  美术馆: "culture",
  科技馆: "culture",
  自然: "nature",
  山水: "nature",
  海滨: "nature",
  公园: "nature",
  亲子: "family",
  乐园: "family",
  动物园: "family",
  美食: "food",
  美食街: "food",
  夜游: "night",
  夜景: "night",
  城市: "gardens"
};
